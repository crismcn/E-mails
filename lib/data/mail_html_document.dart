import 'mail_mapper.dart' show htmlDeclaredWidth;

/// 正文外层包一层自己的容器 —— 也便于用 CSS 压掉邮件给 `body` 的
/// `height:100%` / `overflow:hidden`（那是给桌面客户端整页布局用的）。
const String kMailRootId = 'mail-root';

/// 给详情页浮层让位的两块占位 —— 正文前后各一个我们自己的空 div。
///
/// **刻意不用 `body` 的 `padding`**：邮件普遍自带 `<body style="margin:0;padding:0">`
/// （嵌套 body 标签被解析器丢弃、属性并到文档 body 上），内联样式压过我们的样式表，
/// 留白当场归零 —— 真机上表现为正文顶到屏幕最上、元信息与正文糊在一起（已复现）。
/// 占位换成独立元素后按 **id 选择器 + `!important`** 定高，邮件那边除了猜中同一个 id
/// 否则压不动（`div{}` / `*{}` 的特异度都更低）。
const String kMailTopPadId = 'mail-pad-top';
const String kMailBottomPadId = 'mail-pad-bottom';

/// 邮件正文渲染成的一整份 HTML 文档（含视口、CSP、注入样式）。
///
/// 不再有内联脚本 —— 正文 WebView 现在是有界视口自己滚动，不需要量高回报。
class MailHtmlDocument {
  const MailHtmlDocument({required this.html, required this.layoutScale});

  /// 交给 `WebViewController.loadHtmlString` 的完整文档。
  final String html;

  /// 排版宽度到屏幕宽度的缩放比（≤1）。
  ///
  /// 非响应式邮件（写死 `<table width="600">`）按 600 的「虚拟视口」排版、由浏览器
  /// 整体缩到屏宽，于是文档里的 CSS 像素乘这个比例才是**实际占屏尺寸**。唯一用途是把
  /// chrome 让位的占位高度**反向放大**后写进 CSS（`逻辑像素 / layoutScale`），
  /// 不参与任何盒子高度计算。
  ///
  /// **不要拿它折算 WebView 回报的滚动偏移** —— 那个回报是「视图空间」的量（Android
  /// 设备像素 / iOS point），本就含了页面缩放，详见 `MailHtmlView` 的 `_scrollUnit`。
  final double layoutScale;
}

