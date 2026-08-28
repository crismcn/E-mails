/// Graph 消息 → 邮件列表展示模型的映射（纯函数，便于单测）。
///
/// 边界约定：
/// - Graph 返回的是**单封消息**，不是会话，故 `MailPreview.count`（会话内邮件数）
///   恒为 0（列表项不显示该角标），`MailPreview.unread` 用 0/1 表达已读/未读。
/// - 发件人显示名可能缺失（如草稿），依次回退到邮箱地址、再到占位符 `—`；
///   占位符取语言中立的符号，避免在数据层写死中英文案。
library;

import '../api/mail_api.dart';
import '../models/mail.dart';

/// 无发件人时的占位符 —— 语言中立。
const String kUnknownSender = '—';

/// 把一封 Graph 消息转成列表项。
///
/// [now] 供测试注入「当前时间」，决定时间标签是显示时刻还是日期。
MailPreview mailPreviewFromGraph(GraphMessage message, {DateTime? now}) {
  final received = DateTime.tryParse(message.receivedDateTime);
  return MailPreview(
    id: message.id,
    conversationId: message.conversationId,
    sender: _sender(message),
    subject: _subject(message),
    time: received == null
        ? ''
        : formatMailTime(received, now ?? DateTime.now()),
    unread: message.isRead ? 0 : 1,
  );
}

/// 批量映射 —— 同一批共用一个 [now]，避免逐条取时间导致同批标签不一致。
List<MailPreview> mailPreviewsFromGraph(
  Iterable<GraphMessage> messages, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  return [for (final m in messages) mailPreviewFromGraph(m, now: at)];
}

/// 列表项右上角时间标签：今天显示 `HH:mm`，今年显示 `M/D`，更早显示 `YYYY/M/D`。
///
/// 两个时间都会先转为本地时区再比较 —— Graph 返回的是 UTC，
/// 直接比日期会在跨时区时把「今天的邮件」显示成昨天。
String formatMailTime(DateTime received, DateTime now) {
  final at = received.toLocal();
  final today = now.toLocal();
  if (at.year == today.year && at.month == today.month && at.day == today.day) {
    return '${_two(at.hour)}:${_two(at.minute)}';
  }
  if (at.year == today.year) return '${at.month}/${at.day}';
  return '${at.year}/${at.month}/${at.day}';
}

String _two(int value) => value.toString().padLeft(2, '0');

/// 会话/详情用完整日期标签，如 `2026年8月24日 14:58`（本地时区）。
String formatFullDate(DateTime received) {
  final at = received.toLocal();
  return '${at.year}年${at.month}月${at.day}日 ${_two(at.hour)}:${_two(at.minute)}';
}

/// 把一封 Graph 会话消息转成会话页展示模型 [MailMessage]。
///
/// 会话页气泡默认显示 `bodyPreview`（全文由详情页或 [applyBody] 懒取）。
MailMessage mailMessageFromGraph(GraphMessage message, {DateTime? now}) {
  final received = DateTime.tryParse(message.receivedDateTime);
  return MailMessage(
    id: message.id,
    sender: _sender(message),
    time: received == null ? '' : formatMailTime(received, now ?? DateTime.now()),
    body: message.bodyPreview,
    unread: !message.isRead,
    recipient: message.toRecipients.join('; '),
    subject: message.subject,
    fullDate: received == null ? '' : formatFullDate(received),
  );
}

/// 批量映射会话消息 —— 同一批共用一个 [now]。
List<MailMessage> mailMessagesFromGraph(
  Iterable<GraphMessage> messages, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  return [for (final m in messages) mailMessageFromGraph(m, now: at)];
}

/// 从列表项 [preview] 构造详情页的初始占位消息。
///
/// 列表查询不含全文与完整日期，故 `body` 留空、`fullDate` 留空 —— 详情页按 `id`
/// 懒取全文后会用权威数据整体重建（见 message_detail_page 的 `_fetchBody`）。
/// 这里先带上发件人/主题/未读态，让详情页在加载全文期间也有内容可显示。
MailMessage mailMessageFromPreview(MailPreview preview) {
  return MailMessage(
    id: preview.id,
    sender: preview.sender,
    subject: preview.subject,
    time: preview.time,
    body: '',
    unread: preview.unread > 0,
  );
}

/// 把懒取到的全文（[full] 来自 `getMessage`）并入已有的会话消息 [base]。
///
/// HTML 正文 → `htmlBody`（详情页富文本渲染）；纯文本 → `body`（纯文本回退）。
/// 收件人为空时用取回的补齐。
MailMessage applyBody(MailMessage base, GraphMessage full) {
  final content = full.bodyContent;
  if (content == null || content.isEmpty) return base;
  return base.copyWith(
    htmlBody: full.bodyIsHtml ? content : null,
    body: full.bodyIsHtml ? base.body : content,
    recipient: base.recipient.isEmpty
        ? full.toRecipients.join('; ')
        : base.recipient,
  );
}

/// 发件人：显示名 → 邮箱地址 → 占位符。
String _sender(GraphMessage m) {
  if (m.fromName.isNotEmpty) return m.fromName;
  if (m.from.isNotEmpty) return m.from;
  return kUnknownSender;
}

/// 第二行：主题；主题为空（不少通知类邮件如此）时退回正文摘要。
String _subject(GraphMessage m) =>
    m.subject.isNotEmpty ? m.subject : m.bodyPreview;
