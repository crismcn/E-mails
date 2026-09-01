import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_scope.dart';
import '../api/mail_api.dart';
import '../core/contacts/contact_picker.dart';
import '../data/mail_mapper.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';

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

/// 新建邮件页 —— 视觉 1:1 参照「新建邮件.jpg」与「新建邮件-工具栏.jpg」设计稿。
///
/// 结构：顶栏（返回 / 标题 / 附件 / 发送）+ 四行表单（收件人、抄送·发件人、重要性、
/// 主题）+ 附件条（有附件时才出现）+ 正文编辑区 + 底部两条工具栏
/// （排版栏 + 撤销·重做·Aa·图片）。
///
/// 排版工具栏的取舍：正文是**纯文本** [TextField]，没有富文本引擎，所以字号 / 加粗 /
/// 斜体 / 下划线 / 颜色 / 对齐都**整篇套用**（不是选区富文本）；两个列表按钮在光标所在
/// 行行首插入 `• ` / `N. ` 前缀，缩进按钮同理增删行首空格。排版项多于一屏，故排版栏
/// 可左右滑动，「×」用竖线隔开固定在最右侧（设计稿如此）。
///
/// 附件走 Graph 的小附件形式（base64 内嵌进 sendMail），原始字节总量上限
/// [_ComposePageState._kMaxAttachBytes]。
class ComposePage extends StatefulWidget {
  const ComposePage({
    super.key,
    required this.accountEmail,
    this.contactPicker = pickSystemContactEmails,
  });

  /// 发件账号 —— 顶部「发件人」处展示，日后接入发信时作为 from。
  final String accountEmail;

  /// 选系统联系人的那一步 —— 默认走平台通道，测试注入假实现。
  final ContactEmailPicker contactPicker;

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final TextEditingController _to = TextEditingController();
  final TextEditingController _subject = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final FocusNode _toFocus = FocusNode();

  /// 正文的撤销 / 重做 —— 复用 Flutter 自带编辑历史，底部按钮据此置灰。
  final UndoHistoryController _undo = UndoHistoryController();

  MailImportance _importance = MailImportance.normal;

  /// 填了收件人才点亮发送按钮（设计稿里未填时是灰色）。
  bool _canSend = false;

  /// 发送中 —— 顶栏纸飞机换转圈、按钮禁用，避免重复提交。
  bool _sending = false;

  // ---- 正文排版态（整篇套用，非选区富文本）----
  bool _formatBarOpen = true;

  /// 排版栏这一行当前显示什么 —— 工具按钮 / 字号条 / 颜色条。
  _FormatPanel _panel = _FormatPanel.tools;

  double _fontSize = 16;
  bool _bold = false;
  bool _italic = false;
  bool _underline = false;
  Color? _color;

  /// 正文整篇对齐 —— 只用 left / center / right（设计稿三格）。
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

  /// 缩进单位 —— 无富文本引擎，用行首空格近似（HTML 输出靠 `white-space:pre-wrap` 保留）。
  static const String _kIndentUnit = '    ';

  @override
  void initState() {
    super.initState();
    _to.addListener(_onToChanged);
  }

  @override
  void dispose() {
    _to.removeListener(_onToChanged);
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    _toFocus.dispose();
    _undo.dispose();
    super.dispose();
  }

  void _onToChanged() {
    final can = _to.text.trim().isNotEmpty;
    if (can != _canSend) setState(() => _canSend = can);
  }

  /// 把一个地址追加进收件人框 —— 已有内容则先补 `; ` 分隔。
  void _appendRecipient(String address) {
    final text = _to.text.trimRight();
    final prefix = text.isEmpty
        ? ''
        : text.endsWith(';')
        ? '$text '
        : '$text; ';
    _to.text = '$prefix$address';
    _to.selection = TextSelection.collapsed(offset: _to.text.length);
    _toFocus.requestFocus();
  }

