import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' as physics;

/// 边缘回弹的「小幅 + 迅速」参数 —— 全局与 EasyRefresh 共用同一套，观感一致。
///
/// 阻力系数语义（见 [BouncingScrollPhysics.applyPhysicsToUserOffset]）：
/// 返回值会**乘到**用户拖动量上，所以**值越小越硬**（越过界越拖不动）。
/// iOS 默认 0.52；这里取 0.4 → 过冲距离约为默认的 3/4，只「一点点」，
/// 同时不至于让下拉刷新变得费力（拉到 triggerOffset 仍轻松）。
double snappyFrictionFactor(double overscrollFraction) =>
    0.4 * math.pow(1 - overscrollFraction, 2);

/// 回弹弹簧 —— iOS 默认 stiffness 100 / ratio 1.1（收尾偏拖沓）；
/// 这里加硬到 180 并取临界阻尼 1.0，松手后一次收口、不来回晃，够「迅速」。
final physics.SpringDescription kSnappySpring =
    physics.SpringDescription.withDampingRatio(
      mass: 0.5,
      stiffness: 180,
      ratio: 1.0,
    );

/// 全局滚动行为：边缘带「一点点、且迅速」的回弹。
///
/// 此前是完全禁用回弹（Clamping，到边界急停），但急停观感生硬；改为在 iOS 回弹
/// 物理上收敛（[_SnappyBouncePhysics]）：小幅过冲 + 干脆收口。
/// 系统的边缘光晕/拉伸指示器仍关闭（只要位移回弹，不要 Android 的发光）。
///
/// **注意**：`MaterialApp.scrollBehavior` 管不到 `EasyRefresh` 内部 ——
/// 它会用自己的 `_ERScrollPhysics` 覆盖滚动物理。那些页面需在 `EasyRefresh(...)`
/// 上显式传 `spring: kSnappySpring, frictionFactor: snappyFrictionFactor`。
class SmallBounceScrollBehavior extends MaterialScrollBehavior {
  const SmallBounceScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const _SnappyBouncePhysics();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// 小幅且迅速的回弹物理 —— 参数见 [snappyFrictionFactor] / [kSnappySpring]。
class _SnappyBouncePhysics extends BouncingScrollPhysics {
  const _SnappyBouncePhysics({super.parent});

  @override
  double frictionFactor(double overscrollFraction) =>
      snappyFrictionFactor(overscrollFraction);

  @override
  physics.SpringDescription get spring => kSnappySpring;

  @override
  _SnappyBouncePhysics applyTo(ScrollPhysics? ancestor) =>
      // applyTo 在运行时调用，不能是 const 构造。
      _SnappyBouncePhysics(parent: buildParent(ancestor));
}
