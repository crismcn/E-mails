import 'package:flutter_test/flutter_test.dart';

import 'package:email_manager/data/mail_html_document.dart';

/// 正文 WebView 那份包装文档 —— 纯函数，视口 / CSP / 消毒 / 反色都在这里定死。
///
/// 这份文档里**只有量高那一段脚本**（带随机 nonce）：正文 WebView 按页内量到的高度
/// 占位、自己不滚，宿主必须知道内容有多高。邮件自带的脚本一律进不来。
void main() {
  MailHtmlDocument build(
    String body, {
    double viewportWidth = 360,
    bool dark = true,
    String nonce = 'n0',
  }) => buildMailHtmlDocument(
    body,
    nonce: nonce,
    viewportWidth: viewportWidth,
    dark: dark,
    backgroundHex: '#0a0d12',
  );

  group('视口与缩放', () {
    test('响应式邮件按设备宽度铺开', () {
      final doc = build('<div style="width:100%">你好</div>');
      expect(doc.html, contains('content="width=device-width, initial-scale=1"'));
      expect(doc.layoutScale, 1);
    });

    test('写死宽度且超屏 → 视口取声明宽度，由引擎整体缩到屏宽', () {
      final doc = build('<table width="600"><tr><td>宽版</td></tr></table>');
      expect(doc.html, contains('content="width=600"'));
      // 量到的 CSS 高度要乘这个比例才是实际占屏高度。
      expect(doc.layoutScale, closeTo(360 / 600, 1e-9));
    });

    test('声明宽度比屏幕窄 → 不放大，仍按设备宽度', () {
      final doc = build('<table width="320"></table>', viewportWidth: 360);
      expect(doc.html, contains('width=device-width'));
      expect(doc.layoutScale, 1);
    });

    test('不禁缩放：双指放大要能用', () {
      expect(build('<p>x</p>').html, isNot(contains('user-scalable=no')));
    });
  });

  group('安全姿态', () {
    test('CSP 只放行带 nonce 的那段脚本，其余只放图片 / 内联样式 / 字体', () {
      final html = build('<p>x</p>', nonce: 'abc123').html;
      expect(html, contains("script-src 'nonce-abc123'"));
      expect(html, contains("default-src 'none'"));
      expect(html, contains("object-src 'none'"));
      expect(html, contains("frame-src 'none'"));
      expect(html, contains("form-action 'none'"));
      expect(html, contains("base-uri 'none'"));
      // 内联样式必须放开 —— 邮件全靠它排版；远程样式表不放。
      expect(html, contains("style-src 'unsafe-inline'"));
      expect(html, isNot(contains("script-src 'unsafe-inline'")));
    });

    test('只有量高那一段脚本，且带上 nonce', () {
      final html = build('<p>x</p>', nonce: 'abc123').html;
      expect('<script'.allMatches(html).length, 1);
      expect(html, contains('<script nonce="abc123">'));
      expect(html, contains(kMailMetricsChannel));
      // 放大后能不能在 WebView 内部滚 —— 靠可视视口高度判，与缩放比无关。
      expect(html, contains('visualViewport'));
      expect(html, isNot(contains('.scale')));
    });

    test('nonce 每份文档都换 —— 固定值等于把白名单告诉发件人', () {
      expect(mailHtmlNonce(), isNot(mailHtmlNonce()));
      expect(mailHtmlNonce(), hasLength(16));
    });

    test('邮件自带的 script 整块删掉（CSP 之外的第二道）', () {
      final html = build(
        '<p>前</p><script src="https://evil/x.js"></script>'
        '<script>alert(1)</script><p>后</p>',
      ).html;
      expect(html, contains('<p>前</p>'));
      expect(html, contains('<p>后</p>'));
      expect(html, isNot(contains('alert(1)')));
      expect(html, isNot(contains('evil')));
      // 剩下的那一个是我们自己的量高脚本。
      expect('<script'.allMatches(html).length, 1);
    });

    test('链接协议白名单：只放 http/https/mailto/tel', () {
      expect(isSafeMailLink('https://example.com/a'), isTrue);
      expect(isSafeMailLink('http://example.com'), isTrue);
      expect(isSafeMailLink('mailto:a@b.com'), isTrue);
      expect(isSafeMailLink('tel:+8613800138000'), isTrue);
      expect(isSafeMailLink('javascript:alert(1)'), isFalse);
      expect(isSafeMailLink('file:///etc/passwd'), isFalse);
      expect(isSafeMailLink('myapp://pay?to=x'), isFalse);
      expect(isSafeMailLink('/relative/path'), isFalse);
      expect(isSafeMailLink(''), isFalse);
    });
  });

  group('配色', () {
    test('暗色：只反正文容器 + 图片反回来，页面底色直接写 App 底色（不参与反色）', () {
      final html = build('<p>x</p>', dark: true).html;
      expect(html, contains('#$kMailRootId{filter:invert(1) hue-rotate(180deg)}'));
      expect(html, contains('img,video,picture,svg,canvas{filter:invert(1)'));
      // 关键：底色不靠反色去凑。曾经写 App 底色的反色（近白 #f5f2ed）等滤镜反回来，
      // 浏览器先画背景后合成滤镜 → 中间几帧近白 = 暗色下加载时白闪一下。
      expect(html, isNot(contains('html{filter:')));
      expect(html, contains('html{background:#0a0d12!important'));
      // 邮件写给 body 的白底在反色层外，照办就是暗页面上一大块白。
      expect(html, contains('body{background:transparent!important}'));
    });

    test('亮色：不加滤镜，白底照发件人本意渲染', () {
      final html = build('<p>x</p>', dark: false).html;
      expect(html, isNot(contains('invert(1)')));
      expect(html, contains('html{background:#ffffff'));
      expect(html, isNot(contains('background:transparent!important')));
    });

    test('长串不可断的文字会折行，不撑出横向滚动', () {
      expect(build('<p>x</p>').html, contains('overflow-wrap:anywhere'));
    });
  });

  group('样式覆盖：邮件不能把自己压成一屏高', () {
    test('正文包在自己的容器里 —— 便于用 CSS 覆盖邮件给 body 的样式', () {
      final html = build('<p>正文</p>').html;
      expect(html, contains('<div id="$kMailRootId"><p>正文</p></div>'));
    });

    test('压掉邮件写给 html/body 的 height:100% 与 overflow:hidden', () {
      // 这类声明本是给桌面客户端整页布局用的，照办会把正文压成一屏高。
      final html = build('<p>x</p>').html;
      expect(
        html,
        contains(
          'html,body{height:auto!important;max-height:none!important;'
          'overflow:visible!important}',
        ),
      );
      expect(html, contains('#$kMailRootId{height:auto!important'));
    });

    test('内层滚动容器不画滚动条（主视口那条走原生开关）', () {
      expect(
        build('<p>x</p>').html,
        contains('::-webkit-scrollbar{width:0;height:0}'),
      );
    });
  });
}
