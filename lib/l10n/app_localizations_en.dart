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
  String get searchClear => 'Clear';

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
  String get mailFlagged => 'Flagged';

  @override
  String get mailUnflagged => 'Unflagged';

  @override
  String mailActionFailedToast(String message) {
    return 'Action failed: $message';
  }

  @override
  String get mailEmpty => 'No mail';

  @override
  String get mailLoadFailed => 'Failed to load mail';

  @override
  String mailLoadFailedToast(String message) {
    return 'Load failed: $message';
  }

  @override
  String get commonRetry => 'Retry';

  @override
  String get mailAccountCopied => 'Email address copied';

  @override
  String get folderInbox => 'Inbox';

  @override
  String get folderUnread => 'Unread';

  @override
  String get folderFlagged => 'Flagged';

  @override
  String get folderSent => 'Sent';

  @override
  String get composeTitle => 'New Message';

  @override
  String get composeTo => 'To:';

  @override
  String get composeCc => 'Cc:';

  @override
  String get composeBcc => 'Bcc:';

  @override
  String get composeFrom => 'From:';

  @override
  String get composeCcFrom => 'Cc/Bcc, From:';

  @override
  String get composeRecipientDelete => 'Delete';

  @override
  String get composeRecipientEdit => 'Edit';

  @override
  String get composeRecipientMoveToTo => 'Move to To';

  @override
  String get composeRecipientMoveToCc => 'Move to Cc';

  @override
  String get composeRecipientMoveToBcc => 'Move to Bcc';

  @override
  String get composeRecipientOptions => 'Recipient options';

  @override
  String get composeImportance => 'Importance:';

  @override
  String get composeImportanceHigh => 'High';

  @override
  String get composeImportanceNormal => 'Normal';

  @override
  String get composeImportanceLow => 'Low';

  @override
  String get composeSubject => 'Subject:';

  @override
  String get composeBodyHint => 'Body';

  @override
  String get composeSending => 'Sending…';

  @override
  String get composeSent => 'Sent';

  @override
  String composeSendFailed(String message) {
    return 'Send failed: $message';
  }

  @override
  String get composeNoRecipient => 'Please add a recipient first';

  @override
  String composeInvalidRecipient(String value) {
    return 'Invalid recipient email: $value';
  }

  @override
  String composeAttachTooLarge(String limit) {
    return 'Attachments exceed $limit in total — remove some first';
  }

  @override
  String get composeAttachRemove => 'Remove attachment';

  @override
  String composeAttachEmptyFile(String name) {
    return 'Couldn\'t read \"$name\" — skipped';
  }

  @override
  String get composeContactPick => 'Pick a contact';

  @override
  String get composeContactPickEmail => 'Choose an email address';

  @override
  String get composeContactNoEmail => 'This contact has no email address';

  @override
  String get composeContactDenied =>
      'Contacts permission denied — can\'t pick a contact';

  @override
  String get composeAlignLeft => 'Align left';

  @override
  String get composeAlignCenter => 'Align center';

  @override
  String get composeAlignRight => 'Align right';

  @override
  String get composeIndentIncrease => 'Increase indent';

  @override
  String get composeIndentDecrease => 'Decrease indent';

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
  String get detailRecipient => 'To:';

  @override
  String detailAttachmentCount(int count) {
    return '$count attachments';
  }

  @override
  String get detailAttachmentOpen => 'Open';

  @override
  String get detailAttachmentDownload => 'Download';

  @override
  String detailAttachmentSaved(String name) {
    return 'Saved $name';
  }

  @override
  String get detailAttachmentOpenFallback =>
      'No app on this phone can open it — downloading instead';

  @override
  String detailAttachmentFailed(String message) {
    return 'Couldn\'t fetch attachment: $message';
  }

  @override
  String get actionReply => 'Reply';

  @override
  String get actionReplyAll => 'Reply all';

  @override
  String get actionForward => 'Forward';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionMore => 'More';

  @override
  String get linkOpenFailed => 'Could not open link';

  @override
  String get statusValid => 'Valid';

  @override
  String get statusTokenExpired => 'Token Expired';

  @override
  String get statusPasswordError => 'Password Error';

  @override
  String get statusUnknown => 'Unknown';

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

  @override
  String selectionTitle(int count) {
    return 'Selected $count';
  }

  @override
  String get actionHealthCheck => 'Health check';

  @override
  String get actionElevate => 'Elevate';

  @override
  String get actionSelectAll => 'Select all';

  @override
  String get accountElevateTodo =>
      'Elevating permissions isn\'t implemented yet';

  @override
  String get accountChecking => 'Checking…';

  @override
  String accountCheckSummary(int ok, int bad) {
    return 'Done: $ok healthy, $bad failed';
  }

  @override
  String get accountDeleteTitle => 'Delete mailbox';

  @override
  String accountDeleteMultiBody(int count) {
    return 'You\'ll need to re-import to restore them. Delete $count selected mailboxes?';
  }

  @override
  String accountDeleted(int count) {
    return 'Deleted $count accounts';
  }

  @override
  String get commonCancel => 'Cancel';
}
