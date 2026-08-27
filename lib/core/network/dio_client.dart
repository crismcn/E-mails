import 'package:dio/dio.dart';

import 'api_config.dart';
import 'interceptors/app_log_interceptor.dart';

/// dio 客户端工厂 —— 按 host 产出配置好的实例。
///
/// 两个用途分离：
/// - [buildAuthDio]：OAuth token 端点，form 编码，**不带** Bearer；
/// - [buildGraphDio]：Graph 业务，注入传入的鉴权拦截器（携带 Bearer + 401 重试）。
class DioClientFactory {
  const DioClientFactory._();

  /// OAuth（换 token）客户端 —— form-urlencoded，无鉴权。
  static Dio buildAuthDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.oauthBaseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        sendTimeout: ApiConfig.sendTimeout,
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
      ),
    );
    dio.interceptors.add(AppLogInterceptor());
    return dio;
  }

  /// Graph（邮件业务）客户端 —— JSON，鉴权拦截器由外部注入以避免循环依赖。
  static Dio buildGraphDio(Interceptor authInterceptor) {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.graphBaseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        sendTimeout: ApiConfig.sendTimeout,
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    // 顺序：先鉴权（注入 token / 401 重试），再日志。
    dio.interceptors.add(authInterceptor);
    dio.interceptors.add(AppLogInterceptor());
    return dio;
  }
}
