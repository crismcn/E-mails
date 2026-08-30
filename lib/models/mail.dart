import 'package:flutter/material.dart';

/// 单条邮件（会话）预览 —— 对应邮件列表中的一行。
class MailPreview {
  const MailPreview({
    required this.sender,
    required this.subject,
    required this.time,
    this.id = '',
    this.conversationId = '',
    this.unread = 0,
    this.count = 0,
  });

  /// 服务端消息 id（Graph `message.id`）—— 供列表项去重与后续读/删操作定位。
  /// mock 数据留空。
  final String id;

  /// 会话标识（Graph `conversationId`）—— 供点开后拉取整个会话。mock 数据留空。
  final String conversationId;

  /// 发件人显示名。
  final String sender;

  /// 第二行：主题 / 正文摘要。
  final String subject;

  /// 右上角时间标签（如 `09:38`、`8/25`）。
  final String time;

  /// 未读数（头像右上角蓝色角标）；0 表示不显示。
  final int unread;

  /// 会话内邮件数（第二行右侧灰色角标）；0 表示不显示。
  final int count;

  /// 复制并覆盖部分字段（用于标记已读/未读等本地状态变更）。
  MailPreview copyWith({
    String? id,
    String? conversationId,
    String? sender,
    String? subject,
    String? time,
    int? unread,
    int? count,
  }) {
    return MailPreview(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      sender: sender ?? this.sender,
      subject: subject ?? this.subject,
      time: time ?? this.time,
      unread: unread ?? this.unread,
      count: count ?? this.count,
    );
  }
}

/// 会话详情中的单条邮件消息 —— 以联系人对话方式展示。
///
/// 约定：会话中最后一条为「最近消息」，详细展示；其余为历史消息，简化展示。
class MailMessage {
  const MailMessage({
    required this.sender,
    required this.time,
    required this.body,
    this.id = '',
    this.unread = false,
    this.recipient = '',
    this.subject = '',
    this.fullDate = '',
    this.htmlBody,
    this.isFlagged = false,
  });

  /// 发件人显示名。
  final String sender;

  /// Graph 消息 id —— 供详情页按 id 懒取全文。mock 数据留空。
  final String id;

  /// 消息时间标签（如 `8/24 15:00`）。
  final String time;

  /// 邮件正文（详细展示时完整呈现，简化展示时截断为预览；也是详情页纯文本回退）。
  final String body;

  /// 是否未读 —— 未读消息在发件人名前显示蓝点，并作为「跳转到最新未读」的目标。
  final bool unread;

  /// 收件人邮箱（详情页「收件人：」行）。
  final String recipient;

  /// 邮件主题（详情页大标题）。
  final String subject;

  /// 完整日期（详情页副标题，如 `2026年8月21日周五 21:42`）。
  final String fullDate;

  /// 富文本 HTML 正文；为 null 时详情页用 [body] 走纯文本渲染。
  final String? htmlBody;

  /// 是否已标星（Graph `flag.flagStatus == 'flagged'`）—— 详情页星标初始态。
  final bool isFlagged;

  /// 复制并覆盖部分字段 —— 主要用于懒取全文后并入 body / htmlBody。
  MailMessage copyWith({
    String? sender,
    String? id,
    String? time,
    String? body,
    bool? unread,
    String? recipient,
    String? subject,
    String? fullDate,
    String? htmlBody,
    bool? isFlagged,
  }) {
    return MailMessage(
      sender: sender ?? this.sender,
      id: id ?? this.id,
      time: time ?? this.time,
      body: body ?? this.body,
      unread: unread ?? this.unread,
      recipient: recipient ?? this.recipient,
      subject: subject ?? this.subject,
      fullDate: fullDate ?? this.fullDate,
      htmlBody: htmlBody ?? this.htmlBody,
      isFlagged: isFlagged ?? this.isFlagged,
    );
  }
}

/// 头像柔和底色候选 —— 与设计稿观感一致（紫 / 粉 / 青 / 蓝 / 橙）。
const List<Color> _kAvatarColors = [
  Color(0xFF8E7CC3),
  Color(0xFFE39FB4),
  Color(0xFF6BB2A8),
  Color(0xFF6FA8DC),
  Color(0xFFE0A458),
];

/// 依发件人名稳定地取一个头像底色（同名恒定同色）。
Color mailAvatarColor(String sender) {
  if (sender.isEmpty) return _kAvatarColors.first;
  return _kAvatarColors[sender.codeUnitAt(0) % _kAvatarColors.length];
}

/// 头像首字母 —— 取首个字符（中文取首字、英文转大写）。
String mailAvatarInitial(String sender) {
  if (sender.isEmpty) return '?';
  return sender.substring(0, 1).toUpperCase();
}
