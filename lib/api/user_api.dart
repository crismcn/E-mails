import '../core/network/api_client.dart';
import '../core/network/api_response.dart';

/// Graph 用户信息（`GET /me`）—— 健康检测用它确认「拿到的 token 真能读到账号」。
class GraphUser {
  const GraphUser({
    required this.id,
    required this.displayName,
    required this.userPrincipalName,
    required this.mail,
  });

  final String id;
  final String displayName;
  final String userPrincipalName;

  /// 主邮箱地址；个人账号常为空，此时回退 [userPrincipalName]。
  final String mail;

  /// 展示用邮箱地址 —— mail 优先，其次 userPrincipalName。
  String get address => mail.isNotEmpty ? mail : userPrincipalName;

  factory GraphUser.fromJson(Map<String, dynamic> json) => GraphUser(
    id: json['id'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    userPrincipalName: json['userPrincipalName'] as String? ?? '',
    mail: json['mail'] as String? ?? '',
  );
}

/// 账号自身信息接口 —— 只有 `GET /me`，供健康检测使用。
///
/// 与 [MailApi] 的区别：这里**不走鉴权拦截器**，由调用方显式传入 access_token。
/// 因为健康检测申请的是 `User.Read` scope 的独立 token，不该复用/污染
/// 邮件业务的 token 缓存。
class UserApi {
  UserApi(this._client);

  /// 需注入基于 Graph host 的**裸** [ApiClient]（`buildPlainGraphDio`，无鉴权拦截器）。
  final ApiClient _client;

  /// 读取当前 token 对应的账号信息。
  Future<ApiResponse<GraphUser>> getMe(String accessToken) {
    return _client.request<GraphUser>(
      method: 'GET',
      path: '/me',
      headers: <String, dynamic>{'Authorization': 'Bearer $accessToken'},
      parser: (json) => GraphUser.fromJson(json as Map<String, dynamic>),
    );
  }
}
