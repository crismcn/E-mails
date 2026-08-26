// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Email Manager';

  @override
  String get statTotal => 'Total';

  @override
  String get statValid => 'Valid';

  @override
  String get statError => 'Issues';

  @override
  String get filterAllGroups => 'All Groups';

  @override
  String get searchHint => 'Search email';

  @override
  String get menuImport => 'Import';

  @override
  String get menuSettings => 'Settings';

  @override
  String get loadMore => 'Pull up to load more';

  @override
  String get unread => 'Unread';

  @override
  String get statusValid => 'Valid';

  @override
  String get statusTokenExpired => 'Token Expired';

  @override
  String get statusPasswordError => 'Password Error';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsLanguage => 'Language';
}
