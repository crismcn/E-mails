import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:email_manager/theme/app_icons.dart';
import 'package:email_manager/api/api_service.dart';
import 'package:email_manager/api/mail_api.dart';
import 'package:email_manager/core/auth/credentials_store.dart';
import 'package:email_manager/core/network/api_code.dart';
import 'package:email_manager/core/network/api_response.dart';
import 'package:email_manager/main.dart';
import 'package:email_manager/settings/settings_controller.dart';

import 'fake_mail_api.dart';

const AccountCredentials _kAlice = AccountCredentials(
  email: 'alice@outlook.com',
  clientId: 'c',
  refreshToken: 'r',
);

/// 打开「首页 → 邮件列表」，邮件数据来自注入的 [FakeMailApi]。
Future<void> _pumpMailList(WidgetTester tester, FakeMailApi mailApi) async {
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
        credentialsStore: InMemoryCredentialsStore(const [_kAlice]),
        mailApi: mailApi,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('alice@outlook.com'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('邮件列表渲染 Graph 返回的发件人与主题', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpMailList(tester, api);

    // 首屏只拉一页，且 skip 从 0 开始。
    expect(api.skips, [0]);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('Claude 任务执行通知 · ✅ 任务已完成'), findsOneWidget);
    expect(find.text('蓝湖官方'), findsOneWidget);
    // 未读消息显示角标「1」（单封消息未读数为 1）。
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('首屏加载失败：整页展示原始错误 + 重试可恢复', (WidgetTester tester) async {
    final failing = FakeMailApi(
      failure: const ApiResponse<GraphMessagePage>.failure(
        ApiCode.unauthorized,
        'AADSTS70000: 授权无效',
      ),
    );
    await _pumpMailList(tester, failing);

    expect(find.text('邮件加载失败'), findsOneWidget);
    // 原始错误原样展示 —— 它是定位 scope/租户问题的唯一线索。
    expect(find.text('AADSTS70000: 授权无效'), findsOneWidget);
    expect(find.text('Claude'), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    // 重试确实又打了一次请求（仍失败，错误页保留）。
    expect(failing.skips, [0, 0]);
    expect(find.text('邮件加载失败'), findsOneWidget);
  });

  testWidgets('账号无邮件时展示空态', (WidgetTester tester) async {
    await _pumpMailList(tester, FakeMailApi(messages: const []));

    expect(find.text('暂无邮件'), findsOneWidget);
    expect(find.text('邮件加载失败'), findsNothing);
  });

  testWidgets('搜索框过滤已加载的邮件', (WidgetTester tester) async {
    await _pumpMailList(tester, FakeMailApi());

    await tester.enterText(find.byType(EditableText).last, 'cursor');
    await tester.pumpAndSettle();

    expect(find.text('Cursor Team'), findsOneWidget);
    expect(find.text('Claude'), findsNothing);
  });

  testWidgets('上滑加载更多：按已加载条数续拉下一页并追加', (WidgetTester tester) async {
    // 首页满 20 条才认为还有下一页；共 25 条 → 第二页 5 条后无更多。
    final api = FakeMailApi(
      messages: [
        for (var i = 0; i < 25; i++)
          fakeGraphMessage(id: 'm$i', fromName: '发件人$i', subject: '主题$i'),
      ],
    );
    await _pumpMailList(tester, api);
    expect(api.skips, [0]);

    await tester.fling(
      find.byType(Scrollable).last,
      const Offset(0, -600),
      1500,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    // easy_refresh 的 processedDuration 是一次性 Timer，pumpAndSettle 不会抽干。
    await tester.pump(const Duration(milliseconds: 400));

    // $skip 用「已加载条数」而非页号 —— 第二页从 20 开始。
    expect(api.skips, [0, 20]);
    // 第 21 条（第二页首条）已进入列表：ListView 懒构建，用搜索过滤到它再断言。
    // 断言发件人而非主题 —— 主题文字此刻也在搜索框里，会匹配到两个 widget。
    await tester.enterText(find.byType(EditableText).last, '主题20');
    await tester.pumpAndSettle();
    expect(find.text('发件人20'), findsOneWidget);
  });

  testWidgets('左滑标记已读：乐观更新 + PATCH 回写 Graph', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpMailList(tester, api);

    // 初始两封未读（Claude m1 + 蓝湖 c3-3），各显示角标「1」。
    expect(find.text('1'), findsNWidgets(2));

    // 左滑 Claude 一行露出动作面板，点「标记已读」。
    await tester.drag(find.text('Claude'), const Offset(-320, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(AppIcons.unread).first);
    await tester.pumpAndSettle();

    // 回写记录到 Graph：m1 → isRead true。
    expect(api.readUpdates, [('m1', true)]);
    expect(find.text('已标记为已读'), findsOneWidget);
    // Claude 变已读 → 未读只剩 1（蓝湖）：顶部未读徽标「1」+ 蓝湖角标「1」共 2 处。
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('左滑标记已读失败：回滚本地状态并提示', (WidgetTester tester) async {
    final api = FakeMailApi()..updateReadFails = true;
    await _pumpMailList(tester, api);
    expect(find.text('1'), findsNWidgets(2));

    await tester.drag(find.text('Claude'), const Offset(-320, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(AppIcons.unread).first);
    await tester.pumpAndSettle();

    // 发起过写回，但失败 → 提示操作失败、未读角标回滚为 2。
    expect(api.readUpdates, [('m1', true)]);
    expect(find.textContaining('操作失败'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('点击未读邮件进入详情 → 自动标记已读并回写 Graph', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpMailList(tester, api);
    // 初始两封未读（Claude m1 + 蓝湖 c3-3）。
    expect(find.text('1'), findsNWidgets(2));

    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    // 打开即回写：m1 → isRead true。
    expect(api.readUpdates, [('m1', true)]);

    // 返回列表：Claude 未读已清，未读只剩 1（蓝湖）：顶部徽标 + 角标共 2 处「1」。
    await tester.tap(find.byIcon(AppIcons.back));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('点击已读邮件进入详情 → 不重复回写', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpMailList(tester, api);

    // Cursor Team（m2）本就已读，打开不应触发写回。
    await tester.tap(find.text('Cursor Team'));
    await tester.pumpAndSettle();

    expect(api.readUpdates, isEmpty);
  });

  testWidgets('点击顶部标题复制邮箱号到剪贴板', (WidgetTester tester) async {
    // 拦截剪贴板平台通道，记录写入内容。
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    String? copied;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await _pumpMailList(tester, FakeMailApi());

    // 顶部标题即账号邮箱（列表项里也有同名文本，取第一个 = 标题）。
    await tester.tap(find.text('alice@outlook.com').first);
    await tester.pumpAndSettle();

    expect(copied, 'alice@outlook.com');
    expect(find.text('已复制邮箱号'), findsOneWidget);
  });

  testWidgets('顶部展示文件夹名与未读徽标 + 点击弹出抽屉切换未读视图', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpMailList(tester, api);

    // 首屏默认收件箱：标题即「收件箱」，未拉过其它文件夹。
    expect(find.text('收件箱'), findsOneWidget);
    expect(api.folders, [MailFolder.inbox]);
    // 未读徽标 = 已加载未读数（假数据 2 封未读）。
    expect(find.text('2'), findsOneWidget);

    // 点击标题弹出抽屉：菜单项出现（收件箱在标题+抽屉里各一个 = 2）。
    await tester.tap(find.text('收件箱'));
    await tester.pumpAndSettle();
    expect(find.text('收件箱'), findsNWidgets(2));
    expect(find.text('未读邮件'), findsOneWidget);
    expect(find.text('已标星'), findsOneWidget);
    expect(find.text('已发送'), findsOneWidget);

    // 选「未读邮件」：切换文件夹、重新拉取、标题更新、抽屉收起。
    await tester.tap(find.text('未读邮件'));
    await tester.pumpAndSettle();
    expect(api.folders.last, MailFolder.unread);
    expect(find.text('未读邮件'), findsOneWidget); // 仅标题（抽屉已收起）
  });

  testWidgets('点击添加按钮进入新建邮件页', (WidgetTester tester) async {
    await _pumpMailList(tester, FakeMailApi());

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // 新建邮件页核心元素：标题 + 各表单标签 + 发件人回填当前账号。
    expect(find.text('新建邮件'), findsOneWidget);
    expect(find.text('收件人：'), findsOneWidget);
    expect(find.text('主　题：'), findsOneWidget);
    expect(find.text('alice@outlook.com'), findsOneWidget);
  });

  testWidgets('新建邮件页：填收件人后发送 → 调 Graph 并返回列表', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpMailList(tester, api);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // 未填收件人时发送按钮置灰不可点，不会发请求。
    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pump();
    expect(api.sentMails, isEmpty);

    // 填收件人 + 主题 + 正文后发送。
    await tester.enterText(
      find.byKey(const Key('compose-to-field')),
      'bob@outlook.com',
    );
    await tester.enterText(
      find.byKey(const Key('compose-subject-field')),
      '你好',
    );
    await tester.enterText(find.byKey(const Key('compose-body-field')), '正文内容');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pumpAndSettle();

    // 发信参数正确、纯文本、正常重要性；发送成功后返回列表页。
    expect(api.sentMails.length, 1);
    final sent = api.sentMails.first;
    expect(sent.email, 'alice@outlook.com');
    expect(sent.to, ['bob@outlook.com']);
    expect(sent.subject, '你好');
    expect(sent.body, '正文内容');
    expect(sent.isHtml, false);
    expect(sent.importance, 'normal');
    expect(find.text('已发送'), findsOneWidget);
    // 已回到列表页（新建邮件标题不在树中）。
    expect(find.text('新建邮件'), findsNothing);
  });

  testWidgets('新建邮件页：收件人格式非法则拦截', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpMailList(tester, api);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('compose-to-field')),
      'not-an-email',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pump();

    expect(find.textContaining('收件人邮箱格式有误'), findsOneWidget);
    expect(api.sentMails, isEmpty);
  });

  testWidgets('新建邮件页：发信失败则留在原页并提示', (WidgetTester tester) async {
    final api = FakeMailApi()..sendMailFails = true;
    await _pumpMailList(tester, api);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('compose-to-field')),
      'bob@outlook.com',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pumpAndSettle();

    expect(api.sentMails.length, 1);
    expect(find.textContaining('发送失败'), findsOneWidget);
    // 仍在新建邮件页。
    expect(find.text('新建邮件'), findsOneWidget);
  });

  testWidgets('顶部未读徽标用服务端计数（而非已加载条数）', (WidgetTester tester) async {
    // 服务端说收件箱有 85 封未读，而本页只加载了 3 封（其中 2 封未读）。
    final api = FakeMailApi(
      folderStats: const {'inbox': MailFolderStats(unread: 85, total: 120)},
    );
    await _pumpMailList(tester, api);

    // 取的是 inbox 文件夹计数，徽标显示 85 而非本地的 2。
    expect(api.statsFolders, ['inbox']);
    expect(find.text('85'), findsOneWidget);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('服务端计数取不到时退回本地已加载未读数', (WidgetTester tester) async {
    final api = FakeMailApi()..folderStatsFails = true;
    await _pumpMailList(tester, api);

    // 请求发过但失败 → 徽标退回本地计数 2，不整页报错。
    expect(api.statsFolders, ['inbox']);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('邮件加载失败'), findsNothing);
  });

  testWidgets('切到已发送取 sentitems 计数；已标星无对应文件夹则不请求', (WidgetTester tester) async {
    final api = FakeMailApi();
    await _pumpMailList(tester, api);
    expect(api.statsFolders, ['inbox']);

    // 已发送 → 取 sentitems 文件夹计数。
    await tester.tap(find.text('收件箱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已发送'));
    await tester.pumpAndSettle();
    expect(api.statsFolders, ['inbox', 'sentitems']);

    // 已标星是跨文件夹过滤视图，没有文件夹可查 → 不再新增计数请求。
    await tester.tap(find.text('已发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已标星'));
    await tester.pumpAndSettle();
    expect(api.statsFolders, ['inbox', 'sentitems']);
  });
}
