import 'dart:math';

import 'mail_mapper.dart' show htmlDeclaredWidth;

/// 正文度量回报用的 JS 通道名 —— WebView 侧 `MailMetrics.postMessage("高度,能否内部滚动")`。
const String kMailMetricsChannel = 'MailMetrics';

/// 页内挂在 `window` 上的度量函数名 —— 宿主兜底时直接
/// `runJavaScriptReturningResult('$kMailMetricsProbe()')`，量法与主动回报完全一致。
const String kMailMetricsProbe = 'mailMetrics';

/// 正文外层包一层自己的容器 —— 量高度以它为准，也便于用 CSS 压掉邮件给 `body` 的
/// `height:100%` / `overflow:hidden`（那是给桌面客户端整页布局用的）。
const String kMailRootId = 'mail-root';

/// 邮件正文渲染成的一整份 HTML 文档（含视口、CSP、注入样式与量高脚本）。
class MailHtmlDocument {
  const MailHtmlDocument({required this.html, required this.layoutScale});

  /// 交给 `WebViewController.loadHtmlString` 的完整文档。
  final String html;

  /// 排版宽度到屏幕宽度的缩放比（≤1）。
  ///
  /// 非响应式邮件（写死 `<table width="600">`）按 600 的「虚拟视口」排版、由浏览器
  /// 整体缩到屏宽，于是 JS 量到的 CSS 像素高度要乘这个比例才是**实际占屏高度**。
  ///
  /// 它只跟这封邮件的排版有关，**与用户双指缩放无关** —— 盒子高度一旦按它定死就不再
  /// 变（曾按 `visualViewport.scale` 重新定高，缩放比能到 10、盒子被撑成几万像素，
  /// 一放大就闪退）。放大后看溢出部分靠 WebView 内部平移。
  final double layoutScale;
}

/// `<script>` 整块 —— CSP 只放行带 nonce 的那段，这里再把邮件自带的物理删一遍
/// （多一层，不指望正则万无一失）。
final RegExp _kScriptBlock = RegExp(
  r'<script\b[^>]*>[\s\S]*?</script\s*>|<script\b[^>]*/?>',
  caseSensitive: false,
);

/// 允许点开的链接协议 —— 邮件里的 `javascript:` / 自定义 scheme 一律不往外抛。
const Set<String> kMailLinkSchemes = {'http', 'https', 'mailto', 'tel'};

/// 这个 URL 能不能交给系统浏览器 / 邮件 App 打开。
bool isSafeMailLink(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme) return false;
  return kMailLinkSchemes.contains(uri.scheme.toLowerCase());
}

