import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:email_manager/api/api_service.dart';
import 'package:email_manager/core/auth/credentials_store.dart';
import 'package:email_manager/main.dart';
import 'package:email_manager/settings/settings_controller.dart';

/// 以手机尺寸打开「首页 → 邮件列表 → 邮件会话」，停在会话页。
///
/// 选中未读为 1 的「蓝湖官方」会话，便于验证未读胶囊与跳转。
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

/// 会话页列表的滚动控制器。
ScrollController _threadController(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!;

/// 顶部下拉一次以加载一页历史消息，并抽干指示器收起用的延时器。
Future<void> _loadHistory(WidgetTester tester) async {
  _threadController(tester).jumpTo(0);
  await tester.pumpAndSettle();
  await tester.fling(find.byType(ListView), const Offset(0, 400), 1200);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pumpAndSettle();
  // easy_refresh 的 processedDuration 是一次性 Timer，pumpAndSettle 不会抽干。
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('会话页：最近一条详细展示，较早的简化展示', (WidgetTester tester) async {
    await _pumpThread(tester);

    // 初始三条消息的时间标签均在。
    expect(find.text('8/24 14:58'), findsOneWidget);
    expect(find.text('8/24 15:00'), findsOneWidget);
    expect(find.text('8/24 15:02'), findsOneWidget);
    // 最近一条完整正文（简化展示的两条不含这段）。
    expect(find.textContaining('尊敬的用户'), findsOneWidget);
  });

  testWidgets('会话页：下拉加载更多历史邮件', (WidgetTester tester) async {
    await _pumpThread(tester);

    expect(find.text('8/23 09:05'), findsNothing);

    await _loadHistory(tester);

    // 第一页历史（8/23）整段插入列表头部，保持时间正序。
    expect(find.text('8/23 09:05'), findsOneWidget);
  });

  testWidgets('会话页：点击未读条数跳转到最新未读', (WidgetTester tester) async {
    await _pumpThread(tester);

    expect(find.text('1 封未读'), findsOneWidget);

    // 加载两页历史，把未读消息（8/24 15:00）推到列表靠后、可视区之外。
    await _loadHistory(tester);
    await _loadHistory(tester);
    _threadController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('8/24 15:00'), findsNothing);

    await tester.tap(find.text('1 封未读'));
    await tester.pumpAndSettle();

    // 已滚动到未读消息，且对齐在视口靠上位置。
    expect(find.text('8/24 15:00'), findsOneWidget);
    expect(tester.getTopLeft(find.text('8/24 15:00')).dy, lessThan(260));
  });
}
