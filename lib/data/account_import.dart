/// 导入邮箱的解析逻辑。
///
/// 约定格式（每行一条）：
/// `邮箱----密码----client_id----refresh_token----创建时间`
/// CSV 文件中同样支持以逗号分隔的等价字段。
library;

/// 单条导入记录。
class ImportedAccount {
  const ImportedAccount({
    required this.email,
    required this.password,
    required this.clientId,
    required this.refreshToken,
    required this.createdAt,
  });

  final String email;
  final String password;
  final String clientId;
  final String refreshToken;
  final String createdAt;
}

/// 解析结果：有效记录 + 无效行数。
class ImportResult {
  const ImportResult({required this.accounts, required this.invalidLines});

  final List<ImportedAccount> accounts;
  final int invalidLines;

  bool get isEmpty => accounts.isEmpty && invalidLines == 0;
}

/// 主分隔符（四连字符）。CSV 场景下回退到逗号分隔。
const String _kDelimiter = '----';

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// 解析粘贴文本或 CSV 内容为账号列表。
///
/// 逐行解析：优先按 `----` 拆分，若拆不出多个字段再按 `,` 拆分。
/// 至少需要 5 个字段且首字段为合法邮箱，否则计入 [ImportResult.invalidLines]。
ImportResult parseImportText(String raw) {
  final accounts = <ImportedAccount>[];
  var invalid = 0;

  for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    List<String> parts = line.split(_kDelimiter);
    if (parts.length < 5) {
      parts = line.split(',');
    }
    parts = parts.map((p) => p.trim()).toList();

    if (parts.length < 5 || !_emailPattern.hasMatch(parts[0])) {
      invalid++;
      continue;
    }

    accounts.add(
      ImportedAccount(
        email: parts[0],
        password: parts[1],
        clientId: parts[2],
        refreshToken: parts[3],
        // 创建时间可能包含分隔符外的空格，取剩余字段拼回以保持完整。
        createdAt: parts.sublist(4).join(' ').trim(),
      ),
    );
  }

  return ImportResult(accounts: accounts, invalidLines: invalid);
}
