import 'package:canting/services/fc_next_meal_remote.dart';
import 'package:canting/services/intake_statistics.dart';
import 'package:canting/services/next_meal_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

/// VM-only integration check: dart:io HttpClient reaches the user FC and an
/// explicitly fake credential is rejected. The request contains only this
/// fixed empty-stat sample; never replace the fake token with a real secret.
void main() {
  test('真实 FC 请求：虚构凭据 401 后本地降级', () async {
    final remote = FcNextMealRemote(
      configuration: FcNextMealConfiguration(
        endpoint: Uri.parse(
          'https://cantingan-proxy-lutwihtgyl.cn-beijing.fcapp.run',
        ),
        enabled: true,
        credentialAccess: (ref, use) async => use('invalid-dev-token'),
      ),
    );
    final request = NextMealRequest(
      requestId: 'real-network-invalid-credential',
      today: const TodayIntakeStats(
        date: '2026-09-15',
        revision: 0,
        categories: {},
        completeness: 'complete',
      ),
      rolling7d: Rolling7dIntakeStats(
        startDate: '2026-09-09',
        endDate: '2026-09-15',
        revision: 0,
        days: const [],
        averages: const {},
        foodVarietyAverage: null,
        foodVarietyDenominator: null,
        fishCount: null,
        fishGrams: null,
        nutGrams: null,
        dairyMetDays: 0,
        dairyKnownDays: 0,
        dairyUnknownDays: 7,
        soyMetDays: 0,
        soyKnownDays: 0,
        soyUnknownDays: 7,
        fishCompleteness: 'unknown',
        fishCountCompleteness: 'unknown',
        nutCompleteness: 'unknown',
      ),
      nextMealType: 'dinner',
    );

    final result = await NextMealRecommendationService(
      remoteWithBudget: remote.callWithBudget,
    ).nextMeal(request);

    expect(result.source, 'local_rule');
    expect(result.reasonCode, 'unauthorized');
  });
}
