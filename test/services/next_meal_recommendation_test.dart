import 'dart:convert';

import 'package:canting/services/intake_statistics.dart';
import 'package:canting/services/next_meal_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

TodayIntakeStats today({bool stale = false, int revision = 4}) =>
    TodayIntakeStats(
      date: '2026-09-12',
      revision: revision,
      stale: stale,
      completeness: 'complete',
      categories: {
        'vegetable': const IntakeCategoryStat(
          category: 'vegetable',
          amount: 80,
          knownSubtotal: 80,
          completeness: 'complete',
          target: IntakeTarget(min: 300, max: 500),
          status: 'below',
          gap: 220,
        ),
      },
    );

Rolling7dIntakeStats rolling({bool stale = false, int revision = 4}) =>
    Rolling7dIntakeStats(
      startDate: '2026-09-06',
      endDate: '2026-09-12',
      revision: revision,
      stale: stale,
      days: const [],
      averages: {
        'vegetable': const IntakeAverageStat(
          category: 'vegetable',
          average: 100,
          denominator: 3,
          target: IntakeTarget(min: 300, max: 500),
        ),
      },
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
    );

NextMealRequest request({bool stale = false}) => NextMealRequest(
  requestId: 'request-1',
  today: today(stale: stale),
  rolling7d: rolling(stale: stale),
  nextMealType: 'dinner',
  dietaryExclusions: const [],
  city: '上海',
  availablePlatforms: const ['meituan_waimai'],
);

Map<String, dynamic> aiJson({String dish = '清蒸鲈鱼配时蔬'}) => {
  'suggestions': [
    {
      'dishName': dish,
      'searchKeyword': '清蒸鲈鱼 时蔬 少油',
      'primaryCategory': 'animal_food',
      'estimatedServing': '鱼肉一掌心（估算）',
      'reason': '补充动物性食物并减少油盐。',
    },
    {
      'dishName': '西兰花鸡胸肉饭',
      'searchKeyword': '西兰花鸡胸肉 少油少盐',
      'primaryCategory': 'vegetable',
      'estimatedServing': '蔬菜一小盘（估算）',
      'reason': '补足已知蔬菜缺口。',
    },
  ],
  'guidance': {
    'primary': '优先补足蔬菜。',
    'oilSalt': '少油少盐。',
    'reduceStaple': '主食按小份。',
  },
};

