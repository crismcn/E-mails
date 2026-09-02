import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        BoxHitTestResult,
        ContainerBoxParentData,
        ContainerRenderObjectMixin,
        RenderBoxContainerDefaultsMixin;

import '../api/api_scope.dart';
import '../api/mail_api.dart';
import '../core/contacts/contact_picker.dart';
import '../data/compose_rich_text.dart';
import '../data/mail_mapper.dart';
import '../l10n/app_localizations.dart';
import '../models/mail.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../widgets/app_menu.dart';

/// 邮件重要性 —— 与 Graph `message.importance`（high / normal / low）一一对应。
enum MailImportance { high, normal, low }

extension MailImportanceLabel on MailImportance {
  String label(AppLocalizations l10n) => switch (this) {
    MailImportance.high => l10n.composeImportanceHigh,
    MailImportance.normal => l10n.composeImportanceNormal,
    MailImportance.low => l10n.composeImportanceLow,
  };

  /// Graph `message.importance` 取值（high / normal / low）。
  String get graphValue => name;
}

/// 排版栏当前展示的内容 —— 选字号 / 颜色时，整行原地换成横向选项条。
enum _FormatPanel { tools, fontSize, color }

/// 三个收件栏 —— 收件人 / 抄送 / 密送，三者结构完全一样，只是标签与去向不同。
enum _Field { to, cc, bcc }

/// 点收件人胶囊后弹出的菜单项。
enum _ChipAction { delete, edit, toTo, toCc, toBcc }

/// 新建邮件页 —— 视觉 1:1 参照「新建邮件.jpg」「新建邮件-工具栏.jpg」与 `UI/` 下的
/// 收件人 / 发件人四张图。
///
/// 结构：顶栏（返回 / 标题 / 附件 / 发送）+ 表单（收件人 / 抄送 / 密送 / 发件人 /
/// 重要性 / 主题）+ 附件条（有附件时才出现）+ 正文编辑区 + 底部两条工具栏
/// （排版栏 + 撤销·重做·Aa·图片）。
///
/// **表单 + 附件 + 正文同在一条滚动条里**（`CustomScrollView`）：键盘弹起时视口变矮，
/// 上滑就能把收件人那几行滚走，把整屏留给正文。正文用
/// `SliverFillRemaining(hasScrollBody: false)` 兜底 —— 内容少时至少占满剩余高度
/// （点空白处也能落焦点），多了就把页面撑长。
///
/// **收件人三栏的三种形态**（见 `UI/收件人-*.jpg`、`UI/发件人-*.jpg`）：
/// - **聚焦**：已填的人是灰色胶囊（[_RecipientChip]），**输入框紧跟在最后一枚胶囊后面**
///   、吃掉那一行剩下的宽度（[_ChipsInput]）；输入时下方浮出
///   候选提示卡（[_SuggestionCard]）；点胶囊弹「删除 / 编辑 / 移至抄送 / 移至密送」。
/// - **未聚焦且已填**：折叠成一行主色文字（省地方，设计稿如此），点一下回到聚焦态。
/// - **未聚焦且为空**：留着输入框，光标随时可落。
/// 右侧 `+`（选系统联系人）只在**聚焦或该栏为空**时出现 —— 折叠成一行文字时设计稿没有它。
///
/// **抄送 / 密送整行的显隐**：抄送 / 密送都空、且用户没点开时，三行折叠成一行
/// 「抄送/密送, 发件人：<账号>」（`UI/发件人-无抄送&密送.jpg`）；**点这一行**（设计稿里
/// 的「发件人」列）或已填了抄送 / 密送，就展开成抄送 / 密送 / 发件人三行
/// （`UI/发件人-点击发件人输入框.jpg`）。刻意不再让「聚焦收件人」触发展开 —— 点收件人
/// 只为编辑收件人（用户反馈）；展开后没填任何内容、焦点又离开收件栏，会自动收回折叠行
/// （监听 `FocusManager` 的 primary focus 变化，见 [_ComposePageState._onPrimaryFocusChanged]）。
///
/// 排版工具栏：字号 / 加粗 / 斜体 / 下划线 / 颜色是**选区级**的 —— 选中一段再点，
/// 只有那一段变（逐字格式表 + 自绘 `TextSpan`，见 [_RichBodyController]）；没有选区
/// 时设的是「接下来要打的字」。对齐仍是整篇的（`TextField.textAlign`），两个列表按钮
/// 在光标所在行行首插入 `• ` / `N. ` 前缀，缩进按钮同理增删行首空格。排版项多于一屏，
/// 故排版栏可左右滑动，「×」用竖线隔开固定在最右侧（设计稿如此）。
///
/// 附件走 Graph 的小附件形式（base64 内嵌进 sendMail），原始字节总量上限
/// [_ComposePageState._kMaxAttachBytes]。
class ComposePage extends StatefulWidget {
  const ComposePage({
    super.key,
    required this.accountEmail,
    this.suggestions = const <ComposeContact>[],
    this.contactPicker = pickSystemContactEmails,
  });

  /// 发件账号 —— 顶部「发件人」处展示，发信时作为 from。
  final String accountEmail;

  /// 收件人输入提示的候选池 —— 由邮件列表页把**已加载的发件人**（名称 + 地址）传进来。
  /// 刻意不在这里打接口 / 读系统通讯录：候选只是打字时的便利，不该拖慢或要权限。
  final List<ComposeContact> suggestions;

  /// 选系统联系人的那一步 —— 默认走平台通道，测试注入假实现。
  final ContactEmailPicker contactPicker;

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  /// 三栏已填好的人 —— 胶囊按这个列表渲染，发信时取它们的地址。
  final Map<_Field, List<ComposeContact>> _picked = {
    for (final field in _Field.values) field: <ComposeContact>[],
  };

  /// 三栏各自的「正在输入」那一小段文字（还没变成胶囊的部分）。
  final Map<_Field, TextEditingController> _input = {
    for (final field in _Field.values) field: TextEditingController(),
  };

  final Map<_Field, FocusNode> _node = {
    for (final field in _Field.values) field: FocusNode(),
  };

  /// 候选提示卡挂在哪一栏下面 —— 浮层要跟着这一栏移动。
  final Map<_Field, LayerLink> _link = {
    for (final field in _Field.values) field: LayerLink(),
  };

  /// 当前聚焦的收件栏；null = 没在编辑收件人。
  _Field? _active;

  /// 用户点过折叠行「抄送/密送, 发件人」后置 true —— 抄送 / 密送 / 发件人三行随之展开。
  /// 与「聚焦收件人」解耦：点收件人只编辑收件人，不再顺带把这三行撑开（用户反馈）。
  /// 展开后**没填任何内容、焦点又离开收件栏**时自动收回（[_onPrimaryFocusChanged]）。
  bool _ccBccExpanded = false;

  /// 候选提示卡 —— 走 [Overlay]，不参与表单布局，弹出时不会把下面几行顶下去。
  OverlayEntry? _suggestionOverlay;

  final TextEditingController _subject = TextEditingController();

  /// 正文 —— 逐字记格式，选区级排版全靠它（见 [_RichBodyController]）。
  final _RichBodyController _body = _RichBodyController();
  final FocusNode _bodyFocus = FocusNode();

  /// 正文的撤销 / 重做 —— 复用 Flutter 自带编辑历史，底部按钮据此置灰。
  final UndoHistoryController _undo = UndoHistoryController();

  MailImportance _importance = MailImportance.normal;

  /// 填了收件人才点亮发送按钮（设计稿里未填时是灰色）。
  bool _canSend = false;

  /// 发送中 —— 顶栏纸飞机换转圈、按钮禁用，避免重复提交。
  bool _sending = false;

  // ---- 正文排版态 ----
  bool _formatBarOpen = true;

