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
  String get mailSearchHint => 'Search mail';

  @override
  String refreshLastUpdated(String time) {
    return 'Last updated: $time';
  }

  @override
  String get mailArchived => 'Archived';

  @override
  String get mailDeleted => 'Deleted';

  @override
  String get mailMarkedRead => 'Marked as read';

  @override
  String get mailMarkedUnread => 'Marked as unread';

  @override
  String get loadMoreLoading => 'Loading...';

  @override
  String get loadMoreNoMore => 'No more mail';

  @override
  String get menuImport => 'Import';

  @override
  String get menuSettings => 'Settings';

  @override
  String get loadMore => 'Pull up to load more';

  @override
  String get unread => 'Unread';

  @override
  String get mailReplyHint => 'Reply';

  @override
  String threadUnread(int count) {
    return '$count unread';
  }

  @override
  String get threadLoadHistory => 'Pull down for older mail';

  @override
  String get threadLoadHistoryNoMore => 'No more history';

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

  @override
  String get importTitle => 'Import Emails';

  @override
  String get importCsvSection => 'Import CSV File';

  @override
  String get importCsvHint => 'Tap to choose a CSV file';

  @override
  String get importCsvOnly => 'Only .csv format is supported';

  @override
  String importCsvPicked(String name) {
    return 'Selected: $name';
  }

  @override
  String get importPasteSection => 'Or paste data';

  @override
  String get importPasteHint =>
      'Paste data in the following format:\nemail----password----client_id----refresh_token----created_at\n\nuser1@example.com----123456----xxxx----xxxx----2024-01-01 10:00:00\nuser2@example.com----123456----xxxx----xxxx----2024-01-01 10:00:00';

  @override
  String get importFormatSection => 'Format';

  @override
  String get importFieldEmail => 'email';

  @override
  String get importFieldEmailDesc => 'Email address';

  @override
  String get importFieldPassword => 'password';

  @override
  String get importFieldPasswordDesc => 'Mailbox password';

  @override
  String get importFieldClientId => 'client_id';

  @override
  String get importFieldClientIdDesc => 'App client ID';

  @override
  String get importFieldRefreshToken => 'refresh_token';

  @override
  String get importFieldRefreshTokenDesc => 'Refresh token';

  @override
  String get importFieldCreatedAt => 'created_at';

  @override
  String get importFieldCreatedAtDesc => 'e.g. 2024-01-01 10:00:00';

  @override
  String get importConfirm => 'Confirm Import';

  @override
  String get importEmpty => 'Paste data or choose a CSV file first';

  @override
  String get importNoValid => 'No valid data found, please check the format';

  @override
  String importResultCount(int count) {
    return 'Imported $count emails';
  }

  @override
  String importResultInvalid(int count) {
    return ', $count invalid lines ignored';
  }
}
