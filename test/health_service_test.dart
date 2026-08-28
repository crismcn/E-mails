import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:email_manager/api/auth_api.dart';
import 'package:email_manager/api/user_api.dart';
import 'package:email_manager/core/auth/credentials_store.dart';
import 'package:email_manager/core/auth/health_service.dart';
import 'package:email_manager/core/network/api_client.dart';
import 'package:email_manager/core/network/api_code.dart';
import 'package:email_manager/core/network/api_config.dart';
import 'package:email_manager/core/network/api_response.dart';

/// 假 OAuth 接口 —— 记录收到的 scope，按预置信封返回。
class _FakeAuthApi extends AuthApi {
  _FakeAuthApi(this.result) : super(ApiClient(Dio()));

  final ApiResponse<TokenResult> result;
  String? lastScope;
  int calls = 0;

  @override
  Future<ApiResponse<TokenResult>> refreshToken({
    required String clientId,
    required String refreshToken,
    String scope = ApiConfig.defaultScope,
    String? clientSecret,
  }) async {
    calls++;
    lastScope = scope;
    return result;
  }
}

/// 假 `/me` 接口 —— 记录收到的 token，按预置信封返回。
class _FakeUserApi extends UserApi {
  _FakeUserApi(this.result) : super(ApiClient(Dio()));

  final ApiResponse<GraphUser> result;
  String? lastToken;
  int calls = 0;

  @override
  Future<ApiResponse<GraphUser>> getMe(String accessToken) async {
    calls++;
    lastToken = accessToken;
    return result;
  }
}

const _okToken = ApiResponse<TokenResult>.success(
  TokenResult(accessToken: 'at-1', expiresIn: 3600),
);

const _okUser = ApiResponse<GraphUser>.success(
  GraphUser(
    id: 'u-1',
    displayName: '张三',
    userPrincipalName: 'a@outlook.com',
    mail: '',
  ),
);

HealthService _service({
  required ApiResponse<TokenResult> token,
  required ApiResponse<GraphUser> user,
  CredentialsStore? store,
  _FakeAuthApi? authApi,
  _FakeUserApi? userApi,
}) {
  return HealthService(
    authApi: authApi ?? _FakeAuthApi(token),
    userApi: userApi ?? _FakeUserApi(user),
    credentialsStore: store ??
        InMemoryCredentialsStore(const [
          AccountCredentials(
            email: 'a@outlook.com',
            clientId: 'c',
            refreshToken: 'r',
          ),
        ]),
  );
}

void main() {
  test('两步都通过 → ok，并带回 /me 的账号信息', () async {
    final auth = _FakeAuthApi(_okToken);
    final user = _FakeUserApi(_okUser);
    final store = InMemoryCredentialsStore(const [
      AccountCredentials(email: 'a@outlook.com', clientId: 'c', refreshToken: 'r'),
    ]);
    final report = await _service(
      token: _okToken,
      user: _okUser,
      authApi: auth,
      userApi: user,
      store: store,
    ).check('a@outlook.com');

    expect(report.isOk, isTrue);
    expect(report.displayName, '张三');
    // mail 为空时回退 userPrincipalName。
    expect(report.address, 'a@outlook.com');
    expect(report.userId, 'u-1');
    // 健康检测用 `.default`（账号已授权的全部权限），与邮件业务一致，
    // 避免申请未授权 scope 触发 AADSTS70000 误判。
    expect(auth.lastScope, ApiConfig.healthCheckScope);
    // /me 用的是刚换到的 token。
    expect(user.lastToken, 'at-1');
    // 结论与账号信息已落盘（供首页刷新/统计以持久化为准）。
    final saved = (await store.find('a@outlook.com'))!;
    expect(saved.status, AccountCredentials.statusValid);
    expect(saved.displayName, '张三');
    expect(saved.userId, 'u-1');
  });

  test('refresh_token 失效（invalid_grant → 401）→ 凭据失效，且不再打 /me', () async {
    final user = _FakeUserApi(_okUser);
    final store = InMemoryCredentialsStore(const [
      AccountCredentials(email: 'a@outlook.com', clientId: 'c', refreshToken: 'r'),
    ]);
    final report = await _service(
      token: const ApiResponse<TokenResult>.failure(
        ApiCode.unauthorized,
        'invalid_grant',
      ),
      user: _okUser,
      userApi: user,
      store: store,
    ).check('a@outlook.com');

    expect(report.isCredentialsInvalid, isTrue);
    expect(report.message, 'invalid_grant');
    expect(user.calls, 0);
    // 凭据失效落盘为 Token 过期。
    expect((await store.find('a@outlook.com'))!.status,
        AccountCredentials.statusTokenExpired);
  });

  test('换到 token 但 /me 401/403（账号未授权 User.Read）→ 仍判有效，只是缺账号信息',
      () async {
    final store = InMemoryCredentialsStore(const [
      AccountCredentials(email: 'a@outlook.com', clientId: 'c', refreshToken: 'r'),
    ]);
    final report = await _service(
      token: _okToken,
      user: const ApiResponse<GraphUser>.failure(
        ApiCode.forbidden,
        'insufficient privileges',
      ),
      store: store,
    ).check('a@outlook.com');

    // 能换到 token 即账号可用；/me 读不到（多因未授权 User.Read）不改判。
    expect(report.isOk, isTrue);
    expect(report.displayName, isNull);
    expect((await store.find('a@outlook.com'))!.status,
        AccountCredentials.statusValid);
  });

  test('网络错误 → networkError（不判定为凭据失效）', () async {
    final report = await _service(
      token: const ApiResponse<TokenResult>.failure(ApiCode.network, '网络连接失败'),
      user: _okUser,
    ).check('a@outlook.com');

    expect(report.status, HealthStatus.networkError);
    expect(report.isCredentialsInvalid, isFalse);
  });

  test('无凭据 → 凭据失效，且不发任何请求', () async {
    final auth = _FakeAuthApi(_okToken);
    final report = await _service(
      token: _okToken,
      user: _okUser,
      store: InMemoryCredentialsStore(const []),
      authApi: auth,
    ).check('missing@outlook.com');

    expect(report.isCredentialsInvalid, isTrue);
    expect(auth.calls, 0);
  });

  test('微软轮换 refresh_token → 回写存储', () async {
    final store = InMemoryCredentialsStore(const [
      AccountCredentials(
        email: 'a@outlook.com',
        clientId: 'c',
        refreshToken: 'old',
      ),
    ]);
    await _service(
      token: const ApiResponse<TokenResult>.success(
        TokenResult(accessToken: 'at-1', expiresIn: 3600, refreshToken: 'new'),
      ),
      user: _okUser,
      store: store,
    ).check('a@outlook.com');

    expect((await store.find('a@outlook.com'))!.refreshToken, 'new');
  });

  test('批量检测 → 逐账号独立成败', () async {
    final store = InMemoryCredentialsStore(const [
      AccountCredentials(email: 'a@outlook.com', clientId: 'c', refreshToken: 'r'),
      AccountCredentials(email: 'b@outlook.com', clientId: 'c', refreshToken: 'r'),
    ]);
    final reports = await _service(
      token: _okToken,
      user: _okUser,
      store: store,
    ).checkAll(['a@outlook.com', 'missing@outlook.com']);

    expect(reports.length, 2);
    expect(reports[0].isOk, isTrue);
    expect(reports[1].isCredentialsInvalid, isTrue);
  });
}
