import 'dart:async' show Timer;

import 'package:flutter/foundation.dart' show Factory, kDebugMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../data/mail_html_document.dart';
import '../theme/app_palette.dart';

/// 调试开关：把正文滚动偏移逐条打到控制台（只在 `kDebugMode` 下有效）。
///
/// 排查顶 / 底栏收放时很有用（能直接看出平台回报的单位对不对），但一次滚动会刷几十行，
/// 嫌吵就把它改成 `false`。
const bool kLogMailScroll = true;

/// 邮件 HTML 正文 —— 交给系统 WebView 渲染（iOS 用 WKWebView，Android 用 WebView）。
///
/// **恒定铺满真实全屏，自己滚动 + 双指缩放**：详情页把它 `Positioned.fill` 铺在最底层
/// （含状态栏与底部安全区），顶栏 / 元信息 / 底栏都是浮在它上面的层。WebView 从头到尾
/// 不移动、不改尺寸 —— 视觉上的「整体上移」由正文滚动 [topPadding] 那段内边距实现，
/// 平台视图既不重排也不重建纹理，历史上的「展示不全」在结构上不可能发生。
///
/// **加载期间盖一层 App 底色的遮罩**：WebView 在文档 CSS 生效前会画自己的默认白底，暗色
/// 主题下就是一下白闪。遮罩从第一帧就盖住，等 `onPageFinished` 再淡出。
///
/// **转圈不由本组件画**：遮罩只是一层底色，转圈由详情页浮在内容区正中 —— 从「懒取
/// 全文」到「正文可见」全程是同一个转圈，见 [onCoverChanged]。
class MailHtmlView extends StatefulWidget {
  const MailHtmlView({
    super.key,
    required this.html,
    required this.viewportWidth,
    required this.onTapUrl,
    this.topPadding = 0,
    this.bottomPadding = 0,
    this.onScroll,
    this.onCoverChanged,
  });

  /// 邮件正文 HTML（发件人给的原文，包装与消毒在 [buildMailHtmlDocument] 里做）。
  final String html;

  /// 可用宽度（逻辑像素）—— 判断这封邮件是否需要整体缩放适配屏宽。
  final double viewportWidth;

  /// 点链接 —— 交给外部浏览器打开，WebView 自己不导航。
  final Future<bool> Function(String url) onTapUrl;

  /// 正文起头前 / 收尾后留出的空白（逻辑像素）—— 给浮在 WebView 上的顶栏 + 元信息
  /// 与底部操作栏让位。**写进文档的 CSS，不是 Flutter 侧的 padding**：WebView 恒定
  /// 铺满整屏，「整体上移」由正文自己滚动这段内边距实现，平台视图一次都不用动。
  final double topPadding;
  final double bottomPadding;

  /// 正文内部滚动位置（已折算为逻辑像素，不含 layoutScale 影响）—— 详情页据此驱动
  /// 顶/底栏收放。缩放期间（≥2 指触控）不回报，免收放正反馈。
  final ValueChanged<double>? onScroll;

  /// 遮罩起落（`true` = 刚盖上，`false` = 开始淡出）—— 宿主据此决定要不要显示转圈。
  ///
  /// 转圈刻意交给宿主画：详情页从「懒取全文」到「正文可见」是**一个**等待过程，
  /// 两段各画一个的话交接处会空一两帧（Android 上平台视图首帧还要几十毫秒），
  /// 看着就是**闪一下**。淡出时长与 [kRevealDuration] 一致，宿主的转圈跟着一起淡。
  final ValueChanged<bool>? onCoverChanged;

  /// 遮罩淡出时长 —— 宿主的转圈用同一个值，两者同步淡出。
  static const Duration kRevealDuration = Duration(milliseconds: 240);

  @override
  State<MailHtmlView> createState() => _MailHtmlViewState();
}

