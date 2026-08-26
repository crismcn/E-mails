import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/cupertino.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_palette.dart';

/// 应用统一的下拉刷新头 —— 竖向居中：CupertinoActivityIndicator +「上次更新时间」。
///
/// 首页与邮件列表共用，保持一致风格。用 [ClipRect] 裁剪，
/// 收起（offset≈0）时不占位、不遮挡内容。
Header appRefreshHeader(DateTime lastUpdated) {
  return BuilderHeader(
    triggerOffset: 90,
    clamping: false,
    position: IndicatorPosition.above,
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
Footer appLoadFooter() {
  return BuilderFooter(
    triggerOffset: 70,
    clamping: false,
    position: IndicatorPosition.above,
    processedDuration: const Duration(milliseconds: 300),
    builder: (context, state) => _AppLoadFooterView(state: state),
  );
}

class _AppLoadFooterView extends StatelessWidget {
  const _AppLoadFooterView({required this.state});

  final IndicatorState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    final noMore = state.result == IndicatorResult.noMore;
    final loading = state.mode == IndicatorMode.processing ||
        state.mode == IndicatorMode.ready ||
        state.mode == IndicatorMode.armed;
    final text = noMore
        ? l10n.loadMoreNoMore
        : loading
            ? l10n.loadMoreLoading
            : l10n.loadMore;
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
