import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:email_manager/theme/app_icons.dart';
import 'package:email_manager/api/api_service.dart';
import 'package:email_manager/api/mail_api.dart';
import 'package:email_manager/core/auth/credentials_store.dart';
import 'package:email_manager/core/contacts/contact_picker.dart';
import 'package:email_manager/l10n/app_localizations.dart';
import 'package:email_manager/main.dart';
import 'package:email_manager/models/mail.dart';
import 'package:email_manager/pages/compose_page.dart';
import 'package:email_manager/settings/settings_controller.dart';
import 'package:email_manager/theme/app_theme.dart';

import 'fake_mail_api.dart';

/// 打开「首页 → 邮件列表 → 新建邮件」。
Future<void> _pumpCompose(WidgetTester tester, FakeMailApi mailApi) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    EmailManagerApp(
      settings: SettingsController(prefs),
      api: ApiService.create(
        credentialsStore: InMemoryCredentialsStore(const [
          AccountCredentials(
            email: 'alice@outlook.com',
            clientId: 'c',
            refreshToken: 'r',
          ),
        ]),
        mailApi: mailApi,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('alice@outlook.com'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

/// 直接挂一个 [ComposePage]，注入假的联系人选择器与输入提示候选池。
///
/// 选联系人本身走平台通道（widget 测试碰不到），故只把「选完之后」的逻辑
/// 抽成注入点来验证：多地址二次选择、拼进收件人框、各种失败提示。
Future<void> _pumpComposeWithPicker(
  WidgetTester tester,
  ContactEmailPicker picker, {
  List<ComposeContact> suggestions = const <ComposeContact>[],
  double screenWidth = 1080,
}) async {
  tester.view.physicalSize = Size(screenWidth, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ComposePage(
        accountEmail: 'alice@outlook.com',
        suggestions: suggestions,
        contactPicker: picker,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 没有联系人选择需求时的简写 —— 选择器一律返回「取消」。
Future<void> _pumpComposeOnly(
  WidgetTester tester, {
  List<ComposeContact> suggestions = const <ComposeContact>[],
  double screenWidth = 1080,
}) {
  return _pumpComposeWithPicker(
    tester,
    () async => const ContactPick(ContactPickStatus.cancelled),
    suggestions: suggestions,
    screenWidth: screenWidth,
  );
}

/// 往某一栏敲一个地址并落成胶囊（回车即提交，等价于用户敲 Enter）。
Future<void> _typeRecipient(
  WidgetTester tester,
  String fieldName,
  String address,
) async {
  await tester.enterText(find.byKey(Key('compose-$fieldName-field')), address);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  test('MailAttachment 按 Graph fileAttachment 形状序列化（base64 内容）', () {
    const attachment = MailAttachment(
      name: 'shot.png',
      contentType: 'image/png',
      bytes: <int>[1, 2, 3, 250],
    );
    expect(attachment.size, 4);

    final json = attachment.toJson();
    expect(json['@odata.type'], '#microsoft.graph.fileAttachment');
    expect(json['name'], 'shot.png');
    expect(json['contentType'], 'image/png');
    expect(json['contentBytes'], base64Encode(const <int>[1, 2, 3, 250]));
  });

  testWidgets('收件人右侧按钮：选到联系人的唯一邮箱 → 落成一个胶囊', (WidgetTester tester) async {
    await _pumpComposeWithPicker(
      tester,
      () async =>
          const ContactPick(ContactPickStatus.picked, emails: ['bob@qq.com']),
    );

    await tester.tap(find.byIcon(AppIcons.add));
    await tester.pumpAndSettle();

    // 地址不再是输入框里的一段文字，而是一枚可点开菜单的胶囊。
    expect(
      find.descendant(
        of: find.byKey(const Key('compose-row-to')),
        matching: find.text('bob@qq.com'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('compose-to-field'), skipOffstage: false),
          )
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('已有收件人时再选联系人 → 两枚胶囊并列，不是拼成一串文字', (WidgetTester tester) async {
    await _pumpComposeWithPicker(
      tester,
      () async =>
          const ContactPick(ContactPickStatus.picked, emails: ['c@d.com']),
    );

    await _typeRecipient(tester, 'to', 'a@b.com');
    // 聚焦收件人不再展开抄送 / 密送，故此刻只有收件人这一个「+」；按 key 更稳妥。
    await tester.tap(find.byKey(const Key('compose-to-pick')));
    await tester.pumpAndSettle();

    expect(find.text('a@b.com'), findsOneWidget);
    expect(find.text('c@d.com'), findsOneWidget);
    // 旧实现是「a@b.com; c@d.com」一整串，现在各自成胶囊。
    expect(find.text('a@b.com; c@d.com'), findsNothing);
  });

  testWidgets('收件人光标紧跟胶囊：行尾余量够就同一行，不够才另起一行', (WidgetTester tester) async {
    // 测试字体每个字都是 fontSize 见方（比真机字体宽近一倍）。screenWidth 是物理
    // 像素（÷dpr 3 才是逻辑宽），取 1260 → 逻辑 420，正好落在「一枚胶囊 + 输入框
    // 同排、两枚胶囊把行尾余量挤破最小可用宽度（40）而换行」的区间 —— 比原 1440 更
    // 贴真机：那宽度下两枚胶囊后余量仍上百，阈值收紧后不再换行，断言会失准。
    await _pumpComposeOnly(tester, screenWidth: 1260);
    await _typeRecipient(tester, 'to', 'a@b.com');

    Rect chipOf(String label) => tester.getRect(
      find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first,
    );
    final input = find.byKey(const Key('compose-to-field'));
    final chip = chipOf('a@b.com');
    var box = tester.getRect(input);

    // 光标（输入框）紧跟在胶囊后面、同一行：原来输入框在 `Wrap` 里会铺满整行宽，
    // 只要前面有一枚胶囊就挤不下 —— 收件人在这一行、光标被推到下一行。
    expect(box.left, closeTo(chip.right + 8, 0.5));
    expect(box.center.dy, closeTo(chip.center.dy, 0.5));
    // 行尾余量都归它 —— 一直铺到右侧「+」，胶囊右边那片空白也能点出光标。
    expect(
      box.right,
      closeTo(
        tester.getRect(find.byKey(const Key('compose-to-pick'))).left,
        0.5,
      ),
    );

    // 再填一个：两枚胶囊占掉这一行，余量不足最小可用宽度 → 整行让给输入框。
    await _typeRecipient(tester, 'to', 'c@d.com');
    box = tester.getRect(input);
    expect(box.top, greaterThanOrEqualTo(chipOf('c@d.com').bottom));
    expect(box.left, closeTo(chipOf('a@b.com').left, 0.5));
  });

  testWidgets('联系人有多个邮箱 → 弹层二次选择，选中的那个才落成胶囊', (WidgetTester tester) async {
    await _pumpComposeWithPicker(
      tester,
      () async => const ContactPick(
        ContactPickStatus.picked,
        emails: ['work@qq.com', 'home@qq.com'],
      ),
    );

    await tester.tap(find.byIcon(AppIcons.add));
    await tester.pumpAndSettle();

    // 不默认取第一个 —— 挑错地址等于发错人。
    expect(find.text('选择邮箱地址'), findsOneWidget);
    await tester.tap(find.text('home@qq.com'));
    await tester.pumpAndSettle();

    expect(find.text('home@qq.com'), findsOneWidget);
    expect(find.text('work@qq.com'), findsNothing);
  });

  testWidgets('联系人没邮箱 / 没通讯录权限 → 就地提示，收件人不变', (WidgetTester tester) async {
    await _pumpComposeWithPicker(
      tester,
      () async => const ContactPick(ContactPickStatus.picked),
    );
    await tester.tap(find.byIcon(AppIcons.add));
    await tester.pumpAndSettle();
    expect(find.text('该联系人没有邮箱地址'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('compose-to-field')))
          .controller
          ?.text,
      isEmpty,
    );

    await _pumpComposeWithPicker(
      tester,
      () async => const ContactPick.denied(),
    );
    await tester.tap(find.byIcon(AppIcons.add));
    await tester.pumpAndSettle();
    expect(find.textContaining('没有通讯录权限'), findsOneWidget);
  });

  testWidgets('输入提示：按名称 / 地址模糊匹配，点提示项即落成胶囊', (WidgetTester tester) async {
    await _pumpComposeOnly(
      tester,
      suggestions: const [
        ComposeContact(address: 'noreply@baipiao.org', name: '白嫖社区'),
        ComposeContact(address: 'noreply@github.com', name: 'GitHub'),
      ],
    );

    // 匹配地址片段 —— 提示卡里名称在上、邮箱在下。
    await tester.enterText(
      find.byKey(const Key('compose-to-field')),
      'baipiao',
    );
    await tester.pumpAndSettle();
    expect(find.text('白嫖社区'), findsOneWidget);
    expect(find.text('noreply@baipiao.org'), findsOneWidget);
    // 没匹配上的候选不出现。
    expect(find.text('GitHub'), findsNothing);

    await tester.tap(find.text('白嫖社区'));
    await tester.pumpAndSettle();

    // 提示卡收起、输入框清空，人变成胶囊（胶囊显示名称）。
    expect(find.text('noreply@baipiao.org'), findsNothing);
    expect(find.text('白嫖社区'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('compose-to-field')))
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('输入提示：已经填过的人不再提示', (WidgetTester tester) async {
    await _pumpComposeOnly(
      tester,
      suggestions: const [ComposeContact(address: 'bob@qq.com', name: 'Bob')],
    );

    await _typeRecipient(tester, 'to', 'bob@qq.com');
    await tester.enterText(find.byKey(const Key('compose-to-field')), 'bob');
    await tester.pumpAndSettle();

    // 胶囊显示的是名称还是地址取决于候选有没有名字；这里是手敲的地址，
    // 故只应看到胶囊上的地址，不该再冒出一张写着 Bob 的提示卡。
    expect(find.text('Bob'), findsNothing);
  });

  testWidgets('点收件人胶囊 → 菜单「移至抄送」把人挪到抄送栏', (WidgetTester tester) async {
    await _pumpComposeOnly(tester);

    await _typeRecipient(tester, 'to', 'bob@qq.com');
    await tester.tap(find.text('bob@qq.com'));
    await tester.pumpAndSettle();

    // 四项菜单（在收件人栏里，故「移至」只给抄送 / 密送）。
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('移至抄送'), findsOneWidget);
    expect(find.text('移至密送'), findsOneWidget);
    expect(find.text('移至收件人'), findsNothing);

    await tester.tap(find.text('移至抄送'));
    await tester.pumpAndSettle();

    // 人在抄送栏里；收件人栏空了 → 发送按钮重新置灰。
    expect(
      find.descendant(
        of: find.byKey(const Key('compose-row-cc')),
        matching: find.text('bob@qq.com'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('compose-row-to')),
        matching: find.text('bob@qq.com'),
      ),
      findsNothing,
    );
  });

  testWidgets('点收件人胶囊 → 菜单「编辑」把地址放回输入框', (WidgetTester tester) async {
    await _pumpComposeOnly(tester);

    await _typeRecipient(tester, 'to', 'bob@qq.com');
    await tester.tap(find.text('bob@qq.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('compose-to-field')))
          .controller
          ?.text,
      'bob@qq.com',
    );
  });

  testWidgets('抄送 / 密送：点发件人那行才展开，聚焦收件人不展开；空着失焦自动收回', (
    WidgetTester tester,
  ) async {
    await _pumpComposeOnly(tester);

    // 初始折叠成一行「抄送/密送, 发件人：」。
    expect(find.text('抄送/密送, 发件人：'), findsOneWidget);
    expect(find.text('抄　送：'), findsNothing);

    // 聚焦收件人**不再**展开 —— 点收件人只为编辑收件人。
    await tester.tap(find.byKey(const Key('compose-to-field')));
    await tester.pumpAndSettle();
    expect(find.text('抄送/密送, 发件人：'), findsOneWidget);
    expect(find.text('抄　送：'), findsNothing);

    // 点折叠行（设计稿的「发件人」列）才展开抄送 / 密送 / 发件人三行。
    await tester.tap(find.byKey(const Key('compose-row-ccfrom')));
    await tester.pumpAndSettle();
    expect(find.text('抄　送：'), findsOneWidget);
    expect(find.text('密　送：'), findsOneWidget);
    expect(find.text('发件人：'), findsOneWidget);
    expect(find.text('抄送/密送, 发件人：'), findsNothing);

    // 没填任何内容、焦点离开收件栏 → 自动收回折叠行。
    await tester.tap(find.byKey(const Key('compose-body-field')));
    await tester.pumpAndSettle();
    expect(find.text('抄送/密送, 发件人：'), findsOneWidget);
    expect(find.text('抄　送：'), findsNothing);
  });

  testWidgets('填了抄送 → 即使失焦也不折叠（否则等于把人藏起来）', (WidgetTester tester) async {
    await _pumpComposeOnly(tester);

    // 点发件人行展开后填一个抄送。
    await tester.tap(find.byKey(const Key('compose-row-ccfrom')));
    await tester.pumpAndSettle();
    await _typeRecipient(tester, 'cc', 'cc@qq.com');
    await tester.tap(find.byKey(const Key('compose-body-field')));
    await tester.pumpAndSettle();

    expect(find.text('抄　送：'), findsOneWidget);
    expect(find.text('cc@qq.com'), findsOneWidget);
  });

  testWidgets('页面可上滑：正文短时不滚，变长后整页能滚', (WidgetTester tester) async {
    await _pumpComposeOnly(tester);

    // 正文 TextField 自己也带一个 Scrollable，取最外层那个（树序在前）。
    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    // 正文用 `SliverFillRemaining(hasScrollBody: false)` 兜底：内容装得下时正好占满
    // 剩余高度，一格也滚不动。
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      0,
    );

    await tester.enterText(
      find.byKey(const Key('compose-body-field')),
      List<String>.filled(60, '正文很长').join('\n'),
    );
    await tester.pumpAndSettle();

    // 表单 / 附件 / 正文同在一条滚动条里 —— 正文撑长后上滑就能把收件人那几行滚走。
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      greaterThan(0),
    );
  });

  testWidgets('底栏四格等宽：撤销 / 重做 / Aa / 图片 中心等距', (WidgetTester tester) async {
    await _pumpCompose(tester, FakeMailApi());

    // 「Aa」是文字、其余是图标，内容宽度天然不同；等宽靠格子而非内容。
    final centers = <double>[
      tester.getCenter(find.byIcon(AppIcons.undo)).dx,
      tester.getCenter(find.byIcon(AppIcons.redo)).dx,
      tester.getCenter(find.text('Aa')).dx,
      tester.getCenter(find.byIcon(AppIcons.image)).dx,
    ];
    final gaps = [
      centers[1] - centers[0],
      centers[2] - centers[1],
      centers[3] - centers[2],
    ];
    for (final gap in gaps) {
      expect(gap, closeTo(gaps.first, 0.5));
    }
    // 四格铺满整宽：首格与末格中心到两侧边距相等（各 1/8 屏宽）。
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(centers.first, closeTo(width - centers.last, 0.5));
    expect(gaps.first, closeTo(width / 4, 0.5));
  });

  testWidgets('字号：整行换成横向字号条，选中即生效并切回排版栏', (WidgetTester tester) async {
    await _pumpCompose(tester, FakeMailApi());

    // 入口显示当前字号 16；点开后工具按钮整行让位给字号条。
    await tester.tap(find.text('16'));
    await tester.pumpAndSettle();
    expect(find.byIcon(AppIcons.bold), findsNothing);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('36'), findsOneWidget);

    // 字号条比一屏宽 → 靠左右滑动才能点到末尾的大字号。
    await tester.ensureVisible(find.text('28'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('28'));
    await tester.pumpAndSettle();

    // 选完切回排版栏，入口与正文字号都跟着变。
    expect(find.byIcon(AppIcons.bold), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
    final body = tester.widget<TextField>(find.byType(TextField).last);
    expect(body.style?.fontSize, 28);
  });

  testWidgets('文字颜色：整行换成横向色点条，选中即生效并切回排版栏', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpCompose(tester, api);

    await tester.tap(find.byIcon(AppIcons.textColor));
    await tester.pumpAndSettle();

    // 五个色点（首项「跟随主题」），排版按钮已让位。
    expect(find.byIcon(AppIcons.bold), findsNothing);
    final dots = find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxWidth == 32,
    );
    expect(dots, findsNWidgets(5));

    await tester.tap(dots.at(2));
    await tester.pumpAndSettle();

    // 切回排版栏；选了非默认色 → 发信按 HTML 走并带上 color。
    expect(find.byIcon(AppIcons.bold), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'a@b.com');
    await tester.enterText(find.byType(TextField).last, '带色正文');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pumpAndSettle();

    expect(api.sentMails, hasLength(1));
    expect(api.sentMails.single.isHtml, isTrue);
    expect(api.sentMails.single.body, contains('color:'));
  });

  testWidgets('选中一段改字号 / 加粗 → 屏幕上只有那一段变', (WidgetTester tester) async {
    await _pumpComposeOnly(tester);
    final body = find.byKey(const Key('compose-body-field'));
    await tester.enterText(body, '选中这段其余不动');
    await tester.pumpAndSettle();

    // 选中前三个字（widget 测试拖不动系统选择手柄，直接设选区）。
    final controller = tester.widget<TextField>(body).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.bold));
    await tester.pumpAndSettle();
    // 字号入口显示的是光标处的字号；点开条子挑 28。
    await tester.tap(find.text('16'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('28'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('28'));
    await tester.pumpAndSettle();

    // `EditableText` 每帧就是拿这棵 span 去画的（`TextField.style` 当基础样式）。
    final spans = controller
        .buildTextSpan(
          context: tester.element(body),
          style: const TextStyle(fontSize: 16),
          withComposing: false,
        )
        .children!
        .cast<TextSpan>();
    expect(spans.map((s) => s.text), ['选中这', '段其余不动']);
    expect(spans.first.style?.fontWeight, FontWeight.w700);
    expect(spans.first.style?.fontSize, 28);
    // 没选中的那半截原样 —— 原来是整篇一起变，这正是要治的毛病。
    expect(spans.last.style?.fontWeight, FontWeight.w400);
    expect(spans.last.style?.fontSize, 16);
  });

  testWidgets('选中一段加粗 → 只有那一段带 span 发出去', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpCompose(tester, api);
    await _typeRecipient(tester, 'to', 'bob@qq.com');

    final body = find.byKey(const Key('compose-body-field'));
    await tester.enterText(body, '加粗这段其余不动');
    await tester.pumpAndSettle();
    tester.widget<TextField>(body).controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(AppIcons.bold));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pumpAndSettle();

    final sent = api.sentMails.single;
    expect(sent.isHtml, isTrue);
    expect(
      sent.body,
      contains('<span style="font-weight:700">加粗这</span>段其余不动'),
    );
  });

  testWidgets('没选中文字时点加粗 → 只有接下来打的字变粗', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpCompose(tester, api);
    await _typeRecipient(tester, 'to', 'bob@qq.com');
    await tester.enterText(find.byKey(const Key('compose-body-field')), '原样');
    await tester.pumpAndSettle();

    // 光标在末尾、没有选区 —— 这一下只该定下「接着打的字用粗体」。
    await tester.tap(find.byIcon(AppIcons.bold));
    await tester.pumpAndSettle();
    // 不用 `enterText`：它会先点一下正文，可能挪动光标（挪了就等于放弃刚设的格式），
    // 而真机上用户是接着往下打、键盘连接一直没断。
    tester.testTextInput.enterText('原样加粗');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pumpAndSettle();

    expect(
      api.sentMails.single.body,
      contains('原样<span style="font-weight:700">加粗</span>'),
    );
  });

  testWidgets('排版栏可左右滑动：对齐三格在内、「×」固定在最右', (WidgetTester tester) async {
    await _pumpCompose(tester, FakeMailApi());

    // 排版项多于一屏 → 滚动区把它们全建出来（含设计稿新增的缩进与对齐）。
    expect(find.byIcon(AppIcons.indentIncrease), findsOneWidget);
    expect(find.byIcon(AppIcons.indentDecrease), findsOneWidget);
    expect(find.byIcon(AppIcons.alignLeft), findsOneWidget);
    expect(find.byIcon(AppIcons.alignCenter), findsOneWidget);
    expect(find.byIcon(AppIcons.alignRight), findsOneWidget);

    // 「×」不在滚动区里：把滚动区拉到最左，它仍在视口内可直接点。
    await tester.drag(find.byIcon(AppIcons.bold), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.byIcon(AppIcons.close), findsOneWidget);

    // 点「×」收起排版栏，「Aa」可重新唤出。
    await tester.tap(find.byIcon(AppIcons.close));
    await tester.pumpAndSettle();
    expect(find.byIcon(AppIcons.alignLeft), findsNothing);
    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();
    expect(find.byIcon(AppIcons.alignLeft), findsOneWidget);
  });

  testWidgets('缩进按钮：光标所在行行首增删一个缩进单位', (WidgetTester tester) async {
    await _pumpCompose(tester, FakeMailApi());
    await tester.enterText(find.byKey(const Key('compose-body-field')), '第一行');
    await tester.pumpAndSettle();

    // 排版项超一屏，先滑到按钮再点。
    await tester.ensureVisible(find.byIcon(AppIcons.indentIncrease));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(AppIcons.indentIncrease));
    await tester.pumpAndSettle();
    expect(find.text('    第一行'), findsOneWidget);

    await tester.tap(find.byIcon(AppIcons.indentDecrease));
    await tester.pumpAndSettle();
    expect(find.text('第一行'), findsOneWidget);
  });

  testWidgets('选居中对齐 → 发信改走 HTML 并带 text-align', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpCompose(tester, api);

    await tester.enterText(
      find.byKey(const Key('compose-to-field')),
      'bob@outlook.com',
    );
    await tester.enterText(find.byKey(const Key('compose-body-field')), '正文');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byIcon(AppIcons.alignCenter));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(AppIcons.alignCenter));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pumpAndSettle();

    // 对齐不是纯文本能表达的 → 自动切 HTML，样式内联在外层 div 上。
    final sent = api.sentMails.single;
    expect(sent.isHtml, true);
    expect(sent.body, contains('text-align:center'));
    expect(sent.body, contains('正文'));
    // 没选附件 → 不下发 attachments。
    expect(sent.attachments, isEmpty);
  });

  testWidgets('抄送 / 密送随发信一起下发给 Graph', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpCompose(tester, api);

    await _typeRecipient(tester, 'to', 'to@qq.com');
    // 抄送 / 密送要先点发件人行展开才能输入。
    await tester.tap(find.byKey(const Key('compose-row-ccfrom')));
    await tester.pumpAndSettle();
    await _typeRecipient(tester, 'cc', 'cc@qq.com');
    await _typeRecipient(tester, 'bcc', 'bcc@qq.com');
    await tester.enterText(find.byKey(const Key('compose-body-field')), '正文');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pumpAndSettle();

    final sent = api.sentMails.single;
    expect(sent.to, ['to@qq.com']);
    expect(sent.cc, ['cc@qq.com']);
    expect(sent.bcc, ['bcc@qq.com']);
  });
}
