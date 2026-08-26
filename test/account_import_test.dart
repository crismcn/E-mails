import 'package:flutter_test/flutter_test.dart';

import 'package:email_manager/data/account_import.dart';

void main() {
  group('parseImportText', () {
    test('解析标准 ---- 分隔格式', () {
      const raw =
          'alice@outlook.com----pass1----cid1----token1----2024-01-01 10:00:00\n'
          'bob@outlook.com----pass2----cid2----token2----2024-02-02 11:00:00';
      final result = parseImportText(raw);

      expect(result.accounts.length, 2);
      expect(result.invalidLines, 0);
      expect(result.accounts.first.email, 'alice@outlook.com');
      expect(result.accounts.first.password, 'pass1');
      expect(result.accounts.first.clientId, 'cid1');
      expect(result.accounts.first.refreshToken, 'token1');
      expect(result.accounts.first.createdAt, '2024-01-01 10:00:00');
    });

    test('回退到逗号分隔（CSV）', () {
      const raw = 'carol@outlook.com,pass,cid,token,2024-03-03 09:00:00';
      final result = parseImportText(raw);

      expect(result.accounts.length, 1);
      expect(result.accounts.first.email, 'carol@outlook.com');
      expect(result.accounts.first.createdAt, '2024-03-03 09:00:00');
    });

    test('字段不足或非法邮箱计入无效行', () {
      const raw = 'not-an-email----pass----cid----token----time\n'
          'incomplete@outlook.com----pass\n'
          'dave@outlook.com----pass----cid----token----2024-01-01 00:00:00';
      final result = parseImportText(raw);

      expect(result.accounts.length, 1);
      expect(result.accounts.first.email, 'dave@outlook.com');
      expect(result.invalidLines, 2);
    });

    test('忽略空行', () {
      const raw = '\n\n  \n'
          'eve@outlook.com----p----c----t----2024-01-01 00:00:00\n\n';
      final result = parseImportText(raw);

      expect(result.accounts.length, 1);
      expect(result.invalidLines, 0);
    });
  });
}
