/// 单个账号的 access_token 缓存条目。
class TokenEntry {
  const TokenEntry({required this.accessToken, required this.expiresAt});

  /// 访问令牌（用于 Graph 请求的 Bearer）。
  final String accessToken;

  /// 绝对过期时刻（UTC）。
  final DateTime expiresAt;

  /// 距 [now] 是否已过期（含提前量 [leeway]）。
  bool isExpired(DateTime now, Duration leeway) =>
      now.add(leeway).isAfter(expiresAt);
}

/// 按账号缓存 access_token —— 键为账号邮箱。
///
/// 本次仅内存实现；[TokenStore] 抽象出接口，后续可换成
/// flutter_secure_storage 持久化而不动上层。
abstract class TokenStore {
  TokenEntry? read(String email);
  void write(String email, TokenEntry entry);
  void clear(String email);
  void clearAll();
}

/// 内存版实现 —— 进程内有效，重启即失效。
class InMemoryTokenStore implements TokenStore {
  final Map<String, TokenEntry> _cache = <String, TokenEntry>{};

  @override
  TokenEntry? read(String email) => _cache[email];

  @override
  void write(String email, TokenEntry entry) => _cache[email] = entry;

  @override
  void clear(String email) => _cache.remove(email);

  @override
  void clearAll() => _cache.clear();
}
