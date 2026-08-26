import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 顶部统计项（总账号 / 有效账号 / 异常账号）—— 扁平无背景、无圆角。
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 13,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}
