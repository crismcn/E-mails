import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:email_manager/api/api_service.dart';
import 'package:email_manager/core/auth/credentials_store.dart';
import 'package:email_manager/main.dart';
import 'package:email_manager/settings/settings_controller.dart';

Future<SettingsController> _newController([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return SettingsController(prefs);
}

/// 内存版组合根 —— 预置若干已导入账号，免平台通道。
ApiService _seededApi([Iterable<AccountCredentials> seed = _kSeed]) {
  return ApiService.create(credentialsStore: InMemoryCredentialsStore(seed));
}

const List<AccountCredentials> _kSeed = [
  AccountCredentials(
    email: 'alice@outlook.com',
    clientId: 'c',
    refreshToken: 'r',
  ),
  AccountCredentials(
    email: 'tom@outlook.com',
    clientId: 'c',
    refreshToken: 'r',
  ),
  AccountCredentials(
    email: 'william@outlook.com',
    clientId: 'c',
    refreshToken: 'r',
  ),
];

Future<void> _pumpApp(
  WidgetTester tester,
  SettingsController settings, {
  ApiService? api,
}) async {
  await tester.pumpWidget(
    EmailManagerApp(settings: settings, api: api ?? _seededApi()),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('列表项：有显示名时主行显示 displayName、次行显示邮箱号',
      (WidgetTester tester) async {
    await _pumpApp(
      tester,
      await _newController(),
      api: _seededApi(const [
        AccountCredentials(
          email: 'zoe@outlook.com',
          clientId: 'c',
          refreshToken: 'r',
          status: AccountCredentials.statusValid,
          displayName: '佐伊',
        ),
      ]),
    );

    // 主行 = 显示名；次行 = 邮箱号（不再显示「有效 · Graph」）。
    expect(find.text('佐伊'), findsOneWidget);
    expect(find.text('zoe@outlook.com'), findsOneWidget);
    expect(find.text('有效 · Graph'), findsNothing);
  });

  testWidgets('列表项：无显示名时回退——主行邮箱号、次行「状态 · 协议」',
      (WidgetTester tester) async {
    await _pumpApp(
      tester,
      await _newController(),
      api: _seededApi(const [
        AccountCredentials(email: 'zoe@outlook.com', clientId: 'c', refreshToken: 'r'),
      ]),
    );

    // 未检测（无显示名）：主行仍是邮箱号，次行保留状态文案。
    expect(find.text('zoe@outlook.com'), findsOneWidget);
    expect(find.text('未知 · Graph'), findsOneWidget);
  });

  testWidgets('首页渲染核心元素', (WidgetTester tester) async {
    await _pumpApp(tester, await _newController());

    expect(find.text('邮箱管理'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    // 汇总取自落盘账号：3 个刚载入均为「未知」→ 总数 3、有效 0、异常 0。
    expect(find.text('3'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2));

    // 搜索框与列表项（来自已持久化的账号）
    expect(find.text('搜索邮箱号'), findsOneWidget);
    expect(find.text('alice@outlook.com'), findsOneWidget);
  });

  testWidgets('搜索框按邮箱号过滤列表', (WidgetTester tester) async {
    await _pumpApp(tester, await _newController());

    await tester.enterText(find.byType(TextField), 'tom');
    await tester.pumpAndSettle();

    expect(find.text('tom@outlook.com'), findsOneWidget);
    expect(find.text('alice@outlook.com'), findsNothing);
    // 搜索时隐藏「上拉加载更多」文案
    expect(find.text('上拉加载更多'), findsNothing);
  });

  testWidgets('列表支持下拉刷新', (WidgetTester tester) async {
    await _pumpApp(tester, await _newController());

    expect(find.byType(EasyRefresh), findsOneWidget);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 300),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    // easy_refresh 的 processedDuration 是一次性 Timer，pumpAndSettle 不会抽干。
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('alice@outlook.com'), findsOneWidget);
  });

  testWidgets('进入导入页并粘贴数据确认导入', (WidgetTester tester) async {
    await _pumpApp(tester, await _newController());

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    // 分组与确认按钮（格式说明在列表下方需滚动，此处不断言）
    expect(find.text('导入 CSV 文件'), findsOneWidget);
    expect(find.text('或 粘贴数据'), findsOneWidget);
    expect(find.text('确认导入'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('import-paste-field')),
      'new@outlook.com----pass----cid----token----2024-01-01 10:00:00',
    );
    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();

    expect(find.text('成功导入 1 个邮箱'), findsOneWidget);
  });

  testWidgets('导入页空数据提示', (WidgetTester tester) async {
    await _pumpApp(tester, await _newController());

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('确认导入'));
    await tester.pump();

    expect(find.text('请先粘贴数据或选择 CSV 文件'), findsOneWidget);
  });

  testWidgets('「…」菜单展开导入与设置', (WidgetTester tester) async {
    await _pumpApp(tester, await _newController());

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('导入'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    // 导入项使用上传图标
    expect(find.byIcon(Icons.file_upload_outlined), findsOneWidget);
  });

  testWidgets('进入设置页并切换语言为英文', (WidgetTester tester) async {
    await _pumpApp(tester, await _newController());

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('暗黑'), findsOneWidget);
    expect(find.text('亮白'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
  });

  testWidgets('设置持久化：切换后新建 controller 仍保留选择', (WidgetTester tester) async {
    final controller = await _newController();
    await _pumpApp(tester, controller);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('亮白'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    // 读取同一份已被写入的 prefs 重建 controller，验证持久化
    final prefs = await SharedPreferences.getInstance();
    final restored = SettingsController(prefs);
    expect(restored.themeMode, ThemeMode.light);
    expect(restored.locale.languageCode, 'en');
  });

  testWidgets('主题选择「跟随系统」并持久化', (WidgetTester tester) async {
    await _pumpApp(tester, await _newController());

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    // 三个主题选项均在
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('暗黑'), findsOneWidget);
    expect(find.text('亮白'), findsOneWidget);

    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(SettingsController(prefs).themeMode, ThemeMode.system);
  });

  testWidgets('启动时读取已持久化的设置（英文+亮色）', (WidgetTester tester) async {
    final controller = await _newController({
      'settings.themeMode': 'light',
      'settings.locale': 'en',
    });
    await _pumpApp(tester, controller);

    expect(find.text('Email Manager'), findsOneWidget);
  });
}
