import '../core/network/api_client.dart';
import '../core/network/api_response.dart';
import '../core/network/interceptors/auth_interceptor.dart';

/// 邮件列表可切换的文件夹 / 过滤视图（对应顶部抽屉菜单）。
///
/// - [inbox]：收件箱（`/me/messages`，全部邮件按时间倒序）。
/// - [unread]：仅未读（`$filter=isRead eq false`）。
/// - [flagged]：已标星（`$filter=flag/flagStatus eq 'flagged'`）。
/// - [sent]：已发送（`/me/mailFolders/sentitems/messages`）。
enum MailFolder { inbox, unread, flagged, sent }

/// 各视图对应的 Graph 已知文件夹 id —— 供 [MailApi.getFolderStats] 取服务端计数。
///
/// 「已标星」是跨文件夹的**属性过滤**视图，没有对应文件夹实体（返回 null），
/// 因此它拿不到服务端计数，只能退回「已加载条数」这类本地计数。
extension MailFolderStatsTarget on MailFolder {
  String? get statsFolderId => switch (this) {
    MailFolder.inbox || MailFolder.unread => 'inbox',
    MailFolder.sent => 'sentitems',
    MailFolder.flagged => null,
  };
}

/// 某文件夹的服务端计数 —— 与客户端已加载多少页无关。
class MailFolderStats {
  const MailFolderStats({required this.unread, required this.total});

  /// 未读邮件数（`unreadItemCount`）。
  final int unread;

  /// 邮件总数（`totalItemCount`）。
  final int total;

