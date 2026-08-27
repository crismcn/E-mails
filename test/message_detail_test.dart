import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:email_manager/api/api_service.dart';
import 'package:email_manager/core/auth/credentials_store.dart';
import 'package:email_manager/main.dart';
import 'package:email_manager/settings/settings_controller.dart';

/// 打开「首页 → 邮件列表 → 会话页」，停在「蓝湖官方」会话。
Future<void> _pumpThread(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final api = ApiService.create(
    credentialsStore: InMemoryCredentialsStore(const [
      AccountCredentials(
        email: 'alice@outlook.com',
        clientId: 'c',
        refreshToken: 'r',
      ),
    ]),
  );
  await tester.pumpWidget(
    EmailManagerApp(settings: SettingsController(prefs), api: api),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('alice@outlook.com'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('蓝湖官方'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('点击最新消息气泡 → 详情页渲染 HTML 与可点击链接', (WidgetTester tester) async {
    await _pumpThread(tester);

    // 最新一条气泡展示纯文本预览（含「尊敬的用户」），点击进入详情。
    await tester.tap(find.textContaining('尊敬的用户'));
    await tester.pumpAndSettle();

    // 详情页：收件人行 + HTML 正文（链接文字、按钮文字）。
    // HtmlWidget 用 RichText 渲染，需 findRichText: true 才能匹配其中文本。
    expect(find.text('收件人：'), findsOneWidget);
    expect(find.byType(HtmlWidget), findsOneWidget);
    expect(
      find.textContaining('https://example.com/detail', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('前往安全中心', findRichText: true), findsOneWidget);
  });

  testWidgets('点击历史消息气泡 → 详情页按纯文本渲染', (WidgetTester tester) async {
    await _pumpThread(tester);

    // 历史气泡正文为主题文字，取最上面一条点击进入详情（无 HTML）。
    await tester.tap(find.text('蓝湖免费版权益调整通知 尊敬的蓝湖用户').first);
    await tester.pumpAndSettle();

    expect(find.text('收件人：'), findsOneWidget);
    expect(find.byType(HtmlWidget), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('详情页星标点击切换', (WidgetTester tester) async {
    await _pumpThread(tester);

    await tester.tap(find.textContaining('尊敬的用户'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_border), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byIcon(Icons.star_border), findsNothing);
  });
}
