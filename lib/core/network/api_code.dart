/// 统一业务码 —— 内部信封 [ApiResponse] 的 `code` 取值。
///
/// 微软本身不返回统一码（OAuth 用 `error` 字符串、Graph 用 `error.code` 字符串），
/// 由归一化拦截器把它们映射到这里的整数码，上层只面对一套码。
library;

/// [ApiResponse.code] 的取值集合与判定。
class ApiCode {
  const ApiCode._();

  /// 成功。
  static const int ok = 0;

  /// 鉴权失败 —— token 失效 / invalid_grant / 401。
  /// 上层可据此把账号标记为 tokenExpired / passwordError。
  static const int unauthorized = 401;

  /// 无权限 —— scope 不足 / 403。
  static const int forbidden = 403;

  /// 资源不存在。
  static const int notFound = 404;

  /// 触发限流（Graph 429）。
  static const int rateLimited = 429;

  /// 服务端错误（5xx）。
  static const int serverError = 500;

  /// 网络不可达 / 连接失败（无 HTTP 响应）。
  static const int network = -1;

  /// 请求超时。
  static const int timeout = -2;

  /// 请求被取消。
  static const int cancelled = -3;

  /// 响应解析失败。
  static const int parse = -4;

  /// 未归类错误。
  static const int unknown = -99;

  /// 是否为成功码。
  static bool isSuccess(int code) => code == ok;

  /// 是否为鉴权类失败（供上层触发重新登录 / 标记账号状态）。
  static bool isAuthFailure(int code) =>
      code == unauthorized || code == forbidden;
}
