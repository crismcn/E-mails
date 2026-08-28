import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../core/network/api_response.dart';

/// OAuth 刷新返回的令牌结果。
class TokenResult {
  const TokenResult({
    required this.accessToken,
    required this.expiresIn,
    this.refreshToken,
    this.scope,
    this.tokenType,
  });

  /// 访问令牌。
  final String accessToken;

  /// 有效期（秒）。
  final int expiresIn;

  /// 新的刷新令牌 —— 微软可能轮换，非空时应回写覆盖旧值。
  final String? refreshToken;

  final String? scope;
  final String? tokenType;

  factory TokenResult.fromJson(Map<String, dynamic> json) {
    return TokenResult(
      accessToken: json['access_token'] as String,
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 3600,
      refreshToken: json['refresh_token'] as String?,
      scope: json['scope'] as String?,
      tokenType: json['token_type'] as String?,
    );
  }
}

/// OAuth 接口 —— 目前仅刷新令牌（refresh_token 授权）。
class AuthApi {
  AuthApi(this._client);

  /// 需注入基于 OAuth host 的 [ApiClient]（form 编码、无 Bearer）。
  final ApiClient _client;

  /// 用 refresh_token 换 access_token。
  ///
  /// 请求体为 form-urlencoded；dio 已按 [DioClientFactory.buildAuthDio] 配置
  /// 默认 form 编码，此处传 Map 即可。
  ///
  /// [clientSecret] 仅「机密客户端」需要（导入的账号数据里没有，故通常为 null）；
  /// 非空时才附带，与公共客户端流程保持一致。
  Future<ApiResponse<TokenResult>> refreshToken({
    required String clientId,
    required String refreshToken,
    String scope = ApiConfig.defaultScope,
    String? clientSecret,
  }) {
    return _client.post<TokenResult>(
      ApiConfig.oauthTokenPath,
      data: <String, dynamic>{
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'scope': scope,
        if (clientSecret != null && clientSecret.isNotEmpty)
          'client_secret': clientSecret,
      },
      parser: (json) => TokenResult.fromJson(json as Map<String, dynamic>),
    );
  }
}
