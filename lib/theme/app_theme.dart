import 'package:flutter/material.dart';

import 'app_palette.dart';

/// 应用主题 —— 明/暗两套，均挂载 [AppPalette] 扩展。
class AppTheme {
  AppTheme._();

  static final ThemeData dark = _build(Brightness.dark, AppPalette.dark);
  static final ThemeData light = _build(Brightness.light, AppPalette.light);

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.primary,
        brightness: brightness,
      ).copyWith(surface: palette.background),
      fontFamily: '.SF Pro Text',
      extensions: <ThemeExtension<dynamic>>[palette],
    );
  }
}
