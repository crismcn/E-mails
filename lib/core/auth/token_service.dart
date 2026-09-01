import '../../api/auth_api.dart';
import '../network/api_code.dart';
import '../network/api_exception.dart';
import '../network/api_config.dart';
import 'credentials_store.dart';
import 'token_store.dart';

/// 按账号管理 access_token —— 命中未过期缓存直接返回，否则用凭据刷新。
///
/// 关键点：**同账号并发刷新去重**。多个 Graph 请求同时发现 token 过期时，
/// 只会打一次 OAuth 刷新，其余等待同一个 Future，避免刷新风暴与 refresh_token 抢用。
class TokenService {
  TokenService({
    required AuthApi authApi,
    required TokenStore tokenStore,
    required CredentialsStore credentialsStore,
    DateTime Function()? now,
  }) : _authApi = authApi,
       _tokenStore = tokenStore,
       _credentialsStore = credentialsStore,
       _now = now ?? DateTime.now;

  // ignore_for_file: prefer_initializing_formals
  // 依赖用具名参数注入、字段私有，此处初始化列表比具名初始化形参更清晰。

  final AuthApi _authApi;
  final TokenStore _tokenStore;
  final CredentialsStore _credentialsStore;
  final DateTime Function() _now;

  /// 进行中的刷新 —— 键为邮箱，用于并发合流。
  final Map<String, Future<String>> _inflight = <String, Future<String>>{};

  /// 取指定账号的有效 access_token。
  ///
  /// [forceRefresh] 为 true 时忽略缓存强制刷新（供 401 重试）。
  /// 失败抛 [ApiException]（凭据缺失 / 刷新被拒等）。
  Future<String> accessTokenFor(String email, {bool forceRefresh = false}) {
    if (!forceRefresh) {
      final cached = _tokenStore.read(email);
      if (cached != null &&
          !cached.isExpired(_now().toUtc(), ApiConfig.tokenExpiryLeeway)) {
        return Future<String>.value(cached.accessToken);
      }
    }

    // 已有同账号刷新在飞：合流复用，不再重复刷新。
    final existing = _inflight[email];
    if (existing != null) return existing;

    final future = _refresh(email);
    _inflight[email] = future;
    // 无论成败都要清理在飞标记。
    return future.whenComplete(() => _inflight.remove(email));
  }

  /// 使某账号缓存失效（如收到 401 后先清再重取）。
  void invalidate(String email) => _tokenStore.clear(email);

  Future<String> _refresh(String email) async {
    final credentials = await _credentialsStore.find(email);
    if (credentials == null) {
      throw ApiException(
        code: ApiCode.unauthorized,
        message: '未找到账号凭据：$email',
        type: ApiErrorType.auth,
      );
    }

    final result = await _authApi.refreshToken(
      clientId: credentials.clientId,
      refreshToken: credentials.refreshToken,
    );

    if (!result.isSuccess || result.data == null) {
      throw ApiException(
        code: result.code,
        message: result.message,
        type: ApiCode.isAuthFailure(result.code)
            ? ApiErrorType.auth
            : ApiErrorType.business,
      );
    }

    final token = result.data!;
    final expiresAt = _now().toUtc().add(Duration(seconds: token.expiresIn));
    _tokenStore.write(
      email,
      TokenEntry(accessToken: token.accessToken, expiresAt: expiresAt),
    );

    // 微软轮换了 refresh_token → 回写，避免旧值失效后再也换不到 token。
    final rotated = token.refreshToken;
    if (rotated != null &&
        rotated.isNotEmpty &&
        rotated != credentials.refreshToken) {
      await _credentialsStore.update(
        credentials.copyWith(refreshToken: rotated),
      );
    }

    return token.accessToken;
  }
}
