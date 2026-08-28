import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_scope.dart';
import '../data/mail_mapper.dart';
import '../l10n/app_localizations.dart';
import '../models/mail.dart';
import '../theme/app_palette.dart';

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
  bool _starred = false;

  /// 当前展示的消息（懒取全文后会被替换为带 body/htmlBody 的版本）。
  late MailMessage _message = widget.message;

  /// 正文懒取中 —— 尚无全文时展示占位转圈。
  bool _loadingBody = false;

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
    final res = await ApiScope.of(
      context,
    ).mail.getMessage(widget.accountEmail, widget.message.id);
    if (!mounted) return;
    setState(() {
      if (res.isSuccess && res.data != null) {
        // 用取回的全文整体重建 —— 列表项只带发件人/主题占位，收件人、完整日期、
        // 正文都以权威的 getMessage 结果为准。
        _message = applyBody(mailMessageFromGraph(res.data!), res.data!);
      }
      _loadingBody = false;
    });
  }

  /// 打开正文中的链接（超链接 / 按钮）—— 外部浏览器，失败时提示。
  Future<bool> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              title: message.sender,
              starred: _starred,
              onStar: () => setState(() => _starred = !_starred),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_loadingBody)
                      _BodyLoading(preview: message.body)
                    else
                      _Body(message: message, onTapUrl: _openUrl),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: palette.textPrimary, size: 20),
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
              starred ? Icons.star : Icons.star_border,
              color: starred ? palette.statusWarning : palette.textPrimary,
              size: 26,
            ),
          ),
        ],
      ),
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

/// 正文 —— HTML 优先渲染（含链接点击），否则纯文本。
class _Body extends StatelessWidget {
  const _Body({required this.message, required this.onTapUrl});

  final MailMessage message;
  final Future<bool> Function(String) onTapUrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final html = message.htmlBody;
    if (html != null) {
      return HtmlWidget(
        html,
        onTapUrl: onTapUrl,
        textStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 16,
          height: 1.55,
        ),
      );
    }
    return SelectableText(
      message.body,
      style: TextStyle(color: palette.textPrimary, fontSize: 16, height: 1.55),
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
          _ActionItem(icon: Icons.reply_outlined, label: l10n.actionReply),
          _ActionItem(
            icon: Icons.reply_all_outlined,
            label: l10n.actionReplyAll,
          ),
          _ActionItem(icon: Icons.forward_outlined, label: l10n.actionForward),
          _ActionItem(icon: Icons.delete_outline, label: l10n.actionDelete),
          _ActionItem(icon: Icons.more_vert, label: l10n.actionMore),
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
