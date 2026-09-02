import 'dart:async' show Timer;
import 'dart:math' show max, min;

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../data/mail_html_document.dart';
import '../theme/app_palette.dart';

/// 邮件 HTML 正文 —— 交给系统 WebView 渲染（iOS 用 WKWebView，Android 用 WebView）。
///
/// **按页内量到的渲染高度占位、自己不滚**：排在详情页那一条滚动条里，收件人 / 主题 /
/// 日期 / 附件 / 正文一起上滑。
///
/// **盒子高度有上限**（[_kMaxTexturePhysical] 物理像素 ÷ devicePixelRatio）。Android 的
/// 平台视图走纹理合成（`initSurfaceAndroidView`）：WebView 被画进一张**按控件尺寸开的
/// 纹理**，受 `GL_MAX_TEXTURE_SIZE` 约束。越界后纹理被 clamp 再拉伸铺满 → **画面变形**，
/// 缩放时每帧重绘巨型表面 → **整机卡死**。开 Hybrid Composition 能绕开尺寸限制，但
/// 实测**滚动明显卡顿**（它会让叠在平台视图上的内容走 `FlutterImageView` 覆盖层），
/// 已改回默认的纹理合成 + 高度上限。
///
/// **缩放绝不改盒子高度**：曾按 `visualViewport.scale` 重新定高（想让放大后的下半截靠
/// 页面滚动看完），缩放比能到 10、盒子被撑成几万逻辑像素 → **一放大就闪退**。
///
/// **单指拖动归谁，按「WebView 内部还能不能滚」定**（页内脚本回报的布尔量）：
/// - 能内滚（双指放大后可视视口变小 / 邮件超过高度上限被截）→ 单指归 WebView，
///   在里面滚，够得着被遮住的内容；
/// - 不能内滚（常态：盒子正好等于内容高度）→ 单指归外层滚动视图，整页一起上滑。
///
/// 双指**永远**归 WebView（缩放 + 平移）。单指点击靠手势竞技场清算落到平台视图，
/// 链接照样点得动。见 [_MultiTouchGestureRecognizer]。
///
/// **加载期间盖一层 App 底色的遮罩**：WebView 在 CSS 生效前会画自己的默认白底，暗色
/// 主题下就是一下白闪。遮罩从第一帧就盖住，等「文档加载完 + 量到高度」再淡出。
/// 遮罩期间盒子**至少占满 [viewportHeight]**，也顺手免掉「先给一段短占位、量到高度
/// 再跳一次」。
///
/// **转圈不由本组件画**：遮罩只是一层底色，转圈由详情页浮在内容区正中 —— 从「懒取
/// 全文」到「正文可见」全程是同一个转圈，见 [onCoverChanged]。
class MailHtmlView extends StatefulWidget {
  const MailHtmlView({
    super.key,
    required this.html,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.onTapUrl,
    this.onCoverChanged,
  });

  /// 邮件正文 HTML（发件人给的原文，包装与消毒在 [buildMailHtmlDocument] 里做）。
  final String html;

  /// 可用宽度（逻辑像素）—— 判断这封邮件是否需要整体缩放适配屏宽。
  final double viewportWidth;

  /// 内容区的可见高度（逻辑像素）—— **只**用于加载遮罩期的占位高度。不参与排版
  /// 缩放，变了也不重载文档（键盘弹起 / 旋屏不该让正文重来一遍）。
  final double viewportHeight;

  /// 点链接 —— 交给外部浏览器打开，WebView 自己不导航。
  final Future<bool> Function(String url) onTapUrl;

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

  /// 遮罩最多盖这么久 —— 量高三条路全失败、或远程图片把 `onPageFinished` 吊着不放时
  /// 的兜底，绝不能把正文永远盖着。
  static const Duration _kRevealDeadline = Duration(milliseconds: 1500);

  /// 平台视图纹理的安全边（**物理**像素）。Android 的 `GL_MAX_TEXTURE_SIZE` 拿不到，
  /// 取一个几乎所有在跑 Flutter 的机型都能满足的值；盒子高度按它 ÷ dpr 夹住。
  /// 夹住之后那封邮件在 WebView 内部还能滚（见类注释的单指归属规则），不会被截断。
  static const double _kMaxTexturePhysical = 8192;

  /// 每份文档一枚随机 nonce，且**在 State 里生成**：放进 build 会每次重建都换文档、
  /// 触发无意义的重新加载。
  final String _nonce = mailHtmlNonce();

  /// 加载遮罩的不透明度：1 = 完全盖住（加载中），0 = 已露出正文。
  late final AnimationController _cover = AnimationController(
    vsync: this,
    value: 1,
    duration: MailHtmlView.kRevealDuration,
  );

  /// 兜底淡出的定时器（见 [_kRevealDeadline]）。
  Timer? _revealTimer;

  bool _revealed = false;
  bool _revealScheduled = false;
  bool _pageFinished = false;

