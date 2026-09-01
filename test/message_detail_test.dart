import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:email_manager/theme/app_icons.dart';
import 'package:email_manager/api/api_service.dart';
import 'package:email_manager/core/auth/credentials_store.dart';
import 'package:email_manager/main.dart';
import 'package:email_manager/settings/settings_controller.dart';
import 'package:email_manager/widgets/mail_html_view.dart';

import 'fake_mail_api.dart';

/// 正文 WebView 在 widget 测试里没有平台视图可用，[MailHtmlView] 于是降级成
/// [MailHtmlUnavailable]，把生成好的文档挂在树上 —— 断言就落在这份文档上。
MailHtmlDocumentMatcher get _htmlDoc => MailHtmlDocumentMatcher();

/// 取当前详情页正文那份文档（没有 WebView 可渲染时的降级载体）。
class MailHtmlDocumentMatcher {
  String get html {
    final finder = find.byType(MailHtmlUnavailable);
    expect(finder, findsOneWidget);
    final document = (finder.evaluate().single.widget as MailHtmlUnavailable)
        .document;
    expect(document, isNotNull);
    return document!.html;
  }

  double get layoutScale {
    final finder = find.byType(MailHtmlUnavailable);
    expect(finder, findsOneWidget);
    return (finder.evaluate().single.widget as MailHtmlUnavailable)
        .document!
        .layoutScale;
  }
}

