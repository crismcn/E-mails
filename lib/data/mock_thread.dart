import '../models/mail.dart';

/// 会话历史模拟分页数 —— 下拉两次后即无更多历史。
const int kMockThreadHistoryPages = 2;

/// 会话初始页 —— 最近的若干条消息（最早 → 最新，最后一条为最新）。
///
/// 未读落在较早的消息上（最新一条视为已读），
/// 便于「点击未读条数跳转到最新未读邮件」的向上跳转。
/// 最新一条带 [MailMessage.htmlBody]（演示 HTML 渲染 + 链接点击），
/// 其余仅纯文本（演示纯文本回退）。
List<MailMessage> mockThreadInitial(MailPreview mail) {
  return [
    MailMessage(
      sender: mail.sender,
      time: '8/24 14:58',
      body: mail.subject,
      unread: mail.unread > 1,
      recipient: 'crism@qq.com',
      subject: mail.subject,
      fullDate: '2026年8月24日周日 14:58',
    ),
    MailMessage(
      sender: mail.sender,
      time: '8/24 15:00',
      body: mail.subject,
      unread: mail.unread > 0,
      recipient: 'crism@qq.com',
      subject: mail.subject,
      fullDate: '2026年8月24日周日 15:00',
    ),
    MailMessage(
      sender: mail.sender,
      time: '8/24 15:02',
      body: _plainBody(mail),
      recipient: 'crism@qq.com',
      subject: mail.subject,
      fullDate: '2026年8月24日周日 15:02',
      htmlBody: _htmlBody(mail),
    ),
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
        recipient: 'crism@qq.com',
        subject: mail.subject,
        fullDate: '2026年8月$day日 ${_two(9 + i * 3)}:${_two(5 + i * 7)}',
      ),
  ];
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 纯文本正文回退（当消息无 HTML 时详情页展示）。
String _plainBody(MailPreview mail) {
  return '${mail.subject}\n\n'
      '尊敬的用户，您好！\n\n'
      '您的账号于 ${mail.time} 触发了本次通知。若非您本人或已授权允许的操作，'
      '请尽快前往账号安全中心进行核实与处理。\n\n'
      '如需了解更多信息，可前往对应的管理后台查看完整记录。感谢您的使用。';
}

/// HTML 正文（演示富文本 + 超链接 + 样式化按钮链接）。
String _htmlBody(MailPreview mail) {
  return '''
<h2>${mail.sender} 安全通知</h2>
<p>尊敬的用户，您好！</p>
<p>${mail.subject}</p>
<p>此操作触发于 <b>${mail.time}</b>。若非本人操作，请立即处理：</p>
<ul>
  <li>确认设备与登录地点</li>
  <li>必要时修改密码并开启两步验证</li>
</ul>
<p>
  <a href="https://example.com/security"
     style="display:inline-block;padding:10px 18px;background:#2F80FF;color:#ffffff;border-radius:8px;text-decoration:none;">
    前往安全中心
  </a>
</p>
<p>或点击此链接查看详情：<a href="https://example.com/detail">https://example.com/detail</a></p>
<p>感谢您的使用。<br/>—— ${mail.sender} 团队</p>
''';
}
