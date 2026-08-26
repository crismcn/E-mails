import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/cupertino.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_palette.dart';

/// 应用统一的下拉刷新头 —— 竖向居中：CupertinoActivityIndicator +「上次更新时间」。
///
/// 首页与邮件列表共用，保持一致风格。用 [ClipRect] 裁剪，
/// 收起（offset≈0）时不占位、不遮挡内容。
///
/// [position] 默认浮于内容之上；当滚动视图含固定吸顶头部时改用
/// [IndicatorPosition.locator]，配合 `HeaderLocator.sliver()` 把指示器
/// 放到吸顶区下方，避免被吸顶头部盖住。
Header appRefreshHeader(
  DateTime lastUpdated, {
  IndicatorPosition position = IndicatorPosition.above,
}) {
  return BuilderHeader(
    triggerOffset: 90,
    clamping: false,
    position: position,
    processedDuration: const Duration(milliseconds: 300),
    builder: (context, state) =>
        _AppRefreshHeaderView(state: state, lastUpdated: lastUpdated),
  );
}

class _AppRefreshHeaderView extends StatelessWidget {
  const _AppRefreshHeaderView({required this.state, required this.lastUpdated});

  final IndicatorState state;
  final DateTime lastUpdated;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    // 收起时整体不入树：避免 CupertinoActivityIndicator 常驻空转。
    if (state.offset <= 0) return const SizedBox.shrink();
    String two(int v) => v.toString().padLeft(2, '0');
    final timeText = '${two(lastUpdated.hour)}:${two(lastUpdated.minute)}';
    return ClipRect(
      child: SizedBox(
        height: state.offset,
        width: double.infinity,
        child: OverflowBox(
          minHeight: 0,
          maxHeight: double.infinity,
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoActivityIndicator(
                  radius: 13,
                  color: palette.textSecondary,
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.refreshLastUpdated(timeText),
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 应用统一的上滑加载更多页脚 —— 居中：转圈 + 文案（无更多时仅文案）。
///
/// 首页与邮件列表共用，保持一致风格。用 [ClipRect] 裁剪，收起时不占位。
/// [position] 含义同 [appRefreshHeader]（locator 时配合 `FooterLocator.sliver()`）。
Footer appLoadFooter({IndicatorPosition position = IndicatorPosition.above}) {
  return BuilderFooter(
    triggerOffset: 70,
    clamping: false,
    position: position,
    processedDuration: const Duration(milliseconds: 300),
    builder: (context, state) => _LoadIndicatorView(
      state: state,
      idleText: (l10n) => l10n.loadMore,
      noMoreText: (l10n) => l10n.loadMoreNoMore,
    ),
  );
}

/// 会话页「下拉加载更多历史邮件」头部 —— 与 [appLoadFooter] 同一套视觉。
///
/// 会话按时间正序排列（越早的在上），因此加载更早的消息靠顶部下拉触发，
/// 但指示器样式与邮件列表的上滑加载更多保持一致。
Header appHistoryHeader() {
  return BuilderHeader(
    triggerOffset: 70,
    clamping: false,
    position: IndicatorPosition.above,
    processedDuration: const Duration(milliseconds: 300),
    builder: (context, state) => _LoadIndicatorView(
      state: state,
      idleText: (l10n) => l10n.threadLoadHistory,
      noMoreText: (l10n) => l10n.threadLoadHistoryNoMore,
    ),
  );
}

/// 依当前语言取指示器文案。
typedef _IndicatorText = String Function(AppLocalizations l10n);

/// 加载指示器视图 —— 页脚（上滑）与会话历史头部（下拉）共用。
class _LoadIndicatorView extends StatelessWidget {
  const _LoadIndicatorView({
    required this.state,
    required this.idleText,
    required this.noMoreText,
  });

  final IndicatorState state;
  final _IndicatorText idleText;
  final _IndicatorText noMoreText;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    // 收起时整体不入树：避免 CupertinoActivityIndicator 常驻空转。
    if (state.offset <= 0) return const SizedBox.shrink();
    final noMore = state.result == IndicatorResult.noMore;
    final loading =
        state.mode == IndicatorMode.processing ||
        state.mode == IndicatorMode.ready ||
        state.mode == IndicatorMode.armed;
    final text = noMore
        ? noMoreText(l10n)
        : loading
        ? l10n.loadMoreLoading
        : idleText(l10n);
    return ClipRect(
      child: SizedBox(
        height: state.offset,
        width: double.infinity,
        child: OverflowBox(
          minHeight: 0,
          maxHeight: double.infinity,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading) ...[
                CupertinoActivityIndicator(
                  radius: 9,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                text,
                style: TextStyle(color: palette.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
