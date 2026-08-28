import '../core/network/api_client.dart';
import '../core/network/api_response.dart';
import '../core/network/interceptors/auth_interceptor.dart';

/// Graph 邮件消息（仅取列表/详情所需字段）。
class GraphMessage {
  const GraphMessage({
    required this.id,
    required this.subject,
    required this.from,
    required this.fromName,
    required this.bodyPreview,
    required this.isRead,
    required this.receivedDateTime,
    this.conversationId = '',
    this.toRecipients = const <String>[],
    this.bodyContent,
    this.bodyIsHtml = false,
  });

  final String id;
  final String subject;

  /// 发件人邮箱地址（`from.emailAddress.address`）。
  final String from;

  /// 发件人显示名（`from.emailAddress.name`），可能为空。
  final String fromName;

  final String bodyPreview;
  final bool isRead;

  /// 收件时间，ISO-8601 UTC 字符串（如 `2026-08-28T01:02:03Z`）。
  final String receivedDateTime;

  /// 会话标识 —— 同一会话的消息共享它，供 `listConversation` 串联。
  final String conversationId;

  /// 收件人邮箱地址列表（`toRecipients[].emailAddress.address`）。
  final List<String> toRecipients;

  /// 正文全文 —— **仅** `getMessage`（带 `$select=body`）时有值；列表/会话查询为 null。
  final String? bodyContent;

  /// 正文是否为 HTML（`body.contentType == 'html'`）。
  final bool bodyIsHtml;

  factory GraphMessage.fromJson(Map<String, dynamic> json) {
    final fromField = json['from'];
    String address = '';
    String name = '';
    if (fromField is Map) {
      final emailAddress = fromField['emailAddress'];
      if (emailAddress is Map) {
        if (emailAddress['address'] is String) {
          address = emailAddress['address'] as String;
        }
        if (emailAddress['name'] is String) {
          name = emailAddress['name'] as String;
        }
      }
    }

    // toRecipients: [{emailAddress:{address,name}}, ...] → 取地址。
    final recipients = <String>[];
    final toField = json['toRecipients'];
    if (toField is List) {
      for (final r in toField) {
        if (r is Map) {
          final ea = r['emailAddress'];
          if (ea is Map && ea['address'] is String) {
            recipients.add(ea['address'] as String);
          }
        }
      }
    }

    // body: {contentType:'html'|'text', content:'...'}（仅详情查询返回）。
    String? bodyContent;
    var bodyIsHtml = false;
    final bodyField = json['body'];
    if (bodyField is Map) {
      if (bodyField['content'] is String) {
        bodyContent = bodyField['content'] as String;
      }
      bodyIsHtml = (bodyField['contentType'] as String?)?.toLowerCase() == 'html';
    }

    return GraphMessage(
      id: json['id'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      from: address,
      fromName: name,
      bodyPreview: json['bodyPreview'] as String? ?? '',
      isRead: json['isRead'] as bool? ?? false,
      receivedDateTime: json['receivedDateTime'] as String? ?? '',
      conversationId: json['conversationId'] as String? ?? '',
      toRecipients: recipients,
      bodyContent: bodyContent,
      bodyIsHtml: bodyIsHtml,
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

/// Graph 邮件接口 —— 走统一请求规范：鉴权拦截注入 Bearer + 401 刷新重试 + 响应归一化。
///
/// 已接入邮件列表页（[listMessages]）。
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
        r'$select':
            'id,subject,from,bodyPreview,isRead,receivedDateTime,conversationId',
        r'$orderby': 'receivedDateTime desc',
      },
      extra: <String, dynamic>{AuthInterceptor.accountKey: email},
      parser: (json) =>
          GraphMessagePage.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 列出某会话的全部邮件（同一 [conversationId]）。
  ///
  /// 注意：Graph 的 `$filter=conversationId eq '...'` **不能同时带 `$orderby`**
  /// （否则报 "restriction or sort order is too complex"），故这里不排序，
  /// 由调用方按 `receivedDateTime` 客户端排序。conversationId 里的单引号转义为 `''`，
  /// 其余字符交给 dio 自动 URL 编码。
  Future<ApiResponse<GraphMessagePage>> listConversation(
    String email,
    String conversationId, {
    int top = 50,
  }) {
    final escaped = conversationId.replaceAll("'", "''");
    return _client.request<GraphMessagePage>(
      method: 'GET',
      path: '/me/messages',
      query: <String, dynamic>{
        r'$filter': "conversationId eq '$escaped'",
        r'$select':
            'id,subject,from,toRecipients,bodyPreview,isRead,receivedDateTime,conversationId',
        r'$top': top,
      },
      extra: <String, dynamic>{AuthInterceptor.accountKey: email},
      parser: (json) =>
          GraphMessagePage.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 取单封邮件详情（含全文 `body` 与收件人）。
  Future<ApiResponse<GraphMessage>> getMessage(String email, String id) {
    return _client.request<GraphMessage>(
      method: 'GET',
      path: '/me/messages/$id',
      query: <String, dynamic>{
        r'$select':
            'id,subject,from,toRecipients,body,bodyPreview,isRead,receivedDateTime,conversationId',
      },
      extra: <String, dynamic>{AuthInterceptor.accountKey: email},
      parser: (json) => GraphMessage.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 标记已读 / 未读 —— PATCH `/me/messages/{id}` 改 `isRead`。
  ///
  /// 需要 `Mail.ReadWrite` scope；只授予 `Mail.Read` 的账号会返回 403 / AADSTS70000，
  /// 由调用方据 [ApiResponse.isSuccess] 回滚本地乐观更新并提示。
  Future<ApiResponse<GraphMessage>> updateRead(
    String email,
    String id, {
    required bool isRead,
  }) {
    return _client.request<GraphMessage>(
      method: 'PATCH',
      path: '/me/messages/$id',
      data: <String, dynamic>{'isRead': isRead},
      extra: <String, dynamic>{AuthInterceptor.accountKey: email},
      parser: (json) => GraphMessage.fromJson(json as Map<String, dynamic>),
    );
  }
}
