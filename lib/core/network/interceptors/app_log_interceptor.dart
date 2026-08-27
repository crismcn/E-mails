import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 请求日志拦截器 —— 仅在 debug 打印，并对敏感字段脱敏。
///
/// 脱敏字段：Authorization 头、password / refresh_token / access_token / client_secret
/// 等，只保留掩码，遵守不外泄密钥的约定。生产（release）下整体静默。
class AppLogInterceptor extends Interceptor {
  AppLogInterceptor({this.enabled = kDebugMode});

  /// 是否启用 —— 默认仅 debug。
  final bool enabled;

  static const Set<String> _sensitiveKeys = {
    'password',
    'refresh_token',
    'access_token',
    'client_secret',
    'code',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (enabled) {
      final auth = options.headers['Authorization'];
      final maskedAuth = auth is String ? _maskToken(auth) : null;
      developer.log(
        '→ ${options.method} ${options.uri}'
        '${maskedAuth != null ? '\n  Authorization: $maskedAuth' : ''}'
        '\n  data: ${_maskData(options.data)}',
        name: 'api',
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (enabled) {
      developer.log(
        '← ${response.statusCode} ${response.requestOptions.uri}',
        name: 'api',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (enabled) {
      developer.log(
        '✗ ${err.type} ${err.response?.statusCode} '
        '${err.requestOptions.uri}\n  ${err.message}',
        name: 'api',
      );
    }
    handler.next(err);
  }

  /// 对整体数据脱敏：Map 中命中敏感键的值替换为掩码。
  Object? _maskData(Object? data) {
    if (data is Map) {
      return data.map((key, value) {
        if (key is String && _sensitiveKeys.contains(key.toLowerCase())) {
          return MapEntry(key, _maskValue(value));
        }
        return MapEntry(key, value);
      });
    }
    return data;
  }

  String _maskValue(Object? value) {
    final s = value?.toString() ?? '';
    if (s.length <= 8) return '***';
    return '${s.substring(0, 4)}***${s.substring(s.length - 4)}';
  }

  String _maskToken(String header) {
    final parts = header.split(' ');
    if (parts.length == 2) return '${parts[0]} ${_maskValue(parts[1])}';
    return _maskValue(header);
  }
}
