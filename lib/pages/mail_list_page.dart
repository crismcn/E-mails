import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../api/api_scope.dart';
import '../api/mail_api.dart';
import '../data/mail_mapper.dart';
import '../l10n/app_localizations.dart';
import '../models/mail.dart';
import '../theme/app_page_route.dart';
import '../theme/app_palette.dart';
import '../theme/app_scroll_behavior.dart';
import '../widgets/app_refresh.dart';
import '../widgets/mail_tile.dart';
import 'message_detail_page.dart';

/// 邮件列表页 —— 从首页某个邮箱账号进入，拉取该账号在 Microsoft Graph 上的邮件。
///
/// 数据来自 [MailApi.listMessages]（`GET /me/messages`），按收件时间倒序、
/// `$top`/`$skip` 翻页。token 由鉴权拦截器按账号注入，401 会自动刷新重试一次，
/// 因此本页只需处理「成功 / 失败」两种结果，不感知 token 细节。
class MailListPage extends StatefulWidget {
  const MailListPage({super.key, required this.accountEmail});

  /// 顶部标题展示的账号邮箱，同时用于向拦截器指明取哪个账号的 token。
  final String accountEmail;

  @override
  State<MailListPage> createState() => _MailListPageState();
}

class _MailListPageState extends State<MailListPage> {
  /// 每页条数（Graph `$top`）。
  static const int _pageSize = 20;

  final List<MailPreview> _items = <MailPreview>[];
  String _query = '';

  /// 首帧依赖就绪后只自动拉一次。
  bool _loaded = false;

  /// 首屏加载中 —— 展示居中转圈（此时还没有任何数据可显示）。
  bool _firstLoading = true;

  /// 最近一次失败原因；仅在列表为空时占满整页展示，否则只 toast 提示。
  String? _error;

  /// 是否可能还有下一页（上一页返回满页即认为还有）。
  bool _hasMore = true;

  /// 上次刷新完成时间（下拉刷新头显示）。
  DateTime _lastUpdated = DateTime.now();

