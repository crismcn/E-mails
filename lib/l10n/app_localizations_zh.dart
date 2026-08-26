// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '邮箱管理';

  @override
  String get statTotal => '总账号';

  @override
  String get statValid => '有效账号';

  @override
  String get statError => '异常账号';

  @override
  String get filterAllGroups => '全部分组';

  @override
  String get searchHint => '搜索邮箱号';

  @override
  String get menuImport => '导入';

  @override
  String get menuSettings => '设置';

  @override
  String get loadMore => '上拉加载更多';

  @override
  String get unread => '未读';

  @override
  String get statusValid => '有效';

  @override
  String get statusTokenExpired => 'Token 过期';

  @override
  String get statusPasswordError => '密码错误';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeDark => '暗黑';

  @override
  String get settingsThemeLight => '亮白';

  @override
  String get settingsLanguage => '语言';
}
