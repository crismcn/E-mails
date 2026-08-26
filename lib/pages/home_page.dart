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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header(),
            const SizedBox(height: 8),
            const _StatsRow(),
            const SizedBox(height: 20),
            _SearchBox(onChanged: (value) => setState(() => _query = value)),
            const SizedBox(height: 8),
            Expanded(
              child: EasyRefresh(
                header: appRefreshHeader(_lastUpdated),
                footer: appLoadFooter(),
                onRefresh: _onRefresh,
                onLoad: _onLoad,
                child: _AccountList(accounts: _filtered),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// __REST2__
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            AppLocalizations.of(context).appTitle,
            style: TextStyle(
              color: context.palette.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const _HeaderMenu(),
        ],
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
      offset: const Offset(0, 40),
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
      width: 4,
      height: 4,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(),
        const SizedBox(width: 6),
        dot(),
        const SizedBox(width: 6),
        dot(),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
    );
  }
}

// __REST3__
/// 搜索框 —— 规则椭圆（胶囊/stadium，两端半圆），按邮箱号过滤。
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
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
    );
  }
}

class _AccountList extends StatelessWidget {
  const _AccountList({required this.accounts});

  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: accounts.length,
      separatorBuilder: (context, index) => Divider(
        color: context.palette.divider,
        height: 1,
        thickness: 1,
        // 与邮件列表一致：分隔线缩进对齐邮箱文字（外边距 20 + 头像 50 + 间距 14）。
        indent: 84,
        endIndent: 20,
      ),
      itemBuilder: (context, index) {
        return AccountTile(
          account: accounts[index],
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    MailListPage(accountEmail: accounts[index].email),
              ),
            );
          },
        );
      },
    );
  }
}
