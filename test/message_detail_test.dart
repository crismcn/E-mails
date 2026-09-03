import 'package:flutter/cupertino.dart';
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
    final document =
        (finder.evaluate().single.widget as MailHtmlUnavailable).document;
    expect(document, isNotNull);
    return document!.html;
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

    // 收件人 / 主题 / 日期是**原生组件**（在可收起的顶部区里）；
    // 正文原文被包进 WebView 那份文档里（正文文字不在 Flutter 树上）。
    expect(find.text('收件人：'), findsOneWidget);
    expect(find.text('蓝湖免费版权益调整通知 尊敬的蓝湖用户'), findsOneWidget);
    final html = _htmlDoc.html;
    expect(html, contains('https://example.com/detail'));
    expect(html, contains('前往安全中心'));
    expect(html, contains('<meta name="viewport"'));
    // 正文 WebView 是有界视口自滚，不再量高 —— 整份文档无任何脚本，CSP 收紧到 none。
    expect(html, contains("script-src 'none'"));
    expect('<script'.allMatches(html).length, 0);
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

    // 不是 Flutter 侧 FittedBox 压扁：视口声明成 600，浏览器自己缩到屏宽，
    // 文字由引擎按缩放后的字号重绘，不发虚。
    expect(_htmlDoc.html, contains('content="width=600"'));

    // 正文横向溢出由 WebView 自己消化，Flutter 侧没有额外的横向滚动视图。
    expect(
      find.byWidgetPredicate(
        (w) => w is ScrollView && w.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
    );
  });

  testWidgets('上滑：元信息随正文 1:1 走、顶/底栏整条切出，滚回起点三条都回位', (
    WidgetTester tester,
  ) async {
    await _pumpList(tester);
    // 纯文本长邮件：HTML 正文在测试里没有平台视图、撑不出滚动，故用纯文本验证。
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    final topBar = find.byKey(const Key('detail-top-bar'));
    final meta = find.byKey(const Key('detail-meta'));
    final bottomBar = find.byKey(const Key('detail-bottom-bar'));
    final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;

    // 初始：顶栏贴屏幕顶（含状态栏那条）、元信息紧跟其后、底栏贴屏幕底。
    expect(tester.getRect(topBar).top, closeTo(0, 0.5));
    expect(tester.getRect(meta).top, closeTo(tester.getRect(topBar).bottom, 0.5));
    expect(tester.getRect(bottomBar).bottom, closeTo(screenH, 0.5));
    // 正文起始处的留白 == 顶栏 + 元信息，即正文正好接在元信息下面。
    final bodyScroll = find.byType(SingleChildScrollView).last;
    expect(
      tester.widget<SingleChildScrollView>(bodyScroll).padding?.resolve(null).top,
      closeTo(tester.getRect(meta).bottom, 0.5),
    );

    // 上滑正文（纯文本的 SingleChildScrollView）。
    await tester.timedDrag(
      bodyScroll,
      const Offset(0, -400),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    // 三条全部出画：顶栏 / 元信息移到屏幕上方，底栏移到屏幕下方。
    expect(tester.getRect(topBar).bottom, lessThanOrEqualTo(0.5));
    expect(tester.getRect(meta).bottom, lessThanOrEqualTo(0.5));
    expect(tester.getRect(bottomBar).top, greaterThanOrEqualTo(screenH - 0.5));

    // 滚回起点 → 元信息按 1:1 映射回位，顶 / 底栏整条切回来。
    tester.widget<SingleChildScrollView>(bodyScroll).controller!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getRect(topBar).top, closeTo(0, 0.5));
    expect(tester.getRect(meta).top, closeTo(tester.getRect(topBar).bottom, 0.5));
    expect(tester.getRect(bottomBar).bottom, closeTo(screenH, 0.5));
  });

  testWidgets('顶/底栏按滑动方向收放：小幅滑动不动，够 24 才整条切出，回滑 12 就召回', (
    WidgetTester tester,
  ) async {
    await _pumpList(tester);
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    final topBar = find.byKey(const Key('detail-top-bar'));
    final meta = find.byKey(const Key('detail-meta'));
    final bottomBar = find.byKey(const Key('detail-bottom-bar'));
    final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final topH = tester.getRect(topBar).height;
    final controller = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).last)
        .controller!;

    // 一滑动就切出是不对的（用户反馈「时机不对」）：不足 24 时两条栏一动不动，
    // 只有元信息随正文 1:1 走 —— 它是内容的一部分。
    controller.jumpTo(12);
    await tester.pumpAndSettle();
    expect(tester.getRect(topBar).top, closeTo(0, 0.5));
    expect(tester.getRect(bottomBar).bottom, closeTo(screenH, 0.5));
    expect(tester.getRect(meta).top, closeTo(topH - 12, 0.5));

    // 累计上滑够 24 → 两条栏**整条**切出（中途不会停在半截）。
    controller.jumpTo(30);
    await tester.pumpAndSettle();
    expect(tester.getRect(topBar).bottom, closeTo(0, 0.5));
    expect(tester.getRect(bottomBar).top, closeTo(screenH, 0.5));

    // 回滑不足 12（含越界回弹那点抖动）→ 保持收起，不来回弹。
    controller.jumpTo(22);
    await tester.pumpAndSettle();
    expect(tester.getRect(topBar).bottom, closeTo(0, 0.5));

    // 回滑够 12 → 立刻整条切回来，**不必先滚到顶部**（读到中段也能点底部操作栏）。
    controller.jumpTo(15);
    await tester.pumpAndSettle();
    expect(tester.getRect(topBar).top, closeTo(0, 0.5));
    expect(tester.getRect(bottomBar).bottom, closeTo(screenH, 0.5));
    // 元信息仍按正文偏移摆着（它不参与方向判定）。
    expect(tester.getRect(meta).top, closeTo(topH - 15, 0.5));
  });

  testWidgets('内容装得下一屏：上滑也不动浮层', (WidgetTester tester) async {
    final api = FakeMailApi(
      fullMessages: {
        ...kFakeFullMessages,
        // 短正文、无附件 —— 一屏装得下，正文无法滚动 → 浮层不动。
        'm1': fakeGraphMessage(
          id: 'm1',
          conversationId: 'c1',
          fromName: 'Claude',
          subject: 'Claude 任务执行通知 · ✅ 任务已完成',
          toRecipients: const ['crism@qq.com'],
          bodyContent: '一行就够的短正文。',
        ),
      },
    );
    await _pumpList(tester, api);
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    final topBar = find.byKey(const Key('detail-top-bar'));
    await tester.timedDrag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -320),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    // 正文内容很短，滚不动 → 顶栏仍贴屏幕顶。
    expect(tester.getRect(topBar).top, closeTo(0, 0.5));
  });

  testWidgets('正文懒取中：转圈浮在屏幕正中', (WidgetTester tester) async {
    final api = FakeMailApi()..getMessageHangs = true;
    await _pumpList(tester, api);
    await tester.tap(find.text('Claude'));
    // 转圈会一直转 —— `pumpAndSettle` 永不收敛，只 pump 到路由转场结束。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 转圈在 Stack 的 Positioned.fill 里 → 浮在屏幕正中。
    final spinner = tester.getRect(find.byType(CupertinoActivityIndicator));
    final screenSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(spinner.center.dy, closeTo(screenSize.height / 2, 1));
  });
}