  /// 排版栏这一行当前显示什么 —— 工具按钮 / 字号条 / 颜色条。
  _FormatPanel _panel = _FormatPanel.tools;

  /// 排版栏显示的那一套格式 = **光标 / 选区处**的格式（Gmail 同款：光标停在粗体里，
  /// B 就是亮的）。它由 [_RichBodyController.formatAtCursor] 派生，缓存下来只为
  /// 「没变就不重建」—— 否则每敲一个字整页都要重建一次。
  ComposeTextFormat _shownFormat = ComposeTextFormat.plain;

  /// 正文整篇对齐 —— 只用 left / center / right（设计稿三格）。对齐是段落级属性，
  /// 纯文本 `TextField` 只能整篇给，故它不像字号 / 加粗那样按选区走。
  TextAlign _align = TextAlign.left;

  /// 已选附件（原始字节留在内存，发送时才 base64）。
  final List<MailAttachment> _attachments = <MailAttachment>[];

  /// 选附件中 —— 防止连点重复拉起系统选择器。
  bool _picking = false;

  /// 选联系人中 —— 同上，并把收件人右侧按钮置灰。
  bool _pickingContact = false;

  /// 可选字号 —— 条目多于一屏，故字号条要能左右滑。
  static const List<double> _fontSizes = <double>[
    12,
    14,
    16,
    18,
    20,
    22,
    24,
    28,
    32,
    36,
  ];

  /// 附件原始字节总量上限 3MB —— Graph 要求整个 sendMail 请求体 ≤ 4MB，
  /// base64 会放大约 1/3，留出正文与协议头的余量。
  static const int _kMaxAttachBytes = 3 * 1024 * 1024;

  /// 缩进单位 —— 缩进是段落级的，逐字格式表管不着，故用行首空格近似
  /// （HTML 输出靠 `white-space:pre-wrap` 保留）。
  static const String _kIndentUnit = '    ';

  /// 候选提示最多给几条 —— 提示卡是浮层，再多会盖住整张表单。
  static const int _kMaxSuggestions = 4;

  @override
  void initState() {
    super.initState();
    for (final field in _Field.values) {
      _input[field]!.addListener(() => _onInputChanged(field));
      _node[field]!.addListener(() => _onFocusChanged(field));
    }
    _body.addListener(_onBodyFormatChanged);
    // 焦点一变化就检查「抄送 / 密送开着却没填东西」要不要收回 —— 点发件人行展开时
    // 不带任何焦点事件，收回只能靠「焦点后来挪去别处」来察觉。
    FocusManager.instance.addListener(_onPrimaryFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onPrimaryFocusChanged);
    _removeSuggestions();
    for (final field in _Field.values) {
      _input[field]!.dispose();
      _node[field]!.dispose();
    }
    _subject.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    _undo.dispose();
    super.dispose();
  }

  /// 正文的文字 / 光标一动，排版栏要跟着显示**光标处**的格式。
  ///
  /// 只在派生出的格式真的变了时重建：光标在同一段格式里挪动、连续打字都不该让整页重建
  /// （正文自己会重画）。
  void _onBodyFormatChanged() {
    final format = _body.formatAtCursor;
    if (format == _shownFormat) return;
    setState(() => _shownFormat = format);
  }

  /// 开关型格式（粗 / 斜 / 下划线）—— 按当前显示的那一套取反后落到选区。
  ///
  /// 选区里粗细不一时以**选区头一个字**为准（[_shownFormat] 就是它），与系统编辑器一致。
  void _toggleAttribute(ComposeTextAttribute attribute) {
    final on = !_shownFormat.attribute(attribute);
    _body.applyFormat((format) => format.withAttribute(attribute, on));
  }

  /// 抄送 / 密送（以及独立的「发件人」行）要不要展开。
  ///
  /// 用户点过折叠行才展开（[_ccBccExpanded]）；已填过抄送 / 密送时也必须展开 —— 否则
  /// 填进去的人会被折叠行藏起来，等于凭空丢收件人。**不看收件人有没有聚焦**：点收件人
  /// 只为编辑收件人，不该顺带把这三行撑开（用户反馈）；展开后没填内容且失焦会自动收回
  /// （[_onPrimaryFocusChanged]）。
  bool get _ccBccOpen =>
      _ccBccExpanded ||
      _picked[_Field.cc]!.isNotEmpty ||
      _picked[_Field.bcc]!.isNotEmpty;

  /// 输入框内容变了 —— 刷新候选提示，并重算发送按钮亮不亮。
  void _onInputChanged(_Field field) {
    if (field == _Field.to) _refreshCanSend();
    if (_active == field) _refreshSuggestions();
  }

