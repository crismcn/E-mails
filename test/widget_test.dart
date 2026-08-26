import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:email_manager/main.dart';
import 'package:email_manager/settings/settings_controller.dart';

Future<SettingsController> _newController([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return SettingsController(prefs);
}

Future<void> _pumpApp(WidgetTester tester, SettingsController settings) async {
  await tester.pumpWidget(EmailManagerApp(settings: settings));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首页渲染核心元素', (WidgetTester tester) async {
    await _pumpApp(tester, await _newController());

    expect(find.text('邮箱管理'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    expect(find.text('1268'), findsOneWidget);
    expect(find.text('1123'), findsOneWidget);
    expect(find.text('145'), findsOneWidget);

    // 搜索框与列表项
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

    expect(find.byType(RefreshIndicator), findsOneWidget);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(find.text('alice@outlook.com'), findsOneWidget);
  });

  testWidgets('下拉刷新时顶部显示加载动画', (WidgetTester tester) async {
    await _pumpApp(tester, await _newController());

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 刷新进行中，顶部加载头的转圈应可见
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    expect(find.text('alice@outlook.com'), findsOneWidget);
  });

  testWidgets('「…」菜单展开导入与设置', (WidgetTester tester) async {
    await _pumpApp(tester, await _newController());

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    expect(find.text('导入'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    // 导入项使用上传图标
    expect(find.byIcon(Icons.file_upload_outlined), findsOneWidget);
  });

  testWidgets('进入设置页并切换语言为英文', (WidgetTester tester) async {
    await _pumpApp(tester, await _newController());

    await tester.tap(find.byIcon(Icons.more_horiz));
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

  testWidgets('设置持久化：切换后新建 controller 仍保留选择',
      (WidgetTester tester) async {
    final controller = await _newController();
    await _pumpApp(tester, controller);

    await tester.tap(find.byIcon(Icons.more_horiz));
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

    await tester.tap(find.byIcon(Icons.more_horiz));
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

  testWidgets('启动时读取已持久化的设置（英文+亮色）',
      (WidgetTester tester) async {
    final controller = await _newController({
      'settings.themeMode': 'light',
      'settings.locale': 'en',
    });
    await _pumpApp(tester, controller);

    expect(find.text('Email Manager'), findsOneWidget);
  });
}