/// `<script>` 整块 —— CSP `script-src 'none'` 地挡一遍，这里再把邮件自带的物理删一遍
/// （多一层，不指望 CSP 万无一失）。
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
/// **正文 WebView 是有界视口自己滚动 + 双指缩放**，不再需要量高脚本，故 CSP 直接
/// `script-src 'none'`，无需 nonce / JS 通道。
///
/// 安全姿态（正文是**发件人可控**的内容，按敌意输入对待）：
/// - `<meta http-equiv="Content-Security-Policy">` 只放开图片 / 内联样式 / 字体，
///   脚本、`<iframe>`、表单提交、`<base>` 全部被挡。多份 CSP 取交集执行，正文里
///   再塞一份宽松策略也放不开。
/// - 另外物理删掉 `<script>` 整块，作为 CSP 之外的第二道。
/// - 远程图片照旧会加载（和换 WebView 之前一样），也就是跟踪像素照旧能打点；
///   要拦得做成「点按钮才显示图片」，那是另一个功能。
///
/// 排版：
/// - 声明宽度（[htmlDeclaredWidth]）超过 [viewportWidth] 时，视口按声明宽度铺开，
///   由浏览器整体缩到屏宽作为**初始适配**（引擎重绘，比 Flutter 侧等比压扁清晰）。
/// - 不写 `user-scalable=no`，双指缩放可用。
/// - 长串不可断的 URL 靠 `overflow-wrap: anywhere` 折行，不撑出横条。
/// - [topPadding] / [bottomPadding]（**逻辑像素**）是给详情页那几条 chrome 让出的空间：
///   WebView 铺满真实全屏、顶栏 / 元信息 / 底栏都浮在它上面，正文靠正文前后两块占位
///   （[kMailTopPadId] / [kMailBottomPadId]）起头收尾，于是「整体上移」就等于「正文自己
///   往上滚」——**WebView 一次都不用动、不用改尺寸**。
///   写进 CSS 前要**除以 [MailHtmlDocument.layoutScale]**：宽版邮件在 600 的虚拟视口里
///   排版后被整体缩放，直接写逻辑像素会缩水成 `padding × layoutScale`。
///
/// 配色：[dark] 时**正文容器**（`#mail-root`）做反色（`invert` + `hue-rotate`），图片再反
/// 一次抵消 —— 邮件都是按白底黑字写的，这样能在不猜发件人配色的前提下保证文字始终可读，
/// 版式与对比关系也留着（纯粹强制文字色会把按钮 / 底色块压平）。页面底色由 `html` 直接
/// 写成 App 底色、**不参与反色**，否则滤镜生效前会闪一帧近白。
MailHtmlDocument buildMailHtmlDocument(
  String body, {
  required double viewportWidth,
  required bool dark,
  required String backgroundHex,
  double topPadding = 0,
  double bottomPadding = 0,
}) {
  final declared = htmlDeclaredWidth(body);
  final wide = declared > viewportWidth && viewportWidth > 0;
  final viewport = wide
      ? 'width=${declared.round()}'
      : 'width=device-width, initial-scale=1';
  final scale = wide ? viewportWidth / declared : 1.0;
  // 暗色下页面底色**直接写 App 底色**，不再靠反色滤镜去凑（那样得先写近白色的
  // #f5f2ed，而浏览器先画背景、后合成滤镜 —— 中间几帧就是一下白闪）。
  final pageBackground = dark ? backgroundHex : '#ffffff';

  return MailHtmlDocument(
    layoutScale: scale,
    html:
        '<!DOCTYPE html><html><head>'
        '<meta charset="utf-8">'
        '<meta http-equiv="Content-Security-Policy" content="'
        "default-src 'none'; "
        'img-src * data: blob:; '
        "style-src 'unsafe-inline'; "
        'font-src * data:; '
        'media-src * data:; '
        "script-src 'none'; "
        "frame-src 'none'; object-src 'none'; "
        "form-action 'none'; base-uri 'none'"
        '">'
        '<meta name="viewport" content="$viewport">'
        '<style>'
        '${_style(dark: dark, background: pageBackground, top: topPadding / scale, bottom: bottomPadding / scale)}'
        '</style>'
        '</head><body>'
        '<div id="$kMailTopPadId"></div>'
        '<div id="$kMailRootId">${body.replaceAll(_kScriptBlock, '')}</div>'
        '<div id="$kMailBottomPadId"></div>'
        '</body></html>',
  );
}

String _style({
  required bool dark,
  required String background,
  required double top,
  required double bottom,
}) =>
    ':root{color-scheme:light}'
    // 暗色下这条底色是**防白闪的关键**，必须压得住邮件自带的 `html{background:#fff}`。
    'html{background:$background${dark ? '!important' : ''};'
    '-webkit-text-size-adjust:100%}'
    'body{margin:0;padding:12px 16px;color:#111;'
    'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;'
    'font-size:16px;line-height:1.55;overflow-wrap:anywhere}'
    // 给浮层让位的两块占位（见 kMailTopPadId）。写死 `!important` 且用 id 选择器，
    // 邮件的 `div{}` / 内联 body 样式都压不动它。`clear:both` 防被未清除的浮动吃掉。
    '#$kMailTopPadId,#$kMailBottomPadId{display:block!important;'
    'width:auto!important;margin:0!important;padding:0!important;'
    'border:0!important;background:transparent!important;clear:both!important;'
    'min-height:0!important;max-height:none!important;overflow:hidden!important}'
    '#$kMailTopPadId{height:${top.toStringAsFixed(1)}px!important}'
    '#$kMailBottomPadId{height:${bottom.toStringAsFixed(1)}px!important}'
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