  /// 焦点变了 —— 记住当前栏；离开时把没敲完的那一段落成胶囊。
  ///
  /// 「离开就落地」是为了不丢东西：用户打完地址直接点正文 / 点发送，那段文字也算数。
  void _onFocusChanged(_Field field) {
    final focused = _node[field]!.hasFocus;
    if (focused) {
      setState(() => _active = field);
      _refreshSuggestions();
      return;
    }
    if (_active != field) return;
    _commitPending(field);
    // 焦点可能只是从收件人挪到抄送 —— 下一帧再看是不是真的没人聚焦了，
    // 免得中间闪一下折叠态（会让整个表单跳一下）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final stillActive = _Field.values.any((f) => _node[f]!.hasFocus);
      if (stillActive) return;
      _removeSuggestions();
      setState(() => _active = null);
    });
  }

  /// 任意焦点变化（[FocusManager] 在 primary focus 变化时通知）→ 检查是否收回
  /// 抄送 / 密送。判定放到帧末：此刻 cc / bcc 的「未提交文字」可能刚在 [_onFocusChanged]
  /// 里被落成胶囊，帧末才能拿到最新状态。
  void _onPrimaryFocusChanged() {
    if (!_ccBccExpanded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_ccBccExpanded) return;
      // 收件人 / 抄送 / 密送里还有焦点 —— 可能正要往 cc / bcc 填，不收回。
      if (_Field.values.any((field) => _node[field]!.hasFocus)) return;
      // 填了东西（胶囊或未提交的文字）—— 收回等于把人藏起来，不收回。
      if (_picked[_Field.cc]!.isNotEmpty || _picked[_Field.bcc]!.isNotEmpty) {
        return;
      }
      if (_input[_Field.cc]!.text.trim().isNotEmpty ||
          _input[_Field.bcc]!.text.trim().isNotEmpty) {
        return;
      }
      setState(() => _ccBccExpanded = false);
    });
  }

  void _refreshCanSend() {
    final can =
        _picked[_Field.to]!.isNotEmpty ||
        _input[_Field.to]!.text.trim().isNotEmpty;
    if (can != _canSend) setState(() => _canSend = can);
  }

  /// 把某栏「正在输入」的文字切成地址、落成胶囊。分号 / 逗号 / 空白都算分隔符。
  ///
  /// 不在这里挡格式非法的地址 —— 用户可能只是打了一半；真正的校验在发送前做，
  /// 那时提示更有用（[_send]）。
  void _commitPending(_Field field) {
    final raw = _input[field]!.text;
    if (raw.trim().isEmpty) {
      if (raw.isNotEmpty) _input[field]!.clear();
      return;
    }
    final parts = raw
        .split(RegExp(r'[;,\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    setState(() {
      for (final address in parts) {
        _addContact(field, ComposeContact(address: address), commit: false);
      }
      _input[field]!.clear();
    });
  }

  /// 往某栏加一个人 —— 三栏之间去重（同一地址不该既是收件人又是抄送）。
  ///
  /// [commit] 为 true 时自己包 `setState`；批量添加时由调用方统一包。
  void _addContact(_Field field, ComposeContact contact, {bool commit = true}) {
    void apply() {
      for (final other in _Field.values) {
        _picked[other]!.remove(contact);
      }
      _picked[field]!.add(contact);
    }

    if (commit) {
      setState(apply);
    } else {
      apply();
    }
    _refreshCanSend();
  }

  /// 点候选提示项 —— 填进当前栏，清掉正在输入的那段，焦点留在原地继续填下一个。
  void _acceptSuggestion(_Field field, ComposeContact contact) {
    _input[field]!.clear();
    _addContact(field, contact);
    _removeSuggestions();
    _node[field]!.requestFocus();
  }

  /// 当前该显示哪些候选 —— 按最后一段输入模糊匹配，已填过的人不再提示。
  ///
  /// 只取前 [_kMaxSuggestions] 条：提示卡是浮层，太长会盖住整张表单。
  List<ComposeContact> _suggestionsFor(_Field field) {
    final text = _input[field]!.text;
    // 用户可能一次粘进「a@b.com; ali」，只拿最后那一段去匹配。
    final query = text.split(RegExp(r'[;,]')).last.trim();
    if (query.isEmpty) return const <ComposeContact>[];
    final taken = <ComposeContact>{for (final list in _picked.values) ...list};
    final seen = <ComposeContact>{};
    final matched = <ComposeContact>[];
    for (final contact in widget.suggestions) {
      if (contact.address.isEmpty) continue;
      if (taken.contains(contact) || !seen.add(contact)) continue;
      if (!contact.matches(query)) continue;
      matched.add(contact);
      if (matched.length >= _kMaxSuggestions) break;
    }
    return matched;
  }

  /// 建 / 更新 / 撤掉候选提示浮层。
  ///
  /// 走 [Overlay] 而不是排在表单里：提示卡要**盖在**下面几行上（设计稿如此），
  /// 排进 `Column` 会把抄送 / 密送整行往下顶，每敲一个字表单都跳一次。
  void _refreshSuggestions() {
    final field = _active;
    if (field == null || _suggestionsFor(field).isEmpty) {
      _removeSuggestions();
      return;
    }
    final existing = _suggestionOverlay;
    if (existing != null) {
      existing.markNeedsBuild();
      return;
    }
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        // 宽度跟着**整块收件人内容区**走（`leaderSize` 首帧可能还没量到，退回一个够用
        // 的值）—— 贴的是 [_ChipsInput] 而不是输入框：输入框只占行尾余量，贴它会得到
        // 一张又窄又从行中间起头的卡片。
        width: _link[field]!.leaderSize?.width ?? 240,
        child: CompositedTransformFollower(
          link: _link[field]!,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 6),
          child: _SuggestionCard(
            contacts: _suggestionsFor(field),
            onPick: (contact) => _acceptSuggestion(field, contact),
          ),
        ),
      ),
    );
    _suggestionOverlay = entry;
    Overlay.of(context).insert(entry);
  }

  void _removeSuggestions() {
    _suggestionOverlay?.remove();
    _suggestionOverlay = null;
  }

  /// 滚动中要收提示卡时走这里 —— `ScrollUpdateNotification` 是在**布局期**派发的，
  /// 那时 `OverlayEntry.remove()` 会去 `setState` 重建 `Overlay`，直接报
  /// 「markNeedsBuild called during build」。推到帧末再收。
  void _dismissSuggestionsAfterFrame() {
    if (_suggestionOverlay == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _removeSuggestions();
    });
  }

  /// 点收件人胶囊 —— 弹「删除 / 编辑 / 移至抄送 / 移至密送」。
  ///
  /// 「移至」只列**另外两栏**（在抄送里的人不会看到「移至抄送」）。
  /// [anchor] 是被点的那个胶囊，菜单贴着它弹出。
  Future<void> _openChipMenu(
    _Field field,
    ComposeContact contact,
    BuildContext anchor,
  ) async {
    _removeSuggestions();
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    // 菜单从胶囊底部往下展开（设计稿里盖住下面几行）。
    final position = RelativeRect.fromLTRB(
      topLeft.dx,
      bottomRight.dy,
      overlay.size.width - bottomRight.dx,
      0,
    );

    final action = await showMenu<_ChipAction>(
      context: context,
      position: position,
      color: palette.background,
      surfaceTintColor: palette.background,
      // 浅色、四周发散的柔和阴影 —— 与首页右上角「导入 / 设置」菜单一致。
      elevation: 20,
      shadowColor: const Color(0x4B000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: <PopupMenuEntry<_ChipAction>>[
        _chipMenuItem(
          _ChipAction.delete,
          AppIcons.delete,
          l10n.composeRecipientDelete,
          palette,
        ),
        const AppMenuDivider(),
        _chipMenuItem(
          _ChipAction.edit,
          AppIcons.mailEdit,
          l10n.composeRecipientEdit,
          palette,
        ),
        for (final target in _Field.values)
          if (target != field) ...[
            const AppMenuDivider(),
            _chipMenuItem(
              switch (target) {
                _Field.to => _ChipAction.toTo,
                _Field.cc => _ChipAction.toCc,
                _Field.bcc => _ChipAction.toBcc,
              },
              AppIcons.forward,
              switch (target) {
                _Field.to => l10n.composeRecipientMoveToTo,
                _Field.cc => l10n.composeRecipientMoveToCc,
                _Field.bcc => l10n.composeRecipientMoveToBcc,
              },
              palette,
            ),
          ],
      ],
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _ChipAction.delete:
        setState(() => _picked[field]!.remove(contact));
        _refreshCanSend();
      case _ChipAction.edit:
        // 变回可编辑的文字：删掉胶囊、把地址放进输入框，光标落到末尾。
        setState(() {
          _picked[field]!.remove(contact);
          _input[field]!.text = contact.address;
          _input[field]!.selection = TextSelection.collapsed(
            offset: contact.address.length,
          );
        });
        _node[field]!.requestFocus();
        _refreshCanSend();
      case _ChipAction.toTo:
        _addContact(_Field.to, contact);
      case _ChipAction.toCc:
        _addContact(_Field.cc, contact);
      case _ChipAction.toBcc:
        _addContact(_Field.bcc, contact);
    }
  }

  /// 胶囊菜单的一项 —— 图标 + 文案，尺寸与首页「导入 / 设置」菜单一致（高 52、
  /// 左右 20 边距），颜色随主题自适应。
  PopupMenuItem<_ChipAction> _chipMenuItem(
    _ChipAction action,
    IconData icon,
    String label,
    AppPalette palette,
  ) {
    return PopupMenuItem<_ChipAction>(
      value: action,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: AppMenuRow(icon: icon, label: label, color: palette.textPrimary),
    );
  }

  /// 从系统通讯录选联系人 —— 取回其邮箱地址填进 [field] 那一栏。
  ///
  /// 一个联系人可能留了多个邮箱，那就再让用户挑一个（挑错地址等于发错人，
  /// 不能默认取第一个）；没留邮箱或没权限都就地提示。
  Future<void> _pickContact(_Field field) async {
    if (_pickingContact) return;
    // 两层浮层叠在一起没意义 —— 先收提示卡再拉起系统选择器 / 二次选择弹层。
    _removeSuggestions();
    setState(() => _pickingContact = true);
    try {
      final pick = await widget.contactPicker();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      switch (pick.status) {
        case ContactPickStatus.cancelled:
          return;
        case ContactPickStatus.denied:
          _toast(l10n.composeContactDenied);
          return;
        case ContactPickStatus.picked:
          break;
      }
      if (pick.emails.isEmpty) {
        _toast(l10n.composeContactNoEmail);
        return;
      }
      final address = pick.emails.length == 1
          ? pick.emails.single
          : await _chooseEmail(pick.emails);
      if (address == null || !mounted) return;
      _addContact(field, ComposeContact(address: address));
    } finally {
      if (mounted) setState(() => _pickingContact = false);
    }
  }

  /// 联系人有多个邮箱时的二次选择 —— 底部弹层，返回 null 表示放弃。
  Future<String?> _chooseEmail(List<String> emails) {
    final palette = context.palette;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.card,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                AppLocalizations.of(context).composeContactPickEmail,
                style: TextStyle(color: palette.textSecondary, fontSize: 14),
              ),
            ),
            for (final address in emails)
              ListTile(
                title: Text(
                  address,
                  style: TextStyle(color: palette.textPrimary, fontSize: 16),
                ),
                onTap: () => Navigator.of(context).pop(address),
              ),
          ],
        ),
      ),
    );
  }

  /// 在光标所在行行首插入列表前缀 —— 列表是段落级的，用纯文本近似。
  ///
  /// 有序列表续上一行的编号（上一行是「3. …」则本行为 `4. `），否则从 1 起。
  void _insertListPrefix({required bool numbered}) {
    final text = _body.text;
    final selection = _body.selection;
    final at = selection.isValid
        ? selection.baseOffset.clamp(0, text.length)
        : text.length;
    final lineStart = at == 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;

    var prefix = '• ';
    if (numbered) {
      // lineStart > 0 时 before 以 '\n' 结尾，故上一行是倒数第二段。
      final lines = text.substring(0, lineStart).split('\n');
      final previous = lines.length >= 2 ? lines[lines.length - 2] : '';
      final matched = RegExp(r'^(\d+)\. ').firstMatch(previous);
      final index = matched == null ? 1 : int.parse(matched.group(1)!) + 1;
      prefix = '$index. ';
    }

    _body.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: at + prefix.length),
    );
  }

  /// 调整光标所在行的缩进 —— 行首增删一个 [_kIndentUnit]（纯文本近似）。
  ///
  /// 减少缩进时容忍不足一个单位的残留空格（或一个 Tab），有多少去多少。
  void _indentLine({required bool increase}) {
    final text = _body.text;
    final selection = _body.selection;
    final at = selection.isValid
        ? selection.baseOffset.clamp(0, text.length)
        : text.length;
    final lineStart = at == 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;

    if (increase) {
      _body.value = TextEditingValue(
        text: text.replaceRange(lineStart, lineStart, _kIndentUnit),
        selection: TextSelection.collapsed(offset: at + _kIndentUnit.length),
      );
      return;
    }

    // 行首可去掉的宽度：一个 Tab，或最多 _kIndentUnit 长度的空格。
    var strip = 0;
    if (lineStart < text.length && text[lineStart] == '\t') {
      strip = 1;
    } else {
      while (strip < _kIndentUnit.length &&
          lineStart + strip < text.length &&
          text[lineStart + strip] == ' ') {
        strip++;
      }
    }
    if (strip == 0) return;
    _body.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineStart + strip, ''),
      selection: TextSelection.collapsed(
        offset: (at - strip).clamp(lineStart, text.length - strip),
      ),
    );
  }

  /// 选附件 / 选图 —— [imagesOnly] 为 true 时只让选图片（底栏图片按钮走这条）。
  ///
  /// 读到字节后即转成 [MailAttachment] 存内存；超出 [_kMaxAttachBytes] 的整批拒收并提示，
  /// 不做静默截断 —— 免得用户以为发出去了。
  Future<void> _pickAttachments({required bool imagesOnly}) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await FilePicker.pickFiles(
        type: imagesOnly ? FileType.image : FileType.any,
      );
      if (picked.isEmpty || !mounted) return;

      final added = <MailAttachment>[];
      final unreadable = <String>[];
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          unreadable.add(file.name);
          continue;
        }
        added.add(
          MailAttachment(
            name: file.name,
            contentType: _contentTypeFor(file.extension),
            bytes: bytes,
          ),
        );
      }
      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      final total = [
        ..._attachments,
        ...added,
      ].fold<int>(0, (sum, a) => sum + a.size);
      if (total > _kMaxAttachBytes) {
        _toast(l10n.composeAttachTooLarge(_formatBytes(_kMaxAttachBytes)));
        return;
      }
      setState(() => _attachments.addAll(added));
      if (unreadable.isNotEmpty) {
        _toast(l10n.composeAttachEmptyFile(unreadable.first));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// 扩展名 → MIME，认不出的交给 `application/octet-stream`（Graph 允许）。
  static String _contentTypeFor(String? extension) {
    return switch (extension?.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'pdf' => 'application/pdf',
      'txt' || 'log' || 'csv' => 'text/plain',
      'zip' => 'application/zip',
      'doc' => 'application/msword',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => 'application/octet-stream',
    };
  }

  /// 字节数 → human 可读（附件条与超限提示共用）。
  static String _formatBytes(int bytes) => formatFileSize(bytes);

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1400),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// 某一栏最终要发出去的地址 —— 已落成胶囊的 + 还在输入框里没敲完的，去重。
  List<String> _recipients(_Field field) {
    final pending = _input[field]!.text
        .split(RegExp(r'[;,\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    return <String>{
      for (final contact in _picked[field]!) contact.address,
      ...pending,
    }.toList();
  }

  /// 极简邮箱校验 —— 只挡明显不合法（无 `@` / 无域名点），不做 RFC 全量校验。
  bool _looksLikeEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  /// 把正文与逐字格式转成 Graph 可发送的正文（内容 + 是否 HTML），见 [composeBodyHtml]：
  /// 一个字都没排版过且左对齐 → 纯文本直发；否则包一层 `<div>`，被排版过的每一段各自
  /// 包一个 `<span>`。
  ({String content, bool isHtml}) _composeBody() =>
      composeBodyHtml(text: _body.text, formats: _body.formats, align: _align);

  /// 发送邮件 —— 校验收件人 → 调 Graph `sendMail` → 成功返回列表并提示，失败留在原页。
  ///
  /// 三栏都校验：抄送 / 密送里的错地址一样会让整封发不出去，不能只看收件人。
  Future<void> _send() async {
    if (_sending) return;
    final l10n = AppLocalizations.of(context);

    final to = _recipients(_Field.to);
    final cc = _recipients(_Field.cc);
    final bcc = _recipients(_Field.bcc);
    if (to.isEmpty) {
      _toast(l10n.composeNoRecipient);
      return;
    }
    final invalid = [...to, ...cc, ...bcc].where((r) => !_looksLikeEmail(r));
    if (invalid.isNotEmpty) {
      _toast(l10n.composeInvalidRecipient(invalid.first));
      return;
    }

    final body = _composeBody();
    setState(() => _sending = true);

    final res = await ApiScope.of(context).mail.sendMail(
      widget.accountEmail,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: _subject.text.trim(),
      body: body.content,
      isHtml: body.isHtml,
      importance: _importance.graphValue,
      attachments: List<MailAttachment>.unmodifiable(_attachments),
    );
    if (!mounted) return;

    if (res.isSuccess) {
      // SnackBar 挂在根 ScaffoldMessenger 上，pop 后仍会显示在列表页。
      _toast(l10n.composeSent);
      Navigator.of(context).pop();
      return;
    }
    setState(() => _sending = false);
    _toast(l10n.composeSendFailed(res.message));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(palette, l10n),
            // 表单 / 附件 / 正文同在一条滚动条里：键盘弹起后上滑就能把收件人那几行
            // 滚走，把整屏留给正文（「输入区域太小」那条）。
            Expanded(
              // 提示卡是 Overlay 浮层、不受视口裁剪 —— 一滚就收掉，免得飘到顶栏上。
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (_) {
                  _dismissSuggestionsAfterFrame();
                  return false;
                },
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildFields(palette, l10n)),
                    if (_attachments.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _buildAttachments(palette, l10n),
                      ),
                    // `hasScrollBody: false`：正文短时也至少占满剩余高度（点下方
                    // 空白处能落焦点），长了就把页面撑长、整页可滚。
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildBody(palette, l10n),
                    ),
                  ],
                ),
              ),
            ),
            // 排版栏可被「×」收起、由「Aa」重新唤出；底栏常驻。
            if (_formatBarOpen) _buildFormatBar(palette),
            _buildBottomBar(palette),
          ],
        ),
      ),
    );
  }

  /// 顶栏 —— 返回 + 「新建邮件」+ 附件 + 发送（无收件人时置灰不可点）。
  Widget _buildHeader(AppPalette palette, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            splashRadius: 22,
            icon: Icon(AppIcons.back, color: palette.textPrimary, size: 20),
          ),
          Expanded(
            child: Text(
              l10n.composeTitle,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: _picking
                ? null
                : () => _pickAttachments(imagesOnly: false),
            splashRadius: 22,
            icon: Icon(AppIcons.attach, color: palette.textPrimary, size: 24),
          ),
          IconButton(
            onPressed: (_canSend && !_sending) ? _send : null,
            splashRadius: 22,
            icon: _sending
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        palette.primary,
                      ),
                    ),
                  )
                : Icon(
                    AppIcons.send,
                    size: 24,
                    color: _canSend ? palette.primary : palette.textSecondary,
                  ),
          ),
        ],
      ),
    );
  }

  /// 表单 —— 收件人 / 抄送 / 密送 / 发件人 / 重要性 / 主题，行间 1px 分隔线。
  ///
  /// 抄送 / 密送 / 发件人三行只在 [_ccBccOpen] 时出现；否则折叠成一行
  /// 「抄送/密送, 发件人：<账号>」（`UI/发件人-无抄送&密送.jpg`）。
  ///
  /// **每行都带 key**：行数会随折叠 / 展开变化，没有 key 的话主题那行会与「发件人」行按
  /// 下标错配、`EditableText` 被重建（详见 [_FieldRow] 的注释）。
  Widget _buildFields(AppPalette palette, AppLocalizations l10n) {
    final valueStyle = TextStyle(
      color: palette.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w500,
    );
    return Column(
      children: [
        _recipientRow(_Field.to, l10n.composeTo, palette, l10n),
        if (_ccBccOpen) ...[
          _recipientRow(_Field.cc, l10n.composeCc, palette, l10n),
          _recipientRow(_Field.bcc, l10n.composeBcc, palette, l10n),
          // 发件人固定为当前账号（本页由该账号的邮件列表进入），故只展示不可改。
          _FieldRow(
            key: const Key('compose-row-from'),
            label: l10n.composeFrom,
            child: Text(
              widget.accountEmail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: valueStyle,
            ),
          ),
        ] else
          // 折叠态整行可点 —— 点它（= 设计稿的「发件人」列）才展开抄送 / 密送 / 发件人
          // 三行。key 挪到 GestureDetector 上：它才是 Column 的直接子级，反配对靠它这一层
          // 认（见 [_FieldRow] 注释）。
          GestureDetector(
            key: const Key('compose-row-ccfrom'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _ccBccExpanded = true),
            child: _FieldRow(
              label: l10n.composeCcFrom,
              child: Text(
                widget.accountEmail,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: valueStyle,
              ),
            ),
          ),
        _FieldRow(
          key: const Key('compose-row-importance'),
          label: l10n.composeImportance,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _buildImportance(palette, l10n, valueStyle),
          ),
        ),
        _FieldRow(
          key: const Key('compose-row-subject'),
          label: l10n.composeSubject,
          child: _inlineField(
            _subject,
            valueStyle,
            palette,
            key: const Key('compose-subject-field'),
          ),
        ),
      ],
    );
  }

  /// 一栏收件人 —— 三种形态见类注释。
  ///
  /// 折叠成一行文字时**整行可点**（点了就回到聚焦态）；`+`（选系统联系人）只在聚焦或
  /// 该栏为空时出现。候选提示卡贴着**整块内容区**弹（`CompositedTransformTarget`
  /// 套在 [_ChipsInput] 外面而不是输入框上）—— 输入框现在只占行尾那点余量，贴着它弹
  /// 会得到一张又窄又从行中间起头的卡片。
  ///
  /// **输入框的位置必须是稳定的**：三种形态都把它放在同一个 [_ChipsInput] 的最后一格，
  /// 且带 key。一旦让它在「直接子级」与容器内部之间搬家，`EditableText` 的 element 会被
  /// 重建 —— 表现为**点一下输入框、键盘刚起来又立刻收回**（聚焦触发重建、重建又把焦点
  /// 弄丢）。折叠态用 [Offstage] 把它藏起来而不是移出树，同样是为了保住那个 element。
  Widget _recipientRow(
    _Field field,
    String label,
    AppPalette palette,
    AppLocalizations l10n,
  ) {
    final picked = _picked[field]!;
    final focused = _active == field;
    // 未聚焦且已填 —— 折叠成一行主色文字，省出竖直空间给正文。
    final collapsed = !focused && picked.isNotEmpty;
    final valueStyle = TextStyle(
      color: palette.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w500,
    );

    return _FieldRow(
      key: Key('compose-row-${field.name}'),
      label: label,
      trailing: (focused || picked.isEmpty)
          ? IconButton(
              key: Key('compose-${field.name}-pick'),
              onPressed: _pickingContact ? null : () => _pickContact(field),
              splashRadius: 20,
              tooltip: l10n.composeContactPick,
              icon: Icon(AppIcons.add, color: palette.textPrimary, size: 24),
            )
          : null,
      child: CompositedTransformTarget(
        link: _link[field]!,
        child: _ChipsInput(
          inputHidden: collapsed,
          children: [
            if (collapsed)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _node[field]!.requestFocus(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    picked.map((c) => c.label).join('; '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )
            else
              for (final contact in picked)
                _RecipientChip(
                  label: contact.label,
                  tooltip: l10n.composeRecipientOptions,
                  onTap: (anchor) => _openChipMenu(field, contact, anchor),
                ),
            Offstage(
              key: Key('compose-${field.name}-input'),
              offstage: collapsed,
              child: _inlineField(
                _input[field]!,
                valueStyle,
                palette,
                key: Key('compose-${field.name}-field'),
                focusNode: _node[field]!,
                keyboardType: TextInputType.emailAddress,
                // 敲回车 / 分号即落成胶囊，接着填下一个。
                onSubmitted: (_) {
                  _commitPending(field);
                  _node[field]!.requestFocus();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 表单行里的无边框输入框 —— 只留文字，边框与内边距交给 [_FieldRow]。
  Widget _inlineField(
    TextEditingController controller,
    TextStyle style,
    AppPalette palette, {
    Key? key,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      style: style,
      cursorColor: palette.primary,
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }

  /// 重要性下拉 —— 值 + ▾，落到 Graph 的 high / normal / low。
  Widget _buildImportance(
    AppPalette palette,
    AppLocalizations l10n,
    TextStyle style,
  ) {
    return PopupMenuButton<MailImportance>(
      initialValue: _importance,
      color: palette.card,
      onSelected: (value) => setState(() => _importance = value),
      itemBuilder: (context) => <PopupMenuEntry<MailImportance>>[
        for (final value in MailImportance.values)
          PopupMenuItem<MailImportance>(
            value: value,
            child: Text(
              value.label(l10n),
              style: TextStyle(color: palette.textPrimary, fontSize: 15),
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_importance.label(l10n), style: style),
          const SizedBox(width: 6),
          Icon(AppIcons.dropDown, color: palette.textPrimary, size: 20),
        ],
      ),
    );
  }

  /// 附件条 —— 横向排列的附件卡片（名称 + 大小 + 移除），仅在有附件时入树。
  Widget _buildAttachments(AppPalette palette, AppLocalizations l10n) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.divider, width: 1)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        itemCount: _attachments.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final attachment = _attachments[index];
          return _AttachmentChip(
            name: attachment.name,
            size: _formatBytes(attachment.size),
            isImage: attachment.contentType.startsWith('image/'),
            removeLabel: l10n.composeAttachRemove,
            onRemove: () => setState(() => _attachments.removeAt(index)),
          );
        },
      ),
    );
  }

  /// 正文 —— 排在 `SliverFillRemaining` 里：至少占满剩余高度，内容多了就把页面撑长
  /// （不再自己 `expands`，否则整页没法滚）。逐字格式在
  /// [_RichBodyController.buildTextSpan] 里叠到这里给的基础样式上。
  Widget _buildBody(AppPalette palette, AppLocalizations l10n) {
    final format = _shownFormat;
    return TextField(
      key: const Key('compose-body-field'),
      controller: _body,
      focusNode: _bodyFocus,
      undoController: _undo,
      maxLines: null,
      textAlign: _align,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
      cursorColor: palette.primary,
      // 各段字号可以不同 —— 默认 strut 会按基础样式把每行行高**焊死**
      // （`StrutStyle.fromTextStyle(style, forceStrutHeight: true)`），大字号那几段
      // 就会被压扁、上下叠在一起。关掉 strut，每行按自己那几段的实际字号排。
      strutStyle: StrutStyle.disabled,
      style: TextStyle(
        // 基础样式的**颜色只能是主题正文色**：某段字的 color 为 null 就是「跟随主题」，
        // 靠继承这里取值 —— 若按光标处的颜色给，光标停在红字里时，别处没上色的字会跟着变红。
        color: palette.textPrimary,
        decorationColor: palette.textPrimary,
        height: 1.5,
        // 其余几项逐字都会显式覆盖，串不到旧文字上；这里按光标处那一套给，是为了让
        // 光标高度、空正文时的提示文字与「接下来要打的字」对得上。
        fontSize: format.fontSize,
        fontWeight: format.bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: format.italic ? FontStyle.italic : FontStyle.normal,
        decoration: format.underline
            ? TextDecoration.underline
            : TextDecoration.none,
      ),
      decoration: InputDecoration(
        hintText: l10n.composeBodyHint,
        hintStyle: TextStyle(
          color: palette.textSecondary,
          fontSize: format.fontSize,
        ),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      ),
    );
  }

  /// 排版栏 —— 字号 ▾ / B / I / U / A(颜色) / 列表 / 缩进 / 对齐，可左右滑动；
  /// 「×」用竖线隔开固定在最右侧，不随内容滚走（参照「新建邮件-工具栏.jpg」）。
  ///
  /// 点字号或颜色时**整行原地换成横向选项条**（同样可左右滑），选完即切回工具按钮。
  /// 这样高度恒为 48、不弹浮层盖住正文。
  Widget _buildFormatBar(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 48,
      decoration: BoxDecoration(color: palette.card),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              // 换面板时重建滚动视图，位置从最左开始（否则会沿用上一条的偏移）。
              key: ValueKey<_FormatPanel>(_panel),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: switch (_panel) {
                  _FormatPanel.tools => _formatTools(palette, l10n),
                  _FormatPanel.fontSize => _fontSizeOptions(palette),
                  _FormatPanel.color => _colorOptions(palette),
                },
              ),
            ),
          ),
          // 固定区与滚动区之间的竖线 —— 设计稿里「×」被它隔在最右。
          Container(width: 1, height: 28, color: palette.divider),
          _ToolButton(
            icon: AppIcons.close,
            tooltip: l10n.commonCancel,
            onTap: () => setState(() {
              _formatBarOpen = false;
              _panel = _FormatPanel.tools;
            }),
          ),
        ],
      ),
    );
  }

  /// 排版栏里可滑动的那批按钮（顺序与设计稿一致）。
  List<Widget> _formatTools(AppPalette palette, AppLocalizations l10n) {
    return <Widget>[
      _buildFontSizePicker(palette),
      _ToolButton(
        icon: AppIcons.bold,
        active: _shownFormat.bold,
        onTap: () => _toggleAttribute(ComposeTextAttribute.bold),
      ),
      _ToolButton(
        icon: AppIcons.italic,
        active: _shownFormat.italic,
        onTap: () => _toggleAttribute(ComposeTextAttribute.italic),
      ),
      _ToolButton(
        icon: AppIcons.underline,
        active: _shownFormat.underline,
        onTap: () => _toggleAttribute(ComposeTextAttribute.underline),
      ),
      _buildColorPicker(palette),
      _ToolButton(
        icon: AppIcons.listBulleted,
        onTap: () => _insertListPrefix(numbered: false),
      ),
      _ToolButton(
        icon: AppIcons.listNumbered,
        onTap: () => _insertListPrefix(numbered: true),
      ),
      _ToolButton(
        icon: AppIcons.indentIncrease,
        tooltip: l10n.composeIndentIncrease,
        onTap: () => _indentLine(increase: true),
      ),
      _ToolButton(
        icon: AppIcons.indentDecrease,
        tooltip: l10n.composeIndentDecrease,
        onTap: () => _indentLine(increase: false),
      ),
      _ToolButton(
        icon: AppIcons.alignLeft,
        tooltip: l10n.composeAlignLeft,
        active: _align == TextAlign.left,
        onTap: () => setState(() => _align = TextAlign.left),
      ),
      _ToolButton(
        icon: AppIcons.alignCenter,
        tooltip: l10n.composeAlignCenter,
        active: _align == TextAlign.center,
        onTap: () => setState(() => _align = TextAlign.center),
      ),
      _ToolButton(
        icon: AppIcons.alignRight,
        tooltip: l10n.composeAlignRight,
        active: _align == TextAlign.right,
        onTap: () => setState(() => _align = TextAlign.right),
      ),
    ];
  }

  /// 字号选择 —— 数字 + ▾，点开把整行换成横向字号条。
  Widget _buildFontSizePicker(AppPalette palette) {
    final active = _panel == _FormatPanel.fontSize;
    final color = active ? palette.primary : palette.textPrimary;
    return InkResponse(
      onTap: () => setState(() => _panel = _FormatPanel.fontSize),
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_shownFormat.fontSize.toInt()}',
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(AppIcons.dropDown, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  /// 文字颜色入口 —— 图标染成光标处的颜色，点开把整行换成横向色点条。
  Widget _buildColorPicker(AppPalette palette) {
    return _ToolButton(
      icon: AppIcons.textColor,
      active: _panel == _FormatPanel.color,
      onTap: () => setState(() => _panel = _FormatPanel.color),
      iconColor: _shownFormat.color,
    );
  }

  /// 横向字号条 —— 点一下即落到选区（没选区就是「接下来要打的字」）并切回排版栏。
  List<Widget> _fontSizeOptions(AppPalette palette) {
    return <Widget>[
      for (final size in _fontSizes)
        _OptionChip(
          label: '${size.toInt()}',
          selected: size == _shownFormat.fontSize,
          onTap: () {
            _body.applyFormat((format) => format.withFontSize(size));
            setState(() => _panel = _FormatPanel.tools);
          },
        ),
    ];
  }

  /// 横向色点条 —— 首项「跟随主题」（存 null，切主题不会留下旧色）。
  List<Widget> _colorOptions(AppPalette palette) {
    final colors = _bodyColors(palette);
    return <Widget>[
      for (var i = 0; i < colors.length; i++)
        _ColorDot(
          color: colors[i],
          selected: i == 0
              ? _shownFormat.color == null
              : _shownFormat.color == colors[i],
          onTap: () {
            _body.applyFormat(
              (format) => format.withColor(i == 0 ? null : colors[i]),
            );
            setState(() => _panel = _FormatPanel.tools);
          },
        ),
    ];
  }

  /// 正文可选颜色 —— 首项是「跟随主题」的正文色。
  List<Color> _bodyColors(AppPalette palette) => <Color>[
    palette.textPrimary,
    palette.primary,
    palette.statusError,
    palette.statusWarning,
    const Color(0xFF34C759),
  ];

  /// 底栏 —— 撤销 / 重做（按正文编辑历史自动置灰）+ Aa（开合排版栏）+ 图片。
  ///
  /// 四格**等宽**：每项各占 1/4 并在格内居中。不能用 `spaceAround` —— 各项内容
  /// 宽度不同（图标 24、「Aa」文字更宽），那样排出来图标中心不是等距的。
  Widget _buildBottomBar(AppPalette palette) {
    return Container(
      height: 48,
      decoration: BoxDecoration(color: palette.background),
      child: ValueListenableBuilder<UndoHistoryValue>(
        valueListenable: _undo,
        builder: (context, value, _) => Row(
          children: [
            Expanded(
              child: Center(
                child: _ToolButton(
                  icon: AppIcons.undo,
                  onTap: value.canUndo ? _undo.undo : null,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: _ToolButton(
                  icon: AppIcons.redo,
                  onTap: value.canRedo ? _undo.redo : null,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: _AaToggle(
                  active: _formatBarOpen,
                  onTap: () => setState(() => _formatBarOpen = !_formatBarOpen),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: _ToolButton(
                  icon: AppIcons.image,
                  onTap: _picking
                      ? null
                      : () => _pickAttachments(imagesOnly: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 正文控制器 —— **每个字符记一份 [ComposeTextFormat]**，渲染时按段合并成 `TextSpan`。
/// 选中一段设字号 / 加粗 / 斜体 / 下划线 / 颜色，只有那一段变。
///
/// 为什么不引富文本引擎（flutter_quill 那类）：底部两条工具栏、收件人三栏与整页布局都是
/// 按设计稿 1:1 写的，换引擎等于连编辑器一起换掉；而这里要的只是五种**字符级**属性，
/// 一份与正文等长的格式表就够 —— `TextField` 的光标、选择菜单、输入法、撤销全部照旧。
///
/// 三条约定：
/// - **格式跟着文字挪**：编辑框只给「改完之后的整段文字」，故每次 [value] 变更都先按
///   [composeTextEdit] 求出改了哪一段，再用 [composeSpliceFormats] 挪格式表。新插入的字
///   继承左边那个字的格式（行首取右边），与系统编辑器一致。
/// - **空选区时点工具栏 = 设定「接下来要打的字」**（[_pending]，Word / Gmail 同款）；光标被
///   挪去别处即作废 —— 但**首次落焦点不算挪**（此前压根没有有效选区），否则「先在工具栏选好
///   颜色、再点进正文打字」会一进去就把选好的颜色丢掉。
/// - **格式不进撤销栈**：`UndoHistoryController` 只管文字，撤销回来的那段文字取邻居的格式
///   （已知取舍：重新选一次即可，不至于丢内容）。
class _RichBodyController extends TextEditingController {
  /// 与 `text` 等长的逐字格式表（一格一个 UTF-16 码元，故下标与 `String` 通用）。
  List<ComposeTextFormat> _formats = <ComposeTextFormat>[];

  /// 空选区时点工具栏设下的格式 —— 只作用于接下来插入的字。
  ComposeTextFormat? _pending;

  /// 发信时按它序列化（[composeBodyHtml]）。
  List<ComposeTextFormat> get formats =>
      List<ComposeTextFormat>.unmodifiable(_formats);

  /// 排版栏该显示、也是下一次改动该基于的那一套格式。
  ///
  /// 有选区看**选区头一个字**；只有光标时看它**前面**那个字（刚打出来的字什么样，接着打
  /// 就该什么样）；刚点过工具栏则看 [_pending]。
  ComposeTextFormat get formatAtCursor {
    final pending = _pending;
    if (pending != null) return pending;
    if (_formats.isEmpty) return ComposeTextFormat.plain;
    final selection = value.selection;
    // 还没落过焦点 —— 当作光标在末尾（真要打字也是从那儿续上）。
    if (!selection.isValid) return _formats.last;
    final at = selection.isCollapsed ? selection.start - 1 : selection.start;
    return _formats[at.clamp(0, _formats.length - 1)];
  }

  /// 把一次格式改动落到**当前选区**；没有选区（只有光标）时只影响接下来打的字。
  void applyFormat(ComposeTextFormat Function(ComposeTextFormat) change) {
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) {
      _pending = change(formatAtCursor);
    } else {
      final start = selection.start.clamp(0, _formats.length);
      final end = selection.end.clamp(0, _formats.length);
      for (var i = start; i < end; i++) {
        _formats[i] = change(_formats[i]);
      }
      _pending = null;
    }
    // 文字没变、只有样式变了 —— 不通知的话 `EditableText` 不会重新取 [buildTextSpan]。
    notifyListeners();
  }

  @override
  set value(TextEditingValue newValue) {
    if (newValue.text != value.text) {
      final edit = composeTextEdit(value.text, newValue.text);
      _formats = composeSpliceFormats(
        formats: _formats,
        start: edit.start,
        removed: edit.removed,
        inserted: edit.inserted,
        insertFormat: _pending ?? _formatBefore(edit.start),
      );
    } else if (value.selection.isValid &&
        newValue.selection != value.selection) {
      _pending = null;
    }
    super.value = newValue;
  }

  /// 插入点继承谁的格式 —— 左边那个字，行首取右边那个。
  ComposeTextFormat _formatBefore(int start) {
    if (_formats.isEmpty) return ComposeTextFormat.plain;
    final at = start > 0 ? start - 1 : 0;
    return _formats[at.clamp(0, _formats.length - 1)];
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) return TextSpan(style: style, text: text);
    // 输入法正在拼的那一段照惯例加下划线（基类的默认实现也是这么干的）。
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : null;

    final children = <TextSpan>[];
    for (final run in composeTextRuns(text, _formats)) {
      final runStyle =
          style?.merge(run.format.styleOverride) ?? run.format.styleOverride;
      final from = (composing?.start ?? run.end).clamp(run.start, run.end);
      final to = (composing?.end ?? run.end).clamp(from, run.end);
      void add(int start, int end, {bool underlined = false}) {
        if (end <= start) return;
        children.add(
          TextSpan(
            text: text.substring(start, end),
            style: underlined
                ? runStyle.merge(
                    const TextStyle(decoration: TextDecoration.underline),
                  )
                : runStyle,
          ),
        );
      }

      add(run.start, from);
      add(from, to, underlined: true);
      add(to, run.end);
    }
    return TextSpan(style: style, children: children);
  }
}

/// 表单行 —— 左侧灰色标签 + 内容区 + 可选尾部按钮，底部一条 1px 分隔线。
///
/// **每一行都要带稳定的 key**（见 `_buildFields`）：抄送 / 密送整行会随交互增删，行数一变，
/// 无 key 的兄弟节点就按下标重新配对 —— 主题那行的 `EditableText` 会被当成另一个 widget
/// 重建，正在输入的焦点被踢掉、焦点作用域又把焦点还给上一个（收件人），表现为
/// **在主题里打字，字进了收件人**。
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: EdgeInsets.fromLTRB(20, 0, trailing == null ? 20 : 8, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.divider, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: palette.textSecondary, fontSize: 14),
          ),
          const SizedBox(width: 10),
          Expanded(child: child),
          ?trailing,
        ],
      ),
    );
  }
}

/// 胶囊按行流下去、**输入框吃掉当前行剩下的宽度**（最后一个孩子固定是输入框）。
///
/// 为什么不用 `Wrap`：`Wrap` 给每个孩子的 maxWidth 都是**整行宽**，而 `TextField` 会
/// 铺满拿到的宽度 —— 于是只要前面有一枚胶囊就挤不下，输入框（连光标）被整体推到下一行，
/// 表现为**收件人在这一行、光标在下一行**。这里给输入框的是**当前行的余量**
/// （余量不足 [_kMinInputWidth] 才另起一行、占满整行），光标便紧跟在最后一枚胶囊后面。
/// 顺带治了另一件事：输入框铺满行尾余量，点胶囊右边那片空白也能落焦点（同系统邮件客户端）。
///
/// 代价：地址长过行尾余量时在框内横向滚动（余量至少 [_kMinInputWidth]，够看清正在敲的
/// 几个字符），不再像原来那样独占一整行。
class _ChipsInput extends MultiChildRenderObjectWidget {
  const _ChipsInput({required this.inputHidden, required super.children});

  /// 折叠态：输入框只是留在树上保住 element（见 `_recipientRow`），不参与排版。
  final bool inputHidden;

  @override
  _RenderChipsInput createRenderObject(BuildContext context) =>
      _RenderChipsInput(inputHidden);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderChipsInput renderObject,
  ) {
    renderObject.inputHidden = inputHidden;
  }
}

/// 胶囊之间的横向间距 / 行距，以及行尾输入框的最小可用宽度。
const double _kChipSpacing = 8;
const double _kChipRunSpacing = 6;
const double _kMinInputWidth = 72;

class _ChipsInputParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderChipsInput extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ChipsInputParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ChipsInputParentData> {
  _RenderChipsInput(this._inputHidden);

  bool get inputHidden => _inputHidden;
  bool _inputHidden;
  set inputHidden(bool value) {
    if (_inputHidden == value) return;
    _inputHidden = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ChipsInputParentData) {
      child.parentData = _ChipsInputParentData();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void performLayout() {
    // 宽度由 `_FieldRow` 的 `Expanded` 给死；高度不限（行数越多越高）。
    assert(constraints.hasBoundedWidth);
    final maxWidth = constraints.maxWidth;
    final children = getChildrenAsList();
    final input = children.isEmpty ? null : children.last;
    final chips = children.isEmpty
        ? const <RenderBox>[]
        : children.sublist(0, children.length - 1);

    // 一行里的孩子先按「行顶」记下 dy，等这行收尾（知道了行高）再统一垂直居中。
    final run = <RenderBox>[];
    double x = 0; // 当前行已占宽度
    double y = 0; // 当前行行顶
    double runHeight = 0;

    void closeRun() {
      for (final child in run) {
        final data = child.parentData! as _ChipsInputParentData;
        data.offset = Offset(
          data.offset.dx,
          y + (runHeight - child.size.height) / 2,
        );
      }
      run.clear();
    }

    void place(RenderBox child) {
      (child.parentData! as _ChipsInputParentData).offset = Offset(x, y);
      run.add(child);
      x += child.size.width;
      runHeight = math.max(runHeight, child.size.height);
    }

    void newRun() {
      closeRun();
      y += runHeight + _kChipRunSpacing;
      x = 0;
      runHeight = 0;
    }

    for (final chip in chips) {
      chip.layout(BoxConstraints(maxWidth: maxWidth), parentUsesSize: true);
      if (x == 0) {
        place(chip);
      } else if (x + _kChipSpacing + chip.size.width > maxWidth) {
        newRun();
        place(chip);
      } else {
        x += _kChipSpacing;
        place(chip);
      }
    }

    if (input != null) {
      if (_inputHidden) {
        // 折叠态：零尺寸摆在原点，不占位、不进行内的居中计算（`Offstage` 也不画它）。
        input.layout(BoxConstraints.tight(Size.zero));
        (input.parentData! as _ChipsInputParentData).offset = Offset.zero;
      } else {
        var free = x == 0 ? maxWidth : maxWidth - x - _kChipSpacing;
        if (free < _kMinInputWidth && x > 0) {
          newRun(); // 行尾余量太窄 → 另起一行、整行都归它
          free = maxWidth;
        } else if (x > 0) {
          x += _kChipSpacing;
        }
        free = math.max(free, 0);
        // 宽度给死：`TextField` 会铺满它 —— 这正是「光标紧跟胶囊、空白处也能点」的由来。
        input.layout(
          BoxConstraints(minWidth: free, maxWidth: free),
          parentUsesSize: true,
        );
        place(input);
      }
    }
    closeRun();
    size = constraints.constrain(Size(maxWidth, y + runHeight));
  }
}

/// 已填好的一个收件人 —— 灰底圆角胶囊，点开操作菜单（`UI/收件人-多收件人.jpg`）。
///
/// [onTap] 收的是胶囊自己的 [BuildContext]：菜单要贴着**被点的这一个**弹出，
/// 得拿它的 `RenderBox` 算屏幕位置。
class _RecipientChip extends StatelessWidget {
  const _RecipientChip({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final void Function(BuildContext anchor) onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: Builder(
        builder: (anchor) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(anchor),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 收件人输入提示卡 —— 浮在表单之上，每项「名称 + 邮箱」两行（`UI/收件人-输入提示.jpg`）。
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.contacts, required this.onPick});

  final List<ComposeContact> contacts;
  final ValueChanged<ComposeContact> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.card,
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final contact in contacts)
            InkWell(
              onTap: () => onPick(contact),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 没名字的候选不留空行 —— 直接把地址当主行。
                    Text(
                      contact.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (contact.name.isNotEmpty)
                      Text(
                        contact.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 工具栏按钮 —— 单图标；[active] 高亮当前生效的格式，[onTap] 为空则置灰。
///
/// 图标按钮没有可见文字，故 [tooltip] 非空时包一层 [Tooltip] 兼作无障碍标签
/// （对齐 / 缩进这类图标语义不自明，必须给）。
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    this.onTap,
    this.active = false,
    this.tooltip,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final String? tooltip;

  /// 覆盖默认图标色（文字颜色入口用它显示当前选中的颜色）；
  /// 置灰与 [active] 优先级更高。
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final Color color = onTap == null
        ? palette.textSecondary.withValues(alpha: 0.4)
        : active
        ? palette.primary
        : iconColor ?? palette.textPrimary;
    final Widget button = InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Icon(icon, color: color, size: 24),
      ),
    );
    final label = tooltip;
    if (label == null) return button;
    return Tooltip(message: label, child: button);
  }
}

/// 横向字号条里的一格 —— 选中态用主色淡底 + 主色文字。
class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          constraints: const BoxConstraints(minWidth: 38),
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? palette.primary.withValues(alpha: 0.16) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? palette.primary : palette.textPrimary,
              fontSize: 15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 横向色点条里的一格 —— 选中态在色点外描一圈主色。
class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: palette.primary, width: 2)
                : null,
          ),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

/// 附件卡片 —— 类型图标 + 文件名（截断）+ 大小 + 移除按钮。
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.name,
    required this.size,
    required this.isImage,
    required this.removeLabel,
    required this.onRemove,
  });

  final String name;
  final String size;
  final bool isImage;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.fromLTRB(10, 0, 2, 0),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isImage ? AppIcons.image : AppIcons.file,
            color: palette.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textPrimary, fontSize: 14),
                ),
                Text(
                  size,
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            splashRadius: 16,
            tooltip: removeLabel,
            visualDensity: VisualDensity.compact,
            icon: Icon(AppIcons.close, color: palette.textSecondary, size: 16),
          ),
        ],
      ),
    );
  }
}

/// 底栏「Aa」开关 —— 开合排版工具栏；打开时显主色。
class _AaToggle extends StatelessWidget {
  const _AaToggle({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          'Aa',
          style: TextStyle(
            color: active ? palette.primary : palette.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
