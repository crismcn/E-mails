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

/// 直接挂一个 [ComposePage]，注入假的联系人选择器。
///
/// 选联系人本身走平台通道（widget 测试碰不到），故只把「选完之后」的逻辑
/// 抽成注入点来验证：多地址二次选择、拼进收件人框、各种失败提示。
Future<void> _pumpComposeWithPicker(
  WidgetTester tester,
  ContactEmailPicker picker,
) async {
  tester.view.physicalSize = const Size(1080, 2340);
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
        contactPicker: picker,
      ),
    ),
  );
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

  testWidgets('收件人右侧按钮：选到联系人的唯一邮箱 → 填进收件人框', (WidgetTester tester) async {
    await _pumpComposeWithPicker(
      tester,
      () async =>
          const ContactPick(ContactPickStatus.picked, emails: ['bob@qq.com']),
    );

    await tester.tap(find.byIcon(AppIcons.add));
    await tester.pumpAndSettle();

    final to = tester.widget<TextField>(
      find.byKey(const Key('compose-to-field')),
    );
    expect(to.controller?.text, 'bob@qq.com');
  });

  testWidgets('已有收件人时再选联系人 → 用「; 」追加', (WidgetTester tester) async {
    await _pumpComposeWithPicker(
      tester,
      () async =>
          const ContactPick(ContactPickStatus.picked, emails: ['c@d.com']),
    );

    await tester.enterText(
      find.byKey(const Key('compose-to-field')),
      'a@b.com',
    );
    await tester.tap(find.byIcon(AppIcons.add));
    await tester.pumpAndSettle();

    final to = tester.widget<TextField>(
      find.byKey(const Key('compose-to-field')),
    );
    expect(to.controller?.text, 'a@b.com; c@d.com');
  });

  testWidgets('联系人有多个邮箱 → 弹层二次选择，选中的那个才填进去', (WidgetTester tester) async {
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

    final to = tester.widget<TextField>(
      find.byKey(const Key('compose-to-field')),
    );
    expect(to.controller?.text, 'home@qq.com');
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
}
