import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../theme/app_palette.dart';

/// 账号列表项。
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
          children: [
            // 状态指示点
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: account.status.color(palette),
                shape: BoxShape.circle,
              ),
            ),
            // 邮箱 + 状态描述
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.email,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${account.status.label(l10n)} · ${account.protocol.label}',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // 未读数
            _UnreadBadge(unread: account.unread),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: palette.textSecondary,
              size: 20,
            ),
          ],
        ),
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
