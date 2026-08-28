import 'package:dio/dio.dart';

import 'package:email_manager/api/mail_api.dart';
import 'package:email_manager/core/network/api_client.dart';
import 'package:email_manager/core/network/api_response.dart';

/// 可控的 [MailApi] 替身 —— 从内存数据返回，记录调用参数。
///
/// 直接继承真实 [MailApi] 并覆盖方法：既不必引入 mock 框架，
/// 也保证接口签名跟着真实实现一起演进（签名变了这里编译不过）。
/// `super` 需要一个 [ApiClient]，给个裸 [Dio] 即可 —— 覆盖后不会真的发请求。
class FakeMailApi extends MailApi {
  FakeMailApi({
    List<GraphMessage>? messages,
    Map<String, List<GraphMessage>>? conversations,
    Map<String, GraphMessage>? fullMessages,
    this.failure,
  }) : messages = messages ?? kFakeGraphMessages,
       conversations = conversations ?? kFakeConversations,
       fullMessages = fullMessages ?? kFakeFullMessages,
       super(ApiClient(Dio()));

  /// 服务端「全部」邮件，按 skip/top 切片。
  final List<GraphMessage> messages;

  /// 会话成员：conversationId → 该会话的邮件（乱序即可，页面会自行排序）。
  final Map<String, List<GraphMessage>> conversations;

  /// 单封全文：message.id → 带 body 的消息（供 getMessage 懒取）。
  final Map<String, GraphMessage> fullMessages;

  /// 非空时所有请求都返回它（用于验证错误态）。
  final ApiResponse<GraphMessagePage>? failure;

  /// updateRead 是否失败（模拟只有 Mail.Read 权限的账号写回被拒）。
  bool updateReadFails = false;

  /// 记录每次列表请求的 `$skip`，用于断言翻页参数。
  final List<int> skips = <int>[];

  /// 记录 getMessage 请求过的 id。
  final List<String> fetchedIds = <String>[];

  /// 记录 updateRead 调用：`(id, isRead)`。
  final List<(String, bool)> readUpdates = <(String, bool)>[];

  int get calls => skips.length;

  @override
  Future<ApiResponse<GraphMessagePage>> listMessages(
    String email, {
    int top = 20,
    int skip = 0,
  }) async {
    skips.add(skip);
    final failed = failure;
    if (failed != null) return failed;
    return ApiResponse<GraphMessagePage>.success(
      GraphMessagePage(items: messages.skip(skip).take(top).toList()),
    );
  }

  @override
  Future<ApiResponse<GraphMessagePage>> listConversation(
    String email,
    String conversationId, {
    int top = 50,
  }) async {
    final failed = failure;
    if (failed != null) return failed;
    return ApiResponse<GraphMessagePage>.success(
      GraphMessagePage(
        items: (conversations[conversationId] ?? const []).take(top).toList(),
      ),
    );
  }

  @override
  Future<ApiResponse<GraphMessage>> getMessage(String email, String id) async {
    fetchedIds.add(id);
    final full = fullMessages[id];
    if (full != null) return ApiResponse<GraphMessage>.success(full);
    // 未预置全文的：回退到列表/会话里同 id 的消息（无 body）。
    final all = [
      ...messages,
      for (final c in conversations.values) ...c,
    ];
    final match = all.where((m) => m.id == id);
    if (match.isNotEmpty) {
      return ApiResponse<GraphMessage>.success(match.first);
    }
    return const ApiResponse<GraphMessage>.failure(-99, 'not found');
  }

  @override
  Future<ApiResponse<GraphMessage>> updateRead(
    String email,
    String id, {
    required bool isRead,
  }) async {
    readUpdates.add((id, isRead));
    if (updateReadFails) {
      return const ApiResponse<GraphMessage>.failure(403, 'AADSTS70000: 无写权限');
    }
    return ApiResponse<GraphMessage>.success(
      fakeGraphMessage(id: id, isRead: isRead),
    );
  }
}

/// 造一封 Graph 消息 —— 只填测试关心的字段。
GraphMessage fakeGraphMessage({
  required String id,
  String subject = '',
  String fromName = '',
  String from = '',
  String bodyPreview = '',
  bool isRead = true,
  String receivedDateTime = '2026-08-25T09:38:00Z',
  String conversationId = '',
  List<String> toRecipients = const <String>[],
  String? bodyContent,
  bool bodyIsHtml = false,
}) {
  return GraphMessage(
    id: id,
    subject: subject,
    from: from,
    fromName: fromName,
    bodyPreview: bodyPreview,
    isRead: isRead,
    receivedDateTime: receivedDateTime,
    conversationId: conversationId,
    toRecipients: toRecipients,
    bodyContent: bodyContent,
    bodyIsHtml: bodyIsHtml,
  );
}

