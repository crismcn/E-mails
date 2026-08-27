import 'auth_api.dart';
import 'mail_api.dart';
import '../core/auth/credentials_store.dart';
import '../core/auth/token_service.dart';
import '../core/auth/token_store.dart';
import '../core/network/api_client.dart';
import '../core/network/dio_client.dart';
import '../core/network/interceptors/auth_interceptor.dart';
import '../core/storage/secure_storage.dart';
import '../data/account_import.dart';

/// 组合根 —— 把网络层各部件按依赖顺序装配成可用的接口集合。
///
/// 装配顺序（解开循环依赖）：
/// authDio → ApiClient → AuthApi → TokenService → AuthInterceptor
/// → graphDio → ApiClient → MailApi。
///
/// 用法：
/// ```dart
/// final api = ApiService.create();          // 默认凭据落安全存储
/// await api.saveImported(importedAccounts);  // 导入后持久化
/// final res = await api.mail.listMessages(email);
/// ```
///
/// 说明：access_token 只放内存（[InMemoryTokenStore]，1 小时寿命、冷启动重新刷新），
/// **只有长期敏感的凭据（refresh_token / client_id / password）落安全存储**，
/// 减少落盘的短期令牌攻击面。
class ApiService {
  ApiService._({
    required this.auth,
    required this.mail,
    required this.tokenService,
    required this.credentialsStore,
  });

  final AuthApi auth;
  final MailApi mail;
  final TokenService tokenService;
  final CredentialsStore credentialsStore;

  factory ApiService.create({
    TokenStore? tokenStore,
    CredentialsStore? credentialsStore,
    SecureStorage? secureStorage,
  }) {
    final tokens = tokenStore ?? InMemoryTokenStore();
    // 默认用安全存储持久化凭据；测试可注入 InMemoryCredentialsStore。
    final creds = credentialsStore ??
        SecureCredentialsStore(secureStorage ?? FlutterSecureStorageAdapter());

    // OAuth 客户端 → AuthApi。
    final authApi = AuthApi(ApiClient(DioClientFactory.buildAuthDio()));

    // Token 服务（依赖 AuthApi + 两个 store）。
    final tokenService = TokenService(
      authApi: authApi,
      tokenStore: tokens,
      credentialsStore: creds,
    );

    // 鉴权拦截器 → Graph 客户端 → MailApi。
    final graphDio =
        DioClientFactory.buildGraphDio(AuthInterceptor(tokenService));
    final mailApi = MailApi(ApiClient(graphDio));

    return ApiService._(
      auth: authApi,
      mail: mailApi,
      tokenService: tokenService,
      credentialsStore: creds,
    );
  }

  /// 持久化导入的账号凭据到安全存储（导入确认后调用）。
  Future<void> saveImported(Iterable<ImportedAccount> accounts) {
    return credentialsStore.upsertAll(
      accounts.map(AccountCredentials.fromImported),
    );
  }

  /// 已持久化的账号邮箱列表（供启动后展示 / 批量操作）。
  Future<List<String>> knownAccounts() => credentialsStore.listEmails();
}
