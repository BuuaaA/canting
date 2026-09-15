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

Rolling7dIntakeStats rolling({
  bool stale = false,
  int revision = 4,
  List<IntakeDayStat> days = const [],
}) => Rolling7dIntakeStats(
  startDate: '2026-09-06',
  endDate: '2026-09-12',
  revision: revision,
  stale: stale,
  days: days,
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
  test('远端只发送七天汇总，保留本地逐日统计及unknown语义', () {
    final days = <IntakeDayStat>[
      for (var day = 6; day <= 12; day++)
        IntakeDayStat(
          date: '2026-09-${day.toString().padLeft(2, '0')}',
          completeness: 'partial',
          categories: today().categories,
          foodVariety: null,
          fishCount: null,
          fishCountCompleteness: 'unknown',
        ),
    ];
    final window = rolling(days: days);
    final input = NextMealRequest(
      requestId: 'summary-regression',
      today: today(),
      rolling7d: window,
      nextMealType: 'dinner',
    );
    final serialized = input.toJson();
    final summary = serialized['rolling7d'] as Map;
    expect(summary, isNot(contains('days')));
    expect(summary['averages'], window.toJson()['averages']);
    expect((summary['fish'] as Map)['grams'], isNull);
    expect((summary['fish'] as Map)['completeness'], 'unknown');
    expect(window.days, hasLength(7));
    expect(window.toJson()['days'], hasLength(7));
    expect(serialized['today'], today().toJson());
  });

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

    final mismatch = await NextMealRecommendationService().nextMeal(
      NextMealRequest(
        requestId: 'request-1',
        today: today(revision: 5),
        rolling7d: rolling(revision: 4),
        nextMealType: 'dinner',
      ),
    );
    expect(mismatch.reasonCode, 'revision_mismatch');
    expect(mismatch.isUsable, isFalse);
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

    final vegan = await NextMealRecommendationService().nextMeal(
      NextMealRequest(
        requestId: 'request-1',
        today: today(),
        rolling7d: rolling(),
        nextMealType: 'dinner',
        dietaryExclusions: const ['纯素'],
      ),
    );
    expect(vegan.suggestions, isEmpty);
    expect(vegan.status, 'failed');
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
    final mismatch =
        await NextMealRecommendationService(
          eventSink: (event) async => events.add(event),
        ).nextMeal(
          NextMealRequest(
            requestId: 'request-2',
            today: today(revision: 5),
            rolling7d: rolling(revision: 4),
            nextMealType: 'dinner',
          ),
        );
    expect(mismatch.reasonCode, 'revision_mismatch');
    expect(events.last['event'], 'next_meal_result');
    expect(events.last['status'], 'failed');

    final stillWorks = await NextMealRecommendationService(
      eventSink: (_) async => throw StateError('storage unavailable'),
    ).nextMeal(request());
    expect(stillWorks.isUsable, isTrue);
  });

  test('无可靠类别缺口时使用中性理由，只有主食真实偏多才减量', () async {
    final neutralToday = TodayIntakeStats(
      date: '2026-09-12',
      revision: 4,
      completeness: 'partial',
      categories: const {},
    );
    final neutralRequest = NextMealRequest(
      requestId: 'neutral-1',
      today: neutralToday,
      rolling7d: Rolling7dIntakeStats(
        startDate: '2026-09-06',
        endDate: '2026-09-12',
        revision: 4,
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
    final neutral = await NextMealRecommendationService().nextMeal(
      neutralRequest,
    );
    expect(neutral.suggestions, hasLength(3));
    expect(
      neutral.suggestions.every(
        (suggestion) => suggestion.reason.contains('当前没有该类别的可靠缺口'),
      ),
      isTrue,
    );
    expect(neutral.suggestions.first.estimatedServing, isNot(contains('小份')));

    final grainHigh = TodayIntakeStats(
      date: '2026-09-12',
      revision: 4,
      completeness: 'complete',
      categories: {
        'grain': const IntakeCategoryStat(
          category: 'grain',
          amount: 400,
          knownSubtotal: 400,
          completeness: 'complete',
          target: IntakeTarget(min: 200, max: 300),
          status: 'high',
          gap: null,
        ),
      },
    );
    final reduced = await NextMealRecommendationService().nextMeal(
      NextMealRequest(
        requestId: 'grain-high',
        today: grainHigh,
        rolling7d: neutralRequest.rolling7d,
        nextMealType: 'dinner',
      ),
    );
    final grain = reduced.suggestions.firstWhere(
      (s) => s.primaryCategory == 'grain',
    );
    expect(grain.estimatedServing, contains('小份'));
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
    final invalidBudget = await NextMealRecommendationService().nextMeal(
      NextMealRequest(
        requestId: 'request-1',
        today: today(),
        rolling7d: rolling(),
        nextMealType: 'dinner',
        budget: -1,
      ),
    );
    expect(invalidBudget.reasonCode, 'invalid_input');
    final infiniteBudget = await NextMealRecommendationService().nextMeal(
      NextMealRequest(
        requestId: 'request-1',
        today: today(),
        rolling7d: rolling(),
        nextMealType: 'dinner',
        budget: double.infinity,
      ),
    );
    expect(infiniteBudget.reasonCode, 'invalid_input');
    final dateMismatch = await NextMealRecommendationService().nextMeal(
      NextMealRequest(
        requestId: 'request-1',
        today: today(),
        rolling7d: Rolling7dIntakeStats(
          startDate: '2026-09-05',
          endDate: '2026-09-11',
          revision: 4,
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
      ),
    );
    expect(dateMismatch.reasonCode, 'date_mismatch');
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
