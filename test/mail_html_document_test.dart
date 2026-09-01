import 'package:flutter_test/flutter_test.dart';

import 'package:email_manager/data/mail_html_document.dart';

/// 正文 WebView 那份包装文档 —— 纯函数，视口 / CSP / 消毒 / 反色都在这里定死。
void main() {
  const nonce = 'abc123';

  MailHtmlDocument build(
    String body, {
    double viewportWidth = 360,
    bool dark = true,
  }) => buildMailHtmlDocument(
    body,
    nonce: nonce,
    viewportWidth: viewportWidth,
    dark: dark,
    backgroundHex: '#0a0d12',
  );

  group('视口与缩放', () {
    test('响应式邮件按设备宽度铺开，不整体缩放', () {
      final doc = build('<div style="width:100%">你好</div>');
      expect(doc.html, contains('content="width=device-width, initial-scale=1"'));
      expect(doc.layoutScale, 1);
    });

    test('写死宽度且超屏 → 视口取声明宽度，缩放比 = 屏宽 / 声明宽度', () {
      final doc = build('<table width="600"><tr><td>宽版</td></tr></table>');
      expect(doc.html, contains('content="width=600"'));
      expect(doc.layoutScale, closeTo(360 / 600, 0.0001));
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
    test('CSP 只给带 nonce 的脚本开口，其余全关', () {
      final html = build('<p>x</p>').html;
      expect(html, contains("script-src 'nonce-$nonce'"));
      expect(html, contains("default-src 'none'"));
      expect(html, contains("object-src 'none'"));
      expect(html, contains("frame-src 'none'"));
      expect(html, contains("form-action 'none'"));
      expect(html, contains("base-uri 'none'"));
      // 内联样式必须放开 —— 邮件全靠它排版；远程样式表不放。
      expect(html, contains("style-src 'unsafe-inline'"));
      expect(html, isNot(contains("script-src 'unsafe-inline'")));
      // 量高度那段脚本自己带 nonce，所以能跑。
      expect(html, contains('<script nonce="$nonce">'));
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
      // 只剩我们自己那一个带 nonce 的。
      expect('<script'.allMatches(html).length, 1);
    });

    test('nonce 每次都不一样：固定值等于把白名单告诉发件人', () {
      final seen = {for (var i = 0; i < 20; i++) mailHtmlNonce()};
      expect(seen, hasLength(20));
      expect(seen.every((n) => n.length == 16), isTrue);
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
    test('暗色：整份反色 + 图片反回来，页面底色取 App 底色的反色', () {
      final html = build('<p>x</p>', dark: true).html;
      expect(html, contains('html{filter:invert(1) hue-rotate(180deg)}'));
      expect(html, contains('img,video,picture,svg,canvas{filter:invert(1)'));
      // #0a0d12 反过来是 #f5f2ed，反色滤镜再作用一次正好落回 App 底色。
      expect(html, contains('html{background:#f5f2ed'));
    });

    test('亮色：不加滤镜，白底照发件人本意渲染', () {
      final html = build('<p>x</p>', dark: false).html;
      expect(html, isNot(contains('invert(1)')));
      expect(html, contains('html{background:#ffffff'));
    });

    test('长串不可断的文字会折行，不撑出横向滚动', () {
      expect(build('<p>x</p>').html, contains('overflow-wrap:anywhere'));
    });
  });

  group('量高度：长邮件不能被截断', () {
    test('正文包在自己的容器里 —— 量它，不受邮件给 body 的样式影响', () {
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

    test('量高取多种量法的最大值，并持续跟进（图片后到 / 缓存命中）', () {
      final html = build('<p>x</p>').html;
      expect(html, contains('Math.max(h,r.scrollHeight'));
      expect(html, contains('b.scrollHeight'));
      expect(html, contains('d.scrollHeight'));
      expect(html, contains('ResizeObserver'));
      expect(html, contains('setInterval'));
      expect(html, contains('$kMailHeightChannel.postMessage'));
    });
  });
}
