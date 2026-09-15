import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/services/fc_next_meal_remote.dart';
import 'package:canting/services/next_meal_recommendation.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'next_meal_recommendation_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('FC 默认关闭且未配置时不访问凭据或网络', () async {
    var credentialCalls = 0;
    final remote = FcNextMealRemote(
      configuration: FcNextMealConfiguration(
        endpoint: Uri.parse('https://example.invalid'),
        enabled: false,
        credentialAccess: (ref, use) async {
          credentialCalls++;
        },
      ),
    );
    await expectLater(
      remote.call(fixtures.request()),
      throwsA(isA<NextMealRemoteException>()),
    );
    expect(credentialCalls, 0);
  });

  test('空安全凭据映射为unauthorized，不把凭据写入结果', () async {
    final remote = FcNextMealRemote(
      configuration: FcNextMealConfiguration(
        endpoint: Uri.parse('https://example.invalid'),
        enabled: true,
        credentialAccess: (ref, use) async => use(''),
      ),
    );
    await expectLater(
      remote.call(fixtures.request()),
      throwsA(
        predicate<NextMealRemoteException>(
          (error) =>
              error.reasonCode == 'unauthorized' && error.statusCode == 401,
        ),
      ),
    );
  });

  test('适配器配置拒绝非HTTPS或带查询的端点', () {
    expect(
      FcNextMealConfiguration(
        endpoint: Uri.parse('http://localhost/recommend'),
        enabled: true,
        credentialAccess: (ref, use) async {},
      ).isUsable,
      isFalse,
    );
    expect(
      FcNextMealConfiguration(
        endpoint: Uri.parse('https://example.invalid?token=bad'),
        enabled: true,
        credentialAccess: (ref, use) async {},
      ).isUsable,
      isFalse,
    );
  });

  test('401/403/429/5xx等适配失败均由推荐服务本地降级', () async {
    for (final exception in const [
      NextMealRemoteException('unauthorized', 401),
      NextMealRemoteException('unauthorized', 403),
      NextMealRemoteException('rate_limited', 429),
      NextMealRemoteException('server_error', 500),
    ]) {
      final result = await NextMealRecommendationService(
        remote: (_) async => throw exception,
      ).nextMeal(fixtures.request());
      expect(result.source, 'local_rule');
      expect(result.reasonCode, exception.reasonCode);
    }
  });

  test('真实适配收发：POST /recommend、运行时Bearer和最小prompt均贯通', () async {
    Uri? endpoint;
    Map<String, String>? headers;
    String? body;
    final remote = FcNextMealRemote(
      configuration: FcNextMealConfiguration(
        endpoint: Uri.parse('https://fc.example.test'),
        enabled: true,
        credentialAccess: (ref, use) async => use('runtime-only-token'),
        transport: (requestEndpoint, requestHeaders, requestBody) async {
          endpoint = requestEndpoint;
          headers = requestHeaders;
          body = requestBody;
          return FcNextMealResponse(200, jsonEncode(fixtures.aiJson()));
        },
      ),
    );

    final result = await NextMealRecommendationService(remote: remote.call)
        .nextMeal(fixtures.request());

    expect(result.source, 'ai');
    expect(endpoint.toString(), 'https://fc.example.test/recommend');
    expect(
      headers![HttpHeaders.authorizationHeader],
      'Bearer runtime-only-token',
    );
    final decoded = jsonDecode(body!) as Map<String, dynamic>;
    final prompt = jsonDecode(decoded['prompt'] as String) as Map;
    expect(
      prompt.keys,
      containsAll(<String>[
        'requestId',
        'dataRevision',
        'nextMealType',
        'today',
        'rolling7d',
        'dietaryExclusions',
        'budget',
        'city',
        'availablePlatforms',
        'excludeDishNames',
      ]),
    );
    expect(prompt.keys, isNot(contains('mealRecords')));
    expect(prompt.keys, isNot(contains('profile')));
    expect(prompt.keys, isNot(contains('ocr')));
    expect(body, isNot(contains('runtime-only-token')));
  });

  test('FC非法JSON沿推荐服务约定重试一次后可成功', () async {
    var calls = 0;
    final remote = FcNextMealRemote(
      configuration: FcNextMealConfiguration(
        endpoint: Uri.parse('https://fc.example.test'),
        enabled: true,
        credentialAccess: (ref, use) async => use('runtime-token'),
        transport: (endpoint, headers, body) async {
          calls++;
          return calls == 1
              ? const FcNextMealResponse(200, '{bad-json')
              : FcNextMealResponse(200, jsonEncode(fixtures.aiJson()));
        },
      ),
    );

    final result = await NextMealRecommendationService(remote: remote.call)
        .nextMeal(fixtures.request());

    expect(result.source, 'ai');
    expect(calls, 2);
  });

  test('适配器实际状态码映射和超时均由服务本地降级', () async {
    for (final status in [401, 403, 429, 500]) {
      final remote = FcNextMealRemote(
        configuration: FcNextMealConfiguration(
          endpoint: Uri.parse('https://fc.example.test'),
          enabled: true,
          credentialAccess: (ref, use) async => use('runtime-token'),
          transport: (endpoint, headers, body) async =>
              FcNextMealResponse(status, '{}'),
        ),
      );
      final result = await NextMealRecommendationService(remote: remote.call)
          .nextMeal(fixtures.request());
      expect(result.source, 'local_rule');
      expect(
        result.reasonCode,
        status == 429
            ? 'rate_limited'
            : (status == 401 || status == 403)
            ? 'unauthorized'
            : 'server_error',
      );
    }

    final slowRemote = FcNextMealRemote(
      configuration: FcNextMealConfiguration(
        endpoint: Uri.parse('https://fc.example.test'),
        enabled: true,
        credentialAccess: (ref, use) async => use('runtime-token'),
        transport: (endpoint, headers, body) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return FcNextMealResponse(200, jsonEncode(fixtures.aiJson()));
        },
      ),
      timeout: const Duration(milliseconds: 5),
    );
    final timeoutResult = await NextMealRecommendationService(
      remote: slowRemote.call,
      timeout: const Duration(milliseconds: 20),
    ).nextMeal(fixtures.request());
    expect(timeoutResult.source, 'local_rule');
    expect(timeoutResult.reasonCode, 'timeout');
  });

  test('凭据慢于共享截止时间时不再发起请求', () async {
    var transportCalls = 0;
    final remote = FcNextMealRemote(
      configuration: FcNextMealConfiguration(
        endpoint: Uri.parse('https://fc.example.test'),
        enabled: true,
        credentialAccess: (ref, use) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await use('runtime-token');
        },
        transport: (endpoint, headers, body) async {
          transportCalls++;
          return FcNextMealResponse(200, jsonEncode(fixtures.aiJson()));
        },
      ),
    );

    final result = await NextMealRecommendationService(
      remoteWithBudget: remote.callWithBudget,
      timeout: const Duration(milliseconds: 10),
    ).nextMeal(fixtures.request());

    expect(result.source, 'local_rule');
    expect(result.reasonCode, 'timeout');
    expect(transportCalls, 0);
  });

  test('AppState配置接线可到达远端，缺凭据配置保持本地', () async {
    var calls = 0;
    final helper = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final configured = AppState(
      databaseHelper: helper,
      nextMealRemoteConfiguration: FcNextMealConfiguration(
        endpoint: Uri.parse('https://fc.example.test'),
        enabled: true,
        credentialAccess: (ref, use) async => use('runtime-token'),
        transport: (endpoint, headers, body) async {
          calls++;
          return FcNextMealResponse(200, jsonEncode(fixtures.aiJson()));
        },
      ),
    );
    final result = await configured.nextMealService.nextMeal(
      fixtures.request(),
    );
    expect(result.source, 'ai');
    expect(calls, 1);

    final local = AppState(
      databaseHelper: helper,
      nextMealRemoteConfiguration: const FcNextMealConfiguration(
        endpoint: null,
        enabled: false,
      ),
    );
    final localResult = await local.nextMealService.nextMeal(
      fixtures.request(),
    );
    expect(localResult.source, 'local_rule');
    expect(localResult.reasonCode, 'unconfigured');
    await helper.close();
  });
}