  /// 从系统通讯录选联系人 —— 取回其邮箱地址填进收件人框。
  ///
  /// 一个联系人可能留了多个邮箱，那就再让用户挑一个（挑错地址等于发错人，
  /// 不能默认取第一个）；没留邮箱或没权限都就地提示。
  Future<void> _pickContact() async {
    if (_pickingContact) return;
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
      setState(() => _appendRecipient(address));
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

  /// 在光标所在行行首插入列表前缀 —— 无富文本引擎，用纯文本近似。
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

  /// 收件人输入拆成地址列表 —— 支持分号 / 逗号 / 空白分隔，去空去重。
  List<String> _recipients() {
    return _to.text
        .split(RegExp(r'[;,\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  /// 极简邮箱校验 —— 只挡明显不合法（无 `@` / 无域名点），不做 RFC 全量校验。
  bool _looksLikeEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  /// 把正文与整篇排版态转成 Graph 可发送的正文（内容 + 是否 HTML）。
  ///
  /// 无任何格式改动 → 纯文本直发；一旦启用字号/加粗/斜体/下划线/颜色/对齐，
  /// 就包一层带内联样式的 `<div>`（`white-space:pre-wrap` 保留换行、空格与缩进），
  /// 并转义 HTML 特殊字符，避免正文里的 `<`/`&` 破坏结构。
  ({String content, bool isHtml}) _composeBody() {
    final text = _body.text;
    final hasFormat =
        _bold ||
        _italic ||
        _underline ||
        _color != null ||
        _fontSize != 16 ||
        _align != TextAlign.left;
    if (!hasFormat) return (content: text, isHtml: false);

    final styles = <String>[
      'white-space:pre-wrap',
      'font-size:${_fontSize.toInt()}px',
      if (_align != TextAlign.left) 'text-align:${_align.name}',
      if (_bold) 'font-weight:700',
      if (_italic) 'font-style:italic',
      if (_underline) 'text-decoration:underline',
      if (_color != null)
        'color:#${(_color!.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
    ];
    return (
      content: '<div style="${styles.join(';')}">${_escapeHtml(text)}</div>',
      isHtml: true,
    );
  }

  String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// 发送邮件 —— 校验收件人 → 调 Graph `sendMail` → 成功返回列表并提示，失败留在原页。
  Future<void> _send() async {
    if (_sending) return;
    final l10n = AppLocalizations.of(context);

    final recipients = _recipients();
    if (recipients.isEmpty) {
      _toast(l10n.composeNoRecipient);
      return;
    }
    final invalid = recipients.where((r) => !_looksLikeEmail(r));
    if (invalid.isNotEmpty) {
      _toast(l10n.composeInvalidRecipient(invalid.first));
      return;
    }

    final body = _composeBody();
    setState(() => _sending = true);

    final res = await ApiScope.of(context).mail.sendMail(
      widget.accountEmail,
      to: recipients,
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
            _buildFields(palette, l10n),
            if (_attachments.isNotEmpty) _buildAttachments(palette, l10n),
            Expanded(child: _buildBody(palette, l10n)),
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

  /// 四行表单 —— 收件人 / 抄送·发件人 / 重要性 / 主题，行间 1px 分隔线。
  Widget _buildFields(AppPalette palette, AppLocalizations l10n) {
    final valueStyle = TextStyle(
      color: palette.textPrimary,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
    return Column(
      children: [
        _FieldRow(
          label: l10n.composeTo,
          trailing: IconButton(
            onPressed: _pickingContact ? null : _pickContact,
            splashRadius: 20,
            tooltip: l10n.composeContactPick,
            icon: Icon(AppIcons.add, color: palette.textPrimary, size: 24),
          ),
          child: _inlineField(
            _to,
            valueStyle,
            palette,
            key: const Key('compose-to-field'),
            focusNode: _toFocus,
            keyboardType: TextInputType.emailAddress,
          ),
        ),
        // 发件人固定为当前账号（本页由该账号的邮件列表进入），故只展示不可改。
        _FieldRow(
          label: l10n.composeCcFrom,
          child: Text(
            widget.accountEmail,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: valueStyle,
          ),
        ),
        _FieldRow(
          label: l10n.composeImportance,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _buildImportance(palette, l10n, valueStyle),
          ),
        ),
        _FieldRow(
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

  /// 表单行里的无边框输入框 —— 只留文字，边框与内边距交给 [_FieldRow]。
  Widget _inlineField(
    TextEditingController controller,
    TextStyle style,
    AppPalette palette, {
    Key? key,
    FocusNode? focusNode,
    TextInputType? keyboardType,
  }) {
    return TextField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
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

  /// 正文 —— 撑满剩余高度的多行输入；排版态整篇套用。
  Widget _buildBody(AppPalette palette, AppLocalizations l10n) {
    final color = _color ?? palette.textPrimary;
    return TextField(
      key: const Key('compose-body-field'),
      controller: _body,
      undoController: _undo,
      maxLines: null,
      expands: true,
      textAlign: _align,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
      cursorColor: palette.primary,
      style: TextStyle(
        color: color,
        fontSize: _fontSize,
        height: 1.5,
        fontWeight: _bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: _italic ? FontStyle.italic : FontStyle.normal,
        decoration: _underline ? TextDecoration.underline : TextDecoration.none,
        decorationColor: color,
      ),
      decoration: InputDecoration(
        hintText: l10n.composeBodyHint,
        hintStyle: TextStyle(color: palette.textSecondary, fontSize: _fontSize),
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
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(top: BorderSide(color: palette.divider, width: 1)),
      ),
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
        active: _bold,
        onTap: () => setState(() => _bold = !_bold),
      ),
      _ToolButton(
        icon: AppIcons.italic,
        active: _italic,
        onTap: () => setState(() => _italic = !_italic),
      ),
      _ToolButton(
        icon: AppIcons.underline,
        active: _underline,
        onTap: () => setState(() => _underline = !_underline),
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
              '${_fontSize.toInt()}',
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

  /// 文字颜色入口 —— 图标染成当前色，点开把整行换成横向色点条。
  Widget _buildColorPicker(AppPalette palette) {
    return _ToolButton(
      icon: AppIcons.textColor,
      active: _panel == _FormatPanel.color,
      onTap: () => setState(() => _panel = _FormatPanel.color),
      iconColor: _color,
    );
  }

  /// 横向字号条 —— 点一下即生效并切回排版栏。
  List<Widget> _fontSizeOptions(AppPalette palette) {
    return <Widget>[
      for (final size in _fontSizes)
        _OptionChip(
          label: '${size.toInt()}',
          selected: size == _fontSize,
          onTap: () => setState(() {
            _fontSize = size;
            _panel = _FormatPanel.tools;
          }),
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
          selected: i == 0 ? _color == null : _color == colors[i],
          onTap: () => setState(() {
            _color = i == 0 ? null : colors[i];
            _panel = _FormatPanel.tools;
          }),
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
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.divider, width: 1)),
      ),
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

/// 表单行 —— 左侧灰色标签 + 内容区 + 可选尾部按钮，底部一条 1px 分隔线。
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.child, this.trailing});

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
            style: TextStyle(color: palette.textSecondary, fontSize: 16),
          ),
          const SizedBox(width: 10),
          Expanded(child: child),
          ?trailing,
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
