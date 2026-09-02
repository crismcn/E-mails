import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../api/api_scope.dart';
import '../api/mail_api.dart';
import '../data/mail_mapper.dart';
import '../l10n/app_localizations.dart';
import '../models/mail.dart';
import '../theme/app_page_route.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/app_scroll_behavior.dart';
import '../widgets/app_refresh.dart';
import '../widgets/mail_tile.dart';
import '../widgets/search_field.dart';
import 'compose_page.dart';
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

class _MailListPageState extends State<MailListPage>
    with SingleTickerProviderStateMixin {
  /// 每页条数（Graph `$top`）。
  static const int _pageSize = 20;

  final List<MailPreview> _items = <MailPreview>[];
  String _query = '';

  /// 当前视图（收件箱 / 未读 / 已标星 / 已发送），由顶部抽屉切换。
  MailFolder _folder = MailFolder.inbox;

  /// 抽屉展开动画 —— 驱动菜单下拉 + 遮罩淡入、标题三角翻转。
  late final AnimationController _drawerCtrl;

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

  /// 已加载邮件里的未读数 —— **兜底**计数：服务端计数拿不到时才用它
  /// （受限于已拉取的页，非真实总数）。
  int get _unreadCount => _items.where((m) => m.unread > 0).length;

  /// 当前视图的服务端计数（`mailFolders` 的未读 / 总数）。
  ///
  /// 为 null 表示拿不到：已标星无对应文件夹，或请求失败（如无权限）——
  /// 此时徽标退回 [_unreadCount]。
  MailFolderStats? _stats;

  /// 收件箱的服务端未读数 —— 抽屉「收件箱 / 未读邮件」两行恒用它。
  ///
  /// 首屏就是收件箱，所以切到已发送 / 已标星后它仍保留最近一次的收件箱真实值，
  /// 不会因为当前视图换了而把抽屉里的数字写错。
  int? _inboxUnread;

  /// 顶部徽标：当前视图的服务端未读数，拿不到才退回本地已加载未读数。
  int get _headerUnread => _stats?.unread ?? _unreadCount;

  /// 抽屉里「收件箱 / 未读邮件」的数字：收件箱服务端未读数，拿不到才退回本地。
  int get _drawerUnread => _inboxUnread ?? _unreadCount;

  MailApi get _mailApi => ApiScope.of(context).mail;

  @override
  void initState() {
    super.initState();
    _drawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _drawerCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _reload();
    }
  }

  void _toggleDrawer() {
    _drawerCtrl.isDismissed ? _drawerCtrl.forward() : _drawerCtrl.reverse();
  }

  void _closeDrawer() => _drawerCtrl.reverse();

  /// 切换文件夹 —— 关抽屉、清空列表、回到首屏加载态并重新拉取。
  void _selectFolder(MailFolder folder) {
    _closeDrawer();
    if (folder == _folder) return;
    setState(() {
      _folder = folder;
      _items.clear();
      _firstLoading = true;
      _error = null;
      _hasMore = true;
      _query = '';
    });
    _reload();
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
    // 服务端计数与列表并行拉取 —— 计数失败只让徽标退回本地值，不影响列表。
    final statsFuture = _loadStats();
    final response = await _mailApi.listMessages(
      widget.accountEmail,
      top: _pageSize,
      folder: _folder,
    );
    await statsFuture;
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
      _toast(
        AppLocalizations.of(context).mailLoadFailedToast(response.message),
      );
    }
  }

  /// 拉当前视图的服务端计数 —— 失败**静默**（徽标自动退回本地已加载未读数）。
  ///
  /// 已标星没有对应文件夹（`statsFolderId == null`），直接置空不发请求。
  Future<void> _loadStats() async {
    final folderId = _folder.statsFolderId;
    if (folderId == null) {
      if (mounted) setState(() => _stats = null);
      return;
    }
    final res = await _mailApi.getFolderStats(widget.accountEmail, folderId);
    if (!mounted) return;
    final stats = res.isSuccess ? res.data : null;
    setState(() {
      _stats = stats;
      // 收件箱视图（含「未读邮件」过滤视图）的计数同时喂给抽屉。
      final isInbox =
          _folder == MailFolder.inbox || _folder == MailFolder.unread;
      if (stats != null && isInbox) _inboxUnread = stats.unread;
    });
  }

  /// 未读计数的乐观增减 —— 本地标已读/未读后同步调整服务端计数副本，
  /// 让徽标立刻跟着动;下次刷新会以服务端值校准。
  ///
  /// 只在**调用方的 setState 内**使用（自身不触发重建）。
  void _bumpUnread(int delta) {
    final stats = _stats;
    if (stats != null) {
      _stats = MailFolderStats(
        unread: _atLeastZero(stats.unread + delta),
        total: stats.total,
      );
    }
    final inbox = _inboxUnread;
    if (inbox != null) _inboxUnread = _atLeastZero(inbox + delta);
  }

  static int _atLeastZero(int value) => value < 0 ? 0 : value;

  /// 上滑加载更多 —— 以已加载条数作 `$skip` 续拉下一页。
  Future<IndicatorResult> _onLoad() async {
    if (!_hasMore) return IndicatorResult.noMore;
    final response = await _mailApi.listMessages(
      widget.accountEmail,
      top: _pageSize,
      skip: _items.length,
      folder: _folder,
    );
    if (!mounted) return IndicatorResult.fail;
    final page = response.data;
    if (!response.isSuccess || page == null) {
      _toast(
        AppLocalizations.of(context).mailLoadFailedToast(response.message),
      );
      return IndicatorResult.fail;
    }
    // `$skip` 翻页期间若有新邮件到达，会把上一页的末几条挤到下一页 → 按 id 去重。
    final known = _items.map((m) => m.id).toSet();
    final fresh = mailPreviewsFromGraph(page.items)
        .where((m) => m.id.isEmpty || known.add(m.id))
        .toList();
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
    setState(() {
      _items[index] = mail.copyWith(unread: markRead ? 0 : 1);
      _bumpUnread(markRead ? -1 : 1);
    });
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
      setState(() {
        _items[at] = _items[at].copyWith(unread: mail.unread);
        _bumpUnread(markRead ? 1 : -1);
      });
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

    setState(() {
      _items[index] = _items[index].copyWith(unread: 0);
      _bumpUnread(-1);
    });

    final res = await _mailApi.updateRead(
      widget.accountEmail,
      mail.id,
      isRead: true,
    );
    if (!mounted || res.isSuccess) return;

    final at = _items.indexWhere((m) => m.id == mail.id);
    if (at >= 0) {
      setState(() {
        _items[at] = _items[at].copyWith(unread: mail.unread);
        _bumpUnread(1);
      });
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

  /// 复制账号邮箱到剪贴板（点击顶部标题触发）。
  Future<void> _copyEmail() async {
    await Clipboard.setData(ClipboardData(text: widget.accountEmail));
    if (!mounted) return;
    _toast(AppLocalizations.of(context).mailAccountCopied);
  }

  /// 打开新建邮件页 —— 以当前账号为发件人。
  ///
  /// 顺手把**已加载列表里的发件人**（名称 + 地址，按地址去重）传过去当收件人输入提示的
  /// 候选池：不额外打接口、不读系统通讯录，翻了几页就有几页的人。
  void _openCompose() {
    final seen = <String>{};
    final suggestions = <ComposeContact>[];
    for (final mail in _items) {
      final address = mail.senderAddress.trim();
      if (address.isEmpty || !seen.add(address.toLowerCase())) continue;
      // sender 拿不到显示名时映射层会填占位符「—」，那种就只留地址。
      final name = mail.sender == kUnknownSender ? '' : mail.sender;
      suggestions.add(
        ComposeContact(address: address, name: name == address ? '' : name),
      );
    }
    Navigator.of(context).push(
      appRoute<void>(
        (_) => ComposePage(
          accountEmail: widget.accountEmail,
          suggestions: suggestions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      // 小号圆形添加按钮 —— 点击进入新建邮件页。
      floatingActionButton: SizedBox(
        width: 48,
        height: 48,
        child: FloatingActionButton(
          onPressed: _openCompose,
          backgroundColor: palette.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: const CircleBorder(),
          child: const Icon(AppIcons.add, size: 24),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(
                  folderLabel: _folderLabel(l10n, _folder),
                  email: widget.accountEmail,
                  unread: _headerUnread,
                  drawerAnim: _drawerCtrl,
                  onToggleDrawer: _toggleDrawer,
                  onCopy: _copyEmail,
                ),
                // 抽屉与遮罩浮在搜索框 + 列表之上（不遮标题，标题仍可点击收起）。
                Expanded(
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          const SizedBox(height: 8),
                          // 只过滤**已加载**的邮件（本地过滤），不发起服务端搜索：
                          // Graph 的 `$search` 与 `$orderby` 互斥，混用会打乱按时间倒序。
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: AppSearchField(
                              hintText: l10n.mailSearchHint,
                              onChanged: (v) => setState(() => _query = v),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(child: _buildBody()),
                        ],
                      ),
                      _FolderDrawer(
                        anim: _drawerCtrl,
                        current: _folder,
                        unread: _drawerUnread,
                        flaggedCount: _folder == MailFolder.flagged
                            ? _items.length
                            : null,
                        onSelect: _selectFolder,
                        onClose: _closeDrawer,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // 首屏转圈浮在**整页正中**（CLAUDE.md §4.7）：按下方列表区居中会明显偏下
            // —— 上面压着标题栏 + 搜索框近 120，下面没有对称的底栏来抵消。
            if (_firstLoading)
              Positioned.fill(
                child: IgnorePointer(
                  child: Padding(
                    // `SafeArea(bottom: false)` 是为了让列表能滚到屏幕最底；转圈得自己
                    // 让开系统手势条，否则中线被压低半个 inset。
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    child: Center(
                      child: CupertinoActivityIndicator(
                        radius: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _folderLabel(AppLocalizations l10n, MailFolder folder) =>
      switch (folder) {
        MailFolder.inbox => l10n.folderInbox,
        MailFolder.unread => l10n.folderUnread,
        MailFolder.flagged => l10n.folderFlagged,
        MailFolder.sent => l10n.folderSent,
      };

  /// 三态：首屏加载 / 空列表下的整页错误 / 正常列表（含空态占位）。
  ///
  /// 首屏那个转圈**不在这里** —— 它由 `build` 浮在整页正中（列表区上面压着标题栏 +
  /// 搜索框，按这块区域居中会偏下）。
  Widget _buildBody() {
    if (_firstLoading) return const SizedBox.shrink();
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

/// 顶部标题栏 —— 主行「文件夹名 ▾ 未读徽标」（点击弹抽屉），次行账号邮箱（点击复制）；
/// 左侧保留返回、右侧写信图标。三角随抽屉展开翻转。
class _Header extends StatelessWidget {
  const _Header({
    required this.folderLabel,
    required this.email,
    required this.unread,
    required this.drawerAnim,
    required this.onToggleDrawer,
    required this.onCopy,
  });

  final String folderLabel;
  final String email;
  final int unread;
  final Animation<double> drawerAnim;
  final VoidCallback onToggleDrawer;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(AppIcons.back, color: palette.textPrimary, size: 20),
            splashRadius: 22,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 主行：文件夹名 + 翻转三角 + 未读徽标，整行点击开合抽屉。
                InkWell(
                  onTap: onToggleDrawer,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            folderLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        RotationTransition(
                          turns: Tween<double>(
                            begin: 0,
                            end: 0.5,
                          ).animate(drawerAnim),
                          child: Icon(
                            AppIcons.dropDown,
                            color: palette.textPrimary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (unread > 0) _UnreadPill(count: unread),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: onCopy,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 右上角留白：撑起右侧对称间距（返回箭头 44 宽，这里配平避免标题偏移）。
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// 蓝色未读数胶囊徽标。
class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: palette.primary,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 顶部下拉抽屉 —— 满宽菜单（收件箱 / 未读 / 已标星 / 已发送 / 全部文件夹）。
///
/// 由 [anim] 驱动：紧贴标题栏下沿、自顶向下切入展开（无遮罩）。[anim] 归零时
/// 整体不入树，避免挡住下方列表交互。关闭靠再点标题或选择某项。
class _FolderDrawer extends StatelessWidget {
  const _FolderDrawer({
    required this.anim,
    required this.current,
    required this.unread,
    required this.flaggedCount,
    required this.onSelect,
    required this.onClose,
  });

  final Animation<double> anim;
  final MailFolder current;
  final int unread;
  final int? flaggedCount;
  final ValueChanged<MailFolder> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, child) {
          if (anim.isDismissed) return const SizedBox.shrink();
          // 展开到位后不再裁剪，让底部圆角阴影完整投出；
          // 动画过程中按曲线裁剪高度，实现自顶向下切入。
          if (anim.isCompleted) return child!;
          return ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: Curves.easeOutCubic.transform(anim.value),
              child: child,
            ),
          );
        },
        child: Material(
          color: palette.background,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
          shadowColor: Colors.black.withValues(alpha: 0.28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FolderRow(
                icon: AppIcons.inbox,
                label: l10n.folderInbox,
                trailing: unread > 0 ? '$unread' : null,
                selected: current == MailFolder.inbox,
                onTap: () => onSelect(MailFolder.inbox),
              ),
              _rowDivider(palette),
              _FolderRow(
                icon: AppIcons.unread,
                label: l10n.folderUnread,
                trailing: unread > 0 ? '$unread' : null,
                selected: current == MailFolder.unread,
                onTap: () => onSelect(MailFolder.unread),
              ),
              _rowDivider(palette),
              _FolderRow(
                icon: AppIcons.starredFolder,
                label: l10n.folderFlagged,
                trailing: flaggedCount != null ? '$flaggedCount' : null,
                selected: current == MailFolder.flagged,
                onTap: () => onSelect(MailFolder.flagged),
              ),
              _rowDivider(palette),
              _FolderRow(
                icon: AppIcons.sentFolder,
                label: l10n.folderSent,
                selected: current == MailFolder.sent,
                onTap: () => onSelect(MailFolder.sent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowDivider(AppPalette palette) => Divider(
    color: palette.divider,
    height: 1,
    thickness: 1,
    indent: 60,
    endIndent: 20,
  );
}

/// 抽屉里的单个文件夹行 —— 前置图标 + 名称 + 尾部计数 / 展开箭头。
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = selected ? palette.primary : palette.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: TextStyle(color: palette.textSecondary, fontSize: 15),
              ),
          ],
        ),
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
              Icon(AppIcons.cloudOff, color: palette.textSecondary, size: 40),
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
                  icon: AppIcons.archive,
                  onPressed: () => onArchive(mail),
                ),
                _SwipeAction(
                  color: const Color(0xFF2F80FF),
                  icon: AppIcons.unread,
                  onPressed: () => onToggleRead(mail),
                ),
                _SwipeAction(
                  color: const Color(0xFFFF4D4F),
                  icon: AppIcons.delete,
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
