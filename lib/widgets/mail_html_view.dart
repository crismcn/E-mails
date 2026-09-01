import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../data/mail_html_document.dart';
import '../theme/app_palette.dart';

/// 邮件 HTML 正文 —— 交给系统 WebView 渲染（iOS 用 WKWebView，Android 用 WebView）。
///
/// 排在外层页面的滚动视图里，所以**自己不滚动**：由页内脚本量出正文高度回报过来，
/// 组件按这个高度占位，页面用一条滚动条把「收件人 / 主题 / 附件 / 正文」一起滚。
///
/// 双指缩放开着。放大后是在这块高度固定的区域里平移查看（区域高度按 1 倍算），
/// 不会把外层页面撑长。
class MailHtmlView extends StatefulWidget {
  const MailHtmlView({
    super.key,
    required this.html,
    required this.viewportWidth,
    required this.onTapUrl,
  });

  /// 邮件正文 HTML（发件人给的原文，包装与消毒在 [buildMailHtmlDocument] 里做）。
  final String html;

  /// 可用宽度（逻辑像素）—— 判断这封邮件是否需要整体缩放。
  final double viewportWidth;

  /// 点链接 —— 交给外部浏览器打开，WebView 自己不导航。
  final Future<bool> Function(String url) onTapUrl;

  @override
  State<MailHtmlView> createState() => _MailHtmlViewState();
}

class _MailHtmlViewState extends State<MailHtmlView> {
  /// 首帧的占位高度 —— 平台视图给 0 高度可能不初始化，先给一段再按实测替换。
  static const double _kInitialHeight = 160;

  /// 每份文档一枚随机 nonce，且**在 State 里生成**：放进 build 会每次重建都换文档、
  /// 触发无意义的重新加载。
  final String _nonce = mailHtmlNonce();

  WebViewController? _controller;
  MailHtmlDocument? _document;

  /// 页内量到的正文高度（已按 [MailHtmlDocument.layoutScale] 折算成占屏高度）。
  double? _height;

  bool _dark = false;

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
      return;
    }
    final document = _build(palette);
    final controller = _controller ?? WebViewController();
    if (_controller == null) {
      _configurePlatform(controller);
      controller
        // 量高度的脚本要跑，故引擎层允许 JS；邮件自带的脚本由文档里的 CSP 挡住。
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..enableZoom(true)
        ..addJavaScriptChannel(
          kMailHeightChannel,
          onMessageReceived: _onHeight,
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: _onNavigation,
            onPageFinished: (_) => _measureFromHost(),
          ),
        );
    }
    // 加载前先垫上底色，免得白页一闪。
    controller.setBackgroundColor(palette.background);
    controller.loadHtmlString(document.html);
    _controller = controller;
    _document = document;
    _height = null;
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

  void _onHeight(JavaScriptMessage message) =>
      _applyHeight(double.tryParse(message.message));

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
          // 与页内脚本同一套量法：取几种量法的最大值，少量一种就会截断长邮件。
          '(function(){var r=document.getElementById("$kMailRootId");'
          'var d=document.documentElement;var b=document.body;var h=0;'
          'if(r){h=Math.max(h,r.scrollHeight,r.getBoundingClientRect().bottom);}'
          'if(b){h=Math.max(h,b.scrollHeight);}'
          'if(d){h=Math.max(h,d.scrollHeight);}'
          'return Math.ceil(h);})()',
        );
        _applyHeight(double.tryParse(result.toString()));
      } catch (_) {
        // 量不到就维持现有高度，不打扰用户。
        return;
      }
    }
  }

  void _applyHeight(double? raw) {
    if (raw == null || raw <= 0 || !mounted) return;
    final height = raw * (_document?.layoutScale ?? 1);
    // 只涨不缩：多量几路本就为了不截断，来回缩会让页面抖。
    if (_height != null && height <= _height! + 1) return;
    setState(() => _height = height);
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
    return SizedBox(
      height: _height ?? _kInitialHeight,
      child: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (_height == null)
            Center(
              child: CupertinoActivityIndicator(
                radius: 12,
                color: context.palette.textSecondary,
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
