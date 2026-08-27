import 'package:dio/dio.dart';

import 'api_code.dart';
import 'api_response.dart';
import 'error_mapper.dart';

/// 把响应体解析为业务类型 [T]。入参是 dio 已解好的 JSON（Map/List/原始值）。
typedef ResponseParser<T> = T Function(dynamic json);

/// 高层请求包装 —— 上层业务只写「路径 + 解析函数」，不重复写 try/catch 与解包。
///
/// 统一把成功包成 [ApiResponse.success]，把任何底层错误经 [mapError] 收敛为
/// [ApiResponse.failure]，因此调用方永远拿到信封、不必自己 catch。
class ApiClient {
  const ApiClient(this._dio);

  final Dio _dio;

  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    required ResponseParser<T> parser,
    CancelToken? cancelToken,
  }) =>
      request<T>(
        method: 'GET',
        path: path,
        query: query,
        parser: parser,
        cancelToken: cancelToken,
      );

  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    required ResponseParser<T> parser,
    CancelToken? cancelToken,
  }) =>
      request<T>(
        method: 'POST',
        path: path,
        data: data,
        query: query,
        parser: parser,
        cancelToken: cancelToken,
      );

  /// 通用请求 —— 其余便捷方法都走它。
  ///
  /// [extra] 会并入 `RequestOptions.extra`，供拦截器识别（如注入哪个账号的 token）。
  Future<ApiResponse<T>> request<T>({
    required String method,
    required String path,
    required ResponseParser<T> parser,
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        cancelToken: cancelToken,
        options: Options(method: method, headers: headers, extra: extra),
      );
      try {
        return ApiResponse<T>.success(parser(response.data));
      } catch (e) {
        // 解析阶段的异常单独归到 parse 码，与网络错误区分。
        return ApiResponse<T>.failure(ApiCode.parse, '响应解析失败：$e');
      }
    } catch (error, stackTrace) {
      final ex = mapError(error, stackTrace);
      return ApiResponse<T>.failure(ex.code, ex.message);
    }
  }
}
