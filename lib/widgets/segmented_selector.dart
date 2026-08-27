import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 类 Tabs 的分段选择器 —— 选中项以滑动指示块过渡高亮。
///
/// 无外描边，仅一层轨道底色 + 圆角指示块，选中文字随之淡入高亮。
class SegmentedSelector extends StatelessWidget {
  const SegmentedSelector({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final count = segments.length;
    // 指示块水平对齐：单段居中，多段在 [-1, 1] 间均分。
    final double alignX =
        count <= 1 ? 0 : -1 + 2 * selectedIndex / (count - 1);

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          // 滑动高亮指示块
          AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: Alignment(alignX, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / count,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          // 分段标签
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < count; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          style: TextStyle(
                            color: i == selectedIndex
                                ? Colors.white
                                : palette.textSecondary,
                            fontSize: 14,
                            fontWeight: i == selectedIndex
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          child: Text(segments[i]),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
