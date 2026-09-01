import '../../api/auth_api.dart';
import '../../api/user_api.dart';
import '../network/api_code.dart';
import '../network/api_config.dart';
import 'credentials_store.dart';

/// 单个账号的健康检测结论。
enum HealthStatus {
  /// 凭据可用：换到了 token，且 `GET /me` 读到了账号信息。
  ok,

  /// 凭据失效：refresh_token 过期/被撤销、授权不足（invalid_grant / 401 / 403）。
  /// 需要用户重新授权并重新导入。
  credentialsInvalid,

  /// 网络问题（不可达 / 超时）—— 与凭据无关，不应据此改判账号状态。
  networkError,

  /// 其它未归类错误（服务端 5xx、限流、解析失败等）。
  unknownError,
}

/// 一次健康检测的结果 —— 结论 + 可展示的诊断信息。
class HealthReport {
  const HealthReport({
    required this.email,
    required this.status,
    required this.message,
    this.displayName,
    this.address,
    this.userId,
  });

  final String email;
  final HealthStatus status;

  /// 人类可读说明（成功为账号摘要，失败为微软/网络错误原因）。
  final String message;

  /// 以下三项仅 [HealthStatus.ok] 时有值（来自 `GET /me`）。
  final String? displayName;
  final String? address;
  final String? userId;

  bool get isOk => status == HealthStatus.ok;

  /// 是否为凭据类失效 —— 上层据此把账号标记为「Token 过期」。
  bool get isCredentialsInvalid => status == HealthStatus.credentialsInvalid;
}

/// 账号健康检测 —— 以「refresh_token 能否换到 token」为准：
///
/// 1. 用 `client_id + refresh_token` 打 OAuth token 端点（`common` 租户），
///    scope 用 `.default`（账号已授权的全部权限）。**换到 token 即判定账号可用**
///    ——这与邮件业务用同一 scope，能换到就说明凭据有效；
/// 2. 再尽力用该 token 打 `GET /me` 补全展示信息（displayName/address/id），
///    但这一步**只影响是否有展示信息，不影响健康结论**：账号未授权 `User.Read`
///    时 /me 会 401/403，仍判为有效。
///
/// 刷新过程中若微软轮换了 refresh_token，会回写存储，避免旧值失效后再也换不到 token。
///
/// 刻意**不复用** [TokenService]：那里缓存的是邮件 scope 的 token，
/// 且健康检测要的是「此刻真实重试一次」的结论，不能命中缓存。
class HealthService {
  HealthService({
    required AuthApi authApi,
    required UserApi userApi,
    required CredentialsStore credentialsStore,
  }) : _authApi = authApi,
       _userApi = userApi,
       _credentialsStore = credentialsStore;

  // ignore_for_file: prefer_initializing_formals
  // 依赖用具名参数注入、字段私有（与 TokenService 一致），初始化列表更清晰。

  final AuthApi _authApi;
  final UserApi _userApi;
  final CredentialsStore _credentialsStore;

  /// 检测单个账号。任何失败都收敛为 [HealthReport]，不抛异常。
  ///
  /// 结论与账号信息会**落盘**（成功→valid + `/me` 信息；凭据失效→tokenExpired；
  /// 网络/未知不改判状态，仅保留可能轮换的 refresh_token），
  /// 让首页载入/刷新/统计以持久化数据为准。
  Future<HealthReport> check(String email) async {
    final credentials = await _credentialsStore.find(email);
    if (credentials == null) {
      return HealthReport(
        email: email,
        status: HealthStatus.credentialsInvalid,
        message: '未找到账号凭据，请重新导入',
      );
    }

    // 第 1 步：换 access_token（健康检测专用 scope）。
    final token = await _authApi.refreshToken(
      clientId: credentials.clientId,
      refreshToken: credentials.refreshToken,
      scope: ApiConfig.healthCheckScope,
    );
    if (!token.isSuccess || token.data == null) {
      final status = _statusFor(token.code);
      await _persist(credentials, status);
      return HealthReport(email: email, status: status, message: token.message);
    }

    // 微软轮换了 refresh_token → 并入待落盘的凭据。
    var current = credentials;
    final rotated = token.data!.refreshToken;
    if (rotated != null &&
        rotated.isNotEmpty &&
        rotated != credentials.refreshToken) {
      current = current.copyWith(refreshToken: rotated);
    }

    // 第 2 步：尽力用该 token 读 `GET /me` 补全账号展示信息。
    //
    // 关键：**能换到 token 就说明 refresh_token 有效、账号可用**——这才是健康的
    // 真实信号。/me 需要 `User.Read`，而导入/自助换取的账号未必授权了它
    // （采购号常只有 `Mail.Read`，自助脚本申请的是 `Mail.ReadWrite Mail.Send`），
    // 此时 /me 会 401/403，但**不代表账号不可用**。故读不到只是缺展示信息，
    // 不改判健康结论（否则会把一批能正常收邮件的账号误标为「Token 过期」）。
    final me = await _userApi.getMe(token.data!.accessToken);
    if (me.isSuccess && me.data != null) {
      final user = me.data!;
      await _credentialsStore.update(
        current.copyWith(
          status: AccountCredentials.statusValid,
          displayName: user.displayName,
          address: user.address,
          userId: user.id,
        ),
      );
      return HealthReport(
        email: email,
        status: HealthStatus.ok,
        message: user.displayName.isNotEmpty ? user.displayName : user.address,
        displayName: user.displayName,
        address: user.address,
        userId: user.id,
      );
    }

    // /me 读不到（多因未授权 User.Read）：refresh 已成功，判为有效，仅缺展示信息。
    await _credentialsStore.update(
      current.copyWith(status: AccountCredentials.statusValid),
    );
    return HealthReport(
      email: email,
      status: HealthStatus.ok,
      message: current.email,
    );
  }

  /// 按检测结论落盘状态：凭据失效→tokenExpired；网络/未知→保持原状态
  /// （只写回可能已轮换的 [credentials]，避免抖动误标）。
  Future<void> _persist(AccountCredentials credentials, HealthStatus status) {
    if (status == HealthStatus.credentialsInvalid) {
      return _credentialsStore.update(
        credentials.copyWith(status: AccountCredentials.statusTokenExpired),
      );
    }
    return _credentialsStore.update(credentials);
  }

  /// 批量检测 —— 并发发起，逐账号独立成败。
  Future<List<HealthReport>> checkAll(Iterable<String> emails) =>
      Future.wait(emails.map(check));

  /// 业务码 → 健康结论。
  HealthStatus _statusFor(int code) {
    if (ApiCode.isAuthFailure(code)) return HealthStatus.credentialsInvalid;
    if (code == ApiCode.network || code == ApiCode.timeout) {
      return HealthStatus.networkError;
    }
    return HealthStatus.unknownError;
  }
}
