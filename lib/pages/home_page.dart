import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';

import '../api/api_scope.dart';
import '../core/network/api_exception.dart';
import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../theme/app_page_route.dart';
import '../theme/app_palette.dart';
import '../widgets/account_tile.dart';
import '../widgets/app_refresh.dart';
import '../widgets/stat_card.dart';
import 'import_page.dart';
import 'mail_list_page.dart';
import 'settings_page.dart';

/// 顶部选择栏高度 —— 与标题条 [_HomeHeaderDelegate._titleBand] 等高：
/// 多选时列表整体下移这么多为悬浮栏让位、同时标题条收起同等高度，两者抵消，净布局不跳。
const double _kSelTopBarHeight = 62;

/// 首页 —— 邮箱批量管理主界面。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final List<Account> _items = <Account>[];
  String _query = '';
  bool _loaded = false;

  /// 多选态与已选邮箱集合（长按进入）。
  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  /// 批量健康检测进行中 —— 防重复触发。
  bool _checking = false;

  /// 多选进出动画（0=常态，1=多选态）—— 顶部选择栏从顶切入、底栏从底滑起、
  /// 标题条同步收起都由它统一驱动，保证一致的节奏、避免跳变。
  late final AnimationController _selCtrl;
  late final Animation<double> _selAnim;

  /// 上次刷新完成时间（下拉刷新头显示）。
  DateTime _lastUpdated = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _selAnim = CurvedAnimation(parent: _selCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _selCtrl.dispose();
    super.dispose();
  }

  bool get _isSearching => _query.trim().isNotEmpty;

  int get _validCount =>
      _items.where((a) => a.status == AccountStatus.valid).length;
  int get _errorCount =>
      _items.where((a) => a.status != AccountStatus.valid).length;

  List<Account> get _filtered {
    if (!_isSearching) return _items;
    final q = _query.trim().toLowerCase();
    return _items.where((a) => a.email.toLowerCase().contains(q)).toList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 首帧依赖就绪后载入一次已持久化的账号（ApiScope 在根部提供）。
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  /// 从安全存储载入已导入的账号邮箱，转成展示用 [Account]。
  ///
  /// 状态/未读数暂无来源（健康检查与 Graph 拉取为后续任务），
  /// 载入的账号一律先按「有效 / Graph / 未读未知」占位展示。
  Future<void> _load() async {
    final emails = await ApiScope.of(context).knownAccounts();
    if (!mounted) return;
    emails.sort();
    setState(() {
      _items
        ..clear()
        ..addAll(
          emails.map(
            (email) => Account(
              email: email,
              status: AccountStatus.valid,
              protocol: MailProtocol.graph,
              unread: null,
            ),
          ),
        );
      _lastUpdated = DateTime.now();
    });
  }

  Future<void> _onRefresh() async {
    await _load();
  }

  // ---- 多选交互 ----

  void _enterSelection(String email) {
    setState(() {
      _selectionMode = true;
      _selected
        ..clear()
        ..add(email);
    });
    _selCtrl.forward();
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
    // 反向播放退出动画（顶部栏收起 / 底栏落下 / 标题条展开）。
    _selCtrl.reverse();
  }

  void _toggleSelect(String email) {
    setState(() {
      if (!_selected.remove(email)) _selected.add(email);
    });
  }

  /// 全选 / 取消全选（作用于当前过滤后的列表）。
  void _toggleSelectAll() {
    final all = _filtered.map((a) => a.email).toSet();
    setState(() {
      if (all.isNotEmpty && _selected.containsAll(all)) {
        _selected.removeAll(all);
      } else {
        _selected.addAll(all);
      }
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1400),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ---- 批量操作 ----

  /// 批量健康检测 —— 逐账号强制刷新一次 token：成功记为有效，
  /// 鉴权失败记为 Token 过期，其它错误（网络等）暂不改状态。
  Future<void> _healthCheckSelected() async {
    if (_checking || _selected.isEmpty) return;
    final api = ApiScope.of(context);
    final l10n = AppLocalizations.of(context);
    final emails = _selected.toList();

    setState(() => _checking = true);
    _toast(l10n.accountChecking);

    var ok = 0;
    var bad = 0;
    final results = <String, AccountStatus>{};
    await Future.wait(
      emails.map((email) async {
        try {
          await api.tokenService.accessTokenFor(email, forceRefresh: true);
          results[email] = AccountStatus.valid;
          ok++;
        } on ApiException catch (e) {
          bad++;
          if (e.isAuthFailure) results[email] = AccountStatus.tokenExpired;
        } catch (_) {
          bad++;
        }
      }),
    );

    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _items.length; i++) {
        final status = results[_items[i].email];
        if (status != null) _items[i] = _items[i].copyWith(status: status);
      }
      _checking = false;
      _selectionMode = false;
      _selected.clear();
    });
    _selCtrl.reverse();
    _toast(l10n.accountCheckSummary(ok, bad));
  }

  /// 批量删除 —— 二次确认后从安全存储与列表移除。
  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final count = _selected.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.accountDeleteTitle),
        content: Text(l10n.accountDeleteMultiBody(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final api = ApiScope.of(context);
    final emails = _selected.toList();
    await Future.wait(emails.map(api.credentialsStore.remove));
    if (!mounted) return;
    setState(() {
      _items.removeWhere((a) => _selected.contains(a.email));
      _selectionMode = false;
      _selected.clear();
    });
    _selCtrl.reverse();
    _toast(l10n.accountDeleted(count));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final all = _filtered.map((a) => a.email).toSet();
    final allSelected = all.isNotEmpty && _selected.containsAll(all);
    return PopScope(
      // 多选态下拦截返回：先退出多选，而非离开首页。
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelection();
      },
      child: Scaffold(
        backgroundColor: palette.background,
        body: SafeArea(
          bottom: false,
          // 所有多选动画统一由 _selAnim 驱动，逐帧重建这棵子树。
          child: AnimatedBuilder(
            animation: _selAnim,
            builder: (context, _) {
              final sel = _selAnim.value.clamp(0.0, 1.0);
              return Stack(
                fit: StackFit.expand,
                children: [
                  // 列表区：多选态整体下移 _kSelTopBarHeight，为顶部悬浮选择栏让位。
                  // （标题条会同步收起同等高度，两者抵消，未滚动时净布局不跳。）
                  Padding(
                    padding: EdgeInsets.only(top: _kSelTopBarHeight * sel),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        EasyRefresh(
                          // 吸顶头部会盖住浮于内容之上的指示器，故改用 locator 定位到吸顶区下方。
                          header: appRefreshHeader(
                            _lastUpdated,
                            position: IndicatorPosition.locator,
                          ),
                          onRefresh: _onRefresh,
                          child: CustomScrollView(
                            slivers: [
                              // 汇总 + 搜索框随列表上滑，盖住标题后吸顶固定。
                              // 多选态标题条随 sel 收起（让位给顶部选择栏，避免重复标题）。
                              SliverPersistentHeader(
                                pinned: true,
                                delegate: _HomeHeaderDelegate(
                                  background: palette.background,
                                  total: _items.length,
                                  valid: _validCount,
                                  error: _errorCount,
                                  titleFactor: 1 - sel,
                                  onQueryChanged: (value) =>
                                      setState(() => _query = value),
                                ),
                              ),
                              const HeaderLocator.sliver(),
                              SliverList.separated(
                                itemCount: _filtered.length,
                                separatorBuilder: (context, index) => Divider(
                                  color: palette.divider,
                                  height: 1,
                                  thickness: 1,
                                  // 与邮件列表一致：分隔线缩进对齐邮箱文字（外边距 20 + 头像 50 + 间距 14）。
                                  indent: 84,
                                  endIndent: 20,
                                ),
                                itemBuilder: (context, index) {
                                  final account = _filtered[index];
                                  return AccountTile(
                                    account: account,
                                    selectionMode: _selectionMode,
                                    selected: _selected.contains(account.email),
                                    onLongPress: _selectionMode
                                        ? null
                                        : () => _enterSelection(account.email),
                                    onTap: _selectionMode
                                        ? () => _toggleSelect(account.email)
                                        : () => Navigator.of(context).push(
                                            appRoute<void>(
                                              (_) => MailListPage(
                                                accountEmail: account.email,
                                              ),
                                            ),
                                          ),
                                  );
                                },
                              ),
                              // 底栏浮起时给列表尾部留白，避免遮挡最后一项。
                              SliverToBoxAdapter(
                                child: SizedBox(height: 96 * sel),
                              ),
                            ],
                          ),
                        ),
                        // 右上角「…」菜单 —— 多选态淡出并禁用。
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IgnorePointer(
                            ignoring: _selectionMode,
                            child: Opacity(
                              opacity: 1 - sel,
                              child: _HeaderMenu(onImported: _load),
                            ),
                          ),
                        ),
                        // 底部批量操作栏 —— 随 sel 从屏幕外(下方)滑起。
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            ignoring: !_selectionMode,
                            child: FractionalTranslation(
                              translation: Offset(0, 1 - sel),
                              child: _SelectionBar(
                                hasSelection: _selected.isNotEmpty,
                                allSelected: allSelected,
                                onHealthCheck: _healthCheckSelected,
                                onDelete: _deleteSelected,
                                onSelectAll: _toggleSelectAll,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 顶部选择栏：绝对定位于顶部，进入时由上向下滑入（悬浮于列表之上，不随滚动）。
                  if (sel > 0)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        ignoring: !_selectionMode,
                        child: FractionalTranslation(
                          translation: Offset(0, -(1 - sel)),
                          child: _SelectionTopBar(
                            count: _selected.length,
                            onClose: _exitSelection,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// __REST2__
/// 首页吸顶头部 —— 标题被上移的汇总顶出，汇总/搜索框到顶后吸顶固定。
///
/// 折叠量恰为标题条高度：`shrinkOffset` 从 0 增到 [_titleBand] 期间，
/// 标题、汇总、搜索框作为整体一起上移，标题逐渐滑出顶部（被顶出，而非被覆盖）；
/// 标题完全移出后进入吸顶态，汇总/搜索框固定不动。
class _HomeHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _HomeHeaderDelegate({
    required this.background,
    required this.total,
    required this.valid,
    required this.error,
    required this.titleFactor,
    required this.onQueryChanged,
  });

  /// 头部底色 —— 必须不透明，否则列表滑到吸顶区下方会透出来。
  final Color background;
  final int total;
  final int valid;
  final int error;

  /// 标题条显隐系数（1=完整、0=收起）—— 进入多选时随动画收起，让位给顶部选择栏。
  final double titleFactor;
  final ValueChanged<String> onQueryChanged;

  /// 标题条高度（上边距 6 + 标题行 44 + 下边距 12）。
  static const double _titleBand = 62;

  /// 汇总条高度（上间距 6 + 数值 24 + 间距 5 + 标签 12 + 下间距 16 ≈ 63，留余量取 66）。
  static const double _statsBand = 66;

  /// 搜索条高度（输入框 34 + 下间距 8）。
  static const double _searchBand = 42;

  /// 吸顶后保留的高度 —— 汇总 + 搜索框。
  static const double _pinnedBand = _statsBand + _searchBand;

  /// 当前标题条高度（随 [titleFactor] 收起）。
  double get _band => _titleBand * titleFactor;

  @override
  double get maxExtent => _band + _pinnedBand;

  @override
  double get minExtent => _pinnedBand;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // 可折叠量 = 当前标题条高度；标题完全收起时(_band=0)不再折叠。
    final offset = shrinkOffset > _band ? _band : shrinkOffset;
    // 标题 + 汇总 + 搜索框作为整体上移 offset：标题被顶出顶部，汇总/搜索框随后吸顶。
    // OverflowBox 让内容始终以 maxExtent 完整高度布局，不随吸顶收缩的盒子被压扁。
    return ClipRect(
      child: ColoredBox(
        color: background,
        child: OverflowBox(
          minHeight: 0,
          maxHeight: maxExtent,
          alignment: Alignment.topCenter,
          child: Transform.translate(
            offset: Offset(0, -offset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题条随 titleFactor 收起（高度 + 透明度），多选态让位给顶部选择栏。
                ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: titleFactor.clamp(0.0, 1.0),
                    child: Opacity(
                      opacity: titleFactor.clamp(0.0, 1.0),
                      child: const _HomeTitle(),
                    ),
                  ),
                ),
                _StatsRow(total: total, valid: valid, error: error),
                _SearchBox(onChanged: onQueryChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_HomeHeaderDelegate oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.total != total ||
      oldDelegate.valid != valid ||
      oldDelegate.error != error ||
      oldDelegate.titleFactor != titleFactor ||
      oldDelegate.onQueryChanged != onQueryChanged;
}

/// 标题 —— 固定高度的标题条，垂直居中，右侧留给常驻的「…」菜单。
class _HomeTitle extends StatelessWidget {
  const _HomeTitle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            AppLocalizations.of(context).appTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.palette.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部选择栏 —— 多选态悬浮于顶部的一条（绝对定位、不随列表滚动）。
///
/// 本组件只负责渲染固定高度 [_kSelTopBarHeight] 的栏体；「自上而下滑入」的进出
/// 动画由父级 `FractionalTranslation`（受 `_selAnim` 驱动）负责，故这里不含动画。
class _SelectionTopBar extends StatelessWidget {
  const _SelectionTopBar({required this.count, required this.onClose});

  final int count;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Container(
      height: _kSelTopBarHeight,
      decoration: BoxDecoration(color: palette.background),
      padding: const EdgeInsets.fromLTRB(8, 0, 20, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, color: palette.textPrimary, size: 22),
            splashRadius: 22,
            tooltip: l10n.commonCancel,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.selectionTitle(count),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 右上角「…」菜单：导入 / 设置。
class _HeaderMenu extends StatelessWidget {
  const _HeaderMenu({required this.onImported});

  /// 导入页返回后回调 —— 触发首页重新载入已存账号。
  final VoidCallback onImported;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    // 弹层背景 / 文字随主题自适应，选项间细线分割。
    final menuBg = palette.background;
    final menuText = palette.textPrimary;
    return PopupMenuButton<String>(
      tooltip: '更多',
      offset: const Offset(-12, 40),
      color: menuBg,
      surfaceTintColor: menuBg,
      // 浅色、四周发散的柔和阴影。
      elevation: 20,
      shadowColor: const Color(0x4B000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      icon: _MenuDotsIcon(color: palette.textPrimary),
      onSelected: (value) async {
        switch (value) {
          case 'import':
            await Navigator.of(context)
                .push(appRoute<void>((_) => const ImportPage()));
            // 导入页可能已持久化新账号，回来重新载入列表。
            onImported();
            break;
          case 'settings':
            Navigator.of(context)
                .push(appRoute<void>((_) => const SettingsPage()));
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'import',
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: _MenuRow(
            icon: Icons.file_upload_outlined,
            label: l10n.menuImport,
            color: menuText,
          ),
        ),
        const _MenuDivider(),
        PopupMenuItem<String>(
          value: 'settings',
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: _MenuRow(
            icon: Icons.settings_outlined,
            label: l10n.menuSettings,
            color: menuText,
          ),
        ),
      ],
    );
  }
}

/// 菜单选项之间的分割线 —— 与邮箱列表分隔线保持一致（同色、细、左右缩进 20）。
class _MenuDivider extends PopupMenuEntry<Never> {
  const _MenuDivider();

  @override
  double get height => 1;

  @override
  bool represents(void value) => false;

  @override
  State<_MenuDivider> createState() => _MenuDividerState();
}

class _MenuDividerState extends State<_MenuDivider> {
  @override
  Widget build(BuildContext context) {
    // 分隔线取主题列表分隔色，随明/暗切换，保持与邮箱列表一致的观感。
    return Divider(
      color: context.palette.divider,
      height: 1,
      thickness: 1,
      indent: 20,
      endIndent: 20,
    );
  }
}

/// 菜单项一行：图标 + 文案（颜色随主题自适应）。
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 15, letterSpacing: 1.5),
        ),
      ],
    );
  }
}

/// 三点菜单图标 —— 圆点之间留出更明显的间隔。
class _MenuDotsIcon extends StatelessWidget {
  const _MenuDotsIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget dot() => Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(),
        const SizedBox(height: 6),
        dot(),
        const SizedBox(height: 6),
        dot(),
      ],
    );
  }
}

/// 汇总条 —— 固定高度（吸顶头部需要确定的 extent），内含三个统计项。

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.total,
    required this.valid,
    required this.error,
  });

  final int total;
  final int valid;
  final int error;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 66,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: StatCard(
                label: l10n.statTotal,
                value: '$total',
                valueColor: palette.primary,
              ),
            ),
            Expanded(
              child: StatCard(
                label: l10n.statValid,
                value: '$valid',
                valueColor: palette.primary,
              ),
            ),
            Expanded(
              child: StatCard(
                label: l10n.statError,
                value: '$error',
                valueColor: palette.statusError,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// __REST3__
/// 搜索框 —— 规则椭圆（胶囊/stadium，两端半圆），按邮箱号过滤。
///
/// 固定高度（含底部间距 8），供吸顶头部计算 extent。
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onChanged});

  final ValueChanged<String> onChanged;

  /// 规则椭圆：四角同等大圆角，得到两端半圆的胶囊形。
  static const BorderRadius _pillRadius = BorderRadius.all(
    Radius.circular(100),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 42,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: TextField(
          onChanged: onChanged,
          style: TextStyle(color: palette.textPrimary, fontSize: 14),
          cursorColor: palette.primary,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: palette.card,
            hintText: l10n.searchHint,
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
      ),
    );
  }
}

/// 多选态底部操作栏 —— 从底部滑起：健康检测 / 删除 / 全选。
///
/// 参照「长按操作.jpg」：浅色底、细顶边，图标在上、小字标签在下。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.hasSelection,
    required this.allSelected,
    required this.onHealthCheck,
    required this.onDelete,
    required this.onSelectAll,
  });

  /// 是否有选中项 —— 无选中时健康检测/删除置灰不可点。
  final bool hasSelection;
  final bool allSelected;
  final VoidCallback onHealthCheck;
  final VoidCallback onDelete;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Material(
      color: palette.background,
      elevation: 20,
      shadowColor: const Color(0x33000000),
      child: Container(
        decoration: BoxDecoration(),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BarAction(
                  icon: Icons.health_and_safety_outlined,
                  label: l10n.actionHealthCheck,
                  enabled: hasSelection,
                  onPressed: onHealthCheck,
                ),
                _BarAction(
                  icon: Icons.delete_outline,
                  label: l10n.actionDelete,
                  enabled: hasSelection,
                  onPressed: onDelete,
                ),
                _BarAction(
                  icon: allSelected ? Icons.deselect : Icons.select_all,
                  label: l10n.actionSelectAll,
                  enabled: true,
                  onPressed: onSelectAll,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部操作栏单个按钮 —— 图标在上、标签在下；置灰时降透明度并禁用点击。
class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = enabled
        ? palette.textPrimary
        : palette.textSecondary.withValues(alpha: 0.4);
    return Expanded(
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