  factory MailFolderStats.fromJson(Map<String, dynamic> json) {
    return MailFolderStats(
      unread: json['unreadItemCount'] as int? ?? 0,
      total: json['totalItemCount'] as int? ?? 0,
    );
  }
}

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
    this.isFlagged = false,
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

  /// 是否已标星（`flag.flagStatus == 'flagged'`）。
  final bool isFlagged;

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

    // flag: {flagStatus:'flagged'|'notFlagged'|'complete'} → 是否已标星。
    var isFlagged = false;
    final flagField = json['flag'];
    if (flagField is Map) {
      isFlagged = (flagField['flagStatus'] as String?)?.toLowerCase() ==
          'flagged';
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
      isFlagged: isFlagged,
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

  /// 取某个已知文件夹的服务端计数（未读数 / 总数）。
  ///
  /// 走 `GET /me/mailFolders/{id}` 的 `unreadItemCount` / `totalItemCount` ——
  /// 这是服务端权威计数，与客户端已加载多少页无关。
  ///
  /// 刻意**不用** `/me/messages?$count=true`：裸 messages 集合上的 `@odata.count`
  /// 已知会偏大（须限定到具体文件夹才准），且要额外带 `ConsistencyLevel: eventual`。
  /// [folderId] 取 [MailFolderStatsTarget.statsFolderId]（`inbox` / `sentitems`）。
  Future<ApiResponse<MailFolderStats>> getFolderStats(
    String email,
    String folderId,
  ) {
    return _client.request<MailFolderStats>(
      method: 'GET',
      path: '/me/mailFolders/$folderId',
      query: <String, dynamic>{r'$select': 'unreadItemCount,totalItemCount'},
      extra: <String, dynamic>{AuthInterceptor.accountKey: email},
      parser: (json) =>
          MailFolderStats.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 列出账号的邮件（分页）。
  ///
  /// [folder] 决定取哪个视图：收件箱 / 未读 / 已标星 / 已发送。已发送走
  /// `sentitems` 文件夹端点，其余走 `/me/messages` 并按需附加 `$filter`。
  ///
  /// **已标星特例**：`flag/flagStatus eq 'flagged'` 属于复杂属性过滤，Graph 不允许
  /// 它与 `$orderby=receivedDateTime desc` 同时下发（否则报
  /// "The restriction or sort order is too complex"），故已标星视图**不带 `$orderby`**，
  /// 改由本方法拿到本页后按 `receivedDateTime` 客户端倒序。其余视图仍走服务端排序。
  Future<ApiResponse<GraphMessagePage>> listMessages(
    String email, {
    int top = 20,
    int skip = 0,
    MailFolder folder = MailFolder.inbox,
  }) {
    final path = switch (folder) {
      MailFolder.sent => '/me/mailFolders/sentitems/messages',
      _ => '/me/messages',
    };
    final filter = switch (folder) {
      MailFolder.unread => 'isRead eq false',
      MailFolder.flagged => "flag/flagStatus eq 'flagged'",
      _ => null,
    };
    final query = <String, dynamic>{
      r'$top': top,
      r'$skip': skip,
      r'$select':
          'id,subject,from,bodyPreview,isRead,receivedDateTime,conversationId',
    };
    // 已标星不带 $orderby（复杂过滤 + 排序会被 Graph 拒），其余服务端排序。
    if (folder != MailFolder.flagged) {
      query[r'$orderby'] = 'receivedDateTime desc';
    }
    if (filter != null) query[r'$filter'] = filter;
    return _client.request<GraphMessagePage>(
      method: 'GET',
      path: path,
      query: query,
      extra: <String, dynamic>{AuthInterceptor.accountKey: email},
      parser: (json) {
        final page = GraphMessagePage.fromJson(json as Map<String, dynamic>);
        // 已标星本页客户端倒序（服务端未排序）。
        if (folder != MailFolder.flagged) return page;
        final sorted = [...page.items]
          ..sort((a, b) => b.receivedDateTime.compareTo(a.receivedDateTime));
        return GraphMessagePage(items: sorted, nextLink: page.nextLink);
      },
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
            'id,subject,from,toRecipients,body,bodyPreview,isRead,receivedDateTime,conversationId,flag',
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

  /// 标星 / 取消标星 —— PATCH `/me/messages/{id}` 改 `flag.flagStatus`。
  ///
  /// 与 [updateRead] 同属写操作，需要 `Mail.ReadWrite` scope；仅 `Mail.Read` 的账号
  /// 会返回 403 / AADSTS70000，由调用方据 [ApiResponse.isSuccess] 回滚本地乐观更新并提示。
  Future<ApiResponse<GraphMessage>> updateFlag(
    String email,
    String id, {
    required bool flagged,
  }) {
    return _client.request<GraphMessage>(
      method: 'PATCH',
      path: '/me/messages/$id',
      data: <String, dynamic>{
        'flag': <String, dynamic>{
          'flagStatus': flagged ? 'flagged' : 'notFlagged',
        },
      },
      extra: <String, dynamic>{AuthInterceptor.accountKey: email},
      parser: (json) => GraphMessage.fromJson(json as Map<String, dynamic>),
    );
  }
  ///
  /// 需要 `Mail.Send` scope。导入的账号若未授权它，会返回 403 / AADSTS70000，
  /// 由调用方据 [ApiResponse.isSuccess] 如实提示（需重新授权换 token，见 CLAUDE.md §6）。
  ///
  /// 成功时 Graph 返回 **202 Accepted 且响应体为空**，故解析器忽略 body 直接返回 true。
  /// [importance] 取 `high` / `normal` / `low`；[isHtml] 决定正文 contentType。
  Future<ApiResponse<bool>> sendMail(
    String email, {
    required List<String> to,
    required String subject,
    required String body,
    bool isHtml = false,
    String importance = 'normal',
  }) {
    return _client.request<bool>(
      method: 'POST',
      path: '/me/sendMail',
      data: <String, dynamic>{
        'message': <String, dynamic>{
          'subject': subject,
          'importance': importance,
          'body': <String, dynamic>{
            'contentType': isHtml ? 'html' : 'text',
            'content': body,
          },
          'toRecipients': [
            for (final address in to)
              <String, dynamic>{
                'emailAddress': <String, dynamic>{'address': address},
              },
          ],
        },
        'saveToSentItems': true,
      },
      extra: <String, dynamic>{AuthInterceptor.accountKey: email},
      // 202 无响应体：忽略 body，成功即视为已发送。
      parser: (_) => true,
    );
  }
}
