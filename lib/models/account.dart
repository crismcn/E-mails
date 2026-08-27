import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_palette.dart';

/// 账号连接状态。
enum AccountStatus { valid, tokenExpired, passwordError }

extension AccountStatusView on AccountStatus {
  /// 本地化状态文案。
  String label(AppLocalizations l10n) => switch (this) {
    AccountStatus.valid => l10n.statusValid,
    AccountStatus.tokenExpired => l10n.statusTokenExpired,
    AccountStatus.passwordError => l10n.statusPasswordError,
  };

  /// 状态指示点颜色（随主题取自调色板）。
  Color color(AppPalette palette) => switch (this) {
    AccountStatus.valid => palette.statusValid,
    AccountStatus.tokenExpired => palette.statusWarning,
    AccountStatus.passwordError => palette.statusError,
  };
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
  });

  final String email;
  final AccountStatus status;
  final MailProtocol protocol;

  /// 未读邮件数；`null` 表示无法获取（显示为「–」）。
  final int? unread;

  Account copyWith({AccountStatus? status, MailProtocol? protocol}) => Account(
    email: email,
    status: status ?? this.status,
    protocol: protocol ?? this.protocol,
    unread: unread,
  );
}
