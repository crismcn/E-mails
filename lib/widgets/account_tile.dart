import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/mail.dart';
import '../theme/app_palette.dart';

/// 账号列表项 —— 风格与邮件列表一致：圆形头像（右下角状态点）+ 邮箱/未读 + 状态·协议。
class AccountTile extends StatelessWidget {
  const AccountTile({super.key, required this.account, this.onTap});

  final Account account;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Avatar(
              email: account.email,
              statusColor: account.status.color(palette),
            ),
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
                          account.email,
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
                      _UnreadBadge(unread: account.unread),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${account.status.label(l10n)} · ${account.protocol.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 15,
                    ),
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

/// 圆形头像：柔和底色 + 首字母；右下角叠加状态点（有效/异常随主题描边）。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.email, required this.statusColor});

  final String email;
  final Color statusColor;

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
              color: mailAvatarColor(email),
              shape: BoxShape.circle,
            ),
            child: Text(
              mailAvatarInitial(email),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 0,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                border: Border.all(color: palette.background, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.unread});

  final int? unread;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    final bool hasUnread = unread != null && unread! > 0;
    final String text = unread == null ? '–' : '$unread';
    return Row(
      children: [
        Text(
          l10n.unread,
          style: TextStyle(color: palette.textSecondary, fontSize: 13),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: hasUnread ? palette.primary : palette.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
