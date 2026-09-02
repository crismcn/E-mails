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
    // 正文按页内量到的高度占位 → 需要那一段量高脚本（带 nonce，邮件自带的进不来）。
    expect(html, contains("script-src 'nonce-"));
    expect(html, contains('<script nonce="'));
    expect('<script'.allMatches(html).length, 1);
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

  testWidgets('整页一条滚动条：上滑时收件人 / 主题跟着滚走，返回栏与底部操作栏不收起', (
    WidgetTester tester,
  ) async {
    await _pumpList(tester);
    // 纯文本长邮件：HTML 正文在测试里没有平台视图、撑不出滚动，故用纯文本验证。
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    final recipientBefore = tester.getTopLeft(find.text('收件人：')).dy;
    final headerBefore = tester.getTopLeft(find.byIcon(AppIcons.back)).dy;
    final actionBefore = tester.getTopLeft(find.text('回复')).dy;

    // 上滑。用 `timedDrag` 慢速拖拽而非 `drag` 快速甩：SelectableText 与滚动视图
    // 抢手势时，极高速的测试手势会被当成选择操作吞掉。
    await tester.timedDrag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -320),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    // 元信息与正文同在一条滚动条里 → 一起往上走。
    expect(tester.getTopLeft(find.text('收件人：')).dy, lessThan(recipientBefore));
    // 返回栏与底部操作栏是固定的：不收起、不平移 —— 收起会改正文区尺寸，
    // WebView 一重排就吐新偏移驱动收放，正反馈表现为「全屏来回跳动」。
    expect(tester.getTopLeft(find.byIcon(AppIcons.back)).dy, headerBefore);
    expect(tester.getTopLeft(find.text('回复')).dy, actionBefore);
    expect(find.byType(SizeTransition), findsNothing);
  });

  testWidgets('正文懒取中：转圈落在内容区垂直正中', (WidgetTester tester) async {
    final api = FakeMailApi()..getMessageHangs = true;
    await _pumpList(tester, api);
    await tester.tap(find.text('Claude'));
    // 转圈会一直转 —— `pumpAndSettle` 永不收敛，只 pump 到路由转场结束。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 内容区 = 返回栏与底部操作栏之间那块（滚动视图铺满它）。
    final content = tester.getRect(find.byType(SingleChildScrollView).last);
    final spinner = tester.getRect(find.byType(CupertinoActivityIndicator));
    // 原来转圈紧跟在元信息下面（贴着收件人那几行、偏上一大截），现在浮在正中。
    expect(spinner.center.dy, closeTo(content.center.dy, 0.5));
  });
}
