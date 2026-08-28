import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:email_manager/api/api_service.dart';
import 'package:email_manager/api/auth_api.dart';
import 'package:email_manager/api/user_api.dart';
import 'package:email_manager/core/auth/credentials_store.dart';
import 'package:email_manager/core/auth/health_service.dart';
import 'package:email_manager/core/network/api_client.dart';
import 'package:email_manager/main.dart';
import 'package:email_manager/settings/settings_controller.dart';

const List<String> _kEmails = [
  'alice@outlook.com',
  'tom@outlook.com',
  'william@outlook.com',
];

/// 假健康检测 —— 按邮箱返回预置结论，不触网。
class _FakeHealthService extends HealthService {
  _FakeHealthService(this.statuses)
    : super(
        authApi: AuthApi(ApiClient(Dio())),
        userApi: UserApi(ApiClient(Dio())),
        credentialsStore: InMemoryCredentialsStore(const []),
      );

  /// 未列出的邮箱默认判为健康。
  final Map<String, HealthStatus> statuses;

  @override
  Future<HealthReport> check(String email) async => HealthReport(
    email: email,
    status: statuses[email] ?? HealthStatus.ok,
    message: 'fake',
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  HealthService? healthService,
}) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final api = ApiService.create(
    credentialsStore: InMemoryCredentialsStore([
      for (final e in _kEmails)
        AccountCredentials(email: e, clientId: 'c', refreshToken: 'r'),
    ]),
    healthService: healthService,
  );
  await tester.pumpWidget(
    EmailManagerApp(settings: SettingsController(prefs), api: api),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('长按进入多选：标题、选择圈、底部操作栏', (WidgetTester tester) async {
    await _pumpHome(tester);

    // 常态无「已选择」标题。
    expect(find.textContaining('已选择'), findsNothing);

    await tester.longPress(find.text('alice@outlook.com'));
    await tester.pumpAndSettle();

    // 顶部换成「已选择 1 项」，底部三个操作按钮出现。
    expect(find.text('已选择 1 项'), findsOneWidget);
    expect(find.text('健康检测'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);

    // 再点一项 → 2 项。
    await tester.tap(find.text('tom@outlook.com'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);

    // 全选 → 3 项。
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 3 项'), findsOneWidget);
  });

  testWidgets('多选删除：二次确认后从列表移除', (WidgetTester tester) async {
    await _pumpHome(tester);

    await tester.longPress(find.text('alice@outlook.com'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 确认弹窗。
    expect(find.text('删除邮箱'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    // 已退出多选且 alice 被移除，其余仍在。
    expect(find.textContaining('已选择'), findsNothing);
    expect(find.text('alice@outlook.com'), findsNothing);
    expect(find.text('tom@outlook.com'), findsOneWidget);
  });

  testWidgets('关闭按钮退出多选', (WidgetTester tester) async {
    await _pumpHome(tester);

    await tester.longPress(find.text('alice@outlook.com'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选择'), findsNothing);
    // 退出后恢复常态标题。
    expect(find.text('邮箱管理'), findsOneWidget);
  });

  testWidgets('列表上滑后进入多选：顶部选择栏仍可见（不随滚动消失）', (WidgetTester tester) async {
    await _pumpHome(tester);

    // 先把列表上滑一段（常态标题条被顶出吸顶区之外）。
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -240));
    await tester.pump();

    // 此时长按进入多选：选择栏是独立于列表之上的一条，应可见且贴顶。
    await tester.longPress(find.text('william@outlook.com'));
    await tester.pumpAndSettle();

    final bar = find.text('已选择 1 项');
    expect(bar, findsOneWidget);
    // 贴近顶部（安全区下方一点点），证明它没被滚动带走。
    expect(tester.getTopLeft(bar).dy, lessThan(80));
  });

  testWidgets('批量健康检测：通过记为有效、凭据失效记为 Token 过期', (WidgetTester tester) async {
    await _pumpHome(
      tester,
      healthService: _FakeHealthService(const {
        'tom@outlook.com': HealthStatus.credentialsInvalid,
      }),
    );

    // 载入时状态为「未知」，尚无「Token 过期」。
    expect(find.text('Token 过期 · Graph'), findsNothing);

    await tester.longPress(find.text('alice@outlook.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('健康检测'));
    await tester.pumpAndSettle();

    // 检测完自动退出多选，汇总提示 2 正常 / 1 异常。
    expect(find.textContaining('已选择'), findsNothing);
    expect(find.text('检查完成：正常 2，异常 1'), findsOneWidget);
    // tom 被标为 Token 过期，其余仍有效；异常统计卡随之变为 1。
    expect(find.text('Token 过期 · Graph'), findsOneWidget);
    expect(find.text('有效 · Graph'), findsNWidgets(2));
  });

  testWidgets('健康检测遇网络错误：不改判账号状态', (WidgetTester tester) async {
    await _pumpHome(
      tester,
      healthService: _FakeHealthService(const {
        'tom@outlook.com': HealthStatus.networkError,
      }),
    );

    await tester.longPress(find.text('tom@outlook.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('健康检测'));
    await tester.pumpAndSettle();

    expect(find.text('检查完成：正常 0，异常 1'), findsOneWidget);
    // 网络问题与凭据无关：状态保持原样，不误标为 Token 过期。
    expect(find.text('Token 过期 · Graph'), findsNothing);
  });
}