/// 打开「首页 → 邮件列表」，邮件数据来自注入的 [FakeMailApi]。
///
/// 现在点击列表项**直接进入详情页**（会话页已移除），详情页按 id 懒取全文。
Future<void> _pumpList(
  WidgetTester tester, [
  FakeMailApi? mailApi,
  double screenHeight = 2340,
]) async {
  tester.view.physicalSize = Size(1080, screenHeight);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final api = ApiService.create(
    credentialsStore: InMemoryCredentialsStore(const [
      AccountCredentials(
        email: 'alice@outlook.com',
        clientId: 'c',
        refreshToken: 'r',
      ),
    ]),
    mailApi: mailApi ?? FakeMailApi(),
  );
  await tester.pumpWidget(
    EmailManagerApp(settings: SettingsController(prefs), api: api),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('alice@outlook.com'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('点击列表项 → 直接进入详情页，懒取 HTML 全文并交给 WebView 渲染', (
    WidgetTester tester,
  ) async {
    await _pumpList(tester);

    // 「蓝湖官方」对应最新未读消息 c3-3（HTML 全文）。
    await tester.tap(find.text('蓝湖官方'));
    await tester.pumpAndSettle();

    // 收件人等元信息仍是 Flutter 侧的；正文原文被包进 WebView 那份文档里
    // （正文文字已不在 Flutter 树上，故不能再用 find.text 断言）。
    expect(find.text('收件人：'), findsOneWidget);
    final html = _htmlDoc.html;
    expect(html, contains('https://example.com/detail'));
    expect(html, contains('前往安全中心'));
    expect(html, contains('<meta name="viewport"'));
    expect(html, contains("script-src 'nonce-"));
  });

  testWidgets('点击列表项 → 详情页懒取纯文本全文按纯文本渲染', (WidgetTester tester) async {
    await _pumpList(tester);

    // 「Claude」对应 m1，全文为纯文本。
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    expect(find.text('收件人：'), findsOneWidget);
    // 纯文本不进 WebView，仍走 Flutter 的可选择文本。
    expect(find.byType(MailHtmlUnavailable), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('纯文本正文'), findsOneWidget);
  });

  testWidgets('详情页星标：乐观更新 + PATCH 回写 Graph', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpList(tester, api);

    // 蓝湖 c3-3 服务端未标星 → 进入时空心星。
    await tester.tap(find.text('蓝湖官方'));
    await tester.pumpAndSettle();
    expect(find.byIcon(AppIcons.starEmpty), findsOneWidget);
    expect(find.byIcon(AppIcons.starFilled), findsNothing);

    await tester.tap(find.byIcon(AppIcons.starEmpty));
    await tester.pumpAndSettle();

    // 回写记录到 Graph：c3-3 → flagged true，并提示已标星。
    expect(api.flagUpdates, [('c3-3', true)]);
    expect(find.byIcon(AppIcons.starFilled), findsOneWidget);
    expect(find.text('已标星'), findsOneWidget);

    // 再点一次取消标星 → 回写 false。
    await tester.tap(find.byIcon(AppIcons.starFilled));
    await tester.pumpAndSettle();
    expect(api.flagUpdates, [('c3-3', true), ('c3-3', false)]);
    expect(find.byIcon(AppIcons.starEmpty), findsOneWidget);
    expect(find.text('已取消标星'), findsOneWidget);
  });

  testWidgets('详情页星标失败：回滚星标态并提示', (WidgetTester tester) async {
    final api = FakeMailApi()..updateFlagFails = true;
    await _pumpList(tester, api);

    await tester.tap(find.text('蓝湖官方'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(AppIcons.starEmpty));
    await tester.pumpAndSettle();

    // 发起过写回，但失败 → 提示操作失败、星标回滚为空心。
    expect(api.flagUpdates, [('c3-3', true)]);
    expect(find.textContaining('操作失败'), findsOneWidget);
    expect(find.byIcon(AppIcons.starEmpty), findsOneWidget);
    expect(find.byIcon(AppIcons.starFilled), findsNothing);
  });

  testWidgets('详情页进入即回填服务端星标态', (WidgetTester tester) async {
    await _pumpList(tester);

    // Claude（m1）在假数据里已标星 → 懒取全文后星标应为实心。
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    expect(find.byIcon(AppIcons.starFilled), findsOneWidget);
    expect(find.byIcon(AppIcons.starEmpty), findsNothing);
  });

  testWidgets('附件条默认收起：只显示个数与总大小（内嵌图不计入）', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpList(tester, api);

    // Claude（m1）带 1 图 + 1 txt + 1 内嵌图；内嵌图被过滤 → 2 个附件、3810+44 字节。
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    expect(find.text('2 个附件'), findsOneWidget);
    expect(find.text('3.76KB'), findsOneWidget);
    // 收起态不列具体文件，也不预取任何内容。
    expect(find.text('58.png'), findsNothing);
    expect(find.text('scriptlog.txt'), findsNothing);
    expect(api.fetchedAttachmentIds, isEmpty);
  });

  testWidgets('展开附件：图片出预览、其他文件出类型角标行；只为图片预取字节', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpList(tester, api);
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2 个附件'));
    await tester.pumpAndSettle();

    // 图片：预览图 + 底部信息条（名字 + 大小）。
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('58.png'), findsOneWidget);
    expect(find.text('3.72KB'), findsOneWidget);
    // 文本：蓝色类型角标 + 名称 + 大小。
    expect(find.text('TXT'), findsOneWidget);
    expect(find.text('scriptlog.txt'), findsOneWidget);
    expect(find.text('44B'), findsOneWidget);
    // 只有图片需要内容做预览；txt 等点开才取。
    expect(api.fetchedAttachmentIds, ['att-img']);

    // 再点摘要行收起 → 具体附件移出树。
    await tester.tap(find.text('2 个附件'));
    await tester.pumpAndSettle();
    expect(find.text('scriptlog.txt'), findsNothing);
  });

  testWidgets('附件列表取不到时静默降级：不显示附件条、正文照常', (WidgetTester tester) async {
    final api = FakeMailApi()..listAttachmentsFails = true;
    await _pumpList(tester, api);

    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    expect(find.text('2 个附件'), findsNothing);
    expect(find.textContaining('纯文本正文'), findsOneWidget);
  });

  testWidgets('超宽 HTML：视口按声明宽度铺开，交给引擎整体缩放', (WidgetTester tester) async {
    await _pumpList(tester);

    // Cursor Team（m2）全文是写死 600px 的非响应式邮件。
    await tester.tap(find.text('Cursor Team'));
    await tester.pumpAndSettle();

    // 不再是 Flutter 侧 FittedBox 压扁：视口声明成 600，浏览器自己缩到屏宽，
    // 文字由引擎按缩放后的字号重绘，不发虚。
    expect(_htmlDoc.html, contains('content="width=600"'));
    // 正文通铺整宽（360），故缩放比 = 360/600。
    expect(_htmlDoc.layoutScale, closeTo(360 / 600, 0.0001));

    // 全页只有纵向滚动，正文没有额外的横向滚动视图。
    expect(
      find.byWidgetPredicate(
        (w) => w is ScrollView && w.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
    );
  });

  testWidgets('长邮件上滑：两条浮层滑出屏幕，下滑再切回来，正文不跳位', (WidgetTester tester) async {
    // 带刘海 / home 条的机型：安全区内边距是这条逻辑的关键场景 —— 浮层往外滑
    // 会滑进安全区之外那两条里，没裁剪就赖在那儿不消失。
    tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
    addTearDown(tester.view.resetPadding);

    await _pumpList(tester);
    // 用纯文本长邮件：HTML 正文在测试里没有平台视图、高度为 0，撑不出滚动距离。
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    // 两条栏是绝对定位浮层，收放只做位移 —— 故看 SlideTransition 的位移分数
    // （它的位移是绘制期变换，量它自己的 rect 拿不到，要么看 value 要么量子树）。
    Finder band(Finder inner) =>
        find.ancestor(of: inner, matching: find.byType(SlideTransition)).first;
    Offset slide(Finder inner) =>
        tester.widget<SlideTransition>(band(inner)).position.value;
    double maxExtent() => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .maxScrollExtent;

    final header = find.byIcon(AppIcons.back);
    final actionBar = find.text('回复');
    final headerShown = tester.getRect(header);
    final actionBarShown = tester.getRect(actionBar);
    final headerBand = tester.getSize(band(header)).height;
    final actionBarBand = tester.getSize(band(actionBar)).height;
    final extentShown = maxExtent();
    expect(slide(header), Offset.zero);
    expect(slide(actionBar), Offset.zero);

    // 拖屏幕中央（主题上滑后已移出视口，拿不到可用的落点）。
    const at = Offset(180, 400);
    await tester.dragFrom(at, const Offset(0, -300));
    await tester.pumpAndSettle();

    // 全屏让给正文：各自整条向外挪出自身高度（标题栏往上、操作栏往下）。
    expect(slide(header), const Offset(0, -1));
    expect(slide(actionBar), const Offset(0, 1));
    expect(tester.getRect(header).top, closeTo(headerShown.top - headerBand, 0.01));
    expect(
      tester.getRect(actionBar).top,
      closeTo(actionBarShown.top + actionBarBand, 0.01),
    );

    // 挪出去的部分靠**贴着浮层的** ClipRect 裁掉：Stack 不会裁绘制期变换（浮层的
    // 布局矩形没越界，它认定无溢出、不装裁剪层），少了它，浮层会露在安全区那两条里。
    for (final inner in [header, actionBar]) {
      final clip = find
          .ancestor(of: band(inner), matching: find.byType(ClipRect))
          .first;
      expect(tester.getSize(clip).height, tester.getSize(band(inner)).height);
    }

    // 关键：滚动视图尺寸与内边距都没动 → 可滚动距离不变，正文不会跳一段。
    expect(maxExtent(), extentShown);

    // 反向下滑 → 两条又切回原位。
    await tester.dragFrom(at, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(slide(header), Offset.zero);
    expect(slide(actionBar), Offset.zero);
    expect(tester.getRect(header), headerShown);
    expect(tester.getRect(actionBar), actionBarShown);
    expect(maxExtent(), extentShown);
  });

  testWidgets('内容装得下一屏时上滑不收起标题栏（可滚动距离不足）', (WidgetTester tester) async {
    // 同一封长邮件，把屏幕拉得足够高 → 一屏装得下，收放门槛不该被触发。
    await _pumpList(tester, null, 6000);
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    final header = find.byIcon(AppIcons.back);
    final before = tester.getRect(header);

    await tester.dragFrom(const Offset(180, 400), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(tester.getRect(header), before);
  });
}
