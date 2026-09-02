import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 菜单选项之间的分割线 —— 与邮箱列表分隔线保持一致（同色、细、左右缩进 20）。
///
/// 首页右上角「导入 / 设置」与新建邮件页收件人胶囊菜单共用同一份，保证两处观感一致。
class AppMenuDivider extends PopupMenuEntry<Never> {
  const AppMenuDivider({super.key});

  @override
  double get height => 1;

  @override
  bool represents(void value) => false;

  @override
  State<AppMenuDivider> createState() => _AppMenuDividerState();
}

class _AppMenuDividerState extends State<AppMenuDivider> {
  @override
  Widget build(BuildContext context) {
    // 分隔线取主题列表分隔色，随明/暗切换，保持与邮箱列表一致的观感。
    return Divider(
      color: context.palette.divider,
      height: 1,
      thickness: 1,
      indent: 20,
      endIndent: 20,
    );
  }
}

/// 菜单项一行：图标 + 文案（颜色随主题自适应）。
///
/// 同上，首页与新建邮件页的菜单共用，选项行式保持一致。
class AppMenuRow extends StatelessWidget {
  const AppMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 15, letterSpacing: 1.5),
        ),
      ],
    );
  }
}
