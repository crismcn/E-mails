import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置状态 —— 主题模式与语言，运行时可切换并持久化。
///
/// 通过 [SettingsScope] 注入到 Widget 树，页面用
/// `SettingsScope.of(context)` 读取并调用切换方法。
///
/// 持久化：使用 [SharedPreferences]，每次切换即写盘，App 重启后恢复。
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs)
    : _themeMode = _readThemeMode(_prefs),
      _locale = _readLocale(_prefs);

  final SharedPreferences _prefs;

  static const String _kThemeKey = 'settings.themeMode';
  static const String _kLocaleKey = 'settings.locale';

  ThemeMode _themeMode;
  ThemeMode get themeMode => _themeMode;

  Locale _locale;
  Locale get locale => _locale;

  bool get isDark => _themeMode == ThemeMode.dark;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    _prefs.setString(_kThemeKey, mode.name);
    notifyListeners();
  }

  void setLocale(Locale locale) {
    if (_locale.languageCode == locale.languageCode) return;
    _locale = locale;
    _prefs.setString(_kLocaleKey, locale.languageCode);
    notifyListeners();
  }

  static ThemeMode _readThemeMode(SharedPreferences prefs) {
    final value = prefs.getString(_kThemeKey);
    return switch (value) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  static Locale _readLocale(SharedPreferences prefs) {
    final value = prefs.getString(_kLocaleKey);
    return value == 'en' ? const Locale('en') : const Locale('zh');
  }
}

/// 将 [SettingsController] 沿 Widget 树向下提供。
class SettingsScope extends InheritedNotifier<SettingsController> {
  const SettingsScope({
    super.key,
    required SettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static SettingsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, '未找到 SettingsScope，请在根部包裹。');
    return scope!.notifier!;
  }
}
