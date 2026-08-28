import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:email_manager/api/auth_api.dart';
import 'package:email_manager/core/auth/credentials_store.dart';
import 'package:email_manager/core/auth/token_service.dart';
import 'package:email_manager/core/auth/token_store.dart';
import 'package:email_manager/core/network/api_client.dart';
import 'package:email_manager/core/network/api_code.dart';
import 'package:email_manager/core/network/api_exception.dart';
import 'package:email_manager/core/network/error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可编程的假 HttpClientAdapter —— 不联网，按预设返回，并统计调用次数。
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter({
    required this.statusCode,
    required this.body,
    this.delay = Duration.zero,
  });

  int statusCode;
  Object body; // Map/List → 编码为 JSON 字符串
  Duration delay;

  /// fetch 被调用次数 —— 用于断言「刷新去重只打一次」。
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.httpClientAdapter = adapter;
  return dio;
}

void main() {
  group('ApiClient 归一化', () {
    test('Graph 成功 body → ApiResponse(code:0, data)', () async {
      final adapter = FakeAdapter(
        statusCode: 200,
        body: {
          'value': [
            {'id': '1', 'subject': 'hi'},
          ],
        },
      );
      final client = ApiClient(_dioWith(adapter));

      final resp = await client.get<Map<String, dynamic>>(
        '/me/messages',
        parser: (json) => json as Map<String, dynamic>,
      );

      expect(resp.isSuccess, isTrue);
      expect(resp.code, ApiCode.ok);
      expect((resp.data!['value'] as List).length, 1);
    });

    test('Graph 错误 {error:{code,message}} → 归一化出 code/message', () async {
      final adapter = FakeAdapter(
        statusCode: 403,
        body: {
          'error': {'code': 'ErrorAccessDenied', 'message': '无权访问该邮箱'},
        },
      );
      final client = ApiClient(_dioWith(adapter));

      final resp = await client.get<dynamic>(
        '/me/messages',
        parser: (json) => json,
      );

      expect(resp.isSuccess, isFalse);
      expect(resp.code, ApiCode.forbidden);
      expect(resp.message, '无权访问该邮箱');
    });

    test('OAuth invalid_grant → 映射为鉴权失败码', () async {
      final adapter = FakeAdapter(
        statusCode: 400,
        body: {
          'error': 'invalid_grant',
          'error_description': 'refresh token 已失效',
        },
      );
      final client = ApiClient(_dioWith(adapter));

      final resp = await client.post<dynamic>(
        '/token',
        data: {'grant_type': 'refresh_token'},
        parser: (json) => json,
      );

      expect(resp.isSuccess, isFalse);
      expect(resp.code, ApiCode.unauthorized);
      expect(resp.message, 'refresh token 已失效');
    });

    test('OAuth unauthorized_client（AADSTS700016）→ 映射为鉴权失败码', () async {
      // 400 + unauthorized_client：client_id 未在账号所属目录注册，
      // 属凭据/授权失败而非普通业务错误，须归一化为 unauthorized，
      // 健康检测才能据此把账号标记为凭据失效。
      final adapter = FakeAdapter(
        statusCode: 400,
        body: {
          'error': 'unauthorized_client',
          'error_description':
              "AADSTS700016: Application with identifier 'x' was not found",
        },
      );
      final client = ApiClient(_dioWith(adapter));

      final resp = await client.post<dynamic>(
        '/token',
        data: {'grant_type': 'refresh_token'},
        parser: (json) => json,
      );

      expect(resp.isSuccess, isFalse);
      expect(resp.code, ApiCode.unauthorized);
    });
  });

  group('mapError', () {
    test('连接超时 → timeout 类异常', () {
      final ex = mapError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionTimeout,
        ),
      );
      expect(ex, isA<ApiException>());
      expect(ex.code, ApiCode.timeout);
      expect(ex.type, ApiErrorType.timeout);
    });

    test('连接失败 → network 类异常', () {
      final ex = mapError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(ex.code, ApiCode.network);
      expect(ex.type, ApiErrorType.network);
    });
  });

  group('TokenService 并发刷新去重', () {
    test('同账号并发取 token 只打一次 OAuth 请求', () async {
      // 刷新接口带延迟，制造并发窗口。
      final adapter = FakeAdapter(
        statusCode: 200,
        body: {'access_token': 'AT', 'expires_in': 3600, 'refresh_token': 'RT2'},
        delay: const Duration(milliseconds: 50),
      );
      final authApi = AuthApi(ApiClient(_dioWith(adapter)));
      final creds = InMemoryCredentialsStore([
        const AccountCredentials(
          email: 'a@outlook.com',
          clientId: 'cid',
          refreshToken: 'RT1',
        ),
      ]);
      final service = TokenService(
        authApi: authApi,
        tokenStore: InMemoryTokenStore(),
        credentialsStore: creds,
      );

      // 5 个并发请求，应合流为一次刷新。
      final tokens = await Future.wait([
        for (var i = 0; i < 5; i++) service.accessTokenFor('a@outlook.com'),
      ]);

      expect(tokens.every((t) => t == 'AT'), isTrue);
      expect(adapter.calls, 1);
      // 轮换的 refresh_token 已回写。
      expect((await creds.find('a@outlook.com'))!.refreshToken, 'RT2');
    });

    test('缓存命中不再刷新', () async {
      final adapter = FakeAdapter(
        statusCode: 200,
        body: {'access_token': 'AT', 'expires_in': 3600},
      );
      final service = TokenService(
        authApi: AuthApi(ApiClient(_dioWith(adapter))),
        tokenStore: InMemoryTokenStore(),
        credentialsStore: InMemoryCredentialsStore([
          const AccountCredentials(
            email: 'a@outlook.com',
            clientId: 'cid',
            refreshToken: 'RT1',
          ),
        ]),
      );

      await service.accessTokenFor('a@outlook.com');
      await service.accessTokenFor('a@outlook.com');

      expect(adapter.calls, 1); // 第二次命中缓存
    });
  });
}
