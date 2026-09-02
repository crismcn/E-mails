import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';

/// 搜索框 —— 胶囊形（两端半圆），首页与邮件列表**共用这一份**。
///
/// **高度写死 [kHeight]**：两处曾各写一份，首页被外层 `SizedBox` 夹到 34、邮件列表按
/// 内容自然撑到 35，来回切页面能看出差一线；系统字号放大后差距还会跟着变大（一个被
/// 夹住不动、一个跟着长）。首页吸顶头部要拿这个值算 extent，故它必须是常量而不是
/// 「按内容撑开」。
///
/// **输入非空时右侧出现清除按钮**（叉）：点一下清空并回调 `onChanged('')`，
/// 调用方的过滤条件跟着复位。文本控制器由本组件持有 —— 两处调用方都只关心「当前
/// 输入是什么」，不必各自留一个 controller。
///
/// 左右边距由调用方给（两处都是 20），本组件只负责输入框本身。
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
  });

  /// 提示文案 —— 首页「搜索邮箱号」、邮件列表「搜索邮件」。
  final String hintText;

  final ValueChanged<String> onChanged;

  /// 输入框高度 —— 19 的放大镜 + 14 的文字 + 上下各 7 内边距，取整到 36。
  static const double kHeight = 40;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  /// 规则椭圆：四角同等大圆角，得到两端半圆的胶囊形。
  static const BorderRadius _pillRadius = BorderRadius.all(
    Radius.circular(100),
  );

  static const OutlineInputBorder _border = OutlineInputBorder(
    borderRadius: _pillRadius,
    borderSide: BorderSide.none,
  );

  final TextEditingController _controller = TextEditingController();

  /// 当前有没有内容 —— 只决定清除按钮的显隐，故只在「空 ↔ 非空」翻转时重建。
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncHasText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncHasText() {
    final has = _controller.text.isNotEmpty;
    if (has == _hasText) return;
    setState(() => _hasText = has);
  }

  /// 清空 —— 顺带把空串回调出去（`TextField.onChanged` 不会为程序性修改触发）。
  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: AppSearchField.kHeight,
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        style: TextStyle(color: palette.textPrimary, fontSize: 14),
        cursorColor: palette.primary,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: palette.card,
          hintText: widget.hintText,
          hintStyle: TextStyle(color: palette.textSecondary, fontSize: 14),
          prefixIcon: Icon(
            AppIcons.search,
            color: palette.textSecondary,
            size: 19,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 0,
          ),
          // 清除按钮 —— 空输入时不入树（叉本身就是「有东西可清」的信号）。
          suffixIcon: _hasText ? _ClearButton(onTap: _clear) : null,
          // 不给最小尺寸：`IconButton` 那套 48×48 会把胶囊顶破 [kHeight]。
          suffixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          contentPadding: const EdgeInsets.fromLTRB(4, 7, 12, 7),
          border: _border,
          enabledBorder: _border,
          focusedBorder: _border,
        ),
      ),
    );
  }
}

/// 输入框右侧的清除按钮 —— 叉只有 15，靠内边距把可点区域撑到 33×33。
class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).searchClear,
      child: GestureDetector(
        // 内边距那圈是透明的，不 opaque 就只有叉本身能点中。
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 9, 12, 9),
          child: Icon(AppIcons.close, size: 15, color: palette.textSecondary),
        ),
      ),
    );
  }
}
