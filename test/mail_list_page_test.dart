import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:email_manager/api/api_service.dart';
import 'package:email_manager/api/mail_api.dart';
import 'package:email_manager/core/auth/credentials_store.dart';
import 'package:email_manager/core/network/api_code.dart';
import 'package:email_manager/core/network/api_response.dart';
import 'package:email_manager/main.dart';
import 'package:email_manager/settings/settings_controller.dart';

import 'fake_mail_api.dart';

const AccountCredentials _kAlice = AccountCredentials(
  email: 'alice@outlook.com',
  clientId: 'c',
  refreshToken: 'r',
);

/// 打开「首页 → 邮件列表」，邮件数据来自注入的 [FakeMailApi]。
Future<void> _pumpMailList(WidgetTester tester, FakeMailApi mailApi) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    EmailManagerApp(
      settings: SettingsController(prefs),
      api: ApiService.create(
        credentialsStore: InMemoryCredentialsStore(const [_kAlice]),
        mailApi: mailApi,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('alice@outlook.com'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('邮件列表渲染 Graph 返回的发件人与主题', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpMailList(tester, api);

    // 首屏只拉一页，且 skip 从 0 开始。
    expect(api.skips, [0]);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('Claude 任务执行通知 · ✅ 任务已完成'), findsOneWidget);
    expect(find.text('蓝湖官方'), findsOneWidget);
    // 未读消息显示角标「1」（单封消息未读数为 1）。
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('首屏加载失败：整页展示原始错误 + 重试可恢复', (WidgetTester tester) async {
    final failing = FakeMailApi(
      failure: const ApiResponse<GraphMessagePage>.failure(
        ApiCode.unauthorized,
        'AADSTS70000: 授权无效',
      ),
    );
    await _pumpMailList(tester, failing);

    expect(find.text('邮件加载失败'), findsOneWidget);
    // 原始错误原样展示 —— 它是定位 scope/租户问题的唯一线索。
    expect(find.text('AADSTS70000: 授权无效'), findsOneWidget);
    expect(find.text('Claude'), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    // 重试确实又打了一次请求（仍失败，错误页保留）。
    expect(failing.skips, [0, 0]);
    expect(find.text('邮件加载失败'), findsOneWidget);
  });

  testWidgets('账号无邮件时展示空态', (WidgetTester tester) async {
    await _pumpMailList(tester, FakeMailApi(messages: const []));

    expect(find.text('暂无邮件'), findsOneWidget);
    expect(find.text('邮件加载失败'), findsNothing);
  });

  testWidgets('搜索框过滤已加载的邮件', (WidgetTester tester) async {
    await _pumpMailList(tester, FakeMailApi());

    await tester.enterText(find.byType(EditableText).last, 'cursor');
    await tester.pumpAndSettle();

    expect(find.text('Cursor Team'), findsOneWidget);
    expect(find.text('Claude'), findsNothing);
  });

  testWidgets('上滑加载更多：按已加载条数续拉下一页并追加', (WidgetTester tester) async {
    // 首页满 20 条才认为还有下一页；共 25 条 → 第二页 5 条后无更多。
    final api = FakeMailApi(
      messages: [
        for (var i = 0; i < 25; i++)
          fakeGraphMessage(id: 'm$i', fromName: '发件人$i', subject: '主题$i'),
      ],
    );
    await _pumpMailList(tester, api);
    expect(api.skips, [0]);

    await tester.fling(find.byType(Scrollable).last, const Offset(0, -600), 1500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    // easy_refresh 的 processedDuration 是一次性 Timer，pumpAndSettle 不会抽干。
    await tester.pump(const Duration(milliseconds: 400));

    // $skip 用「已加载条数」而非页号 —— 第二页从 20 开始。
    expect(api.skips, [0, 20]);
    // 第 21 条（第二页首条）已进入列表：ListView 懒构建，用搜索过滤到它再断言。
    // 断言发件人而非主题 —— 主题文字此刻也在搜索框里，会匹配到两个 widget。
    await tester.enterText(find.byType(EditableText).last, '主题20');
    await tester.pumpAndSettle();
    expect(find.text('发件人20'), findsOneWidget);
  });

  testWidgets('左滑标记已读：乐观更新 + PATCH 回写 Graph', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpMailList(tester, api);

    // 初始两封未读（Claude m1 + 蓝湖 c3-3），各显示角标「1」。
    expect(find.text('1'), findsNWidgets(2));

    // 左滑 Claude 一行露出动作面板，点「标记已读」。
    await tester.drag(find.text('Claude'), const Offset(-320, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.mark_email_unread_outlined).first);
    await tester.pumpAndSettle();

    // 回写记录到 Graph：m1 → isRead true。
    expect(api.readUpdates, [('m1', true)]);
    expect(find.text('已标记为已读'), findsOneWidget);
    // Claude 变已读 → 未读角标只剩 1 个（蓝湖）。
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('左滑标记已读失败：回滚本地状态并提示', (WidgetTester tester) async {
    final api = FakeMailApi()..updateReadFails = true;
    await _pumpMailList(tester, api);
    expect(find.text('1'), findsNWidgets(2));

    await tester.drag(find.text('Claude'), const Offset(-320, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.mark_email_unread_outlined).first);
    await tester.pumpAndSettle();

    // 发起过写回，但失败 → 提示操作失败、未读角标回滚为 2。
    expect(api.readUpdates, [('m1', true)]);
    expect(find.textContaining('操作失败'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('点击未读邮件进入详情 → 自动标记已读并回写 Graph', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpMailList(tester, api);
    // 初始两封未读（Claude m1 + 蓝湖 c3-3）。
    expect(find.text('1'), findsNWidgets(2));

    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    // 打开即回写：m1 → isRead true。
    expect(api.readUpdates, [('m1', true)]);

    // 返回列表：Claude 未读角标已清，仅剩蓝湖的「1」。
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('点击已读邮件进入详情 → 不重复回写', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpMailList(tester, api);

    // Cursor Team（m2）本就已读，打开不应触发写回。
    await tester.tap(find.text('Cursor Team'));
    await tester.pumpAndSettle();

    expect(api.readUpdates, isEmpty);
  });
}