  /// 遮罩是否已经**彻底淡完** —— 到这时才把盒子交回实测高度。
  ///
  /// 刻意不用「开始淡出」：短邮件的实测高度可能比一屏还矮，在淡出**期间**收盒子会让
  /// WebView 的视口跟着变小、文档重排 —— 那一下正好透过半透明的遮罩被看见。
  bool _coverGone = false;

  /// 手势识别器只建一份 —— 每帧换新的 `Set` 会让平台视图反复重挂。
  late final Set<Factory<OneSequenceGestureRecognizer>> _gestures =
      <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(
          () => _MultiTouchGestureRecognizer(
            claimSingleTouch: () => _canScrollInside,
          ),
        ),
      };

  WebViewController? _controller;
  MailHtmlDocument? _document;

  /// 页内量到的正文高度（已按 [MailHtmlDocument.layoutScale] 折算并夹上上限）。
  double? _height;

  /// WebView 内部当前还有没有纵向可滚距离（放大后 / 超上限被夹时为真）。
  ///
  /// **刻意不放进 `setState`**：它每次双指平移都可能翻转，只被手势识别器读，
  /// 不影响任何绘制 —— 重建界面会把 WebView 也带着重排。
  bool _canScrollInside = false;

  bool _dark = false;

  @override
  void initState() {
    super.initState();
    // 淡完了才把盒子交回实测高度（见 [_coverGone]）。
    _cover.addStatusListener((status) {
      if (status != AnimationStatus.dismissed || _coverGone) return;
      setState(() => _coverGone = true);
    });
  }

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
        widget.viewportWidth != oldWidget.viewportWidth) {
      _load(context.palette);
    }
  }

  /// 建 / 重建 WebView 并载入文档。
  ///
  /// 两个调用点（`didChangeDependencies` / `didUpdateWidget`）之后框架都会紧接着
  /// 重建，故这里只改字段、不 `setState`。
  void _load(AppPalette palette) {
    // 测试环境没有注册平台视图 —— 不建 WebView，走下面的降级分支。
    if (WebViewPlatform.instance == null) {
      _document = _build(palette);
      // 没有 WebView 就没有遮罩，宿主的转圈不能一直挂着。
      _notifyCover(false);
      return;
    }
    final document = _build(palette);
    final controller = _controller ?? WebViewController();
    if (_controller == null) {
      _configurePlatform(controller);
      controller
        // 量高度的脚本要跑，故引擎层允许 JS；邮件自带的脚本由文档里的 CSP
        // （`script-src 'nonce-…'`）与正则删除双重挡住。
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..enableZoom(true)
        ..addJavaScriptChannel(
          kMailMetricsChannel,
          onMessageReceived: _onMetrics,
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: _onNavigation,
            onPageFinished: (_) => _onPageFinished(),
          ),
        );
      // 滚动条不画（用户要求）—— 盒子等于内容高度时本来也不该出现，但放大之后
      // WebView 内部就有可滚动距离了，那两条原生滚动条会冒出来。
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
    _height = null;
    _canScrollInside = false;
    // 重新盖上遮罩：换主题会重载文档，反色前的白底同样会闪一下。
    _pageFinished = false;
    _revealed = false;
    _revealScheduled = false;
    _coverGone = false;
    _cover.value = 1;
    _revealTimer?.cancel();
    _revealTimer = Timer(_kRevealDeadline, _reveal);
    _notifyCover(true);
  }

  /// 把遮罩的起落告诉宿主（详情页据此显示 / 淡出那个转圈）。
  ///
  /// **排到帧末**：两个调用点之一是 `didChangeDependencies`（换主题重载），此刻宿主
  /// 正在构建，直接回调会撞上「setState() called during build」。
  void _notifyCover(bool covered) {
    final notify = widget.onCoverChanged;
    if (notify == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) notify(covered);
    });
  }

  /// 文档加载完 —— 宿主侧补量一次高度，并看看够不够条件让遮罩淡出。
  void _onPageFinished() {
    _pageFinished = true;
    _measureFromHost();
    _maybeReveal();
  }

  /// 「文档加载完 + 已经量到高度」才排淡出：此时看到的就是最终版式，不会先给一眼
  /// 占位高度再跳一次。再压 [_kRevealSettle] 等首帧上纹理。
  ///
  /// 只排一次 —— 图片是陆续到的，每次高度增长都重排会把淡出一直推到兜底时间。
  void _maybeReveal() {
    if (_revealScheduled || !_pageFinished || _height == null) return;
    _revealScheduled = true;
    _revealTimer?.cancel();
    _revealTimer = Timer(_kRevealSettle, _reveal);
  }

  /// 遮罩淡出，只做一次。
  ///
  /// 盒子交回实测高度是在**淡完之后**（[_coverGone] 的状态监听里），不在这里 ——
  /// 淡出期间收盒子会让 WebView 视口变小、文档重排，正好被看见。
  void _reveal() {
    if (!mounted || _revealed) return;
    _revealTimer?.cancel();
    _revealed = true;
    _cover.reverse();
    // 宿主那个转圈跟着一起淡出（同一时长）。
    _notifyCover(false);
  }

  /// Android WebView 默认 `useWideViewPort = false`，会**忽略** `viewport` meta ——
  /// 写死 600px 的邮件于是按屏宽排版、横向溢出，而我们又按声明宽度算了缩放比，
  /// 结果高度算少、长邮件被截断。打开它，行为才和 WKWebView 一致。
  void _configurePlatform(WebViewController controller) {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setUseWideViewPort(true);
    }
  }

  MailHtmlDocument _build(AppPalette palette) => buildMailHtmlDocument(
    widget.html,
    nonce: _nonce,
    viewportWidth: widget.viewportWidth,
    dark: _dark,
    backgroundHex: _hex(palette.background),
  );
  void _onMetrics(JavaScriptMessage message) => _applyMetrics(message.message);

  /// 从宿主侧再量一次 —— 页内那段脚本是主路径（能跟上图片后到导致的变高），
  /// 这条是兜底：万一 CSP / 注入时机让它没跑起来，正文也不会卡在占位高度。
  /// 图片是陆续到的，故隔几拍各量一次。
  Future<void> _measureFromHost() async {
    for (final delay in const [0, 300, 900, 2000]) {
      if (delay > 0) await Future<void>.delayed(Duration(milliseconds: delay));
      final controller = _controller;
      if (!mounted || controller == null) return;
      try {
        final result = await controller.runJavaScriptReturningResult(
          // 直接调页内那个量法，两条路径不会算出不同的高度。
          'window.$kMailMetricsProbe?window.$kMailMetricsProbe():""',
        );
        _applyMetrics(result.toString());
      } catch (_) {
        // 量不到就维持现有高度，不打扰用户。
        return;
      }
    }
  }

  /// 收下页内回报的 `"高度,能否内部滚动"`。
  ///
  /// 高度**只涨不缩**（多量几路本就为了不截断，来回缩会让页面抖）并夹上纹理上限；
  /// 「能否内部滚动」只写字段、不 `setState`。
  void _applyMetrics(String raw) {
    if (!mounted) return;
    final parts = raw.replaceAll('"', '').split(',');
    final measured = double.tryParse(parts.first.trim());
    if (parts.length > 1) _canScrollInside = parts[1].trim() == '1';
    if (measured == null || measured <= 0) return;

    final scaled = measured * (_document?.layoutScale ?? 1);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final height = min(scaled, _kMaxTexturePhysical / (ratio <= 0 ? 1 : ratio));
    if (_height != null && height <= _height! + 1) return;
    setState(() => _height = height);
    _maybeReveal();
  }

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
    // 遮罩还盖着时盒子至少占满内容区：量到高度前不必先给一段短占位，省掉一次版式
    // 跳动。**淡完**（不是开始淡）才回到实测高度，见 [_coverGone]（量不到高度时
    // 退回一屏高，比一段短占位更不容易截断）。
    final measured = _height;
    final height = _coverGone
        ? (measured ?? widget.viewportHeight)
        : max(measured ?? 0, widget.viewportHeight);
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          // 用默认的纹理合成（不开 Hybrid Composition）—— HC 能绕开纹理尺寸限制，
          // 但实测滚动明显卡顿；改成默认合成 + 高度上限。
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

