import 'package:dio/dio.dart';

import 'api_code.dart';
import 'api_exception.dart';

/// 把底层错误（[DioException]、解析异常等）统一映射为 [ApiException]。
///
/// 设计上不做成 dio 拦截器 —— dio 的错误流走 `onError(DioException)`，
/// 在高层 [ApiClient] 用一次 try/catch 调用本映射，比在拦截器里 resolve/reject
/// 更直观，且是纯函数、易单测。
///
/// 微软两种错误体在此归一：
/// - Graph：`{"error": {"code": "...", "message": "..."}}`
/// - OAuth：`{"error": "invalid_grant", "error_description": "..."}`
ApiException mapError(Object error, [StackTrace? stackTrace]) {
  if (error is ApiException) return error;

  if (error is DioException) {
    return _mapDioException(error, stackTrace ?? error.stackTrace);
  }

  return ApiException(
    code: ApiCode.unknown,
    message: error.toString(),
    type: ApiErrorType.unknown,
    cause: error,
    stackTrace: stackTrace,
  );
}

ApiException _mapDioException(DioException e, StackTrace? stackTrace) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return ApiException(
        code: ApiCode.timeout,
        message: '请求超时，请稍后重试',
        type: ApiErrorType.timeout,
        cause: e,
        stackTrace: stackTrace,
      );

    case DioExceptionType.cancel:
      return ApiException(
        code: ApiCode.cancelled,
        message: '请求已取消',
        type: ApiErrorType.cancelled,
        cause: e,
        stackTrace: stackTrace,
      );

    case DioExceptionType.connectionError:
      return ApiException(
        code: ApiCode.network,
        message: '网络连接失败，请检查网络',
        type: ApiErrorType.network,
        cause: e,
        stackTrace: stackTrace,
      );

    case DioExceptionType.badCertificate:
      return ApiException(
        code: ApiCode.network,
        message: '证书校验失败',
        type: ApiErrorType.network,
        cause: e,
        stackTrace: stackTrace,
      );

    case DioExceptionType.badResponse:
      return _mapBadResponse(e, stackTrace);

    case DioExceptionType.unknown:
      return ApiException(
        code: ApiCode.unknown,
        message: e.message ?? '未知错误',
        type: ApiErrorType.unknown,
        cause: e,
        stackTrace: stackTrace,
      );
  }
}

/// 解析微软返回的错误体（Graph / OAuth 两种），映射出业务码与提示。
ApiException _mapBadResponse(DioException e, StackTrace? stackTrace) {
  final status = e.response?.statusCode ?? ApiCode.unknown;
  final body = e.response?.data;

  String message = _extractMessage(body) ?? 'HTTP $status';
  final oauthError = _extractOAuthError(body);

  // 归一化业务码：401 / OAuth 凭据类错误归鉴权失败，其余按 HTTP 状态。
  int code;
  ApiErrorType type;
  if (status == 401 || _isOAuthAuthError(oauthError)) {
    code = ApiCode.unauthorized;
    type = ApiErrorType.auth;
  } else if (status == 403) {
    code = ApiCode.forbidden;
    type = ApiErrorType.auth;
  } else if (status == 404) {
    code = ApiCode.notFound;
    type = ApiErrorType.business;
  } else if (status == 429) {
    code = ApiCode.rateLimited;
    type = ApiErrorType.business;
  } else if (status >= 500) {
    code = ApiCode.serverError;
    type = ApiErrorType.business;
  } else {
    code = status;
    type = ApiErrorType.business;
  }

  return ApiException(
    code: code,
    message: message,
    type: type,
    cause: e,
    stackTrace: stackTrace,
  );
}

/// 从错误体提取可读信息 —— 优先 Graph 的 `error.message`，再 OAuth 的
/// `error_description`，再退回 `error` 字符串本身。
String? _extractMessage(Object? body) {
  if (body is! Map) return null;
  final error = body['error'];
  if (error is Map) {
    final msg = error['message'];
    if (msg is String && msg.isNotEmpty) return msg;
  }
  final desc = body['error_description'];
  if (desc is String && desc.isNotEmpty) return desc;
  if (error is String && error.isNotEmpty) return error;
  return null;
}

/// 提取 OAuth 的 `error` 字符串（如 `invalid_grant`），非 OAuth 错误返回 null。
String? _extractOAuthError(Object? body) {
  if (body is! Map) return null;
  final error = body['error'];
  return error is String ? error : null;
}

/// OAuth 的 `error` 是否为「凭据/授权层面」的失败 —— 这类错误重试也没用，
/// 需要用户重新授权并重新导入，故统一归到 [ApiCode.unauthorized]，
/// 让健康检测把账号标记为凭据失效（而非笼统的业务错误、被误当「正常」）。
///
/// 覆盖的典型码：
/// - `invalid_grant`：refresh_token 过期 / 被撤销；
/// - `invalid_client` / `unauthorized_client`：client_id 无效或应用未在该租户注册
///   （对应 AADSTS700016：导入的凭据 client_id 在账号所属目录里查不到）；
/// - `invalid_scope`：申请的 scope 未被授权；
/// - `interaction_required` / `consent_required`：需要用户重新交互授权。
bool _isOAuthAuthError(String? oauthError) => switch (oauthError) {
  'invalid_grant' ||
  'invalid_client' ||
  'unauthorized_client' ||
  'invalid_scope' ||
  'interaction_required' ||
  'consent_required' => true,
  _ => false,
};