/// 把邮件正文 HTML 包成一份可安全渲染的完整文档。
///
/// **正文 WebView 按这份文档渲染完的高度占位、自己不滚**，与上方收件人 / 主题 / 附件
/// 共用页面那一条滚动条；故这里需要一段量高脚本把高度回报给宿主。见 `MailHtmlView`。
///
/// 安全姿态（正文是**发件人可控**的内容，按敌意输入对待）：
/// - `<meta http-equiv="Content-Security-Policy">` 只放开图片 / 内联样式 / 字体，
///   脚本仅允许带 [nonce] 的那一段（也就是下面量高度用的那几行）。邮件自带的
///   `<script>`、内联 `onclick=`、`<iframe>`、表单提交、`<base>` 全部被挡。
///   多份 CSP 是**取交集**执行的，正文里再塞一份宽松策略也放不开。
/// - [nonce] 必须每份文档随机重生成：固定值等于把白名单告诉发件人。
/// - 另外物理删掉 `<script>` 整块，作为 CSP 之外的第二道。
/// - 远程图片照旧会加载（和换 WebView 之前一样），也就是跟踪像素照旧能打点；
///   要拦得改成「点按钮才显示图片」，那是另一个功能。
///
/// 排版：
/// - 声明宽度（[htmlDeclaredWidth]）超过 [viewportWidth] 时，视口按声明宽度铺开，
///   由浏览器整体缩到屏宽作为**初始适配**（引擎重绘，比 Flutter 侧等比压扁清晰）。
/// - 不写 `user-scalable=no`，双指缩放可用（在固定高度的盒子内缩放 + 平移）。
/// - 长串不可断的 URL 靠 `overflow-wrap: anywhere` 折行，不撑出横条。
///
/// 配色：[dark] 时**正文容器**（`#mail-root`）做反色（`invert` + `hue-rotate`），图片再反
/// 一次抵消 —— 邮件都是按白底黑字写的，这样能在不猜发件人配色的前提下保证文字始终可读，
/// 版式与对比关系也留着（纯粹强制文字色会把按钮 / 底色块压平）。页面底色由 `html` 直接
/// 写成 App 底色、**不参与反色**，否则滤镜生效前会闪一帧近白。
MailHtmlDocument buildMailHtmlDocument(
  String body, {
  required String nonce,
  required double viewportWidth,
  required bool dark,
  required String backgroundHex,
}) {
  final declared = htmlDeclaredWidth(body);
  final wide = declared > viewportWidth && viewportWidth > 0;
  final viewport = wide
      ? 'width=${declared.round()}'
      : 'width=device-width, initial-scale=1';
  // 暗色下页面底色**直接写 App 底色**，不再靠反色滤镜去凑（那样得先写近白色的
  // #f5f2ed，而浏览器先画背景、后合成滤镜 —— 中间几帧就是一下白闪）。
  final pageBackground = dark ? backgroundHex : '#ffffff';

  return MailHtmlDocument(
    layoutScale: wide ? viewportWidth / declared : 1,
    html:
        '<!DOCTYPE html><html><head>'
        '<meta charset="utf-8">'
        '<meta http-equiv="Content-Security-Policy" content="'
        "default-src 'none'; "
        'img-src * data: blob:; '
        "style-src 'unsafe-inline'; "
        'font-src * data:; '
        'media-src * data:; '
        "script-src 'nonce-$nonce'; "
        "frame-src 'none'; object-src 'none'; "
        "form-action 'none'; base-uri 'none'"
        '">'
        '<meta name="viewport" content="$viewport">'
        '<style>${_style(dark: dark, background: pageBackground)}</style>'
        '</head><body>'
        '<div id="$kMailRootId">${body.replaceAll(_kScriptBlock, '')}</div>'
        '<script nonce="$nonce">${_heightProbe()}</script>'
        '</body></html>',
  );
}

/// 生成一次性 nonce —— 走 [Random.secure]，发件人猜不到就没法让自己的脚本过 CSP。
String mailHtmlNonce() {
  final rnd = Random.secure();
  return List<String>.generate(
    16,
    (_) => rnd.nextInt(16).toRadixString(16),
  ).join();
}

String _style({required bool dark, required String background}) =>
    ':root{color-scheme:light}'
    // 暗色下这条底色是**防白闪的关键**，必须压得住邮件自带的 `html{background:#fff}`。
    'html{background:$background${dark ? '!important' : ''};'
    '-webkit-text-size-adjust:100%}'
    'body{margin:0;padding:12px 16px;color:#111;'
    'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;'
    'font-size:16px;line-height:1.55;overflow-wrap:anywhere}'
    // 不少邮件给 html/body 写 `height:100%` 或 `overflow:hidden`（原本是给
    // 桌面客户端的整页布局用的），照办的话正文会被压成一屏高、后面全没了。
    // `!important` 压得住邮件里后写的普通声明。
    'html,body{height:auto!important;max-height:none!important;'
    'overflow:visible!important}'
    '#$kMailRootId{height:auto!important;max-height:none!important;'
    'overflow:visible!important}'
    // 超宽图片仍夹回容器内（宽度推断刻意忽略 img，见 htmlDeclaredWidth）。
    'img{max-width:100%;height:auto}'
    'table{max-width:100%}'
    'pre{white-space:pre-wrap}'
    // 邮件自带的内层滚动容器不画滚动条（主视口那条是原生绘制的，靠
    // `setVerticalScrollBarEnabled(false)` 关，见 MailHtmlView）。
    '::-webkit-scrollbar{width:0;height:0}'
    '${dark ? _kDarkFilter : ''}';