/// 列表默认数据 —— 沿用原发件人/主题，让会话页与详情页的既有断言继续成立。
final List<GraphMessage> kFakeGraphMessages = [
  fakeGraphMessage(
    id: 'm1',
    conversationId: 'c1',
    fromName: 'Claude',
    from: 'noreply@anthropic.com',
    subject: 'Claude 任务执行通知 · ✅ 任务已完成',
    isRead: false,
  ),
  fakeGraphMessage(
    id: 'm2',
    conversationId: 'c2',
    fromName: 'Cursor Team',
    from: 'team@cursor.com',
    subject: 'Get more room to build with Cursor',
    bodyPreview: 'Cursor 邀请你体验新功能',
  ),
  // 蓝湖官方 —— 会话 c3 的最新一条（未读），点开进入多消息会话。
  fakeGraphMessage(
    id: 'c3-3',
    conversationId: 'c3',
    fromName: '蓝湖官方',
    from: 'notice@lanhuapp.com',
    subject: '蓝湖免费版权益调整通知 尊敬的蓝湖用户',
    bodyPreview: '尊敬的用户，请查收本次通知',
    isRead: false,
    receivedDateTime: '2026-08-24T15:02:00Z',
  ),
];

/// 会话成员：c1/c2 各 1 封（单封会话），c3 为 3 封多消息会话。
final Map<String, List<GraphMessage>> kFakeConversations = {
  'c1': [kFakeGraphMessages[0]],
  'c2': [kFakeGraphMessages[1]],
  'c3': [
    fakeGraphMessage(
      id: 'c3-1',
      conversationId: 'c3',
      fromName: '蓝湖官方',
      from: 'notice@lanhuapp.com',
      subject: '蓝湖免费版权益调整通知 尊敬的蓝湖用户',
      bodyPreview: '蓝湖历史消息一',
      receivedDateTime: '2026-08-24T14:58:00Z',
      toRecipients: const ['crism@qq.com'],
    ),
    fakeGraphMessage(
      id: 'c3-2',
      conversationId: 'c3',
      fromName: '蓝湖官方',
      from: 'notice@lanhuapp.com',
      subject: '蓝湖免费版权益调整通知 尊敬的蓝湖用户',
      bodyPreview: '蓝湖历史消息二',
      receivedDateTime: '2026-08-24T15:00:00Z',
      toRecipients: const ['crism@qq.com'],
    ),
    kFakeGraphMessages[2], // c3-3，最新未读
  ],
};

/// 单封全文（getMessage）：最新一条为 HTML（含链接），历史为纯文本。
final Map<String, GraphMessage> kFakeFullMessages = {
  // Claude（列表项 m1）—— 纯文本全文，供详情页纯文本渲染路径。
  'm1': fakeGraphMessage(
    id: 'm1',
    conversationId: 'c1',
    fromName: 'Claude',
    subject: 'Claude 任务执行通知 · ✅ 任务已完成',
    toRecipients: const ['crism@qq.com'],
    receivedDateTime: '2026-08-25T09:38:00Z',
    bodyContent: '这是 Claude 通知的纯文本正文，仅用于验证纯文本渲染。',
    bodyIsHtml: false,
  ),
  'c3-1': fakeGraphMessage(
    id: 'c3-1',
    conversationId: 'c3',
    fromName: '蓝湖官方',
    subject: '蓝湖免费版权益调整通知 尊敬的蓝湖用户',
    toRecipients: const ['crism@qq.com'],
    receivedDateTime: '2026-08-24T14:58:00Z',
    bodyContent: '这是历史消息一的纯文本正文，仅用于验证纯文本渲染。',
    bodyIsHtml: false,
  ),
  'c3-3': fakeGraphMessage(
    id: 'c3-3',
    conversationId: 'c3',
    fromName: '蓝湖官方',
    subject: '蓝湖免费版权益调整通知 尊敬的蓝湖用户',
    toRecipients: const ['crism@qq.com'],
    receivedDateTime: '2026-08-24T15:02:00Z',
    bodyIsHtml: true,
    bodyContent: '''
<h2>蓝湖官方 安全通知</h2>
<p>尊敬的用户，您好！</p>
<p>请及时处理：</p>
<p><a href="https://example.com/security">前往安全中心</a></p>
<p>或查看详情：<a href="https://example.com/detail">https://example.com/detail</a></p>
''',
  ),
};
