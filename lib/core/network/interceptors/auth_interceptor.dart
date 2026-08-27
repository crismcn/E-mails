import 'package:dio/dio.dart';

import '../../auth/token_service.dart';
import '../api_exception.dart';

/// Graph 请求的鉴权拦截器 —— 注入 Bearer + 401 自动刷新重试一次。
///
/// 约定：调用方通过 `Options(extra: {AuthInterceptor.accountKey: email})`
/// 指明这条请求属于哪个账号，拦截器据此取该账号的 access_token。
///
/// 用 [QueuedInterceptorsWrapper]：同一时刻只处理一个请求的鉴权流程，
/// 天然避免多请求同时触发刷新时的竞态（刷新去重另由 [TokenService] 兜底）。
class AuthInterceptor extends QueuedInterceptorsWrapper {
  AuthInterceptor(this._tokenService);

  final TokenService _tokenService;

  /// `extra` 中标识账号邮箱的键。
  static const String accountKey = 'account';

  /// `extra` 中标识「已重试过」的键，防止 401 无限重试。
  static const String _retriedKey = '__auth_retried__';

  /// 供重试用的裸 dio —— 不含本拦截器，避免重试再次进入鉴权流程造成递归。
  final Dio _retryDio = Dio();

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final email = options.extra[accountKey] as String?;
    if (email == null || email.isEmpty) {
      // 未指明账号：不注入 token，交由后端返回 401（也可视为编程错误）。
      handler.next(options);
      return;
    }
    try {
      final token = await _tokenService.accessTokenFor(email);
      options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    } on ApiException catch (e) {
      // 取 token 就失败（凭据缺失 / 刷新被拒）：直接以 DioException 中断。
      handler.reject(
        DioException(requestOptions: options, error: e, message: e.message),
      );
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final email = options.extra[accountKey] as String?;
    final alreadyRetried = options.extra[_retriedKey] == true;
    final status = err.response?.statusCode;

    // 仅对「首次 401 且有账号」触发一次刷新重试。
    if (status != 401 || email == null || email.isEmpty || alreadyRetried) {
      handler.next(err);
      return;
    }

    try {
      // 强制刷新该账号 token 后带着新 token 重发一次。
      _tokenService.invalidate(email);
      final token = await _tokenService.accessTokenFor(email, forceRefresh: true);
      options.headers['Authorization'] = 'Bearer $token';
      options.extra[_retriedKey] = true;
      final response = await _retryDio.fetch<dynamic>(options);
      handler.resolve(response);
    } on ApiException catch (e) {
      handler.reject(
        DioException(requestOptions: options, error: e, message: e.message),
      );
    } on DioException catch (e) {
      // 重试仍失败：把新的错误往下传。
      handler.next(e);
    }
  }
}
