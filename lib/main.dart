import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_localizations.dart';
import 'pages/home_page.dart';
import 'settings/settings_controller.dart';
import 'theme/app_scroll_behavior.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(EmailManagerApp(settings: SettingsController(prefs)));
}

class EmailManagerApp extends StatefulWidget {
  const EmailManagerApp({super.key, required this.settings});

  final SettingsController settings;

  @override
  State<EmailManagerApp> createState() => _EmailManagerAppState();
}

class _EmailManagerAppState extends State<EmailManagerApp> {
  @override
  void dispose() {
    widget.settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return SettingsScope(
      controller: settings,
      child: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          final platformDark =
              WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                  Brightness.dark;
          final effectiveDark = switch (settings.themeMode) {
            ThemeMode.dark => true,
            ThemeMode.light => false,
            ThemeMode.system => platformDark,
          };
          SystemChrome.setSystemUIOverlayStyle(
            effectiveDark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
          );
          return MaterialApp(
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            debugShowCheckedModeBanner: false,
            scrollBehavior: const NoStretchScrollBehavior(),
            themeMode: settings.themeMode,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            locale: settings.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomePage(),
          );
        },
      ),
    );
  }
}

