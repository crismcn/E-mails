import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:email_manager/api/api_service.dart';
import 'package:email_manager/core/auth/credentials_store.dart';
import 'package:email_manager/main.dart';
import 'package:email_manager/settings/settings_controller.dart';

import 'fake_mail_api.dart';

/// 打开「首页 → 邮件列表」，邮件数据来自注入的 [FakeMailApi]。
///
/// 现在点击列表项**直接进入详情页**（会话页已移除），详情页按 id 懒取全文。
Future<void> _pumpList(WidgetTester tester, [FakeMailApi? mailApi]) async {
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
    mailApi: mailApi ?? FakeMailApi(),
  );
  await tester.pumpWidget(
    EmailManagerApp(settings: SettingsController(prefs), api: api),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('alice@outlook.com'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('点击列表项 → 直接进入详情页，懒取 HTML 全文并渲染可点击链接', (
    WidgetTester tester,
  ) async {
    await _pumpList(tester);

    // 「蓝湖官方」对应最新未读消息 c3-3（HTML 全文）。
    await tester.tap(find.text('蓝湖官方'));
    await tester.pumpAndSettle();

    // 详情页懒取全文后：收件人行 + HTML 正文（链接文字、按钮文字）。
    // HtmlWidget 用 RichText 渲染，需 findRichText: true 才能匹配其中文本。
    expect(find.text('收件人：'), findsOneWidget);
    expect(find.byType(HtmlWidget), findsOneWidget);
    expect(
      find.textContaining('https://example.com/detail', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('前往安全中心', findRichText: true), findsOneWidget);
  });

  testWidgets('点击列表项 → 详情页懒取纯文本全文按纯文本渲染', (WidgetTester tester) async {
    await _pumpList(tester);

    // 「Claude」对应 m1，全文为纯文本。
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    expect(find.text('收件人：'), findsOneWidget);
    expect(find.byType(HtmlWidget), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('纯文本正文'), findsOneWidget);
  });

  testWidgets('详情页星标：乐观更新 + PATCH 回写 Graph', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpList(tester, api);

    // 蓝湖 c3-3 服务端未标星 → 进入时空心星。
    await tester.tap(find.text('蓝湖官方'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    // 回写记录到 Graph：c3-3 → flagged true，并提示已标星。
    expect(api.flagUpdates, [('c3-3', true)]);
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.text('已标星'), findsOneWidget);

    // 再点一次取消标星 → 回写 false。
    await tester.tap(find.byIcon(Icons.star));
    await tester.pumpAndSettle();
    expect(api.flagUpdates, [('c3-3', true), ('c3-3', false)]);
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    expect(find.text('已取消标星'), findsOneWidget);
  });

  testWidgets('详情页星标失败：回滚星标态并提示', (WidgetTester tester) async {
    final api = FakeMailApi()..updateFlagFails = true;
    await _pumpList(tester, api);

    await tester.tap(find.text('蓝湖官方'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    // 发起过写回，但失败 → 提示操作失败、星标回滚为空心。
    expect(api.flagUpdates, [('c3-3', true)]);
    expect(find.textContaining('操作失败'), findsOneWidget);
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('详情页进入即回填服务端星标态', (WidgetTester tester) async {
    await _pumpList(tester);

    // Claude（m1）在假数据里已标星 → 懒取全文后星标应为实心。
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byIcon(Icons.star_border), findsNothing);
  });
}
