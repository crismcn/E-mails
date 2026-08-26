import '../models/mail.dart';

/// 会话历史模拟分页数 —— 下拉两次后即无更多历史。
const int kMockThreadHistoryPages = 2;

/// 会话初始页 —— 最近的若干条消息（最早 → 最新，最后一条为最新）。
///
/// 未读落在较早的消息上（最新一条视为已读），
/// 便于「点击未读条数跳转到最新未读邮件」的向上跳转。
List<MailMessage> mockThreadInitial(MailPreview mail) {
  return [
    MailMessage(
      sender: mail.sender,
      time: '8/24 14:58',
      body: mail.subject,
      unread: mail.unread > 1,
    ),
    MailMessage(
      sender: mail.sender,
      time: '8/24 15:00',
      body: mail.subject,
      unread: mail.unread > 0,
    ),
    MailMessage(sender: mail.sender, time: '8/24 15:02', body: _detailBody(mail)),
  ];
}

/// 第 [page] 页历史消息（1 起）—— 越大的页码时间越早，返回值内部仍为最早 → 最新。
///
/// 调用方将其整段插到现有列表头部即可保持全局时间正序。
List<MailMessage> mockThreadHistory(MailPreview mail, int page) {
  final day = 24 - page;
  return [
    for (int i = 0; i < 3; i++)
      MailMessage(
        sender: mail.sender,
        time: '8/$day ${_two(9 + i * 3)}:${_two(5 + i * 7)}',
        body: mail.subject,
      ),
  ];
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 最近一条的完整正文（模拟一封通知邮件）。
String _detailBody(MailPreview mail) {
  return '${mail.subject}\n\n'
      '尊敬的用户，您好！\n\n'
      '您的账号于 ${mail.time} 触发了本次通知。若非您本人或已授权允许的操作，'
      '请尽快前往账号安全中心进行核实与处理。\n\n'
      '如需了解更多信息，可前往对应的管理后台查看完整记录。感谢您的使用。';
}
