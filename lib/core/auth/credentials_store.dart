import 'dart:convert';

import '../../data/account_import.dart';
import '../storage/secure_storage.dart';

/// 账号的敏感凭据 + 最近一次的健康状态/账号信息。
///
/// OAuth 用 client_id + refresh_token；password 供 IMAP 备用。
/// [status] 与 [displayName]/[address]/[userId] 是「最近一次健康检测」的落盘结果，
/// 让首页载入/刷新/统计都以持久化数据为准（而非每次重载都硬编码占位）。
class AccountCredentials {
  const AccountCredentials({
    required this.email,
    required this.clientId,
    required this.refreshToken,
    this.password,
    this.status = statusUnknown,
    this.displayName,
    this.address,
    this.userId,
  });

  /// 状态取值 —— 与 UI 层 `AccountStatus.name` 对齐（core 不反向依赖 UI 枚举）。
  static const String statusUnknown = 'unknown';
  static const String statusValid = 'valid';
  static const String statusTokenExpired = 'tokenExpired';

  final String email;
  final String clientId;
  final String refreshToken;

  /// 邮箱密码 —— OAuth 路径用不到，为将来 IMAP 保留（导入数据里带）。
  final String? password;

  /// 最近一次检测结论（`AccountStatus.name`）；未检测为 [statusUnknown]。
  final String status;

  /// 以下三项来自最近一次成功的 `GET /me`，仅健康时有值。
  final String? displayName;
  final String? address;
  final String? userId;

  AccountCredentials copyWith({
    String? refreshToken,
    String? status,
    String? displayName,
    String? address,
    String? userId,
  }) => AccountCredentials(
    email: email,
    clientId: clientId,
    refreshToken: refreshToken ?? this.refreshToken,
    password: password,
    status: status ?? this.status,
    displayName: displayName ?? this.displayName,
    address: address ?? this.address,
    userId: userId ?? this.userId,
  );

  /// 由导入记录构造 —— 状态默认「未知」（尚未检测）。
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
        'status': status,
        if (displayName != null) 'displayName': displayName,
        if (address != null) 'address': address,
        if (userId != null) 'userId': userId,
      };

  factory AccountCredentials.fromJson(Map<String, dynamic> json) =>
      AccountCredentials(
        email: json['email'] as String,
        clientId: json['clientId'] as String,
        refreshToken: json['refreshToken'] as String,
        password: json['password'] as String?,
        status: json['status'] as String? ?? statusUnknown,
        displayName: json['displayName'] as String?,
        address: json['address'] as String?,
        userId: json['userId'] as String?,
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

  /// 读取全部账号记录（含状态/用户信息）—— 供首页按落盘数据渲染与统计。
  Future<List<AccountCredentials>> findAll();
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
  Future<List<AccountCredentials>> findAll() async => _map.values.toList();

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
  Future<List<AccountCredentials>> findAll() async {
    final all = await _storage.readAll();
    return [
      for (final entry in all.entries)
        if (entry.key.startsWith(_prefix))
          AccountCredentials.fromJson(
            jsonDecode(entry.value) as Map<String, dynamic>,
          ),
    ];
  }

  @override
  Future<void> remove(String email) => _storage.delete(_keyFor(email));
}