class _MailHtmlViewState extends State<MailHtmlView>
    with SingleTickerProviderStateMixin {
  /// 条件满足后再多盖这么久 —— `onPageFinished` 只说明文档加载完，WebView 把带样式
  /// （暗色下还带反色滤镜）的首帧真正合成到纹理上还要一两帧。早淡出就是一下闪动。
  static const Duration _kRevealSettle = Duration(milliseconds: 140);

  /// 遮罩最多盖这么久 —— 远程图片把 `onPageFinished` 吊着不放时的兜底。
  static const Duration _kRevealDeadline = Duration(milliseconds: 1500);

  /// 手势识别器只建一份 —— 每帧换新的 `Set` 会让平台视图反复重挂。
  late final Set<Factory<OneSequenceGestureRecognizer>> _gestures =
      <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(
          () => EagerGestureRecognizer(),
        ),
      };

  WebViewController? _controller;
  MailHtmlDocument? _document;

  bool _dark = false;

  /// 加载遮罩的不透明度：1 = 完全盖住（加载中），0 = 已露出正文。
  late final AnimationController _cover = AnimationController(
    vsync: this,
    value: 1,
    duration: MailHtmlView.kRevealDuration,
  );

  /// 兜底淡出的定时器（见 [_kRevealDeadline]）。
  Timer? _revealTimer;
  bool _revealed = false;

  /// 触控手指数 —— ≥2 时不回报滚动（避免缩放抖动驱动收放）。
  int _pointers = 0;

  /// 这个 WebView 的滚动回报是不是 Android 那套单位（见 [_scrollUnit]）。
  bool _androidScroll = false;

  /// 把 WebView 回报的滚动偏移换成**逻辑像素**的系数。
  ///
  /// **两个平台的单位不同，而且都不是 CSS 像素**（插件源码为证）：
  /// - Android：`WebView.onScrollChanged` 转手的是 `View.getScrollY()`，**设备像素**
  ///   （已含页面缩放）→ 要除以 `devicePixelRatio`；
  /// - iOS：`scrollView.contentOffset.y`，**point** = 逻辑像素（已含 `zoomScale`）→ 原样。
  ///
  /// 两者都是「视图空间」里的量，故**不能再乘 [MailHtmlDocument.layoutScale]**
  /// （那是 CSS → 屏幕的比例，只用来反算文档里的占位高度）。曾经乘过：Android 上
  /// 回报值本就是设备像素，再乘 0.6 后偏移被高估约 dpr/scale 倍，顶 / 底栏提前跑完。
  double get _scrollUnit =>
      _androidScroll ? 1 / View.of(context).devicePixelRatio : 1;

  @override
  void dispose() {
    _revealTimer?.cancel();
    _cover.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.palette;
    if (_controller != null && dark == _dark) return;
    _dark = dark;
    _load(palette);
  }

  @override
  void didUpdateWidget(MailHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.html != oldWidget.html ||
        widget.viewportWidth != oldWidget.viewportWidth ||
        widget.topPadding != oldWidget.topPadding ||
        widget.bottomPadding != oldWidget.bottomPadding) {
      _load(context.palette);
    }
  }

  /// 建 / 重建 WebView 并载入文档。
  void _load(AppPalette palette) {
    // 测试环境没有注册平台视图 —— 不建 WebView，走下面的降级分支。
    if (WebViewPlatform.instance == null) {
      _document = _build(palette);
      _notifyCover(false);
      return;
    }
    final document = _build(palette);
    final controller = _controller ?? WebViewController();
    if (_controller == null) {
      _configurePlatform(controller);
      controller
        // 邮件自带的脚本由文档里的 CSP `script-src 'none'` 与正则删除双重挡住。
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..enableZoom(true)
        ..setOnScrollPositionChange(_onScrollPosition)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: _onNavigation,
            onPageFinished: (_) => _onPageFinished(),
          ),
        );
      // 滚动条不画（用户要求）。
      if (controller.platform.supportsSetScrollBarsEnabled()) {
        controller
          ..setVerticalScrollBarEnabled(false)
          ..setHorizontalScrollBarEnabled(false);
      }
    }
    // 加载前先垫上底色，免得白页一闪。
    controller.setBackgroundColor(palette.background);
    controller.loadHtmlString(document.html);
    _controller = controller;
    _document = document;
    if (kDebugMode) {
      debugPrint(
        '[MailHtmlView] load viewport=${widget.viewportWidth.toStringAsFixed(1)} '
        'layoutScale=${document.layoutScale.toStringAsFixed(3)} '
        'topPad=${widget.topPadding.toStringAsFixed(1)} '
        'bottomPad=${widget.bottomPadding.toStringAsFixed(1)} '
        '→ cssTopPad=${(widget.topPadding / document.layoutScale).toStringAsFixed(1)}',
      );
    }
    // 重新盖上遮罩：换主题会重载文档，反色前的白底同样会闪一下。
    _revealed = false;
    _cover.value = 1;
    _revealTimer?.cancel();
    _revealTimer = Timer(_kRevealDeadline, _reveal);
    _notifyCover(true);
  }

  /// WebView 内部滚动回报 —— 折算为逻辑像素后交给页面（缩放期间不报）。
  void _onScrollPosition(ScrollPositionChange change) {
    // 平台回调可能在 dispose 之后还来一发，`_scrollUnit` 要读 context。
    if (!mounted || _pointers >= 2) return;
    final y = change.y * _scrollUnit;
    if (kDebugMode && kLogMailScroll) {
      debugPrint(
        '[MailHtmlView] scroll raw=${change.y.toStringAsFixed(1)} '
        '→ logical=${y.toStringAsFixed(1)}',
      );
    }
    widget.onScroll?.call(y);
  }

  void _onPageFinished() {
    _revealTimer?.cancel();
    _revealTimer = Timer(_kRevealSettle, _reveal);
  }

  /// 遮罩淡出，只做一次。
  void _reveal() {
    if (!mounted || _revealed) return;
    _revealTimer?.cancel();
    _revealed = true;
    _cover.reverse();
    _notifyCover(false);
  }

  /// 把遮罩的起落告诉宿主（详情页据此显示 / 淡出那个转圈）。
  ///
  /// **排到帧末**：调用点是 `didChangeDependencies`（换主题重载），此刻宿主正在构建，
  /// 直接回调会撞上「setState() called during build」。
  void _notifyCover(bool covered) {
    final notify = widget.onCoverChanged;
    if (notify == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) notify(covered);
    });
  }

  /// Android WebView 默认 `useWideViewPort = false`，会**忽略** `viewport` meta ——
  /// 写死 600px 的邮件于是按屏宽排版、横向溢出。打开它，行为才和 WKWebView 一致。
  void _configurePlatform(WebViewController controller) {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setUseWideViewPort(true);
      // 滚动回报的单位跟着平台走，见 [_scrollUnit]。
      _androidScroll = true;
    }
  }

  MailHtmlDocument _build(AppPalette palette) => buildMailHtmlDocument(
    widget.html,
    viewportWidth: widget.viewportWidth,
    dark: _dark,
    backgroundHex: _hex(palette.background),
    topPadding: widget.topPadding,
    bottomPadding: widget.bottomPadding,
  );

  /// WebView 自己只加载我们塞进去的那份文档（`about:blank`）；其余一律不导航，
  /// 链接改由外部浏览器打开 —— 顺手挡掉 `javascript:` 之类的协议。
  NavigationDecision _onNavigation(NavigationRequest request) {
    final url = request.url;
    if (url == 'about:blank' || url.startsWith('data:')) {
      return NavigationDecision.navigate;
    }
    if (isSafeMailLink(url)) widget.onTapUrl(url);
    return NavigationDecision.prevent;
  }

  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final document = _document;
    if (controller == null) {
      return MailHtmlUnavailable(document: document);
    }
    final palette = context.palette;
    return Listener(
      onPointerDown: (_) => _pointers++,
      onPointerUp: (_) {
        if (_pointers > 0) _pointers--;
      },
      onPointerCancel: (_) {
        if (_pointers > 0) _pointers--;
      },
      child: Stack(
        children: [
          // 有界 WebView：填满可用空间，内部滚动 + 双指缩放。
          // 用默认的纹理合成（不开 Hybrid Composition）。
          WebViewWidget(controller: controller, gestureRecognizers: _gestures),
          // 加载遮罩 —— 只是一层 App 底色。**淡出的是这层 Flutter 覆盖层，不是
          // WebView 自己的 `opacity`**：平台视图的透明度在 iOS 上不保证生效
          // （embedder 只稳定支持裁剪与变换），盖一层两端都靠得住。
          //
          // 转圈不在这里画 —— 详情页从懒取到正文可见全程用同一个，见
          // [MailHtmlView.onCoverChanged]。
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _cover,
                builder: (context, _) => _cover.isDismissed
                    ? const SizedBox.shrink()
                    : FadeTransition(
                        opacity: _cover,
                        child: ColoredBox(color: palette.background),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 平台视图不可用时的降级占位（实际只有 widget 测试会走到 —— 两个目标平台的
/// WebView 插件都是启动即注册）。挂着生成好的文档，便于断言包装与消毒结果。
class MailHtmlUnavailable extends StatelessWidget {
  const MailHtmlUnavailable({super.key, required this.document});

  final MailHtmlDocument? document;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}