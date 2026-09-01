import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
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

class _MessageDetailPageState extends State<MessageDetailPage> {
  late bool _starred = widget.message.isFlagged;

  /// 标星写回进行中 —— 去重，避免连点发出多次 PATCH。
  bool _flagBusy = false;

  /// 当前展示的消息（懒取全文后会被替换为带 body/htmlBody 的版本）。
  late MailMessage _message = widget.message;

  /// 正文懒取中 —— 尚无全文时展示占位转圈。
  bool _loadingBody = false;

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
  // `Column`：**固定**的返回栏 / 元信息与正文同在一条滚动条里 / **固定**的底部操作栏。
  //
  // 返回栏与底部操作栏**不再随滑动收起**（用户要求）。收起过 —— 无论压高度还是浮层
  // 平移 —— 都会改变正文区尺寸或滚动几何，而正文是个 WebView：一改尺寸就重排、
  // 重排又吐新的滚动偏移去驱动收放，形成正反馈，表现为「全屏状态来回跳动」。
  // 不收起就没有这条回路。

  @override
  void initState() {
    super.initState();
    // 无全文（htmlBody/body 皆空）且有 id → 懒取。会话预览的 body 可能已含摘要，
    // 但为拿到完整 HTML/纯文本仍以 id 取一次权威全文。
    if (widget.message.id.isNotEmpty && widget.message.htmlBody == null) {
      _loadingBody = true;
    }
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
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              title: message.sender,
              starred: _starred,
              onStar: _toggleStar,
            ),
            // 整页一条滚动条：收件人 / 主题 / 日期 / 附件 / 正文一起上滑。
            Expanded(
              child: SingleChildScrollView(
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
                    _body(palette, message),
                  ],
                ),
              ),
            ),
            const _ActionBar(),
          ],
        ),
      ),
    );
  }

  /// 正文 —— 排在页面那条滚动条里，与上方元信息一起滚。
  ///
  /// HTML 交给 [MailHtmlView]：**按页内量到的高度占位、自己不滚**，双指在这块固定
  /// 高度里缩放 + 平移。纯文本仍是 Flutter 的可选择文本。
  Widget _body(AppPalette palette, MailMessage message) {
    if (_loadingBody) {
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
          onTapUrl: _openUrl,
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

/// 正文懒取中 —— 先展示已有预览文字 + 一行转圈，避免整页空白。
class _BodyLoading extends StatelessWidget {
  const _BodyLoading({required this.preview});

  final String preview;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preview.isNotEmpty)
          Text(
            preview,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 16,
              height: 1.55,
            ),
          ),
        const SizedBox(height: 16),
        Center(
          child: CupertinoActivityIndicator(
            radius: 12,
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// 底部操作栏 —— 回复 / 全部回复 / 转发 / 删除 / 更多。
class _ActionBar extends StatelessWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.divider, width: 1)),
      ),
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
