import 'package:flutter/material.dart';

/// 单条邮件（会话）预览 —— 对应邮件列表中的一行。
class MailPreview {
  const MailPreview({
    required this.sender,
    required this.subject,
    required this.time,
    this.unread = 0,
    this.count = 0,
  });

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
    String? sender,
    String? subject,
    String? time,
    int? unread,
    int? count,
  }) {
    return MailPreview(
      sender: sender ?? this.sender,
      subject: subject ?? this.subject,
      time: time ?? this.time,
      unread: unread ?? this.unread,
      count: count ?? this.count,
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
