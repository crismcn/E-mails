import 'package:flutter/material.dart';

/// 全局滚动行为：取消所有页面的「拉升回弹 / 边缘拉伸光晕」效果。
///
/// - `getScrollPhysics` 返回 [ClampingScrollPhysics]，滚动到边界即停，无 iOS 回弹。
/// - `buildOverscrollIndicator` 直接返回子组件，去掉 Android 的边缘拉伸/发光指示器。
///
/// 通过 `MaterialApp.scrollBehavior` 挂载后，全项目（含后续新增页面）自动生效，
/// 页面内的 `ListView` 等无需再单独设置 physics。
class NoStretchScrollBehavior extends MaterialScrollBehavior {
  const NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}
