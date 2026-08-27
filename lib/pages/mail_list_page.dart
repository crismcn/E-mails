import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../data/mock_mails.dart';
import '../l10n/app_localizations.dart';
import '../models/mail.dart';
import '../theme/app_page_route.dart';
import '../theme/app_palette.dart';
import '../widgets/app_refresh.dart';
import '../widgets/mail_tile.dart';
import 'mail_thread_page.dart';

/// 邮件列表页 —— 从首页某个邮箱账号进入，展示该账号的邮件。
class MailListPage extends StatefulWidget {
  const MailListPage({super.key, required this.accountEmail});

  /// 顶部标题展示的账号邮箱。
  final String accountEmail;

  @override
  State<MailListPage> createState() => _MailListPageState();
}

class _MailListPageState extends State<MailListPage> {
  /// 模拟分页：共 3 页，加载完即无更多。
  static const int _maxPages = 3;

  final List<MailPreview> _items = List<MailPreview>.of(kMockMails);
  String _query = '';
  int _page = 1;

  bool get _hasMore => _page < _maxPages;

  /// 上次刷新完成时间（下拉刷新头显示）。
  DateTime _lastUpdated = DateTime.now();

  List<MailPreview> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items
        .where(
          (m) =>
              m.sender.toLowerCase().contains(q) ||
              m.subject.toLowerCase().contains(q),
        )
        .toList();
  }

  /// 下拉刷新 —— 重置为初始邮件、重置分页并记录刷新时间。
  Future<void> _onRefresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(kMockMails);
      _page = 1;
      _lastUpdated = DateTime.now();
    });
  }

  /// 上滑加载更多 —— 追加下一页；加载完返回 [IndicatorResult.noMore]。
  Future<IndicatorResult> _onLoad() async {
    if (!_hasMore) return IndicatorResult.noMore;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return IndicatorResult.success;
    setState(() {
      _items.addAll(_generatePage(_page));
      _page += 1;
    });
    return _hasMore ? IndicatorResult.success : IndicatorResult.noMore;
  }

  /// 生成第 [page] 页的模拟邮件（各项唯一，供 [ObjectKey] 区分）。
  List<MailPreview> _generatePage(int page) {
    return [
      for (final m in kMockMails)
        m.copyWith(sender: '${m.sender} #$page', unread: 0),
    ];
  }

  /// 左滑动作：归档（移动）。
  void _archive(MailPreview mail) {
    final l10n = AppLocalizations.of(context);
    setState(() => _items.remove(mail));
    _toast(l10n.mailArchived);
  }

  /// 左滑动作：标记已读 / 未读（切换）。
  void _toggleRead(MailPreview mail) {
    final l10n = AppLocalizations.of(context);
    final index = _items.indexOf(mail);
    if (index < 0) return;
    final markRead = mail.unread > 0;
    setState(() => _items[index] = mail.copyWith(unread: markRead ? 0 : 1));
    _toast(markRead ? l10n.mailMarkedRead : l10n.mailMarkedUnread);
  }

  /// 左滑动作：删除。
  void _delete(MailPreview mail) {
    final l10n = AppLocalizations.of(context);
    setState(() => _items.remove(mail));
    _toast(l10n.mailDeleted);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: palette.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        child: const Icon(Icons.add, size: 28),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(title: widget.accountEmail),
            const SizedBox(height: 8),
            _SearchBox(onChanged: (v) => setState(() => _query = v)),
            const SizedBox(height: 8),
            Expanded(
              child: _MailList(
                mails: _filtered,
                lastUpdated: _lastUpdated,
                onRefresh: _onRefresh,
                onLoad: _onLoad,
                onArchive: _archive,
                onToggleRead: _toggleRead,
                onDelete: _delete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部标题 —— 左侧返回箭头 + 账号邮箱（加粗大字）。
class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(
              Icons.arrow_back,
              color: palette.textPrimary,
              size: 20,
            ),
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

// __SEARCHBOX__
/// 搜索框 —— 胶囊形（两端半圆），按发件人/主题过滤。
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onChanged});

  final ValueChanged<String> onChanged;

  static const BorderRadius _pillRadius = BorderRadius.all(
    Radius.circular(100),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: TextField(
        onChanged: onChanged,
        style: TextStyle(color: palette.textPrimary, fontSize: 14),
        cursorColor: palette.primary,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: palette.card,
          hintText: l10n.mailSearchHint,
          hintStyle: TextStyle(color: palette.textSecondary, fontSize: 14),
          prefixIcon: Icon(
            Icons.search,
            color: palette.textSecondary,
            size: 19,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 0,
          ),
          contentPadding: const EdgeInsets.fromLTRB(4, 7, 12, 7),
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
    );
  }
}

class _MailList extends StatelessWidget {
  const _MailList({
    required this.mails,
    required this.lastUpdated,
    required this.onRefresh,
    required this.onLoad,
    required this.onArchive,
    required this.onToggleRead,
    required this.onDelete,
  });

  final List<MailPreview> mails;
  final DateTime lastUpdated;
  final Future<void> Function() onRefresh;
  final Future<IndicatorResult> Function() onLoad;
  final ValueChanged<MailPreview> onArchive;
  final ValueChanged<MailPreview> onToggleRead;
  final ValueChanged<MailPreview> onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EasyRefresh(
      header: appRefreshHeader(lastUpdated),
      footer: appLoadFooter(),
      onRefresh: onRefresh,
      onLoad: onLoad,
      child: SlidableAutoCloseBehavior(
        child: ListView.separated(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          itemCount: mails.length,
          separatorBuilder: (context, index) => Divider(
            color: palette.divider,
            height: 1,
            thickness: 1,
            // 左侧缩进对齐发件人文字（头像 50 + 间距 14 + 外边距 20）。
            indent: 84,
            endIndent: 20,
          ),
          itemBuilder: (context, index) {
            final mail = mails[index];
            return Slidable(
              key: ObjectKey(mail),
              endActionPane: ActionPane(
                motion: const ScrollMotion(),
                extentRatio: 0.62,
                children: [
                  _SwipeAction(
                    color: const Color(0xFF34C759),
                    icon: Icons.drive_file_move_outlined,
                    onPressed: () => onArchive(mail),
                  ),
                  _SwipeAction(
                    color: const Color(0xFF2F80FF),
                    icon: Icons.mark_email_unread_outlined,
                    onPressed: () => onToggleRead(mail),
                  ),
                  _SwipeAction(
                    color: const Color(0xFFFF4D4F),
                    icon: Icons.delete_outline,
                    onPressed: () => onDelete(mail),
                  ),
                ],
              ),
              child: MailTile(
                mail: mail,
                onTap: () => Navigator.of(
                  context,
                ).push(appRoute<void>((_) => MailThreadPage(mail: mail))),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 左滑动作按钮 —— 浅灰条上悬浮的圆形彩色按钮（白色图标）。
class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.color,
    required this.icon,
    required this.onPressed,
  });

  final Color color;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CustomSlidableAction(
      // 条状底色随主题（浅灰 / 深灰），圆形按钮浮于其上。
      backgroundColor: context.palette.card,
      onPressed: (_) => onPressed(),
      padding: EdgeInsets.zero,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
