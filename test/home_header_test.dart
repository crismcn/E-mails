import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:email_manager/api/api_service.dart';
import 'package:email_manager/core/auth/credentials_store.dart';
import 'package:email_manager/main.dart';
import 'package:email_manager/settings/settings_controller.dart';
import 'package:email_manager/widgets/stat_card.dart';

/// 预置账号（含 alice / james，供滚动定位断言）。
const List<String> _kEmails = [
  'alice@outlook.com',
  'tom@outlook.com',
  'william@outlook.com',
  'emma@outlook.com',
  'james@outlook.com',
  'sophia@outlook.com',
];

/// 以较矮的手机视口打开首页，保证示例账号列表可滚动。
Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 1200);
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
  );
  await tester.pumpWidget(
    EmailManagerApp(settings: SettingsController(prefs), api: api),
  );
  await tester.pumpAndSettle();
}

double _dy(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

/// 上滑 [delta] 逻辑像素（不带惯性；实际滚动量会扣掉触摸 slop）。
Future<void> _scrollUp(WidgetTester tester, double delta) async {
  await tester.drag(find.byType(CustomScrollView), Offset(0, -delta));
  await tester.pump();
}

void main() {
  /// 可折叠的量 —— 与 `_HomeHeaderDelegate._titleBand` 一致。
  const double titleBand = 70;

  final title = find.text('邮箱管理');
  // 汇总条的定位基准 —— 取第一张统计卡顶部（等价于旧断言里的数字位置）。
  final stats = find.byType(StatCard).first;
  final search = find.text('搜索邮箱号');

  testWidgets('首页上滑：汇总、搜索框、列表同步上移，标题被一起顶出', (WidgetTester tester) async {
    await _pumpHome(tester);

    final titleDy = _dy(tester, title);
    final statsDy = _dy(tester, stats);
    final searchDy = _dy(tester, search);
    final itemDy = _dy(tester, find.text('alice@outlook.com'));
    // 初始态：标题在最上，汇总、搜索框依次在下。
    expect(statsDy, greaterThan(titleDy));
    expect(searchDy, greaterThan(statsDy));

    await _scrollUp(tester, 40);

    final moved = statsDy - _dy(tester, stats);
    // 尚未吸顶：汇总上移了一段但不足一个标题条。
    expect(moved, greaterThan(0));
    expect(moved, lessThan(titleBand));
    // 搜索框、列表、以及标题本身都同步上移同样距离（标题被顶出，而非被覆盖）。
    expect(searchDy - _dy(tester, search), closeTo(moved, 0.01));
    expect(
      itemDy - _dy(tester, find.text('alice@outlook.com')),
      closeTo(moved, 0.01),
    );
    expect(titleDy - _dy(tester, title), closeTo(moved, 0.01));
  });

  testWidgets('首页上滑：标题顶出后汇总与搜索框吸顶，列表继续滚动', (WidgetTester tester) async {
    await _pumpHome(tester);

    final titleDy = _dy(tester, title);
    final statsDy = _dy(tester, stats);
    final searchDy = _dy(tester, search);

    // 滑过标题条：汇总恰好上移一个标题条高度后吸顶，标题被顶出同样距离。
    await _scrollUp(tester, 200);
    final pinnedStats = _dy(tester, stats);
    final pinnedSearch = _dy(tester, search);
    expect(statsDy - pinnedStats, closeTo(titleBand, 1));
    expect(searchDy - pinnedSearch, closeTo(titleBand, 1));
    // 标题被顶到吸顶区之上（离开可视顶部）。
    expect(titleDy - _dy(tester, title), closeTo(titleBand, 1));
    expect(pinnedStats, lessThanOrEqualTo(titleDy));

    // 列表继续上滑，汇总与搜索框不再移动。
    final itemDy = _dy(tester, find.text('james@outlook.com'));
    await _scrollUp(tester, 40);
    expect(_dy(tester, stats), closeTo(pinnedStats, 0.01));
    expect(_dy(tester, search), closeTo(pinnedSearch, 0.01));
    expect(_dy(tester, find.text('james@outlook.com')), lessThan(itemDy));
  });

  testWidgets('首页上滑：右上角「…」菜单固定不动且仍可点开', (WidgetTester tester) async {
    await _pumpHome(tester);

    final menu = find.byType(PopupMenuButton<String>);
    final menuDy = _dy(tester, menu);

    await _scrollUp(tester, 200);
    expect(_dy(tester, menu), closeTo(menuDy, 0.01));

    // 被汇总覆盖后仍浮在最上层、可点击。
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('导入'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
