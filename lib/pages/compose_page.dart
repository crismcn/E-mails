import 'package:flutter/material.dart';

import '../api/api_scope.dart';
import '../l10n/app_localizations.dart';
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

/// 新建邮件页 —— 视觉 1:1 参照「新建邮件.jpg」设计稿。
///
/// 结构：顶栏（返回 / 标题 / 附件 / 发送）+ 四行表单（收件人、抄送·发件人、重要性、
/// 主题）+ 正文编辑区 + 底部两条工具栏（排版栏 + 撤销·重做·Aa·图片）。
///
/// 排版工具栏的取舍：正文是**纯文本** [TextField]，没有富文本引擎，所以字号 / 加粗 /
/// 斜体 / 下划线 / 颜色都**整篇套用**（不是选区富文本）；两个列表按钮在光标所在行
/// 行首插入 `• ` / `N. ` 纯文本前缀。发送与附件尚未接入（CLAUDE.md §10 路线图 5）。
class ComposePage extends StatefulWidget {
  const ComposePage({super.key, required this.accountEmail});

  /// 发件账号 —— 顶部「发件人」处展示，日后接入发信时作为 from。
  final String accountEmail;

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
  double _fontSize = 16;
  bool _bold = false;
  bool _italic = false;
  bool _underline = false;
  Color? _color;

  static const List<double> _fontSizes = <double>[12, 14, 16, 18, 20, 24];

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

  /// 追加下一个收件人 —— 补分隔符并聚焦，方便连续填多个地址。
  void _addRecipient() {
    final text = _to.text.trimRight();
    if (text.isNotEmpty && !text.endsWith(';')) _to.text = '$text; ';
    _to.selection = TextSelection.collapsed(offset: _to.text.length);
    _toFocus.requestFocus();
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
  /// 无任何格式改动 → 纯文本直发；一旦启用字号/加粗/斜体/下划线/颜色，
  /// 就包一层带内联样式的 `<div>`（`white-space:pre-wrap` 保留换行与空格），
  /// 并转义 HTML 特殊字符，避免正文里的 `<`/`&` 破坏结构。
  ({String content, bool isHtml}) _composeBody() {
    final text = _body.text;
    final hasFormat =
        _bold || _italic || _underline || _color != null || _fontSize != 16;
    if (!hasFormat) return (content: text, isHtml: false);

    final styles = <String>[
      'white-space:pre-wrap',
      'font-size:${_fontSize.toInt()}px',
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
            icon: Icon(
              Icons.arrow_back_ios_new,
              color: palette.textPrimary,
              size: 20,
            ),
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
            onPressed: () => _toast(l10n.composeAttachTodo),
            splashRadius: 22,
            icon: Icon(Icons.attach_file, color: palette.textPrimary, size: 24),
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
                      valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
                    ),
                  )
                : Icon(
                    Icons.send_outlined,
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
            onPressed: _addRecipient,
            splashRadius: 20,
            icon: Icon(Icons.add, color: palette.textPrimary, size: 24),
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
          Icon(Icons.arrow_drop_down, color: palette.textPrimary, size: 20),
        ],
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

  /// 排版栏 —— 字号 ▾ / B / I / U / A(颜色) / 无序列表 / 有序列表 / 关闭。
  Widget _buildFormatBar(AppPalette palette) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(top: BorderSide(color: palette.divider, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildFontSizePicker(palette),
          _ToolButton(
            icon: Icons.format_bold,
            active: _bold,
            onTap: () => setState(() => _bold = !_bold),
          ),
          _ToolButton(
            icon: Icons.format_italic,
            active: _italic,
            onTap: () => setState(() => _italic = !_italic),
          ),
          _ToolButton(
            icon: Icons.format_underlined,
            active: _underline,
            onTap: () => setState(() => _underline = !_underline),
          ),
          _buildColorPicker(palette),
          _ToolButton(
            icon: Icons.format_list_bulleted,
            onTap: () => _insertListPrefix(numbered: false),
          ),
          _ToolButton(
            icon: Icons.format_list_numbered,
            onTap: () => _insertListPrefix(numbered: true),
          ),
          _ToolButton(
            icon: Icons.close,
            onTap: () => setState(() => _formatBarOpen = false),
          ),
        ],
      ),
    );
  }

  /// 字号选择 —— 数字 + ▾，选中值即正文字号（整篇）。
  Widget _buildFontSizePicker(AppPalette palette) {
    return PopupMenuButton<double>(
      initialValue: _fontSize,
      color: palette.card,
      onSelected: (value) => setState(() => _fontSize = value),
      itemBuilder: (context) => <PopupMenuEntry<double>>[
        for (final size in _fontSizes)
          PopupMenuItem<double>(
            value: size,
            child: Text(
              '${size.toInt()}',
              style: TextStyle(color: palette.textPrimary, fontSize: 15),
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_fontSize.toInt()}',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          Icon(Icons.arrow_drop_down, color: palette.textPrimary, size: 20),
        ],
      ),
    );
  }

  /// 文字颜色 —— 一列色点，首项「跟随主题」（存 null，切主题不会留下旧色）。
  Widget _buildColorPicker(AppPalette palette) {
    final colors = <Color>[
      palette.textPrimary,
      palette.primary,
      palette.statusError,
      palette.statusWarning,
      const Color(0xFF34C759),
    ];
    return PopupMenuButton<int>(
      color: palette.card,
      onSelected: (index) =>
          setState(() => _color = index == 0 ? null : colors[index]),
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        for (var i = 0; i < colors.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 40,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: colors[i],
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
      child: Icon(
        Icons.format_color_text,
        color: _color ?? palette.textPrimary,
        size: 22,
      ),
    );
  }

  /// 底栏 —— 撤销 / 重做（按正文编辑历史自动置灰）+ Aa（开合排版栏）+ 图片。
  Widget _buildBottomBar(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.divider, width: 1)),
      ),
      child: ValueListenableBuilder<UndoHistoryValue>(
        valueListenable: _undo,
        builder: (context, value, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ToolButton(
              icon: Icons.undo,
              onTap: value.canUndo ? _undo.undo : null,
            ),
            _ToolButton(
              icon: Icons.redo,
              onTap: value.canRedo ? _undo.redo : null,
            ),
            _AaToggle(
              active: _formatBarOpen,
              onTap: () => setState(() => _formatBarOpen = !_formatBarOpen),
            ),
            _ToolButton(
              icon: Icons.image_outlined,
              onTap: () => _toast(l10n.composeAttachTodo),
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
class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, this.onTap, this.active = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final Color color = onTap == null
        ? palette.textSecondary.withValues(alpha: 0.4)
        : active
        ? palette.primary
        : palette.textPrimary;
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Icon(icon, color: color, size: 24),
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