  MailApi get _mailApi => ApiScope.of(context).mail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _reload();
    }
  }

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

  /// 拉取第一页（首屏 / 下拉刷新 / 失败重试共用）。
  ///
  /// 失败时的取舍：**已有数据就不清空**，只 toast 提示，避免刷新失败把已读到的
  /// 邮件抹掉；列表本来就空才整页展示错误 + 重试。
  Future<void> _reload() async {
    final response = await _mailApi.listMessages(
      widget.accountEmail,
      top: _pageSize,
    );
    if (!mounted) return;
    final page = response.data;
    if (response.isSuccess && page != null) {
      setState(() {
        _firstLoading = false;
        _error = null;
        _items
          ..clear()
          ..addAll(mailPreviewsFromGraph(page.items));
        _hasMore = page.items.length >= _pageSize;
        _lastUpdated = DateTime.now();
      });
      return;
    }
    setState(() {
      _firstLoading = false;
      _error = response.message;
    });
    if (_items.isNotEmpty) {
      _toast(AppLocalizations.of(context).mailLoadFailedToast(response.message));
    }
  }

  /// 上滑加载更多 —— 以已加载条数作 `$skip` 续拉下一页。
  Future<IndicatorResult> _onLoad() async {
    if (!_hasMore) return IndicatorResult.noMore;
    final response = await _mailApi.listMessages(
      widget.accountEmail,
      top: _pageSize,
      skip: _items.length,
    );
    if (!mounted) return IndicatorResult.fail;
    final page = response.data;
    if (!response.isSuccess || page == null) {
      _toast(AppLocalizations.of(context).mailLoadFailedToast(response.message));
      return IndicatorResult.fail;
    }
    // `$skip` 翻页期间若有新邮件到达，会把上一页的末几条挤到下一页 → 按 id 去重。
    final known = _items.map((m) => m.id).toSet();
    final fresh = mailPreviewsFromGraph(
      page.items,
    ).where((m) => m.id.isEmpty || known.add(m.id)).toList();
    setState(() {
      _items.addAll(fresh);
      _hasMore = page.items.length >= _pageSize;
    });
    return _hasMore ? IndicatorResult.success : IndicatorResult.noMore;
  }

  // ---- 左滑动作 ----
  //
  // 已读/未读已回写 Graph（[_toggleRead]）。归档=move、删除=DELETE 仍仅本地态，
  // 下拉刷新会恢复服务端真实状态；真正写回留作单独任务。

  /// 归档（移动）—— 仅本地移除。
  void _archive(MailPreview mail) {
    final l10n = AppLocalizations.of(context);
    setState(() => _items.remove(mail));
    _toast(l10n.mailArchived);
  }

  /// 标记已读 / 未读（切换）—— 乐观更新本地后 PATCH 回写 Graph；失败则回滚并提示。
  ///
  /// 注意：写回需 `Mail.ReadWrite` scope。只授予 `Mail.Read` 的账号会失败（403 /
  /// AADSTS70000），此时回滚本地状态、如实提示，不假装成功。
  Future<void> _toggleRead(MailPreview mail) async {
    final l10n = AppLocalizations.of(context);
    final index = _items.indexOf(mail);
    if (index < 0 || mail.id.isEmpty) return;
    final markRead = mail.unread > 0;

    // 乐观更新：先切本地状态与提示，让操作即时可见。
    setState(() => _items[index] = mail.copyWith(unread: markRead ? 0 : 1));
    _toast(markRead ? l10n.mailMarkedRead : l10n.mailMarkedUnread);

    final res = await _mailApi.updateRead(
      widget.accountEmail,
      mail.id,
      isRead: markRead,
    );
    if (!mounted || res.isSuccess) return;

    // 失败回滚 —— 按 id 定位（期间列表可能已变动），恢复原未读值。
    final at = _items.indexWhere((m) => m.id == mail.id);
    if (at >= 0) {
      setState(() => _items[at] = _items[at].copyWith(unread: mail.unread));
    }
    _toast(l10n.mailActionFailedToast(res.message));
  }

  /// 打开邮件（进入详情页）时自动标记为已读 —— 乐观清角标 + PATCH 回写。
  ///
  /// 与手动 [_toggleRead] 的区别：这是「打开」的副作用而非显式手势，故**静默**处理
  /// （不弹提示）；失败（无写权限 / 网络）则悄悄回滚未读角标，如实反映未成功。
  /// 已读或无 id 的项直接跳过，避免无谓请求。
  Future<void> _markReadOnOpen(MailPreview mail) async {
    if (mail.unread == 0 || mail.id.isEmpty) return;
    final index = _items.indexWhere((m) => m.id == mail.id);
    if (index < 0) return;

    setState(() => _items[index] = _items[index].copyWith(unread: 0));

    final res = await _mailApi.updateRead(
      widget.accountEmail,
      mail.id,
      isRead: true,
    );
    if (!mounted || res.isSuccess) return;

    final at = _items.indexWhere((m) => m.id == mail.id);
    if (at >= 0) {
      setState(() => _items[at] = _items[at].copyWith(unread: mail.unread));
    }
  }

  /// 删除 —— 仅本地移除。
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
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  /// 三态：首屏转圈 / 空列表下的整页错误 / 正常列表（含空态占位）。
  Widget _buildBody() {
    if (_firstLoading) {
      return Center(
        child: CupertinoActivityIndicator(
          radius: 13,
          color: context.palette.textSecondary,
        ),
      );
    }
    if (_error != null && _items.isEmpty) {
      return _ErrorView(message: _error!, onRetry: _reload);
    }
    return _MailList(
      mails: _filtered,
      accountEmail: widget.accountEmail,
      lastUpdated: _lastUpdated,
      onRefresh: _reload,
      onLoad: _onLoad,
      onOpen: _markReadOnOpen,
      onArchive: _archive,
      onToggleRead: _toggleRead,
      onDelete: _delete,
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

/// 首屏加载失败 —— 居中展示微软/网络返回的原始原因 + 重试按钮。
///
/// 刻意把 [message] 原样显示：凭据 scope 不足、租户不匹配等问题全靠这句话定位，
/// 换成笼统的「加载失败」会把唯一的线索丢掉。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                color: palette.textSecondary,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.mailLoadFailed,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 搜索框 —— 胶囊形（两端半圆）。
///
/// 只过滤**已加载**的邮件（本地过滤），不发起服务端搜索：Graph 的 `$search`
/// 与 `$orderby` 互斥，混用会打乱按时间倒序的列表。
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

/// 邮件列表 —— 下拉刷新 + 上滑加载更多 + 左滑动作。
class _MailList extends StatelessWidget {
  const _MailList({
    required this.mails,
    required this.accountEmail,
    required this.lastUpdated,
    required this.onRefresh,
    required this.onLoad,
    required this.onOpen,
    required this.onArchive,
    required this.onToggleRead,
    required this.onDelete,
  });

  final List<MailPreview> mails;
  final String accountEmail;
  final DateTime lastUpdated;
  final Future<void> Function() onRefresh;
  final Future<IndicatorResult> Function() onLoad;
  final ValueChanged<MailPreview> onOpen;
  final ValueChanged<MailPreview> onArchive;
  final ValueChanged<MailPreview> onToggleRead;
  final ValueChanged<MailPreview> onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EasyRefresh(
      // EasyRefresh 自带物理会覆盖 MaterialApp.scrollBehavior，需显式传同一套回弹参数。
      spring: kSnappySpring,
      frictionFactor: snappyFrictionFactor,
      header: appRefreshHeader(lastUpdated),
      footer: appLoadFooter(),
      onRefresh: onRefresh,
      onLoad: onLoad,
      child: mails.isEmpty ? _buildEmpty(context) : _buildList(palette),
    );
  }

  /// 空态仍放在可滚动容器里 —— 否则 EasyRefresh 拿不到 scrollable，下拉刷新会失效。
  Widget _buildEmpty(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 4),
      children: [
        SizedBox(
          height: 240,
          child: Center(
            child: Text(
              AppLocalizations.of(context).mailEmpty,
              style: TextStyle(
                color: context.palette.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList(AppPalette palette) {
    return SlidableAutoCloseBehavior(
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
            // 真实数据用服务端 id 作 key（翻页/刷新后仍稳定）；mock 无 id 时退回实例。
            key: mail.id.isEmpty ? ObjectKey(mail) : ValueKey<String>(mail.id),
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
              // 点击直接进入邮件详情页（跳过会话页）；同时把该邮件标记为已读。
              onTap: () {
                onOpen(mail);
                Navigator.of(context).push(
                  appRoute<void>(
                    (_) => MessageDetailPage(
                      message: mailMessageFromPreview(mail),
                      accountEmail: accountEmail,
                    ),
                  ),
                );
              },
            ),
          );
        },
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
