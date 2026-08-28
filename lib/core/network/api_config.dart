/// 网络层集中配置 —— 直连微软 OAuth（换 token）+ Microsoft Graph（收发邮件）。
///
/// 所有 host / 端点 / 超时 / scope 常量集中于此，便于统一调整与切换租户。
library;

/// 微软 OAuth 与 Graph 的端点、超时、scope 配置。
class ApiConfig {
  const ApiConfig._();

  // ── OAuth（换取 access_token） ─────────────────────────────────────────
  //
  // 用 `common` 租户端点：同时接受个人 Outlook 与组织/学校账号（导入的账号两种都有，
  // 用 `consumers` 会把组织账号挡在门外）。导入凭据提供 client_id + refresh_token，
  // 走 refresh_token 授权。

  /// OAuth token 端点所在 host。
  static const String oauthBaseUrl = 'https://login.microsoftonline.com';

  /// token 端点路径（相对 [oauthBaseUrl]）。
  static const String oauthTokenPath = '/common/oauth2/v2.0/token';

  // ── Microsoft Graph（邮件业务） ────────────────────────────────────────

  /// Graph API 基地址（v1.0 稳定版）。
  static const String graphBaseUrl = 'https://graph.microsoft.com/v1.0';

  // ── 授权 scope ─────────────────────────────────────────────────────────

  /// 刷新 token 时申请的 scope —— 用 `.default`：换取该账号**已授权的全部**
  /// Graph 委托权限，而不是写死一串具体 scope。
  ///
  /// 为什么不用 `Mail.ReadWrite Mail.Send`：实测导入的批量账号**只授权了
  /// `Mail.Read`**（未含 `Mail.ReadWrite`）。OAuth 的规则是「请求的任一 scope
  /// 未授权 → 整个请求以 AADSTS70000 失败」，写死 `Mail.ReadWrite` 会让这些账号
  /// 连读都拉不到 token。`.default` 只取「已同意」的权限，因此：
  /// - 只授权 `Mail.Read` 的账号 → 能读列表 / 详情（读接口够用）；
  /// - 额外授权 `Mail.ReadWrite` / `Mail.Send` 的账号 → 写操作也能用；
  /// - 完全没授权邮件权限的账号 → Graph 侧返回 403，由错误页如实展示。
  ///
  /// `.default` 不与其它 scope 混用；`offline_access` 已在原始授权里，
  /// 刷新流程照常回传轮换后的 refresh_token。
  static const String defaultScope = 'https://graph.microsoft.com/.default';

  /// 健康检测 scope —— 同样用 `.default`（换取账号**已授权的全部**权限）。
  ///
  /// 早期这里显式申请 `User.Read`，但实测导入/自助换取的账号**普遍没有授权
  /// `User.Read`**（采购来的常只有 `Mail.Read`；自助脚本 get-token.mjs 申请的是
  /// `Mail.ReadWrite Mail.Send`）。OAuth 规则「请求任一未授权 scope → 整个换 token
  /// 请求 AADSTS70000 失败」，会把这些**其实完全可用**的账号误判成凭据失效。
  ///
  /// 因此健康检测与邮件业务一致用 `.default`：能换到 token（refresh_token 有效）
  /// 就是账号可用的真实信号；`GET /me` 只作「尽力补全账号展示信息」，读不到
  /// （多因未授权 `User.Read` 返回 403）也不改判健康结论。
  static const String healthCheckScope = defaultScope;

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
