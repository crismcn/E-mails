import 'package:flutter/material.dart';

/// 主题调色板 —— 以 [ThemeExtension] 形式随明/暗主题切换。
///
/// 页面与组件统一通过 `context.palette` 取色，
/// 从而在切换主题时自动重建为对应配色，无需散落硬编码颜色。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.card,
    required this.cardHighlight,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.statusValid,
    required this.statusWarning,
    required this.statusError,
    required this.glow,
  });

  final Color background;
  final Color card;
  final Color cardHighlight;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color primary;
  final Color statusValid;
  final Color statusWarning;
  final Color statusError;
  final Color glow;

  /// 暗色（默认）—— 参照「邮箱管理」设计稿。
  static const AppPalette dark = AppPalette(
    background: Color(0xFF0A0D12),
    card: Color(0xFF141A24),
    cardHighlight: Color(0xFF162238),
    divider: Color(0xFF1B212B),
    textPrimary: Color(0xFFF4F6FA),
    textSecondary: Color(0xFF8B93A0),
    primary: Color(0xFF2F80FF),
    statusValid: Color(0xFF2F80FF),
    statusWarning: Color(0xFFF5A623),
    statusError: Color(0xFFFF4D4F),
    glow: Color(0xFF1E3A8A),
  );

  /// 亮色 —— 简约高级的近白配色，品牌蓝与状态色保持一致。
  static const AppPalette light = AppPalette(
    background: Color(0xFFFFFFFF),
    card: Color(0xFFF4F6FA),
    cardHighlight: Color(0xFFE8F0FF),
    divider: Color(0xFFECEEF2),
    textPrimary: Color(0xFF0A0D12),
    textSecondary: Color(0xFF6B7280),
    primary: Color(0xFF2F80FF),
    statusValid: Color(0xFF2F80FF),
    statusWarning: Color(0xFFF5A623),
    statusError: Color(0xFFFF4D4F),
    glow: Color(0xFFDCE7FF),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? card,
    Color? cardHighlight,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? primary,
    Color? statusValid,
    Color? statusWarning,
    Color? statusError,
    Color? glow,
  }) {
    return AppPalette(
      background: background ?? this.background,
      card: card ?? this.card,
      cardHighlight: cardHighlight ?? this.cardHighlight,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      primary: primary ?? this.primary,
      statusValid: statusValid ?? this.statusValid,
      statusWarning: statusWarning ?? this.statusWarning,
      statusError: statusError ?? this.statusError,
      glow: glow ?? this.glow,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardHighlight: Color.lerp(cardHighlight, other.cardHighlight, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      statusValid: Color.lerp(statusValid, other.statusValid, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusError: Color.lerp(statusError, other.statusError, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
    );
  }
}

/// 便捷取色：`context.palette.textPrimary`。
extension AppPaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
