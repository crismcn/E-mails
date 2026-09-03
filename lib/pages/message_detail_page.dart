import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
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

/// 邮件消息详情页 —— 从邮件列表点击某封邮件进入，展示完整详情。
///
/// 正文支持 HTML 渲染（[MailMessage.htmlBody] 非空时），否则按纯文本渲染；
/// HTML 中的超链接 / 按钮链接点击后用外部浏览器打开。
///
/// **结构：正文恒定铺满真实全屏，三条 chrome 浮在它上面。**
/// `Stack` 最底层是 `Positioned.fill` 的正文（WebView / 纯文本），铺满整屏含状态栏与
/// 底部安全区 —— **从头到尾不移动、不改尺寸**。顶栏（状态栏底色 + 返回 + 发件人 + 星标）、
/// 元信息（收件人 / 主题 / 日期 / 附件摘要）、底部操作栏是三层浮层。
///
/// 正文起头处留出 `顶栏高 + 元信息高` 的空白（HTML 走文档 CSS 的 `padding-top`，
/// 纯文本走 `SingleChildScrollView.padding`），于是「页面整体上移」= 正文自己往上滚这段
/// 空白，**平台视图一次都不用动** —— 历史上「量高撑盒子 / 收放改尺寸」那条重排回路
/// （病根：改尺寸 → 重排 → 吐出新偏移 → 又驱动收放）在结构上不存在了。
///
/// **三条浮层分两类，收放时机不同**：
/// - **元信息是「内容级」**：`dy = -min(y, 顶栏高 + 元信息高)`，随正文 **1:1 跟手**上移直到
///   出画。它的下边缘恒等于正文那段留白的末端（两者都是 `顶栏+元信息-y`），所以任何时刻
///   都压不到正文文字 —— 这也是它必须跟手、不能做成整条动画的原因。
/// - **顶栏 / 底栏是「chrome 级」**：按**滑动方向**整条切入切出（[_kBarsDuration]），只有
///   「全在 / 全出」两态，**中途绝不出现半截栏**（半截栏 + OS 状态栏文字叠在一起最难看）。
///   上滑累计 [_kBarsHideSlop] 收起、回滑 [_kBarsShowSlop] 展开、正文回到顶部强制全在，
///   见 [_updateBars]。好处是读到邮件中段也能回滑一点把底部操作栏叫回来，不必先滚回顶部。
///
/// 正文起始位置到达 y=0 时元信息正好出画、WebView 就是真实全屏，正文在里面继续滚 /
/// 双指缩放。
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

  // ---- 浮层位移 ----

  /// 正文当前滚动偏移（逻辑像素）—— 元信息那条浮层的唯一输入，也是顶 / 底栏方向判定的输入。
  ///
  /// 刻意用 `ValueNotifier` + `AnimatedBuilder` 而不是 `setState`：`setState` 会重建
  /// 整棵子树、把正文 WebView 带着重排。这里只让那几层浮层各自重绘一个
  /// `Transform.translate`（绘制期变换，不触发布局）。
  final ValueNotifier<double> _bodyY = ValueNotifier<double>(0);

  /// 越界回弹会报负偏移，夹掉 —— 否则元信息会被推到比原位更低的地方、露出一条背景。
  double get _scrolled {
    final y = _bodyY.value;
    return y > 0 ? y : 0;
  }

  /// 顶栏 / 底栏整条切入切出的时长。
  static const Duration _kBarsDuration = Duration(milliseconds: 220);

  /// 正文偏移小于这个值就当「在顶部」—— 顶 / 底栏一律全在，不看方向。
  static const double _kBarsPinTop = 4;

  /// 收起 / 展开各自要求的最小回滑距离（逻辑像素）。
  ///
  /// **刻意不对称**：收起要求 24（多一点「确实想往下读」的意图，免得手抖一下整条就跑了），
  /// 展开只要 12（想点回复 / 删除时要立刻能叫回来）。两者都比一次回弹的抖动大 ——
  /// 这层 slop 就是历史上那类「回弹被误判成反向 → 刚收起又弹回来」的闸门。
  static const double _kBarsHideSlop = 24;
  static const double _kBarsShowSlop = 12;

  /// 顶栏 / 底栏的收起进度：0 = 全在，1 = 全出。
  late final AnimationController _barsCtrl = AnimationController(
    vsync: this,
    duration: _kBarsDuration,
  );

  /// 上面那条加了缓动 —— 切入切出各用一半的缓动方向，观感与系统导航栏一致。
  late final Animation<double> _bars = CurvedAnimation(
    parent: _barsCtrl,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  bool _barsHidden = false;

  /// 方向判定的锚点 —— **当前方向的极值**（展开态记最小 y、收起态记最大 y）。
  /// 记极值而不是「上一次的 y」，slop 才是真的「回滑了这么多」，不会被逐帧小增量磨掉。
  double _dirAnchor = 0;

  // 三条 chrome 的实测高度：顶栏（含状态栏）/ 元信息（含附件摘要行，不含展开的附件列表）
  // / 底栏（含底部安全区）。正文的上下留白就是它们，故必须先量准再建正文。
  final GlobalKey _topKey = GlobalKey();
  final GlobalKey _metaKey = GlobalKey();
  final GlobalKey _bottomKey = GlobalKey();

  double _topH = 0;
  double _metaH = 0;
  double _bottomH = 0;

  /// 正文的上下留白已经量准、可以建正文了。
  ///
  /// 量高与建正文有先后：留白写进 HTML 文档（改了就得重载），所以**元信息内容一变就
  /// 置 false**，等下一帧量完再放行 —— 全程只在转圈底下发生，看不见。
  bool _bodyReady = false;

  /// 正文起始处的留白 = 顶栏 + 元信息。
  double get _bodyTopPad => _topH + _metaH;

  /// 纯文本正文的滚动控制器（HTML 正文的滚动由 WebView 内部管理）。
  final ScrollController _textScroll = ScrollController();

  // ---- 懒取与生命周期 ----

  @override
  void initState() {
    super.initState();
    _textScroll.addListener(_onTextScroll);
    if (widget.message.id.isNotEmpty && widget.message.htmlBody == null) {
      _loadingBody = true;
    }
    _spinner = AnimationController(
      vsync: this,
      duration: MailHtmlView.kRevealDuration,
      value: _loadingBody || widget.message.htmlBody != null ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _textScroll.dispose();
    _bodyY.dispose();
    _barsCtrl.dispose();
    _spinner.dispose();
    super.dispose();
  }

  // ---- 量 chrome 高度 ----

  /// 每帧末量一次三条浮层的实高（字号 / 主题 / 转屏 / 附件出现都会改变它）。
  ///
  /// 只在真的变了时 `setState` —— 否则每帧一次重建。
  void _measureChrome() {
    if (!mounted) return;
    final top = _heightOf(_topKey) ?? _topH;
    final meta = _heightOf(_metaKey) ?? _metaH;
    final bottom = _heightOf(_bottomKey) ?? _bottomH;
    if (_bodyReady && top == _topH && meta == _metaH && bottom == _bottomH) {
      return;
    }
    setState(() {
      _topH = top;
      _metaH = meta;
      _bottomH = bottom;
      _bodyReady = true;
    });
    if (kDebugMode) {
      debugPrint(
        '[MessageDetail] chrome 实测 top=${top.toStringAsFixed(1)} '
        'meta=${meta.toStringAsFixed(1)} bottom=${bottom.toStringAsFixed(1)} '
        '→ 正文留白 top=${_bodyTopPad.toStringAsFixed(1)}',
      );
    }
  }

  static double? _heightOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : null;
  }

  // ---- 正文滚动 → 浮层位移（HTML 与纯文本统一入口）----

  void _onBodyScroll(double y) {
    _bodyY.value = y;
    _updateBars(y);
  }

  /// 顶栏 / 底栏的收放判定 —— 按**滑动方向**整条切入切出。
  ///
  /// 锚点 [_dirAnchor] 记的是**当前方向的极值**：展开态一路记最小 y（往下读时被 y 推着走），
  /// 于是「y - 锚点」就是这一次连续上滑的净距离，够 [_kBarsHideSlop] 才收；收起态反过来记
  /// 最大 y，「锚点 - y」够 [_kBarsShowSlop] 才展开。极值锚点是关键 —— 若锚点记「上一次的
  /// y」，逐帧的小增量会把 slop 磨成 0，回弹抖动照样能翻转它（历史上就是这么抖的）。
  void _updateBars(double y) {
    // 正文回到顶部：一律全在，不看方向（此刻元信息也正好回位，观感是三条一起就位）。
    if (y <= _kBarsPinTop) {
      _dirAnchor = y;
      _setBarsHidden(false);
      return;
    }
    if (_barsHidden) {
      if (y > _dirAnchor) {
        _dirAnchor = y; // 继续往下读，把极值跟上。
      } else if (_dirAnchor - y >= _kBarsShowSlop) {
        _dirAnchor = y;
        _setBarsHidden(false);
      }
    } else {
      if (y < _dirAnchor) {
        _dirAnchor = y;
      } else if (y - _dirAnchor >= _kBarsHideSlop) {
        _dirAnchor = y;
        _setBarsHidden(true);
      }
    }
  }

  void _setBarsHidden(bool hidden) {
    if (hidden == _barsHidden) return;
    _barsHidden = hidden;
    if (kDebugMode) {
      debugPrint(
        '[MessageDetail] 顶/底栏 ${hidden ? '收起' : '展开'} '
        '@ y=${_bodyY.value.toStringAsFixed(1)}',
      );
    }
    if (hidden) {
      _barsCtrl.forward();
    } else {
      _barsCtrl.reverse();
    }
  }

  void _onTextScroll() {
    if (!_textScroll.hasClients) return;
    _onBodyScroll(_textScroll.offset);
  }

  // ---- 懒取正文 ----

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadingBody) _fetchBody();
  }

  /// 懒取全文 **+ 附件列表**，两段合成一次等待、一次 `setState`。
  ///
  /// 刻意不分两次落地：附件摘要行属于元信息，元信息一高一低就得改正文文档的内边距
  /// （= 重载 WebView）。合起来等，只在同一个转圈底下发生一次（CLAUDE.md §4.7）。
  Future<void> _fetchBody() async {
    final mail = ApiScope.of(context).mail;
    final res = await mail.getMessage(widget.accountEmail, widget.message.id);
    if (!mounted) return;

    var next = _message;
    if (res.isSuccess && res.data != null) {
      next = applyBody(mailMessageFromGraph(res.data!), res.data!);
    }

    var attachments = const <GraphAttachment>[];
    if (res.isSuccess && (res.data?.hasAttachments ?? false)) {
      final list = await mail.listAttachments(widget.accountEmail, next.id);
      if (!mounted) return;
      if (list.isSuccess) {
        attachments = (list.data ?? const <GraphAttachment>[])
            .where((a) => !a.isInline)
            .toList();
      }
    }

    setState(() {
      _message = next;
      _starred = next.isFlagged;
      _attachments = attachments;
      _loadingBody = false;
      // 元信息内容变了 → 留白要重量，量准前不建正文（免得建完又重载）。
      _bodyReady = false;
    });
    if (_message.htmlBody == null) _spinner.reverse();
  }

  void _toggleAttachments() {
    final next = !_attachExpanded;
    setState(() => _attachExpanded = next);
    if (!next) return;
    for (final a in _attachments) {
      if (a.isImage) _ensureBytes(a);
    }
  }

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

  Future<void> _openAttachment(GraphAttachment attachment) async {
    final bytes = await _ensureBytes(attachment);
    if (bytes == null || !mounted) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeFileName(attachment.name)}');
    await file.writeAsBytes(bytes, flush: true);
    final result = await OpenFilex.open(
      file.path,
      type: attachment.contentType.isEmpty ? null : attachment.contentType,
    );
    if (!mounted || result.type == ResultType.done) return;
    _toast(AppLocalizations.of(context).detailAttachmentOpenFallback);
    await _downloadAttachment(attachment);
  }

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
    if (!mounted || saved == null) return;
    _toast(AppLocalizations.of(context).detailAttachmentSaved(attachment.name));
  }

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

  // ---- 星标 ----

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

  void _onBodyCoverChanged(bool covered) {
    if (!mounted) return;
    if (covered) {
      // 重新加载文档（首次进入 / 换主题）会把 WebView 的滚动归零，浮层跟着回位，
      // 否则会停在「已收起」的位置上，而正文其实已经回到起点。
      _bodyY.value = 0;
      _dirAnchor = 0;
      _barsHidden = false;
      _barsCtrl.value = 0;
      _spinner.value = 1;
    } else {
      _spinner.reverse();
    }
  }

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

  // ---- 构建 ----

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final message = _message;
    final statusBarTop = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // 三条浮层的实高帧末量一次（只在变了时 setState，见 [_measureChrome]）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureChrome());
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          // ① 正文 —— 恒定铺满真实全屏（含状态栏 / 底部安全区），永不移动、永不改尺寸。
          Positioned.fill(child: _body(palette, message)),
          // ② 元信息 —— 贴在正文起始处之上，随正文 1:1 上移直到移出屏幕。
          _floating(
            top: _topH,
            animation: _bodyY,
            offset: () => -math.min(_scrolled, _bodyTopPad),
            child: Column(
              key: const Key('detail-meta'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _MetaBlock(
                  key: _metaKey,
                  message: message,
                  attachments: _attachments,
                  expanded: _attachExpanded,
                  onToggle: _toggleAttachments,
                ),
                // 展开的附件列表**不计入留白**（否则一展开就得重载正文），
                // 直接盖在正文上，自带底色与内部滚动。
                if (_attachExpanded && _attachments.isNotEmpty)
                  _AttachmentPanel(
                    attachments: _attachments,
                    bytes: _attachBytes,
                    busy: _attachBusy,
                    onOpen: _openAttachment,
                    onDownload: _downloadAttachment,
                  ),
              ],
            ),
          ),
          // ③ 顶栏 —— 状态栏底色 + 返回 + 发件人 + 星标，按滑动方向整条切出 / 切入。
          _floating(
            top: 0,
            animation: _bars,
            offset: () => -_topH * _bars.value,
            child: KeyedSubtree(
              key: const Key('detail-top-bar'),
              child: ColoredBox(
                key: _topKey,
                color: palette.background,
                child: Padding(
                  padding: EdgeInsets.only(top: statusBarTop),
                  child: _Header(
                    title: message.sender,
                    starred: _starred,
                    onStar: _toggleStar,
                  ),
                ),
              ),
            ),
          ),
          // ④ 底部操作栏 —— 与顶栏同进同出。
          _floating(
            bottom: 0,
            animation: _bars,
            offset: () => _bottomH * _bars.value,
            child: KeyedSubtree(
              key: const Key('detail-bottom-bar'),
              child: ColoredBox(
                key: _bottomKey,
                color: palette.background,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  child: const _ActionBar(),
                ),
              ),
            ),
          ),
          // ⑤ 正文还看不到时的转圈 —— 浮在屏幕正中，懒取与渲染共用同一个。
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
        ],
      ),
    );
  }

  /// 一条会平移的浮层 —— `Transform.translate` 是**绘制期**变换，不触发布局，底下的
  /// WebView 一格都不会重排。
  ///
  /// [animation] 是驱动源（元信息用正文偏移 `_bodyY`，顶 / 底栏用 `_bars` 那条动画），
  /// [offset] 每帧算一次 y 方向的位移。
  Widget _floating({
    double? top,
    double? bottom,
    required Listenable animation,
    required double Function() offset,
    required Widget child,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, inner) =>
            Transform.translate(offset: Offset(0, offset()), child: inner),
        child: child,
      ),
    );
  }

  /// 正文 —— 铺满整屏，起头处留出 `顶栏 + 元信息` 的空白，收尾留出底栏的高度。
  ///
  /// HTML 交给 [MailHtmlView]（留白写进文档 CSS）；纯文本走 `SingleChildScrollView`
  /// （留白写进 `padding`），两条路的滚动偏移都汇到 [_onBodyScroll]。
  Widget _body(AppPalette palette, MailMessage message) {
    // 留白还没量准就先不建 —— 建了就得按错的内边距重载一次（只差一帧，转圈盖着）。
    if (_loadingBody || !_bodyReady) return const SizedBox.shrink();
    final html = message.htmlBody;
    if (html != null) {
      return LayoutBuilder(
        builder: (context, constraints) => MailHtmlView(
          html: html,
          viewportWidth: constraints.maxWidth,
          topPadding: _bodyTopPad,
          bottomPadding: _bottomH,
          onTapUrl: _openUrl,
          onScroll: _onBodyScroll,
          onCoverChanged: _onBodyCoverChanged,
        ),
      );
    }
    return SingleChildScrollView(
      controller: _textScroll,
      padding: EdgeInsets.fromLTRB(20, _bodyTopPad, 20, _bottomH + 24),
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

// =====================================================================
// 以下私有组件：_Header / _MetaBlock / _AttachmentSummary /
// _AttachmentPanel / _ImageAttachmentCard / _FileAttachmentRow /
// _AttachmentMenu / _RecipientRow / _ActionBar / _ActionItem
// =====================================================================

/// 顶部：返回箭头 + 发件人名（加粗大字）+ 右侧收藏星标。
class _Header extends StatelessWidget {
  const _Header({
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
    return Padding(
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
    );
  }
}

/// 元信息 —— 收件人 / 主题 / 日期 + 附件摘要行。**这块的高度就是正文起始处的留白**
/// （连同顶栏），所以展开的附件列表刻意不在这里（见 [_AttachmentPanel]）。
///
/// 文字部分包 `IgnorePointer`：底下就是铺满整屏的正文，让开命中测试后在这片区域按下
/// 也能滚正文 —— 否则顶上一大条按下去毫无反应。附件摘要行要点，故留在外面。
class _MetaBlock extends StatelessWidget {
  const _MetaBlock({
    super.key,
    required this.message,
    required this.attachments,
    required this.expanded,
    required this.onToggle,
  });

  final MailMessage message;
  final List<GraphAttachment> attachments;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IgnorePointer(
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
              ],
            ),
          ),
          if (attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _AttachmentSummary(
                attachments: attachments,
                expanded: expanded,
                onToggle: onToggle,
              ),
            ),
        ],
      ),
    );
  }
}

