import '../models/account.dart';

/// 首页示例数据 —— 与设计稿一致。
const List<Account> kMockAccounts = [
  Account(
    email: 'alice@outlook.com',
    status: AccountStatus.valid,
    protocol: MailProtocol.graph,
    unread: 12,
  ),
  Account(
    email: 'tom@outlook.com',
    status: AccountStatus.valid,
    protocol: MailProtocol.imap,
    unread: 3,
  ),
  Account(
    email: 'william@outlook.com',
    status: AccountStatus.valid,
    protocol: MailProtocol.graph,
    unread: 8,
  ),
  Account(
    email: 'emma@outlook.com',
    status: AccountStatus.valid,
    protocol: MailProtocol.graph,
    unread: 0,
  ),
  Account(
    email: 'james@outlook.com',
    status: AccountStatus.tokenExpired,
    protocol: MailProtocol.imap,
    unread: 5,
  ),
  Account(
    email: 'sophia@outlook.com',
    status: AccountStatus.passwordError,
    protocol: MailProtocol.graph,
    unread: null,
  ),
];
