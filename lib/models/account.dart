import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_palette.dart';

/// 账号连接状态。
enum AccountStatus { unknown, valid, tokenExpired, passwordError }

extension AccountStatusView on AccountStatus {
  /// 本地化状态文案。
  String label(AppLocalizations l10n) => switch (this) {
    AccountStatus.unknown => l10n.statusUnknown,
    AccountStatus.valid => l10n.statusValid,
    AccountStatus.tokenExpired => l10n.statusTokenExpired,
    AccountStatus.passwordError => l10n.statusPasswordError,
  };

  /// 状态指示点颜色（随主题取自调色板）。
  Color color(AppPalette palette) => switch (this) {
    // 未知 = 尚未检测，用中性灰。
    AccountStatus.unknown => palette.textSecondary,
    AccountStatus.valid => palette.statusValid,
    AccountStatus.tokenExpired => palette.statusWarning,
    AccountStatus.passwordError => palette.statusError,
  };

  /// 是否为「异常」状态（供统计：未知不计为异常）。
  bool get isError =>
      this == AccountStatus.tokenExpired || this == AccountStatus.passwordError;
}

/// 邮箱协议类型。
enum MailProtocol { graph, imap }

extension MailProtocolLabel on MailProtocol {
  String get label => switch (this) {
    MailProtocol.graph => 'Graph',
    MailProtocol.imap => 'IMAP',
  };
}

/// 邮箱账号数据模型。
class Account {
  const Account({
    required this.email,
    required this.status,
    required this.protocol,
    required this.unread,
    this.displayName,
  });

  final String email;
  final AccountStatus status;
  final MailProtocol protocol;

  /// 未读邮件数；`null` 表示无法获取（显示为「–」）。
  final int? unread;

  /// 健康检测（`GET /me`）拿到的显示名；未检测 / 账号未授权 `User.Read` 时为空。
  final String? displayName;

  /// 是否有可展示的显示名。
  bool get hasDisplayName => displayName != null && displayName!.isNotEmpty;

  /// 列表主标题：优先显示名，缺失时回退邮箱号。
  String get title => hasDisplayName ? displayName! : email;

  Account copyWith({
    AccountStatus? status,
    MailProtocol? protocol,
    String? displayName,
  }) => Account(
    email: email,
    status: status ?? this.status,
    protocol: protocol ?? this.protocol,
    unread: unread,
    displayName: displayName ?? this.displayName,
  );
}
