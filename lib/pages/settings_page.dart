import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/settings_controller.dart';
import '../theme/app_palette.dart';
import '../widgets/segmented_selector.dart';

/// 设置页 —— 主题与语言切换。
///
/// 选项采用类 Tabs 的分段选择器（[SegmentedSelector]），选中带滑动过渡动画。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const List<ThemeMode> _themeOrder = [
    ThemeMode.system,
    ThemeMode.dark,
    ThemeMode.light,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    final settings = SettingsScope.of(context);

    final themeIndex = _themeOrder.indexOf(settings.themeMode);
    final localeIndex = settings.locale.languageCode == 'en' ? 1 : 0;

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(title: l10n.settingsTitle),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _SectionLabel(l10n.settingsTheme),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SegmentedSelector(
                      segments: [
                        l10n.settingsThemeSystem,
                        l10n.settingsThemeDark,
                        l10n.settingsThemeLight,
                      ],
                      selectedIndex: themeIndex < 0 ? 0 : themeIndex,
                      onChanged: (i) =>
                          settings.setThemeMode(_themeOrder[i]),
                    ),
                  ),
                  const SizedBox(height: 36),
                  _SectionLabel(l10n.settingsLanguage),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SegmentedSelector(
                      segments: const ['中文', 'English'],
                      selectedIndex: localeIndex,
                      onChanged: (i) => settings.setLocale(
                        i == 1 ? const Locale('en') : const Locale('zh'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部标题栏：返回 + 标题，平铺无边框。
class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back,
                color: palette.textPrimary, size: 20),
            splashRadius: 22,
          ),
          const SizedBox(width: 4),
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分组小标题（次要色、间距克制）。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Text(
        text,
        style: TextStyle(
          color: palette.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
