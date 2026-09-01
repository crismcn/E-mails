import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/mail.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';

/// 账号列表项 —— 风格与邮件列表一致：圆形头像（右下角状态点）+ 邮箱/未读 + 状态·协议。
///
/// [selectionMode] 为 true 时右侧从右向左切入一个选择圈（选中为蓝色对勾），
/// 点击行由外部改为切换选中；长按 [onLongPress] 进入多选。
///
/// 选择圈的进出用显式 [AnimationController] 驱动（`SizeTransition` 让它占位/展开
/// + `SlideTransition` 从右侧滑入 + `FadeTransition` 淡入）。用显式控制器而非隐式
/// 动画：列表项按索引复用 Element，State 得以保留，切多选时能确定地播放动画。
class AccountTile extends StatefulWidget {
  const AccountTile({
    super.key,
    required this.account,
    this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  final Account account;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;

  @override
  State<AccountTile> createState() => _AccountTileState();
}

class _AccountTileState extends State<AccountTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      // 初值对齐当前态：已在多选中的项（如滚动新建）直接展开，不回放动画。
      value: widget.selectionMode ? 1 : 0,
    );
    _anim = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(AccountTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectionMode != oldWidget.selectionMode) {
      widget.selectionMode ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Avatar(
              email: widget.account.email,
              statusColor: widget.account.status.color(palette),
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
                          widget.account.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _UnreadBadge(unread: widget.account.unread),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // 有显示名时次行展示邮箱号；否则退回「状态 · 协议」
                    // （状态另有头像右下角色点表达，不至于丢失）。
                    widget.account.hasDisplayName
                        ? widget.account.email
                        : '${widget.account.status.label(l10n)} · ${widget.account.protocol.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            // 多选态：占位宽度随动画展开，同时选择圈从右侧滑入并淡入。
            SizeTransition(
              axis: Axis.horizontal,
              alignment: Alignment.centerRight,
              sizeFactor: _anim,
              child: FadeTransition(
                opacity: _anim,
                child: SlideTransition(
                  position: _anim.drive(
                    Tween<Offset>(
                      begin: const Offset(0.8, 0),
                      end: Offset.zero,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: _SelectCircle(selected: widget.selected),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选择圈 —— 未选为浅灰描边空心圆，选中为主色实心圆 + 白色对勾。
class _SelectCircle extends StatelessWidget {
  const _SelectCircle({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? palette.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: selected
            ? null
            : Border.all(color: palette.textSecondary, width: 1.5),
      ),
      child: selected
          ? const Icon(
              AppIcons.check,
              color: Colors.white,
              size: 16,
              fontWeight: FontWeight.w700,
            )
          : null,
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
                fontSize: 20,
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
          style: TextStyle(color: palette.textSecondary, fontSize: 12),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: hasUnread ? palette.primary : palette.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
