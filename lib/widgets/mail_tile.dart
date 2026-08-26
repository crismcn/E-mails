import 'package:flutter/material.dart';

import '../models/mail.dart';
import '../theme/app_palette.dart';

/// 邮件列表项 —— 头像（带未读角标）+ 发件人/时间 + 主题/会话数角标。
class MailTile extends StatelessWidget {
  const MailTile({super.key, required this.mail, this.onTap});

  final MailPreview mail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Avatar(sender: mail.sender, unread: mail.unread),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          mail.sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        mail.time,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          mail.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (mail.count > 0) ...[
                        const SizedBox(width: 8),
                        _CountBadge(count: mail.count),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 圆形头像：柔和底色 + 首字母；未读时右上角叠加蓝色角标。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.sender, required this.unread});

  final String sender;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 50,
      height: 46,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: mailAvatarColor(sender),
              shape: BoxShape.circle,
            ),
            child: Text(
              mailAvatarInitial(sender),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (unread > 0)
            Positioned(
              top: -2,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.primary,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.background, width: 2),
                ),
                child: Text(
                  '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 第二行右侧的会话数角标 —— 灰底圆角小标签。
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: palette.divider,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: palette.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.0,
        ),
      ),
    );
  }
}
