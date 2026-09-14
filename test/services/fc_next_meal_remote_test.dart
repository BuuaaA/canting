import 'package:canting/services/fc_next_meal_remote.dart';
import 'package:canting/services/next_meal_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'next_meal_recommendation_test.dart' as fixtures;

void main() {
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
}