/// 附件摘要行 —— 回形针 + 「N 个附件」+ 总大小 + 展开箭头。
class _AttachmentSummary extends StatelessWidget {
  const _AttachmentSummary({
    required this.attachments,
    required this.expanded,
    required this.onToggle,
  });

  final List<GraphAttachment> attachments;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    final total = attachments.fold<int>(0, (sum, a) => sum + a.size);
    final style = TextStyle(
      color: palette.primary,
      fontSize: 16,
      fontWeight: FontWeight.w500,
    );
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(AppIcons.attach, size: 18, color: palette.textSecondary),
            const SizedBox(width: 8),
            Text(l10n.detailAttachmentCount(attachments.length), style: style),
            const SizedBox(width: 10),
            Text(formatFileSize(total), style: style),
            const Spacer(),
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
    );
  }
}

/// 展开后的附件列表 —— **浮在正文上**，不计入正文留白。
///
/// 计入留白的话，一展开就得改文档内边距 = 重载 WebView（白闪 + 滚动归零）。它是一块
/// 主动展开的披露面板，盖住正文是应有之义；自身太高时内部滚动，不至于顶穿屏幕。
class _AttachmentPanel extends StatelessWidget {
  const _AttachmentPanel({
    required this.attachments,
    required this.bytes,
    required this.busy,
    required this.onOpen,
    required this.onDownload,
  });

  final List<GraphAttachment> attachments;
  final Map<String, Uint8List> bytes;
  final Set<String> busy;
  final ValueChanged<GraphAttachment> onOpen;
  final ValueChanged<GraphAttachment> onDownload;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ColoredBox(
      color: palette.background,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.45,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
            ],
          ),
        ),
      ),
    );
  }
}

/// 图片附件卡片 —— 大图预览 + 底部半透明信息条（文件名 / 大小 / ⋮）。
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

/// 附件的「⋮」菜单 —— 打开 / 下载两项。
class _AttachmentMenu extends StatelessWidget {
  const _AttachmentMenu({
    required this.color,
    required this.onOpen,
    required this.onDownload,
  });

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

/// 底部操作栏 —— 回复 / 全部回复 / 转发 / 删除 / 更多。
///
/// 底色与底部安全区由外层那条浮层给（见 `_MessageDetailPageState.build`）。
class _ActionBar extends StatelessWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
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