import '../core/network/api_client.dart';
import '../core/network/api_response.dart';
import '../core/network/interceptors/auth_interceptor.dart';

/// Graph 邮件消息（示例模型，仅取常用字段）。
class GraphMessage {
  const GraphMessage({
    required this.id,
    required this.subject,
    required this.from,
    required this.bodyPreview,
    required this.isRead,
    required this.receivedDateTime,
  });

  final String id;
  final String subject;
  final String from;
  final String bodyPreview;
  final bool isRead;
  final String receivedDateTime;

  factory GraphMessage.fromJson(Map<String, dynamic> json) {
    final fromField = json['from'];
    String address = '';
    if (fromField is Map) {
      final emailAddress = fromField['emailAddress'];
      if (emailAddress is Map && emailAddress['address'] is String) {
        address = emailAddress['address'] as String;
      }
    }
    return GraphMessage(
      id: json['id'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      from: address,
      bodyPreview: json['bodyPreview'] as String? ?? '',
      isRead: json['isRead'] as bool? ?? false,
      receivedDateTime: json['receivedDateTime'] as String? ?? '',
    );
  }
}

/// 一页消息 —— 列表 + 下一页链接（Graph 的 `@odata.nextLink`）。
class GraphMessagePage {
  const GraphMessagePage({required this.items, this.nextLink});

  final List<GraphMessage> items;
  final String? nextLink;

  factory GraphMessagePage.fromJson(Map<String, dynamic> json) {
    final value = (json['value'] as List?) ?? const [];
    return GraphMessagePage(
      items: value
          .whereType<Map<String, dynamic>>()
          .map(GraphMessage.fromJson)
          .toList(),
      nextLink: json['@odata.nextLink'] as String?,
    );
  }
}

/// Graph 邮件接口（示例）—— 演示「请求规范」用法：鉴权拦截 + 401 重试 + 归一化。
///
/// 尚未接入 UI / 替换页面 mock，仅证明封装层可用。
class MailApi {
  MailApi(this._client);

  /// 需注入基于 Graph host 的 [ApiClient]（带鉴权拦截器）。
  final ApiClient _client;

  /// 列出账号的邮件（分页）。
  Future<ApiResponse<GraphMessagePage>> listMessages(
    String email, {
    int top = 20,
    int skip = 0,
  }) {
    return _client.request<GraphMessagePage>(
      method: 'GET',
      path: '/me/messages',
      query: <String, dynamic>{
        r'$top': top,
        r'$skip': skip,
        r'$select': 'id,subject,from,bodyPreview,isRead,receivedDateTime',
        r'$orderby': 'receivedDateTime desc',
      },
      extra: <String, dynamic>{AuthInterceptor.accountKey: email},
      parser: (json) =>
          GraphMessagePage.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 取单封邮件详情。
  Future<ApiResponse<GraphMessage>> getMessage(String email, String id) {
    return _client.request<GraphMessage>(
      method: 'GET',
      path: '/me/messages/$id',
      extra: <String, dynamic>{AuthInterceptor.accountKey: email},
      parser: (json) => GraphMessage.fromJson(json as Map<String, dynamic>),
    );
  }
}