void main() {
  test('未配置安全AI通道时不发请求并返回具体本地候选', () async {
    // null is the production default: no transport exists to call.
    final service = NextMealRecommendationService();
    final result = await service.nextMeal(request());
    expect(result.source, 'local_rule');
    expect(result.reasonCode, 'unconfigured');
    expect(result.suggestions, hasLength(3));
    expect(result.suggestions.first.searchKeyword, isNotEmpty);
  });

  test('AI输出验证通过时只接受2到3个候选', () async {
    final result = await NextMealRecommendationService(
      remote: (_) async => jsonEncode(aiJson()),
    ).nextMeal(request());
    expect(result.source, 'ai');
    expect(result.status, 'success');
    expect(result.suggestions, hasLength(2));
  });

  test('连续两次非法JSON后降级，且不会无限重试', () async {
    var calls = 0;
    final result = await NextMealRecommendationService(
      remote: (_) async {
        calls++;
        return 'not-json';
      },
    ).nextMeal(request());
    expect(calls, 2);
    expect(result.reasonCode, 'invalid_json');
    expect(result.source, 'local_rule');
  });

  test('超时降级；过时统计不展示为最新推荐', () async {
    final timeoutResult = await NextMealRecommendationService(
      timeout: const Duration(milliseconds: 1),
      remote: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return jsonEncode(aiJson());
      },
    ).nextMeal(request());
    expect(timeoutResult.reasonCode, 'timeout');
    expect(timeoutResult.source, 'local_rule');

    final staleResult = await NextMealRecommendationService().nextMeal(
      request(stale: true),
    );
    expect(staleResult.reasonCode, 'stale_input');
    expect(staleResult.isUsable, isFalse);

    await expectLater(
      NextMealRecommendationService().nextMeal(
        NextMealRequest(
          requestId: 'request-1',
          today: today(revision: 5),
          rolling7d: rolling(revision: 4),
          nextMealType: 'dinner',
        ),
      ),
      throwsArgumentError,
    );
  });

  test('缺字段、禁忌和泛化文案均拒绝为正常AI结果', () async {
    final bad = aiJson()..['suggestions'] = [aiJson()['suggestions'][0]];
    final missing = await NextMealRecommendationService(
      remote: (_) async => jsonEncode(bad),
    ).nextMeal(request());
    expect(missing.reasonCode, 'invalid_json');

    final excluded =
        await NextMealRecommendationService(
          remote: (_) async => jsonEncode(aiJson(dish: '花生鸡肉饭')),
        ).nextMeal(
          NextMealRequest(
            requestId: 'request-1',
            today: today(),
            rolling7d: rolling(),
            nextMealType: 'dinner',
            dietaryExclusions: const ['花生'],
          ),
        );
    expect(excluded.source, 'local_rule');

    final repeated =
        await NextMealRecommendationService(
          remote: (_) async => jsonEncode(aiJson()),
        ).nextMeal(
          NextMealRequest(
            requestId: 'request-1',
            today: today(),
            rolling7d: rolling(),
            nextMealType: 'dinner',
            excludeDishNames: const ['清蒸鲈鱼配时蔬'],
          ),
        );
    expect(repeated.source, 'local_rule');
  });

  test('语义忌口同时过滤本地和远端候选，全部不安全时不强保数量', () async {
    final local = await NextMealRecommendationService().nextMeal(
      NextMealRequest(
        requestId: 'request-1',
        today: today(),
        rolling7d: rolling(),
        nextMealType: 'dinner',
        dietaryExclusions: const ['不吃鱼'],
      ),
    );
    expect(local.suggestions.every((s) => !s.dishName.contains('鱼')), isTrue);

    final dairy = await NextMealRecommendationService().nextMeal(
      NextMealRequest(
        requestId: 'request-1',
        today: today(),
        rolling7d: rolling(),
        nextMealType: 'dinner',
        dietaryExclusions: const ['乳制品'],
      ),
    );
    expect(dairy.suggestions.every((s) => !s.dishName.contains('酸奶')), isTrue);

    final vegetarian = await NextMealRecommendationService().nextMeal(
      NextMealRequest(
        requestId: 'request-1',
        today: today(),
        rolling7d: rolling(),
        nextMealType: 'dinner',
        dietaryExclusions: const ['素食', '乳制品'],
      ),
    );
    expect(vegetarian.suggestions, isEmpty);
    expect(vegetarian.status, 'failed');
  });

  test('request/result 事件仅记录脱敏元信息，事件失败不阻塞主流程', () async {
    final events = <Map<String, dynamic>>[];
    final result = await NextMealRecommendationService(
      eventSink: (event) async => events.add(event),
    ).nextMeal(request());
    expect(result.isUsable, isTrue);
    expect(events.map((e) => e['event']), [
      'next_meal_request',
      'next_meal_result',
    ]);
    expect(
      events.every(
        (e) => !e.containsKey('today') && !e.containsKey('rolling7d'),
      ),
      isTrue,
    );

    final stillWorks = await NextMealRecommendationService(
      eventSink: (_) async => throw StateError('storage unavailable'),
    ).nextMeal(request());
    expect(stillWorks.isUsable, isTrue);
  });

  test('反馈保存失败不阻塞，成功后accept去重且缓存有界', () async {
    var calls = 0;
    final result = await NextMealRecommendationService().nextMeal(request());
    final failing = NextMealRecommendationService(
      feedbackSink: (_) async {
        calls++;
        throw StateError('db unavailable');
      },
    );
    await failing.recordFeedback(
      result: result,
      action: NextMealFeedbackAction.accept,
      acceptanceBasis: 'platform_open_accepted',
    );
    expect(calls, 1);
  });

  test('校验日期和预算边界', () async {
    await expectLater(
      NextMealRecommendationService().nextMeal(
        NextMealRequest(
          requestId: 'request-1',
          today: today(),
          rolling7d: rolling(),
          nextMealType: 'dinner',
          budget: -1,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      NextMealRecommendationService().nextMeal(
        NextMealRequest(
          requestId: 'request-1',
          today: today(),
          rolling7d: rolling(),
          nextMealType: 'dinner',
          budget: double.infinity,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('反馈按request关联，accept一次且必须有平台打开依据', () async {
    final events = <NextMealFeedback>[];
    final service = NextMealRecommendationService(
      feedbackSink: (event) async => events.add(event),
    );
    final result = await service.nextMeal(request());
    await service.recordFeedback(
      result: result,
      action: NextMealFeedbackAction.accept,
      acceptanceBasis: 'platform_open_accepted',
    );
    await service.recordFeedback(
      result: result,
      action: NextMealFeedbackAction.accept,
      acceptanceBasis: 'platform_open_accepted',
    );
    await service.recordFeedback(
      result: result,
      action: NextMealFeedbackAction.refresh,
    );
    expect(events.map((e) => e.action), [
      NextMealFeedbackAction.accept,
      NextMealFeedbackAction.refresh,
    ]);
    expect(events.first.requestId, 'request-1');
  });
}
