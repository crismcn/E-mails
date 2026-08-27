import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';

import '../data/mock_thread.dart';
import '../l10n/app_localizations.dart';
import '../models/mail.dart';
import '../theme/app_page_route.dart';
import '../theme/app_palette.dart';
import '../widgets/app_refresh.dart';
import 'message_detail_page.dart';

/// 邮件会话详情页 —— 从邮件列表项进入，以联系人对话方式展示邮件消息。
///
/// 约定：消息按时间正序排列（越早的在上），最近的一条完整展示，
/// 之前的消息简化展示（截断为预览）。视觉参照「邮件列表消息」设计稿。
class MailThreadPage extends StatefulWidget {
  const MailThreadPage({super.key, required this.mail});

  /// 被点开的邮件会话（提供发件人、未读数等）。
  final MailPreview mail;

  @override
  State<MailThreadPage> createState() => _MailThreadPageState();
}

class _MailThreadPageState extends State<MailThreadPage> {
  final ScrollController _scrollController = ScrollController();

  /// 每条消息对应的 [GlobalKey] —— 供「跳转到最新未读」精确定位。
  final Map<MailMessage, GlobalKey> _keys = <MailMessage, GlobalKey>{};

  late final List<MailMessage> _messages = mockThreadInitial(widget.mail);

  /// 已加载的历史页数（0 表示只有初始页）。
  int _historyPage = 0;

  bool get _hasMoreHistory => _historyPage < kMockThreadHistoryPages;

  /// 最新一条未读消息的下标；无未读时为 -1。
  int get _latestUnreadIndex => _messages.lastIndexWhere((m) => m.unread);

  GlobalKey _keyFor(MailMessage message) =>
      _keys.putIfAbsent(message, () => GlobalKey());

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 下拉加载更早的历史消息 —— 整页插入列表头部以保持时间正序。
  Future<IndicatorResult> _onLoadHistory() async {
    if (!_hasMoreHistory) return IndicatorResult.noMore;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return IndicatorResult.success;
    setState(() {
      _historyPage += 1;
      _messages.insertAll(0, mockThreadHistory(widget.mail, _historyPage));
    });
    return _hasMoreHistory ? IndicatorResult.success : IndicatorResult.noMore;
  }

  /// 点击未读胶囊 —— 滚动到最新一条未读消息。
  Future<void> _jumpToLatestUnread() async {
    final index = _latestUnreadIndex;
    if (index < 0) return;
    final target = _messages[index];
    // 目标已在可视区附近构建：直接精确对齐到视口靠上位置。
    final built = _keyFor(target).currentContext;
    if (built != null) {
      await Scrollable.ensureVisible(
        built,
        alignment: 0.05,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      return;
    }
    // 目标已滚出可视区（尚未构建）：先按比例滚过去，再精确对齐。
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    var estimate = maxExtent * (index / _messages.length);
    if (estimate < 0) estimate = 0;
    if (estimate > maxExtent) estimate = maxExtent;
    await _scrollController.animateTo(
      estimate,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    if (!mounted) return;
    final ctx = _keyFor(target).currentContext;
    if (ctx == null || !ctx.mounted) return;
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.05,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final unread = widget.mail.unread;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(title: widget.mail.sender),
            Expanded(
              child: Stack(
                children: [
                  EasyRefresh(
                    header: appHistoryHeader(),
                    onRefresh: _onLoadHistory,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        return _MessageItem(
                          key: _keyFor(message),
                          message: message,
                          // 最近一条详细展示，其余简化展示。
                          detailed: index == _messages.length - 1,
                        );
                      },
                    ),
                  ),
                  // 未读胶囊常驻底部居中（浮于列表之上），点击跳到最新未读。
                  if (unread > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: Center(
                        child: _UnreadPill(
                          count: unread,
                          onTap: _jumpToLatestUnread,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const _ReplyBar(),
          ],
        ),
      ),
    );
  }
}

/// 顶部标题 —— 返回箭头 + 联系人名（加粗大字）。
class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 10),
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
        ],
      ),
    );
  }
}

/// 单条消息 —— 左侧头像 + 右侧（发件人/时间 + 气泡）。
class _MessageItem extends StatelessWidget {
  const _MessageItem({
    super.key,
    required this.message,
    required this.detailed,
  });

  final MailMessage message;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(sender: message.sender),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 发件人名（左，未读时带蓝点） + 时间（右）。
                Padding(
                  padding: const EdgeInsets.only(right: 2, bottom: 8),
                  child: Row(
                    children: [
                      if (message.unread) ...[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: palette.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          message.sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        message.time,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _Bubble(
                  body: message.body,
                  detailed: detailed,
                  onTap: () => Navigator.of(context).push(
                    appRoute<void>((_) => MessageDetailPage(message: message)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 圆形头像 —— 依发件人稳定取色 + 首字母（与邮件列表一致）。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.sender});

  final String sender;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: mailAvatarColor(sender),
        shape: BoxShape.circle,
      ),
      child: Text(
        mailAvatarInitial(sender),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 消息气泡 —— 浅灰圆角。详细展示完整正文，简化展示截断为 2 行。点击进入详情。
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.body,
    required this.detailed,
    required this.onTap,
  });

  final String body;
  final bool detailed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              body,
              maxLines: detailed ? null : 2,
              overflow: detailed ? TextOverflow.clip : TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                height: 1.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 未读胶囊 —— 蓝底白字，向上箭头 +「N 封未读」；点击跳到最新未读消息。
class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Material(
      color: palette.primary,
      borderRadius: BorderRadius.circular(100),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.keyboard_arrow_up,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                l10n.threadUnread(count),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部回复栏 —— 胶囊输入框 +「+」+ 发送。
class _ReplyBar extends StatelessWidget {
  const _ReplyBar();

  static const BorderRadius _pillRadius = BorderRadius.all(
    Radius.circular(100),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              style: TextStyle(color: palette.textPrimary, fontSize: 14),
              cursorColor: palette.primary,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: palette.card,
                hintText: l10n.mailReplyHint,
                hintStyle: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                border: const OutlineInputBorder(
                  borderRadius: _pillRadius,
                  borderSide: BorderSide.none,
                ),
                enabledBorder: const OutlineInputBorder(
                  borderRadius: _pillRadius,
                  borderSide: BorderSide.none,
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: _pillRadius,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: Icon(
              Icons.add_circle_outline,
              color: palette.textSecondary,
              size: 30,
            ),
            splashRadius: 22,
          ),
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.send_outlined, color: palette.primary, size: 24),
            splashRadius: 22,
          ),
        ],
      ),
    );
  }
}
