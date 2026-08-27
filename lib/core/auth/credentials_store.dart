import 'dart:convert';

import '../../data/account_import.dart';
import '../storage/secure_storage.dart';

/// 账号的敏感凭据 —— OAuth 用 client_id + refresh_token；password 供 IMAP 备用。
class AccountCredentials {
  const AccountCredentials({
    required this.email,
    required this.clientId,
    required this.refreshToken,
    this.password,
  });

  final String email;
  final String clientId;
  final String refreshToken;

  /// 邮箱密码 —— OAuth 路径用不到，为将来 IMAP 保留（导入数据里带）。
  final String? password;

  AccountCredentials copyWith({String? refreshToken}) => AccountCredentials(
        email: email,
        clientId: clientId,
        refreshToken: refreshToken ?? this.refreshToken,
        password: password,
      );

  /// 由导入记录构造。
  factory AccountCredentials.fromImported(ImportedAccount a) =>
      AccountCredentials(
        email: a.email,
        clientId: a.clientId,
        refreshToken: a.refreshToken,
        password: a.password,
      );

  Map<String, dynamic> toJson() => {
        'email': email,
        'clientId': clientId,
        'refreshToken': refreshToken,
        if (password != null) 'password': password,
      };

  factory AccountCredentials.fromJson(Map<String, dynamic> json) =>
      AccountCredentials(
        email: json['email'] as String,
        clientId: json['clientId'] as String,
        refreshToken: json['refreshToken'] as String,
        password: json['password'] as String?,
      );
}

/// 按邮箱读取 / 更新账号凭据 —— 接口为异步以适配安全存储。
///
/// 微软刷新 token 时可能下发新的 refresh_token，[update] 用于回写，
/// 避免旧 refresh_token 失效后再也换不到 token。
abstract class CredentialsStore {
  Future<AccountCredentials?> find(String email);
  Future<void> update(AccountCredentials credentials);
  Future<void> upsertAll(Iterable<AccountCredentials> credentials);
  Future<List<String>> listEmails();
  Future<void> remove(String email);
}

/// 内存版实现 —— 用于测试与临时场景，重启即失效。
class InMemoryCredentialsStore implements CredentialsStore {
  InMemoryCredentialsStore([Iterable<AccountCredentials> seed = const []]) {
    for (final c in seed) {
      _map[c.email] = c;
    }
  }

  final Map<String, AccountCredentials> _map = <String, AccountCredentials>{};

  @override
  Future<AccountCredentials?> find(String email) async => _map[email];

  @override
  Future<void> update(AccountCredentials credentials) async =>
      _map[credentials.email] = credentials;

  @override
  Future<void> upsertAll(Iterable<AccountCredentials> credentials) async {
    for (final c in credentials) {
      _map[c.email] = c;
    }
  }

  @override
  Future<List<String>> listEmails() async => _map.keys.toList();

  @override
  Future<void> remove(String email) async => _map.remove(email);
}

/// 安全存储版实现 —— 每个账号凭据以 JSON 存于一个键（前缀 [_prefix]）。
///
/// 键形如 `cred.a@outlook.com`；[listEmails] 靠 `readAll` 过滤前缀得到，
/// 因此无需再维护单独的索引键。
class SecureCredentialsStore implements CredentialsStore {
  SecureCredentialsStore(this._storage);

  final SecureStorage _storage;

  static const String _prefix = 'cred.';

  String _keyFor(String email) => '$_prefix$email';

  @override
  Future<AccountCredentials?> find(String email) async {
    final raw = await _storage.read(_keyFor(email));
    if (raw == null) return null;
    return AccountCredentials.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> update(AccountCredentials credentials) =>
      _storage.write(_keyFor(credentials.email), jsonEncode(credentials.toJson()));

  @override
  Future<void> upsertAll(Iterable<AccountCredentials> credentials) async {
    for (final c in credentials) {
      await update(c);
    }
  }

  @override
  Future<List<String>> listEmails() async {
    final all = await _storage.readAll();
    return [
      for (final key in all.keys)
        if (key.startsWith(_prefix)) key.substring(_prefix.length),
    ];
  }

  @override
  Future<void> remove(String email) => _storage.delete(_keyFor(email));
}
