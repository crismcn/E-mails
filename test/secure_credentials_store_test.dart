import 'package:email_manager/core/auth/credentials_store.dart';
import 'package:email_manager/core/storage/secure_storage.dart';
import 'package:email_manager/data/account_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存假 SecureStorage —— 免平台通道，验证凭据的存取/枚举/删除。
class FakeSecureStorage implements SecureStorage {
  final Map<String, String> _map = {};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<Map<String, String>> readAll() async => Map.of(_map);

  @override
  Future<void> deleteAll() async => _map.clear();
}

void main() {
  group('SecureCredentialsStore', () {
    late FakeSecureStorage storage;
    late SecureCredentialsStore store;

    setUp(() {
      storage = FakeSecureStorage();
      store = SecureCredentialsStore(storage);
    });

    test('写入后可读回，字段完整', () async {
      await store.update(const AccountCredentials(
        email: 'a@outlook.com',
        clientId: 'cid',
        refreshToken: 'RT1',
        password: 'pw',
      ));

      final read = await store.find('a@outlook.com');
      expect(read, isNotNull);
      expect(read!.clientId, 'cid');
      expect(read.refreshToken, 'RT1');
      expect(read.password, 'pw');
    });

    test('凭据以密文外的独立键存储，可按前缀枚举邮箱', () async {
      await store.upsertAll([
        const AccountCredentials(
            email: 'a@outlook.com', clientId: 'c', refreshToken: 'r'),
        const AccountCredentials(
            email: 'b@outlook.com', clientId: 'c', refreshToken: 'r'),
      ]);

      final emails = await store.listEmails();
      expect(emails, containsAll(['a@outlook.com', 'b@outlook.com']));
      // 底层键带前缀，避免与其他用途的键冲突。
      expect((await storage.readAll()).keys, contains('cred.a@outlook.com'));
    });

    test('refresh_token 轮换回写覆盖旧值', () async {
      await store.update(const AccountCredentials(
          email: 'a@outlook.com', clientId: 'c', refreshToken: 'old'));
      final updated =
          (await store.find('a@outlook.com'))!.copyWith(refreshToken: 'new');
      await store.update(updated);

      expect((await store.find('a@outlook.com'))!.refreshToken, 'new');
    });

    test('删除后读不到', () async {
      await store.update(const AccountCredentials(
          email: 'a@outlook.com', clientId: 'c', refreshToken: 'r'));
      await store.remove('a@outlook.com');

      expect(await store.find('a@outlook.com'), isNull);
      expect(await store.listEmails(), isEmpty);
    });

    test('由导入记录持久化', () async {
      await store.upsertAll([
        const ImportedAccount(
          email: 'a@outlook.com',
          password: 'pw',
          clientId: 'cid',
          refreshToken: 'RT',
          createdAt: '2026-08-27',
        ),
      ].map(AccountCredentials.fromImported));

      final read = await store.find('a@outlook.com');
      expect(read!.refreshToken, 'RT');
      expect(read.password, 'pw');
      // 导入即「未知」状态（尚未检测）。
      expect(read.status, AccountCredentials.statusUnknown);
    });

    test('状态与账号信息可落盘并回读，findAll 返回完整记录', () async {
      await store.update(const AccountCredentials(
        email: 'a@outlook.com',
        clientId: 'c',
        refreshToken: 'r',
        status: AccountCredentials.statusValid,
        displayName: '张三',
        address: 'a@outlook.com',
        userId: 'u-1',
      ));

      final read = await store.find('a@outlook.com');
      expect(read!.status, AccountCredentials.statusValid);
      expect(read.displayName, '张三');
      expect(read.userId, 'u-1');

      final all = await store.findAll();
      expect(all, hasLength(1));
      expect(all.single.displayName, '张三');
    });
  });
}
