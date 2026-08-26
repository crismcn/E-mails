import 'package:flutter/material.dart';

import '../data/mock_accounts.dart';
import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../theme/app_palette.dart';
import '../widgets/account_tile.dart';
import '../widgets/stat_card.dart';
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

  final ScrollController _scrollController = ScrollController();
  final List<Account> _items = List<Account>.of(kMockAccounts);
  String _query = '';
  int _page = 1;
  bool _isLoadingMore = false;
  bool _isRefreshing = false;

  bool get _hasMore => _page < _maxPages;
  bool get _isSearching => _query.trim().isNotEmpty;

  List<Account> get _filtered {
    if (!_isSearching) return _items;
    final q = _query.trim().toLowerCase();
    return _items.where((a) => a.email.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // __REST__
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 120) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isSearching) return;
    setState(() => _isLoadingMore = true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _items.addAll(_generatePage(_page));
      _page += 1;
      _isLoadingMore = false;
    });
  }

  Future<void> _onRefresh() async {
    setState(() => _isRefreshing = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(kMockAccounts);
      _page = 1;
      _isLoadingMore = false;
      _isRefreshing = false;
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
    final showFooter = !_isSearching && (_hasMore || _isLoadingMore);
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
            _SearchBox(
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                // 隐藏 Material 悬浮圆环，改用下方 _RefreshHeader 将列表下移并在顶部显示 loading
                color: Colors.transparent,
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: Column(
                  children: [
                    _RefreshHeader(active: _isRefreshing),
                    Expanded(
                      child: _AccountList(
                        controller: _scrollController,
                        accounts: _filtered,
                        showFooter: showFooter,
                        isLoadingMore: _isLoadingMore,
                      ),
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

// __REST2__
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
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
    return PopupMenuButton<String>(
      tooltip: '更多',
      offset: const Offset(0, 40),
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      icon: Icon(
        Icons.more_horiz,
        color: palette.textPrimary,
        size: 26,
      ),
      onSelected: (value) {
        switch (value) {
          case 'import':
            // TODO: 打开导入流程
            break;
          case 'settings':
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsPage(),
              ),
            );
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'import',
          child: Row(
            children: [
              Icon(Icons.file_upload_outlined,
                  color: palette.textPrimary, size: 20),
              const SizedBox(width: 12),
              Text(l10n.menuImport,
                  style: TextStyle(color: palette.textPrimary, fontSize: 15)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined,
                  color: palette.textPrimary, size: 20),
              const SizedBox(width: 12),
              Text(l10n.menuSettings,
                  style: TextStyle(color: palette.textPrimary, fontSize: 15)),
            ],
          ),
        ),
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
  static const BorderRadius _pillRadius =
      BorderRadius.all(Radius.circular(100));

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
          prefixIcon: Icon(Icons.search, color: palette.textSecondary, size: 20),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 38, minHeight: 0),
          contentPadding:
              const EdgeInsets.fromLTRB(4, 9, 12, 9),
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
  const _AccountList({
    required this.controller,
    required this.accounts,
    required this.showFooter,
    required this.isLoadingMore,
  });

  final ScrollController controller;
  final List<Account> accounts;
  final bool showFooter;
  final bool isLoadingMore;

  @override
  Widget build(BuildContext context) {
    final itemCount = accounts.length + (showFooter ? 1 : 0);
    return ListView.separated(
      controller: controller,
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (context, index) {
        // footer（加载更多）前不显示分隔线
        if (showFooter && index == accounts.length - 1) {
          return const SizedBox.shrink();
        }
        return Divider(
          color: context.palette.divider,
          height: 1,
          thickness: 1,
          indent: 20,
          endIndent: 20,
        );
      },
      itemBuilder: (context, index) {
        if (showFooter && index == accounts.length) {
          return _LoadMoreFooter(loading: isLoadingMore);
        }
        return AccountTile(account: accounts[index], onTap: () {});
      },
    );
  }
}

/// 下拉刷新时置于列表顶部的加载头：激活时高度从 0 展开，把列表整体下移并显示转圈。
class _RefreshHeader extends StatelessWidget {
  const _RefreshHeader({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: active ? 56 : 0,
        width: double.infinity,
        child: active
            ? Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// 底部「加载更多」提示：加载中转圈，否则显示上拉文案；无更多时整体不渲染。
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
                ),
              )
            : Text(
                AppLocalizations.of(context).loadMore,
                style: TextStyle(color: palette.textSecondary, fontSize: 13),
              ),
      ),
    );
  }
}



