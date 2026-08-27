import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_scope.dart';
import '../data/account_import.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_palette.dart';

/// 导入邮箱页 —— 支持 CSV 文件导入与文本粘贴导入。
///
/// 约定格式：`邮箱----密码----client_id----refresh_token----创建时间`。
class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  static const int _maxChars = 5000;

  final TextEditingController _pasteController = TextEditingController();
  String? _csvName;
  String _csvContent = '';

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _pickCsv() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _csvName = file.name;
      _csvContent = utf8.decode(bytes, allowMalformed: true);
    });
  }

  Future<void> _onConfirm() async {
    final l10n = AppLocalizations.of(context);
    final api = ApiScope.of(context);
    final navigator = Navigator.of(context);
    final buffer = StringBuffer()
      ..writeln(_pasteController.text)
      ..writeln(_csvContent);
    final source = buffer.toString().trim();

    final messenger = ScaffoldMessenger.of(context);
    void show(String text) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }

    if (source.isEmpty) {
      show(l10n.importEmpty);
      return;
    }

    final parsed = parseImportText(source);
    if (parsed.accounts.isEmpty) {
      show(l10n.importNoValid);
      return;
    }

    // 持久化到安全存储（refresh_token / client_id / password 等长期凭据落盘）。
    await api.saveImported(parsed.accounts);
    if (!mounted) return;

    var message = l10n.importResultCount(parsed.accounts.length);
    if (parsed.invalidLines > 0) {
      message += l10n.importResultInvalid(parsed.invalidLines);
    }
    show(message);
    // 持久化成功后返回首页（携带结果，首页据此重新载入已存账号）。
    navigator.maybePop(parsed.accounts);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(title: l10n.importTitle),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _SectionLabel(l10n.importCsvSection),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _CsvDropZone(fileName: _csvName, onTap: _pickCsv),
                  ),
                  const SizedBox(height: 28),
                  _SectionLabel(l10n.importPasteSection),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _PasteField(
                      controller: _pasteController,
                      maxChars: _maxChars,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _SectionLabel(l10n.importFormatSection),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _FormatCard(),
                  ),
                ],
              ),
            ),
            _ConfirmBar(label: l10n.importConfirm, onPressed: _onConfirm),
          ],
        ),
      ),
    );
  }
}

/// 顶部标题栏：返回 + 标题，平铺无边框（与设置页一致）。
class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: palette.textPrimary, size: 20),
            splashRadius: 22,
          ),
          const SizedBox(width: 4),
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分组小标题（主色、加粗，间距克制）。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Text(
        text,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// CSV 选择区：虚线卡片，点击选择 .csv 文件；已选则显示文件名。
class _CsvDropZone extends StatelessWidget {
  const _CsvDropZone({required this.fileName, required this.onTap});

  final String? fileName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    final picked = fileName != null;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          child: Column(
            children: [
              Icon(
                picked
                    ? Icons.check_circle_outline
                    : Icons.file_upload_outlined,
                color: picked ? palette.primary : palette.textSecondary,
                size: 36,
              ),
              const SizedBox(height: 14),
              Text(
                picked ? l10n.importCsvPicked(fileName!) : l10n.importCsvHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.importCsvOnly,
                style: TextStyle(color: palette.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 粘贴数据输入框：多行、带字数上限与 0/5000 计数。
class _PasteField extends StatelessWidget {
  const _PasteField({required this.controller, required this.maxChars});

  final TextEditingController controller;
  final int maxChars;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return TextField(
      key: const Key('import-paste-field'),
      controller: controller,
      maxLines: 8,
      maxLength: maxChars,
      style: TextStyle(color: palette.textPrimary, fontSize: 14, height: 1.5),
      cursorColor: palette.primary,
      decoration: InputDecoration(
        filled: true,
        fillColor: palette.card,
        hintText: l10n.importPasteHint,
        hintStyle: TextStyle(
          color: palette.textSecondary,
          fontSize: 14,
          height: 1.5,
        ),
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        counterStyle: TextStyle(color: palette.textSecondary, fontSize: 12),
      ),
    );
  }
}

/// 格式说明卡片：字段 → 含义 的对照表。
class _FormatCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    final rows = <List<String>>[
      [l10n.importFieldEmail, l10n.importFieldEmailDesc],
      [l10n.importFieldPassword, l10n.importFieldPasswordDesc],
      [l10n.importFieldClientId, l10n.importFieldClientIdDesc],
      [l10n.importFieldRefreshToken, l10n.importFieldRefreshTokenDesc],
      [l10n.importFieldCreatedAt, l10n.importFieldCreatedAtDesc],
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(color: palette.divider, height: 1, thickness: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      rows[i][0],
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rows[i][1],
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 底部固定的「确认导入」按钮（椭圆形，无提示文案）。
class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({required this.label, required this.onPressed});

  /// 微软蓝（Fluent / Communication Blue）。
  static const Color _msBlue = Color(0xFF0078D4);

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: _msBlue,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
