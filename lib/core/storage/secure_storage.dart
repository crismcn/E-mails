import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 键值安全存储的抽象 —— 只暴露本层需要的能力。
///
/// 抽象出接口而非直接依赖 [FlutterSecureStorage]，是为了：
/// - 上层（凭据存储）不感知具体后端；
/// - 单元测试可注入内存假实现，免去平台通道 mock。
abstract class SecureStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
  Future<void> deleteAll();
}

/// 基于 flutter_secure_storage 的实现 —— iOS Keychain / Android Keystore(AES-GCM)。
///
/// v11 默认即用 AES-GCM 加密，无需再设 `encryptedSharedPreferences`。
class FlutterSecureStorageAdapter implements SecureStorage {
  FlutterSecureStorageAdapter([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}
