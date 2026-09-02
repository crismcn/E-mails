import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_scope.dart';
import '../api/mail_api.dart';
import '../data/mail_html_document.dart';
import '../data/mail_mapper.dart';
import '../l10n/app_localizations.dart';
import '../models/mail.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../widgets/mail_html_view.dart';

/// 邮件消息详情页 —— 从会话页点击某条消息进入，展示完整详情。
///
/// 正文支持 HTML 渲染（[MailMessage.htmlBody] 非空时），否则按纯文本渲染；
/// HTML 中的超链接 / 按钮链接点击后用外部浏览器打开。视觉参照「邮件详情」设计稿。
///
/// 会话页传入的 [MailMessage] 只带 `bodyPreview`（会话查询不含全文），
/// 故本页在 `initState` 若发现无全文且有 `id`，就按 id 懒取 `body` 并补全。
class MessageDetailPage extends StatefulWidget {
  const MessageDetailPage({
    super.key,
    required this.message,
    required this.accountEmail,
  });

  final MailMessage message;

  /// 所属账号邮箱 —— 供懒取全文时按账号取 token。
  final String accountEmail;

  @override
  State<MessageDetailPage> createState() => _MessageDetailPageState();
}

class _MessageDetailPageState extends State<MessageDetailPage>
    with TickerProviderStateMixin {
  late bool _starred = widget.message.isFlagged;

  /// 标星写回进行中 —— 去重，避免连点发出多次 PATCH。
  bool _flagBusy = false;

  /// 当前展示的消息（懒取全文后会被替换为带 body/htmlBody 的版本）。
  late MailMessage _message = widget.message;

  /// 正文懒取中 —— 尚无全文时展示占位转圈。
  bool _loadingBody = false;

  /// 「正文还看不到」时浮在内容区正中那个转圈的不透明度。
  ///
  /// **懒取全文与正文 WebView 渲染两段共用同一个转圈**：之前是两段各画一个（页面画
  /// 懒取那个、[MailHtmlView] 在遮罩里画渲染那个），交接处有一两帧谁都没画 ——
  /// Android 上平台视图首帧还要几十毫秒，看着就是**闪一下**。
  ///
  /// 用控制器只为跟正文遮罩**同步淡出**（同一时长 [MailHtmlView.kRevealDuration]）；
  /// `dismissed` 时整层移出树，否则转圈会在 `opacity:0` 下面一直空转、每帧重绘
  /// （CLAUDE.md §4.6）。
  late final AnimationController _spinner;

  // ---- 附件 ----

  /// 附件元信息（已过滤正文内嵌图）—— 空列表即不显示附件条。
  List<GraphAttachment> _attachments = const <GraphAttachment>[];

  /// 附件条是否展开（默认收起，与设计稿一致）。
  bool _attachExpanded = false;

  /// 已取到的附件内容：attachment.id → 字节。图片预览与打开/下载共用这份缓存。
  final Map<String, Uint8List> _attachBytes = <String, Uint8List>{};

  /// 正在取内容的附件 id —— 防重复请求，并给卡片显示转圈。
  final Set<String> _attachBusy = <String>{};

  // ---- 页面结构 ----
  //
  // `Stack`：滚动视图 `Positioned.fill` **恒定**铺满整块内容区（收件人 / 主题 / 日期 /
  // 附件 / 正文都在里面，整页一条滚动条），返回栏与底部操作栏是浮在它上面的两条
  // **绝对定位**浮层，靠滚动视图**恒定**的上下内边距让位。
  //
  // 上滑把两条浮层收起、下滑切回，**只用 `SlideTransition` 做绘制期平移** ——
  // 绝不改滚动视图的尺寸，也绝不改那份内边距。历史上「全屏状态来回跳动」的病根是
  // 收放改了正文区的尺寸或滚动几何：正文是 WebView，一改尺寸就重排、重排又吐出新的
  // 滚动偏移去驱动收放，正反馈。现在 `maxScrollExtent` 全程恒定（测试里有断言），
  // WebView 一次都不会因收放而重排，那条回路不存在。

  /// 两条浮层的显隐（1 = 完全展开，0 = 完全移出屏幕）。
  late final AnimationController _chrome = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );

  late final Animation<Offset> _headerSlide = _slide(const Offset(0, -1));
  late final Animation<Offset> _actionBarSlide = _slide(const Offset(0, 1));

  Animation<Offset> _slide(Offset hidden) =>
      Tween<Offset>(begin: hidden, end: Offset.zero).animate(
        CurvedAnimation(
          parent: _chrome,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        ),
      );

  /// 页面那条滚动条 —— 收放由它驱动（不是 WebView 的滚动回报）。
  final ScrollController _scroll = ScrollController();

  /// 收放的当前目标（1 = 展开）—— 让 [_setChromeVisible] 幂等，滚动回调每帧都来。
  double _chromeTarget = 1;

  /// 贴顶这么近就恒展开 —— 顶部那一小段永远看得见返回箭头。
  static const double _kChromeShowOffset = 60;

  /// 上滑越过这里才允许收起。
  static const double _kChromeHideOffset = 80;

  /// 可滚距离不足这么多就不收 —— 内容本来就快装得下，收了也没多少可看。
  static const double _kChromeMinExtent = 200;

  /// 两条浮层的高度估值（首帧用，随后被实测值校正，见 [_measureChrome]）。
  static const double _kHeaderEstimate = 64;
  static const double _kActionBarEstimate = 70;

  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _actionBarKey = GlobalKey();

  double _headerHeight = _kHeaderEstimate;
  double _actionBarHeight = _kActionBarEstimate;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // 无全文（htmlBody/body 皆空）且有 id → 懒取。会话预览的 body 可能已含摘要，
    // 但为拿到完整 HTML/纯文本仍以 id 取一次权威全文。
    if (widget.message.id.isNotEmpty && widget.message.htmlBody == null) {
      _loadingBody = true;
    }
    _spinner = AnimationController(
      vsync: this,
      duration: MailHtmlView.kRevealDuration,
      // 正文要走 WebView 的话遮罩会接着盖住，故一开始就把转圈亮着 —— 等
      // [MailHtmlView] 回报（帧末）中间就空了一帧。
      value: _loadingBody || widget.message.htmlBody != null ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _chrome.dispose();
    _spinner.dispose();
    super.dispose();
  }

  /// 按滚动位置与方向决定两条浮层的收放。
  ///
  /// **下滑立刻切回**（不是等快到顶部才回来）：`appRoute` 没有 iOS 侧滑返回，
  /// 返回箭头藏着就退不出这一页。
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels <= _kChromeShowOffset ||
        position.maxScrollExtent < _kChromeMinExtent) {
      _setChromeVisible(true);
      return;
    }
    switch (position.userScrollDirection) {
      case ScrollDirection.reverse: // 手指上滑看后文 → 收起，全屏留给正文
        if (position.pixels > _kChromeHideOffset) _setChromeVisible(false);
      case ScrollDirection.forward: // 下滑 → 立刻切回
        _setChromeVisible(true);
      case ScrollDirection.idle:
        break;
    }
  }

  /// 收 / 放两条浮层。
  ///
  /// **只驱动动画、不 `setState`**：重建会把正文那块 WebView 一起重排 —— 那正是
  /// 历史上「来回跳动」的起点。`SlideTransition` 自己听动画，只重绘那两条浮层。
  void _setChromeVisible(bool visible) {
    final target = visible ? 1.0 : 0.0;
    if (_chromeTarget == target) return;
    _chromeTarget = target;
    if (visible) {
      _chrome.forward();
    } else {
      _chrome.reverse();
    }
  }

  /// 帧后量一次两条浮层的实高，校正滚动视图的留白。
  ///
  /// 写死会因平台字体 / 系统文字缩放差几像素，内容正好露在浮层边缘那一线。
  /// 只在值真的变了时 `setState` —— 否则量→重建→再量就成环了。
  void _measureChrome() {
    final header = _bandHeight(_headerKey);
    final actionBar = _bandHeight(_actionBarKey);
    if (header == null || actionBar == null) return;
    if ((header - _headerHeight).abs() < 0.5 &&
        (actionBar - _actionBarHeight).abs() < 0.5) {
      return;
    }
    setState(() {
      _headerHeight = header;
      _actionBarHeight = actionBar;
    });
  }

  static double? _bandHeight(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadingBody) _fetchBody();
  }

  Future<void> _fetchBody() async {
    final res = await ApiScope.of(context).mail
        .getMessage(widget.accountEmail, widget.message.id);
    if (!mounted) return;
    setState(() {
      if (res.isSuccess && res.data != null) {
        // 用取回的全文整体重建 —— 列表项只带发件人/主题占位，收件人、完整日期、
        // 正文都以权威的 getMessage 结果为准。
        _message = applyBody(mailMessageFromGraph(res.data!), res.data!);
        // 星标以权威结果为准（列表项未带 flag，进入时可能是占位 false）。
        _starred = _message.isFlagged;
      }
      _loadingBody = false;
    });
    // 纯文本正文（含取全文失败）没有 WebView 遮罩接手，转圈就此淡出；HTML 则等
    // [MailHtmlView] 回报「遮罩淡了」，见 [_onBodyCoverChanged]。
    if (_message.htmlBody == null) _spinner.reverse();
    // 带附件才多打一次附件列表请求（内嵌图也会让 hasAttachments 为 true，
    // 过滤后可能仍是空列表 —— 那就什么都不显示）。
    if (res.isSuccess && (res.data?.hasAttachments ?? false)) {
      await _loadAttachments();
    }
  }

  /// 拉附件元信息 —— 失败静默（正文已能看），不因附件挡住整封邮件。
  Future<void> _loadAttachments() async {
    final res = await ApiScope.of(context).mail
        .listAttachments(widget.accountEmail, _message.id);
    if (!mounted || !res.isSuccess) return;
    final items = (res.data ?? const <GraphAttachment>[])
        .where((a) => !a.isInline)
        .toList();
    setState(() => _attachments = items);
  }

  /// 展开 / 收起附件条 —— 首次展开时把图片附件的内容取回来做预览。
  void _toggleAttachments() {
    final next = !_attachExpanded;
    setState(() => _attachExpanded = next);
    if (!next) return;
    for (final a in _attachments) {
      if (a.isImage) _ensureBytes(a);
    }
  }

  /// 取附件内容（带缓存 / 防重入）—— 返回 null 表示取失败，已就地提示。
  Future<Uint8List?> _ensureBytes(GraphAttachment attachment) async {
    final cached = _attachBytes[attachment.id];
    if (cached != null) return cached;
    if (_attachBusy.contains(attachment.id)) return null;

    setState(() => _attachBusy.add(attachment.id));
    final res = await ApiScope.of(context).mail
        .getAttachmentBytes(widget.accountEmail, _message.id, attachment.id);
    if (!mounted) return null;
    setState(() {
      _attachBusy.remove(attachment.id);
      if (res.isSuccess && res.data != null) {
        _attachBytes[attachment.id] = Uint8List.fromList(res.data!);
      }
    });
    if (!res.isSuccess) {
      _toast(AppLocalizations.of(context).detailAttachmentFailed(res.message));
      return null;
    }
    return _attachBytes[attachment.id];
  }

  /// 点附件 —— 先交给手机上的应用打开；打不开（没有可处理的应用）就转为下载。
  Future<void> _openAttachment(GraphAttachment attachment) async {
    final bytes = await _ensureBytes(attachment);
    if (bytes == null || !mounted) return;

    // 写进应用私有临时目录再交给系统 —— 文件名做净化，附件名来自远端，
    // 不能让它带路径分隔符跳出目录。
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeFileName(attachment.name)}');
    await file.writeAsBytes(bytes, flush: true);

    final result = await OpenFilex.open(
      file.path,
      type: attachment.contentType.isEmpty ? null : attachment.contentType,
    );
    if (!mounted || result.type == ResultType.done) return;
    // 没有应用能打开（或被系统拒绝）→ 退回「下载」，让用户自己存到文件里。
    _toast(AppLocalizations.of(context).detailAttachmentOpenFallback);
    await _downloadAttachment(attachment);
  }

  /// 下载附件 —— 走系统保存对话框（Android SAF / iOS 文件），用户选位置。
  Future<void> _downloadAttachment(GraphAttachment attachment) async {
    final bytes = await _ensureBytes(attachment);
    if (bytes == null || !mounted) return;
    final saved = await FilePicker.saveFile(
      fileName: _safeFileName(attachment.name),
      bytes: bytes,
      mimeType: attachment.contentType.isEmpty
          ? 'application/octet-stream'
          : attachment.contentType,
    );
    if (!mounted || saved == null) return; // null = 用户取消，不提示
    _toast(AppLocalizations.of(context).detailAttachmentSaved(attachment.name));
  }

  /// 附件名净化 —— 去掉路径分隔符与空名，避免写到目标目录之外。
  static String _safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[/\\]'), '_').trim();
    return cleaned.isEmpty ? 'attachment' : cleaned;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1800),
        ),
      );
  }

  /// 切换标星 —— 乐观更新 + PATCH 回写 Graph，失败回滚并提示。
  Future<void> _toggleStar() async {
    if (_flagBusy || _message.id.isEmpty) return;
    final next = !_starred;
    setState(() {
      _starred = next;
      _flagBusy = true;
    });
    final res = await ApiScope.of(context).mail
        .updateFlag(widget.accountEmail, _message.id, flagged: next);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (res.isSuccess) {
      _message = _message.copyWith(isFlagged: next);
      setState(() => _flagBusy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(next ? l10n.mailFlagged : l10n.mailUnflagged),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1400),
          ),
        );
    } else {
      // 回滚本地星标态，并原样提示失败原因（多为 Mail.ReadWrite 未授权）。
      setState(() {
        _starred = !next;
        _flagBusy = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.mailActionFailedToast(res.message)),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1800),
          ),
        );
    }
  }

  /// 正文遮罩起落 —— 转圈跟着它亮 / 跟着它淡（时长相同，见 [_spinner]）。
  void _onBodyCoverChanged(bool covered) {
    if (!mounted) return;
    if (covered) {
      _spinner.value = 1;
    } else {
      _spinner.reverse();
    }
  }

  /// 打开正文中的链接（超链接 / 按钮）—— 外部浏览器，失败时提示。
  ///
  /// 只放行 http/https/mailto/tel：正文是发件人可控的，`javascript:` 或自定义
  /// scheme 不该被原样丢给系统去启动。
  Future<bool> _openUrl(String url) async {
    final uri = isSafeMailLink(url) ? Uri.tryParse(url) : null;
    var ok = false;
    if (uri != null) {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!ok && mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.linkOpenFailed),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1600),
          ),
        );
    }
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final message = _message;
    // 浮层实高帧后校正一次（只在真的变了时 setState，见 [_measureChrome]）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureChrome();
    });
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        // `LayoutBuilder` 只为拿内容区总高：正文 WebView 的加载遮罩期要按「可见高度」
        // 占位（量到真实高度前先占满一屏，见 [MailHtmlView]）。
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            // `expand`：滚动视图铺满内容区（默认 loose 会让它按内容缩，短邮件时
            // 下半截就点不着、滑不动）。
            fit: StackFit.expand,
            children: [
              // 整页一条滚动条：收件人 / 主题 / 日期 / 附件 / 正文一起上滑。
              //
              // 铺满整块内容区、靠**恒定**的上下留白给两条浮层让位 —— 收放不动这份
              // 留白，`maxScrollExtent` 恒定，正文一格都不跳。内容会滑到浮层**背后**
              // （浮层不透明），收起时那部分就露出来。
              Positioned.fill(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.only(
                    top: _headerHeight,
                    bottom: _actionBarHeight,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MetaSection(
                        message: message,
                        attachments: _attachments,
                        expanded: _attachExpanded,
                        bytes: _attachBytes,
                        busy: _attachBusy,
                        onToggle: _toggleAttachments,
                        onOpen: _openAttachment,
                        onDownload: _downloadAttachment,
                      ),
                      _body(
                        palette,
                        message,
                        box.maxHeight - _headerHeight - _actionBarHeight,
                      ),
                    ],
                  ),
                ),
              ),
              // 「正文还看不到」时的转圈 —— 浮在内容区正中，懒取全文与正文渲染两段
              // 共用它、中间不落幕（见 [_spinner]）。排在元信息下面时它会贴着收件人
              // 那几行，看着像挂在页面上三分之一处。两条浮层高度相当，故按整块内容区
              // 居中即可（CLAUDE.md §4.7）。
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _spinner,
                    builder: (context, _) => _spinner.isDismissed
                        ? const SizedBox.shrink()
                        : FadeTransition(
                            opacity: _spinner,
                            child: Center(
                              child: CupertinoActivityIndicator(
                                radius: 12,
                                color: palette.textSecondary,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              // 两条浮层。**`ClipRect` 是必需的**：`SlideTransition` 是绘制期变换，
              // 浮层的布局矩形始终在 `Stack` 范围内 → `RenderStack` 认为没有溢出 →
              // 不装裁剪层 → 挪出去的部分照画。真机上表现为「顶栏没隐藏」：它滑进
              // 状态栏那条安全区里赖着不走（测试的 view padding 为 0 时越界即出屏被
              // 裁，所以第一版测试没抓到 —— 现在断言按各自的裁剪窗来判）。
              // 裁剪同时管住命中测试：藏起来的浮层点不到。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ClipRect(
                  key: const Key('detail-header-clip'),
                  child: SlideTransition(
                    position: _headerSlide,
                    child: _Header(
                      key: _headerKey,
                      title: message.sender,
                      starred: _starred,
                      onStar: _toggleStar,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ClipRect(
                  key: const Key('detail-actionbar-clip'),
                  child: SlideTransition(
                    position: _actionBarSlide,
                    child: _ActionBar(key: _actionBarKey),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 正文 —— 排在页面那条滚动条里，与上方元信息一起滚。
  ///
  /// HTML 交给 [MailHtmlView]：**按页内量到的高度占位、自己不滚**，双指在这块固定
  /// 高度里缩放 + 平移。纯文本仍是 Flutter 的可选择文本。
  ///
  /// [viewportHeight] 是内容区的可见高度，只用来给 [MailHtmlView] 的加载遮罩定占位高度。
  Widget _body(AppPalette palette, MailMessage message, double viewportHeight) {
    if (_loadingBody) {
      // 转圈由页面浮在内容区正中（见 build），这里只把已有的预览文字先摆出来。
      if (message.body.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: _BodyLoading(preview: message.body),
      );
    }
    final html = message.htmlBody;
    if (html != null) {
      // 左右不留白：邮件按整屏宽设计，挤进边距里会被多缩一截。
      return LayoutBuilder(
        builder: (context, constraints) => MailHtmlView(
          html: html,
          viewportWidth: constraints.maxWidth,
          viewportHeight: viewportHeight,
          onTapUrl: _openUrl,
          onCoverChanged: _onBodyCoverChanged,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: SelectableText(
        message.body,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 16,
          height: 1.55,
        ),
      ),
    );
  }
}

/// 元信息 —— 收件人 / 主题 / 日期 / 附件条，都是原生组件，排在正文上方、同一条
/// 滚动条里（不再自带高度上限与内部滚动：整页一起滚，它自然会被滑走）。
class _MetaSection extends StatelessWidget {
  const _MetaSection({
    required this.message,
    required this.attachments,
    required this.expanded,
    required this.bytes,
    required this.busy,
    required this.onToggle,
    required this.onOpen,
    required this.onDownload,
  });

  final MailMessage message;
  final List<GraphAttachment> attachments;
  final bool expanded;
  final Map<String, Uint8List> bytes;
  final Set<String> busy;
  final VoidCallback onToggle;
  final ValueChanged<GraphAttachment> onOpen;
  final ValueChanged<GraphAttachment> onDownload;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RecipientRow(recipient: message.recipient),
          const SizedBox(height: 20),
          Text(
            message.subject,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message.fullDate,
            style: TextStyle(color: palette.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          if (attachments.isNotEmpty)
            _AttachmentSection(
              attachments: attachments,
              expanded: expanded,
              bytes: bytes,
              busy: busy,
              onToggle: onToggle,
              onOpen: onOpen,
              onDownload: onDownload,
            ),
        ],
      ),
    );
  }
}

/// 顶部：返回箭头 + 发件人名（加粗大字）+ 右侧收藏星标。
///
/// 现在是浮在正文上的一条浮层，故必须自带不透明底色。
class _Header extends StatelessWidget {
  const _Header({
    super.key,
    required this.title,
    required this.starred,
    required this.onStar,
  });

  final String title;
  final bool starred;
  final VoidCallback onStar;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ColoredBox(
      color: palette.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(AppIcons.back, color: palette.textPrimary, size: 20),
              splashRadius: 22,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: onStar,
              splashRadius: 22,
              icon: Icon(
                starred ? AppIcons.starFilled : AppIcons.starEmpty,
                color: starred ? palette.statusWarning : palette.textPrimary,
                size: 26,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 附件区 —— 摘要行（回形针 + 「N 个附件」+ 总大小 + 展开箭头），展开后列出各附件。
///
/// 视觉 1:1 参照「邮件详情-附件信息.jpg」（收起）与「邮件详情-附件预览.jpg」（展开）：
/// 图片附件出大图预览、底部半透明条压名字与大小；其余文件出「类型角标 + 名称 + 大小」一行。
/// 它在元信息里（见 [_MetaSection]），与正文同在页面那条滚动条中。
class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({
    required this.attachments,
    required this.expanded,
    required this.bytes,
    required this.busy,
    required this.onToggle,
    required this.onOpen,
    required this.onDownload,
  });

  final List<GraphAttachment> attachments;
  final bool expanded;
  final Map<String, Uint8List> bytes;
  final Set<String> busy;
  final VoidCallback onToggle;
  final ValueChanged<GraphAttachment> onOpen;
  final ValueChanged<GraphAttachment> onDownload;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    final total = attachments.fold<int>(0, (sum, a) => sum + a.size);
    final summaryStyle = TextStyle(
      color: palette.primary,
      fontSize: 16,
      fontWeight: FontWeight.w500,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(AppIcons.attach, size: 18, color: palette.textSecondary),
                const SizedBox(width: 8),
                Text(
                  l10n.detailAttachmentCount(attachments.length),
                  style: summaryStyle,
                ),
                const SizedBox(width: 10),
                Text(formatFileSize(total), style: summaryStyle),
                const Spacer(),
                // 字库里只有向下的 `v`，展开态转 180° —— 上下两态造型才一致。
                RotatedBox(
                  quarterTurns: expanded ? 2 : 0,
                  child: Icon(
                    AppIcons.chevronDown,
                    size: 24,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          for (final attachment in attachments)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: attachment.isImage
                  ? _ImageAttachmentCard(
                      attachment: attachment,
                      data: bytes[attachment.id],
                      loading: busy.contains(attachment.id),
                      onOpen: () => onOpen(attachment),
                      onDownload: () => onDownload(attachment),
                    )
                  : _FileAttachmentRow(
                      attachment: attachment,
                      loading: busy.contains(attachment.id),
                      onOpen: () => onOpen(attachment),
                      onDownload: () => onDownload(attachment),
                    ),
            ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// 图片附件卡片 —— 大图预览 + 底部半透明信息条（文件名 / 大小 / ⋮）。
///
/// 内容未取到时先占位：正在取转圈，取失败留图标（点一下会重试）。
class _ImageAttachmentCard extends StatelessWidget {
  const _ImageAttachmentCard({
    required this.attachment,
    required this.data,
    required this.loading,
    required this.onOpen,
    required this.onDownload,
  });

  final GraphAttachment attachment;
  final Uint8List? data;
  final bool loading;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final image = data;
    return GestureDetector(
      onTap: onOpen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            if (image != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Image.memory(
                  image,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              )
            else
              Container(
                height: 200,
                width: double.infinity,
                color: palette.card,
                child: Center(
                  child: loading
                      ? CupertinoActivityIndicator(
                          radius: 12,
                          color: palette.textSecondary,
                        )
                      : Icon(
                          AppIcons.image,
                          size: 32,
                          color: palette.textSecondary,
                        ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              // 压在图片上的信息条：图上文字只能用固定的半透明黑底 + 白字，
              // 与调色板无关（palette 里也没有这种 scrim 色）。
              child: Container(
                color: Colors.black.withValues(alpha: 0.45),
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatFileSize(attachment.size),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const Spacer(),
                    _AttachmentMenu(
                      color: Colors.white,
                      onOpen: onOpen,
                      onDownload: onDownload,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 非图片附件一行 —— 蓝色类型角标（TXT / PDF …）+ 文件名 + 大小 + ⋮。
class _FileAttachmentRow extends StatelessWidget {
  const _FileAttachmentRow({
    required this.attachment,
    required this.loading,
    required this.onOpen,
    required this.onDownload,
  });

  final GraphAttachment attachment;
  final bool loading;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: palette.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              attachment.extensionLabel,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textPrimary, fontSize: 17),
                ),
                const SizedBox(height: 2),
                Text(
                  formatFileSize(attachment.size),
                  style: TextStyle(color: palette.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
          if (loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CupertinoActivityIndicator(
                radius: 9,
                color: palette.textSecondary,
              ),
            )
          else
            _AttachmentMenu(
              color: palette.textPrimary,
              onOpen: onOpen,
              onDownload: onDownload,
            ),
        ],
      ),
    );
  }
}

/// 附件的「⋮」菜单 —— 打开 / 下载两项（设计稿里图片条与文件行右侧都是它）。
class _AttachmentMenu extends StatelessWidget {
  const _AttachmentMenu({
    required this.color,
    required this.onOpen,
    required this.onDownload,
  });

  /// 图标色 —— 压在图片上时给白色，普通行给主文本色。
  final Color color;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<int>(
      tooltip: l10n.actionMore,
      color: palette.background,
      surfaceTintColor: palette.background,
      icon: Icon(AppIcons.more, color: color, size: 20),
      onSelected: (value) => value == 0 ? onOpen() : onDownload(),
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        PopupMenuItem<int>(
          value: 0,
          child: Text(
            l10n.detailAttachmentOpen,
            style: TextStyle(color: palette.textPrimary, fontSize: 15),
          ),
        ),
        PopupMenuItem<int>(
          value: 1,
          child: Text(
            l10n.detailAttachmentDownload,
            style: TextStyle(color: palette.textPrimary, fontSize: 15),
          ),
        ),
      ],
    );
  }
}

/// 收件人行 —— `收件人：` 灰字 + 邮箱蓝色。
class _RecipientRow extends StatelessWidget {
  const _RecipientRow({required this.recipient});

  final String recipient;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          l10n.detailRecipient,
          style: TextStyle(color: palette.textSecondary, fontSize: 16),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$recipient;',
            style: TextStyle(
              color: palette.primary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// 正文懒取中已有的预览文字 —— 转圈不在这里：它由页面浮在**内容区正中**
/// （见 `_MessageDetailPageState.build`），跟在预览文字后面会贴着元信息、偏上一大截。
class _BodyLoading extends StatelessWidget {
  const _BodyLoading({required this.preview});

  final String preview;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Text(
      preview,
      style: TextStyle(
        color: palette.textSecondary,
        fontSize: 16,
        height: 1.55,
      ),
    );
  }
}

/// 底部操作栏 —— 回复 / 全部回复 / 转发 / 删除 / 更多。
class _ActionBar extends StatelessWidget {
  const _ActionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(color: palette.background),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ActionItem(icon: AppIcons.reply, label: l10n.actionReply),
          _ActionItem(icon: AppIcons.replyAll, label: l10n.actionReplyAll),
          _ActionItem(icon: AppIcons.forward, label: l10n.actionForward),
          _ActionItem(icon: AppIcons.delete, label: l10n.actionDelete),
          _ActionItem(icon: AppIcons.more, label: l10n.actionMore),
        ],
      ),
    );
  }
}

/// 单个底部操作 —— 竖排图标 + 文案。
class _ActionItem extends StatelessWidget {
  const _ActionItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: palette.textPrimary, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: palette.textPrimary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
