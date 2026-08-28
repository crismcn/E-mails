import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:email_manager/theme/app_scroll_behavior.dart';

/// 造一个可滚动的长列表页，用给定的 [behavior] 作为全局滚动行为。
Future<ScrollController> _pumpList(
  WidgetTester tester,
  ScrollBehavior behavior,
) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      scrollBehavior: behavior,
      home: Scaffold(
        body: ListView.builder(
          controller: controller,
          itemCount: 60,
          itemBuilder: (context, i) => SizedBox(height: 60, child: Text('$i')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

/// 在顶部分多步继续下拉共 [distance]，返回越界量（越界时 pixels 为负）。
///
/// 必须**分步**移动：`applyPhysicsToUserOffset` 只在「本次移动前已越界」时才施加
/// 阻力，一次性 drag 整段距离会全额生效，测不出阻力系数差异。
Future<double> _overscrollAtTop(
  WidgetTester tester,
  ScrollController controller,
  double distance, {
  int steps = 10,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ListView)),
  );
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, distance / steps));
    await tester.pump();
  }
  final pixels = controller.position.pixels;
  await gesture.up();
  await tester.pump();
  return pixels;
}

void main() {
  testWidgets('触顶可越界回弹，且松手后收回到顶部', (WidgetTester tester) async {
    final controller = await _pumpList(
      tester,
      const SmallBounceScrollBehavior(),
    );

    final overscroll = await _overscrollAtTop(tester, controller, 150);
    // 越过顶部边界（若是 ClampingScrollPhysics 会被钳在 0）。
    expect(overscroll, lessThan(0));

    await tester.pumpAndSettle();
    // 回弹结束精确回到顶部。
    expect(controller.position.pixels, 0);
  });

  testWidgets('回弹幅度小于 iOS 默认（只「一点点」）', (WidgetTester tester) async {
    const drag = 150.0;

    final ours = await _pumpList(tester, const SmallBounceScrollBehavior());
    final oursOverscroll = await _overscrollAtTop(tester, ours, drag);
    await tester.pumpAndSettle();

    final defaults = await _pumpList(tester, const _IosDefaultBehavior());
    final defaultOverscroll = await _overscrollAtTop(tester, defaults, drag);
    await tester.pumpAndSettle();

    // 同样的拖动距离，我们的过冲更小（阻力系数 0.4 < iOS 默认 0.52）。
    expect(oursOverscroll.abs(), lessThan(defaultOverscroll.abs()));
  });

  test('回弹弹簧比 iOS 默认更硬、且为临界阻尼（收口迅速不来回晃）', () {
    // iOS 默认：stiffness 100、ratio 1.1。
    expect(kSnappySpring.stiffness, greaterThan(100));
    // 临界阻尼 ζ=1 → damping = 2*sqrt(mass*stiffness)。
    final critical = 2 * (kSnappySpring.mass * kSnappySpring.stiffness);
    expect(kSnappySpring.damping * kSnappySpring.damping, closeTo(critical * 2, 1));
  });

  test('阻力系数随越界比例递减，且始终小于 iOS 默认', () {
    expect(snappyFrictionFactor(0), closeTo(0.4, 1e-9));
    expect(snappyFrictionFactor(0.5), lessThan(snappyFrictionFactor(0)));
    // iOS 默认为 0.52 * (1-f)^2，同比例下我们更硬。
    for (final f in [0.0, 0.25, 0.5, 0.75]) {
      expect(snappyFrictionFactor(f), lessThan(0.52 * (1 - f) * (1 - f)));
    }
  });
}

/// 对照组：iOS 默认回弹（未做收敛）。
class _IosDefaultBehavior extends MaterialScrollBehavior {
  const _IosDefaultBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