/// 反色一遍正文，图片 / 视频再反回来 —— 照片和 logo 的颜色才是对的。
///
/// **滤镜只作用在 `#mail-root`，不作用在 `html`**：曾经反的是整份文档，于是页面底色得
/// 先写成 App 底色的**反色**（近白的 `#f5f2ed`）才能反回来 —— 而浏览器是先画背景、再
/// 合成滤镜的，中间几帧就照着近白画，暗色下表现为**加载时白闪一下**。现在 `html` 直接
/// 写真实底色，任何时刻都是暗的。
///
/// 已知取舍：白底 logo 反两次仍是白底（暗页面上一块白），元素的
/// `background-image` 没法单独反回来（会连带子节点），深底设计的邮件会被反成亮底。
const String _kDarkFilter =
    '#$kMailRootId{filter:invert(1) hue-rotate(180deg)}'
    // 邮件常带 `<body style="background:#fff">`（嵌套的 body 标签被解析器丢弃、属性
    // 并到文档 body 上），而 body 在反色层**外面** —— 照办就是暗页面上一大块白。
    // 暗色下底色一律由 html 提供。
    'body{background:transparent!important}'
    'img,video,picture,svg,canvas{filter:invert(1) hue-rotate(180deg)}';

/// 量正文高度、并顺带告诉宿主「WebView 内部现在还能不能纵向滚」。
///
/// 高度取 `#mail-root` / `body` / `documentElement` 三种量法的**最大值**：邮件可能给
/// `body` 写死高度、可能整封浮动（父元素高度塌成 0）、也可能被 `overflow` 裁掉。
/// 少量一种就会把长邮件截断，宁可多算一点空白。图片是后到的，故 `ResizeObserver`
/// + 轮询持续跟。
///
/// 「能不能内部滚」= 内容高度是否超过**可视视口**（`visualViewport.height`，双指放大
/// 后它会变小）。宿主拿它决定单指拖动归谁：能内滚就归 WebView（放大后够得着下半截 /
/// 超高被截顶的邮件也能读全），不能内滚就归外层页面（整页一起上滑）。
///
/// **刻意不回报缩放比去改盒子高度**：那条路上盒子会被撑成几万像素，一放大就闪退。
/// 这里回报的高度与缩放无关，缩放只影响那个布尔量，宿主收到它不重建界面。
String _heightProbe() =>
    '(function(){var lastH=-1;var lastS=-1;'
    'function measure(){var r=document.getElementById("$kMailRootId");'
    'var d=document.documentElement;var b=document.body;var h=0;'
    'if(r){h=Math.max(h,r.scrollHeight,r.getBoundingClientRect().bottom);}'
    'if(b){h=Math.max(h,b.scrollHeight);}'
    'if(d){h=Math.max(h,d.scrollHeight);}'
    'return Math.ceil(h);}'
    'function view(){var v=window.visualViewport;'
    'return v?v.height:document.documentElement.clientHeight;}'
    'function metrics(){var h=measure();'
    'return h+","+((h-view())>2?1:0);}'
    'function report(){var h=measure();var s=(h-view())>2?1:0;'
    'if(h<=0||(h===lastH&&s===lastS)){return;}lastH=h;lastS=s;'
    '$kMailMetricsChannel.postMessage(h+","+s);}'
    'window.$kMailMetricsProbe=metrics;'
    'report();window.addEventListener("load",report);'
    'if(window.ResizeObserver){var ro=new ResizeObserver(report);'
    'ro.observe(document.documentElement);'
    'var r=document.getElementById("$kMailRootId");if(r){ro.observe(r);}}'
    // 双指缩放 / 平移会改可视视口 —— 只有那个布尔量会变，宿主不重建界面，
    // 所以这里监听是安全的（历史上是「按缩放比重新定高」才炸的）。
    'if(window.visualViewport){'
    'window.visualViewport.addEventListener("resize",report);'
    'window.visualViewport.addEventListener("scroll",report);}'
    // 图片没有 load 事件冒泡到 window 的保障（缓存命中时可能早于监听），
    // 再补几拍轮询兜底。
    'var n=0;var t=setInterval(function(){report();if(++n>10){'
    'clearInterval(t);}},300);})();';
