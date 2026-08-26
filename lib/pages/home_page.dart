import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';

import '../data/mock_accounts.dart';
import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../theme/app_palette.dart';
import '../widgets/account_tile.dart';
import '../widgets/app_refresh.dart';
import '../widgets/stat_card.dart';
import 'import_page.dart';
import 'mail_list_page.dart';
import 'settings_page.dart';

/// 首页 —— 邮箱批量管理主界面。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 模拟分页：共 3 页，加载完即无更多。
  static const int _maxPages = 3;

  final List<Account> _items = List<Account>.of(kMockAccounts);
  String _query = '';
  int _page = 1;

  /// 上次刷新完成时间（下拉刷新头显示）。
  DateTime _lastUpdated = DateTime.now();

  bool get _hasMore => _page < _maxPages;
  bool get _isSearching => _query.trim().isNotEmpty;

  List<Account> get _filtered {
    if (!_isSearching) return _items;
    final q = _query.trim().toLowerCase();
    return _items.where((a) => a.email.toLowerCase().contains(q)).toList();
  }

  /// 上滑加载更多 —— 追加下一页；加载完返回 [IndicatorResult.noMore]。
  Future<IndicatorResult> _onLoad() async {
    if (!_hasMore) return IndicatorResult.noMore;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return IndicatorResult.success;
    setState(() {
      _items.addAll(_generatePage(_page));
      _page += 1;
    });
    return _hasMore ? IndicatorResult.success : IndicatorResult.noMore;
  }

  Future<void> _onRefresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(kMockAccounts);
      _page = 1;
      _lastUpdated = DateTime.now();
    });
  }

  /// 生成第 [page] 页的模拟数据（邮箱号唯一）。
  List<Account> _generatePage(int page) {
    return [
      for (int i = 0; i < kMockAccounts.length; i++)
        Account(
          email: 'user$page${i + 1}@outlook.com',
          status: kMockAccounts[i].status,
          protocol: kMockAccounts[i].protocol,
          unread: kMockAccounts[i].unread,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            EasyRefresh(
              // 吸顶头部会盖住浮于内容之上的指示器，故改用 locator 定位到吸顶区下方。
              header: appRefreshHeader(
                _lastUpdated,
                position: IndicatorPosition.locator,
              ),
              footer: appLoadFooter(position: IndicatorPosition.locator),
              onRefresh: _onRefresh,
              onLoad: _onLoad,
              child: CustomScrollView(
                slivers: [
                  // 汇总 + 搜索框随列表上滑，盖住标题后吸顶固定。
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _HomeHeaderDelegate(
                      background: palette.background,
                      onQueryChanged: (value) => setState(() => _query = value),
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
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                MailListPage(accountEmail: account.email),
                          ),
                        ),
                      );
                    },
                  ),
                  const FooterLocator.sliver(),
                ],
              ),
            ),
            // 右上角「…」菜单 —— 汇总上滑覆盖标题后，它仍固定在原位且可点。
            const Positioned(top: 8, right: 8, child: _HeaderMenu()),
          ],
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
    required this.onQueryChanged,
  });

  /// 头部底色 —— 必须不透明，否则列表滑到吸顶区下方会透出来。
  final Color background;
  final ValueChanged<String> onQueryChanged;

  /// 标题条高度（上边距 8 + 标题行 48 + 下边距 14）。
  static const double _titleBand = 70;

  /// 汇总条高度（上间距 8 + 数值 28 + 间距 6 + 标签 13 + 下间距 20）。
  static const double _statsBand = 75;

  /// 搜索条高度（输入框 38 + 下间距 8）。
  static const double _searchBand = 46;

  /// 吸顶后保留的高度 —— 汇总 + 搜索框。
  static const double _pinnedBand = _statsBand + _searchBand;

  @override
  double get maxExtent => _titleBand + _pinnedBand;

  @override
  double get minExtent => _pinnedBand;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final offset = shrinkOffset > _titleBand ? _titleBand : shrinkOffset;
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
                const _HomeTitle(),
                const _StatsRow(),
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
      oldDelegate.onQueryChanged != onQueryChanged;
}

/// 标题 —— 固定高度的标题条，垂直居中，右侧留给常驻的「…」菜单。
class _HomeTitle extends StatelessWidget {
  const _HomeTitle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 70,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 72, 14),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            AppLocalizations.of(context).appTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.palette.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// 右上角「…」菜单：导入 / 设置。
class _HeaderMenu extends StatelessWidget {
  const _HeaderMenu();

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
      onSelected: (value) {
        switch (value) {
          case 'import':
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const ImportPage()));
            break;
          case 'settings':
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            );
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
///
/// 右侧留出 56 —— 吸顶后汇总会盖到标题条位置，需避开常驻在右上角的「…」菜单。
class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 76, 20),
        child: Row(
        children: [
          Expanded(
            child: StatCard(
              label: l10n.statTotal,
              value: '1268',
              valueColor: palette.primary,
            ),
          ),
          Expanded(
            child: StatCard(
              label: l10n.statValid,
              value: '1123',
              valueColor: palette.primary,
            ),
          ),
          Expanded(
            child: StatCard(
              label: l10n.statError,
              value: '145',
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
      height: 46,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: TextField(
        onChanged: onChanged,
        style: TextStyle(color: palette.textPrimary, fontSize: 15),
        cursorColor: palette.primary,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: palette.card,
          hintText: l10n.searchHint,
          hintStyle: TextStyle(color: palette.textSecondary, fontSize: 15),
          prefixIcon: Icon(
            Icons.search,
            color: palette.textSecondary,
            size: 20,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 0,
          ),
          contentPadding: const EdgeInsets.fromLTRB(4, 9, 12, 9),
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
