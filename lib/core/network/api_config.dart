/// 网络层集中配置 —— 直连微软 OAuth（换 token）+ Microsoft Graph（收发邮件）。
///
/// 所有 host / 端点 / 超时 / scope 常量集中于此，便于统一调整与切换租户。
library;

/// 微软 OAuth 与 Graph 的端点、超时、scope 配置。
class ApiConfig {
  const ApiConfig._();

  // ── OAuth（换取 access_token） ─────────────────────────────────────────
  //
  // 个人版 Outlook 账号用 `consumers` 租户；若为组织/学校账号，改成 `common`
  // 或具体租户 ID。导入凭据提供 client_id + refresh_token，走 refresh_token 授权。

  /// OAuth token 端点所在 host。
  static const String oauthBaseUrl = 'https://login.microsoftonline.com';

  /// token 端点路径（相对 [oauthBaseUrl]）。
  static const String oauthTokenPath = '/consumers/oauth2/v2.0/token';

  // ── Microsoft Graph（邮件业务） ────────────────────────────────────────

  /// Graph API 基地址（v1.0 稳定版）。
  static const String graphBaseUrl = 'https://graph.microsoft.com/v1.0';

  // ── 授权 scope ─────────────────────────────────────────────────────────

  /// 刷新 token 时申请的 scope —— 邮件读写 + 离线（拿回新的 refresh_token）。
  static const String defaultScope =
      'https://graph.microsoft.com/Mail.ReadWrite '
      'https://graph.microsoft.com/Mail.Send offline_access';

  // ── 超时 ─────────────────────────────────────────────────────────────

  /// 建立连接超时。
  static const Duration connectTimeout = Duration(seconds: 15);

  /// 接收数据超时。
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// 发送数据超时。
  static const Duration sendTimeout = Duration(seconds: 30);

  /// access_token 过期前的提前刷新余量 —— 剩余寿命小于它就视为需刷新，
  /// 避免临界时刻请求携带即将失效的 token。
  static const Duration tokenExpiryLeeway = Duration(seconds: 60);
}
