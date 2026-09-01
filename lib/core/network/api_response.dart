import 'api_code.dart';

/// 统一响应信封 —— 上层业务只面对 `{code, message, data}` 这一种结构。
///
/// 微软的两种线格式（OAuth token / Graph 资源）由归一化拦截器映射成本类型：
/// - 成功 → `ApiResponse.success(data)`（code = [ApiCode.ok]）；
/// - 失败 → `ApiResponse.failure(code, message)`（data 为 null）。
class ApiResponse<T> {
  const ApiResponse({required this.code, required this.message, this.data});

  /// 成功。
  const ApiResponse.success(T value, {this.message = 'ok'})
    : code = ApiCode.ok,
      data = value;

  /// 失败 —— 携带归一化后的业务码与提示。
  const ApiResponse.failure(this.code, this.message) : data = null;

  /// 业务码（见 [ApiCode]）。
  final int code;

  /// 提示信息（成功为 'ok'，失败为微软/网络错误描述）。
  final String message;

  /// 业务数据；失败时为 null。
  final T? data;

  /// 是否成功。
  bool get isSuccess => ApiCode.isSuccess(code);

  /// 成功时取数据，失败抛 [StateError] —— 供确信成功的调用点简化取值。
  T get requireData {
    final value = data;
    if (!isSuccess || value == null) {
      throw StateError('ApiResponse 无数据可取：code=$code, message=$message');
    }
    return value;
  }

  /// 把 data 变换为另一类型，保留 code/message（失败原样传递）。
  ApiResponse<R> map<R>(R Function(T data) transform) {
    final value = data;
    if (isSuccess && value != null) {
      return ApiResponse<R>(
        code: code,
        message: message,
        data: transform(value),
      );
    }
    return ApiResponse<R>(code: code, message: message);
  }

  @override
  String toString() =>
      'ApiResponse(code: $code, message: $message, data: $data)';
}
