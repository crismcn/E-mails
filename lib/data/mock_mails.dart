import '../models/mail.dart';

/// 邮件列表示例数据 —— 与「邮件列表」设计稿一致。
const List<MailPreview> kMockMails = [
  MailPreview(
    sender: 'Claude',
    subject: 'Claude 任务执行通知 · ✅ 任务已完成',
    time: '09:38',
    unread: 45,
    count: 146,
  ),
  MailPreview(
    sender: 'Cursor Team',
    subject: 'Get more room to build with Cursor',
    time: '8/25',
  ),
  MailPreview(
    sender: 'npm',
    subject: 'You still do not have two-factor authentication',
    time: '8/25',
  ),
  MailPreview(
    sender: 'GitHub',
    subject: 'Hey CrismLeo! A third-party OAuth application',
    time: '8/25',
    unread: 8,
    count: 15,
  ),
  MailPreview(
    sender: 'Google',
    subject: 'Keep track of your Google Account activity',
    time: '8/25',
    unread: 4,
    count: 5,
  ),
  MailPreview(
    sender: 'crism',
    subject: 'YYF · 悦音坊软件 crism@qq.com 的邮件',
    time: '8/25',
  ),
  MailPreview(
    sender: '蓝湖官方',
    subject: '蓝湖免费版权益调整通知 尊敬的蓝湖用户',
    time: '8/25',
    unread: 1,
  ),
  MailPreview(
    sender: '[crismcn] Run failed: Scrape',
    subject: 'crismcn: [crismcn/HwNews] Scrape workflow',
    time: '8/25',
    unread: 1,
  ),
  MailPreview(
    sender: '全村的API（正式版）',
    subject: '您好，你正在进行全村的API（正式版）的调用',
    time: '8/25',
  ),
];
