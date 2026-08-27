import 'api_code.dart';

/// 网络请求失败的统一异常 —— 所有底层错误（DioException、解析失败、微软错误）
/// 最终收敛为本类型，上层只需 `catch (ApiException)`。
///
/// 也可通过 [toResponse] 转成 [ApiResponse] 失败信封，供不抛异常的调用风格使用。
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.type = ApiErrorType.unknown,
    this.cause,
    this.stackTrace,
  });

  /// 归一化业务码（见 [ApiCode]）。
  final int code;

  /// 人类可读的错误描述。
  final String message;

  /// 错误大类，便于 UI 分支（如超时可提示重试、鉴权可跳登录）。
  final ApiErrorType type;

  /// 原始错误对象（DioException / FormatException 等），便于日志排查。
  final Object? cause;

  /// 原始堆栈。
  final StackTrace? stackTrace;

  bool get isAuthFailure => ApiCode.isAuthFailure(code);

  @override
  String toString() => 'ApiException($type, code: $code, message: $message)';
}

/// 错误大类。
enum ApiErrorType {
  /// 网络不可达 / 连接失败。
  network,

  /// 超时。
  timeout,

  /// 请求被取消。
  cancelled,

  /// 鉴权失败（token 失效 / 无权限）。
  auth,

  /// 业务错误（微软返回的 4xx/5xx 或错误体）。
  business,

  /// 响应解析失败。
  parse,

  /// 未归类。
  unknown,
}