/// 决定单指拖动归 WebView 还是归外层滚动视图的识别器。
///
/// - [claimSingleTouch] 为真（WebView 内部还有可滚距离：放大后 / 邮件超高被夹）→
///   第一根手指落下即认领，单指在 WebView 里滚；
/// - 为假（常态：盒子正好装下内容）→ 单指只「跟踪」不认领，留给外层页面滚动视图；
/// - **第二根手指**落下一律认领 —— 双指永远是缩放 + 平移。
///
/// 不认领时抬手由竞技场清算，平台视图照样收到那一串事件，链接点得动。
class _MultiTouchGestureRecognizer extends OneSequenceGestureRecognizer {
  _MultiTouchGestureRecognizer({required this.claimSingleTouch});

  /// 当下单指是否也该归 WebView —— 每次手指落下现问一遍。
  final bool Function() claimSingleTouch;

  int _pointers = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _pointers++;
    if (_pointers >= 2 || claimSingleTouch()) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
      if (_pointers > 0) _pointers--;
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) => _pointers = 0;

  @override
  String get debugDescription => 'mail html multi-touch';
}

/// 平台视图不可用时的降级占位（实际只有 widget 测试会走到 —— 两个目标平台的
/// WebView 插件都是启动即注册）。挂着生成好的文档，便于断言包装与消毒结果。
class MailHtmlUnavailable extends StatelessWidget {
  const MailHtmlUnavailable({super.key, required this.document});

  final MailHtmlDocument? document;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
