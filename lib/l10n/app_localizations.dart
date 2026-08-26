import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'邮箱管理'**
  String get appTitle;

  /// No description provided for @statTotal.
  ///
  /// In zh, this message translates to:
  /// **'总账号'**
  String get statTotal;

  /// No description provided for @statValid.
  ///
  /// In zh, this message translates to:
  /// **'有效账号'**
  String get statValid;

  /// No description provided for @statError.
  ///
  /// In zh, this message translates to:
  /// **'异常账号'**
  String get statError;

  /// No description provided for @filterAllGroups.
  ///
  /// In zh, this message translates to:
  /// **'全部分组'**
  String get filterAllGroups;

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索邮箱号'**
  String get searchHint;

  /// No description provided for @mailSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索邮件'**
  String get mailSearchHint;

  /// No description provided for @refreshLastUpdated.
  ///
  /// In zh, this message translates to:
  /// **'上次更新时间：{time}'**
  String refreshLastUpdated(String time);

  /// No description provided for @mailArchived.
  ///
  /// In zh, this message translates to:
  /// **'已归档'**
  String get mailArchived;

  /// No description provided for @mailDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除'**
  String get mailDeleted;

  /// No description provided for @mailMarkedRead.
  ///
  /// In zh, this message translates to:
  /// **'已标记为已读'**
  String get mailMarkedRead;

  /// No description provided for @mailMarkedUnread.
  ///
  /// In zh, this message translates to:
  /// **'已标记为未读'**
  String get mailMarkedUnread;

  /// No description provided for @loadMoreLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中...'**
  String get loadMoreLoading;

  /// No description provided for @loadMoreNoMore.
  ///
  /// In zh, this message translates to:
  /// **'没有更多邮件'**
  String get loadMoreNoMore;

  /// No description provided for @menuImport.
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get menuImport;

  /// No description provided for @menuSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get menuSettings;

  /// No description provided for @loadMore.
  ///
  /// In zh, this message translates to:
  /// **'上拉加载更多'**
  String get loadMore;

  /// No description provided for @unread.
  ///
  /// In zh, this message translates to:
  /// **'未读'**
  String get unread;

  /// No description provided for @mailReplyHint.
  ///
  /// In zh, this message translates to:
  /// **'回复'**
  String get mailReplyHint;

  /// No description provided for @threadUnread.
  ///
  /// In zh, this message translates to:
  /// **'{count} 封未读'**
  String threadUnread(int count);

  /// No description provided for @threadLoadHistory.
  ///
  /// In zh, this message translates to:
  /// **'下拉加载更多历史邮件'**
  String get threadLoadHistory;

  /// No description provided for @threadLoadHistoryNoMore.
  ///
  /// In zh, this message translates to:
  /// **'没有更多历史邮件'**
  String get threadLoadHistoryNoMore;

  /// No description provided for @statusValid.
  ///
  /// In zh, this message translates to:
  /// **'有效'**
  String get statusValid;

  /// No description provided for @statusTokenExpired.
  ///
  /// In zh, this message translates to:
  /// **'Token 过期'**
  String get statusTokenExpired;

  /// No description provided for @statusPasswordError.
  ///
  /// In zh, this message translates to:
  /// **'密码错误'**
  String get statusPasswordError;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsAppearance;

  /// No description provided for @settingsTheme.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeDark.
  ///
  /// In zh, this message translates to:
  /// **'暗黑'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeLight.
  ///
  /// In zh, this message translates to:
  /// **'亮白'**
  String get settingsThemeLight;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get settingsLanguage;

  /// No description provided for @importTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入邮箱'**
  String get importTitle;

  /// No description provided for @importCsvSection.
  ///
  /// In zh, this message translates to:
  /// **'导入 CSV 文件'**
  String get importCsvSection;

  /// No description provided for @importCsvHint.
  ///
  /// In zh, this message translates to:
  /// **'点击选择 CSV 文件'**
  String get importCsvHint;

  /// No description provided for @importCsvOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅支持 .csv 格式'**
  String get importCsvOnly;

  /// No description provided for @importCsvPicked.
  ///
  /// In zh, this message translates to:
  /// **'已选择：{name}'**
  String importCsvPicked(String name);

  /// No description provided for @importPasteSection.
  ///
  /// In zh, this message translates to:
  /// **'或 粘贴数据'**
  String get importPasteSection;

  /// No description provided for @importPasteHint.
  ///
  /// In zh, this message translates to:
  /// **'请粘贴数据，格式如下：\n邮箱----密码----client_id----refresh_token----创建时间\n\nuser1@example.com----123456----xxxx----xxxx----2024-01-01 10:00:00\nuser2@example.com----123456----xxxx----xxxx----2024-01-01 10:00:00'**
  String get importPasteHint;

  /// No description provided for @importFormatSection.
  ///
  /// In zh, this message translates to:
  /// **'格式说明'**
  String get importFormatSection;

  /// No description provided for @importFieldEmail.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get importFieldEmail;

  /// No description provided for @importFieldEmailDesc.
  ///
  /// In zh, this message translates to:
  /// **'邮箱地址'**
  String get importFieldEmailDesc;

  /// No description provided for @importFieldPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get importFieldPassword;

  /// No description provided for @importFieldPasswordDesc.
  ///
  /// In zh, this message translates to:
  /// **'邮箱密码'**
  String get importFieldPasswordDesc;

  /// No description provided for @importFieldClientId.
  ///
  /// In zh, this message translates to:
  /// **'client_id'**
  String get importFieldClientId;

  /// No description provided for @importFieldClientIdDesc.
  ///
  /// In zh, this message translates to:
  /// **'应用客户端 ID'**
  String get importFieldClientIdDesc;

  /// No description provided for @importFieldRefreshToken.
  ///
  /// In zh, this message translates to:
  /// **'refresh_token'**
  String get importFieldRefreshToken;

  /// No description provided for @importFieldRefreshTokenDesc.
  ///
  /// In zh, this message translates to:
  /// **'刷新令牌'**
  String get importFieldRefreshTokenDesc;

  /// No description provided for @importFieldCreatedAt.
  ///
  /// In zh, this message translates to:
  /// **'创建时间'**
  String get importFieldCreatedAt;

  /// No description provided for @importFieldCreatedAtDesc.
  ///
  /// In zh, this message translates to:
  /// **'如 2024-01-01 10:00:00'**
  String get importFieldCreatedAtDesc;

  /// No description provided for @importConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认导入'**
  String get importConfirm;

  /// No description provided for @importEmpty.
  ///
  /// In zh, this message translates to:
  /// **'请先粘贴数据或选择 CSV 文件'**
  String get importEmpty;

  /// No description provided for @importNoValid.
  ///
  /// In zh, this message translates to:
  /// **'未识别到有效数据，请检查格式'**
  String get importNoValid;

  /// No description provided for @importResultCount.
  ///
  /// In zh, this message translates to:
  /// **'成功导入 {count} 个邮箱'**
  String importResultCount(int count);

  /// No description provided for @importResultInvalid.
  ///
  /// In zh, this message translates to:
  /// **'，{count} 行格式有误已忽略'**
  String importResultInvalid(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
