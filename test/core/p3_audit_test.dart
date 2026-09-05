import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:canting/core_engine.dart';
import 'package:canting/core/record_window.dart';
import 'package:canting/core/recommendation_safety.dart';
import 'package:canting/core/models/local_food.dart';

void main() {
  final now = DateTime(2026, 3, 1, 18);
  const target = DailyIntake(
    grains: 5,
    vegetables: 5,
    fruits: 3,
    protein: 4,
    proteinSoy: 2,
    oil: 3,
    bmr: 1500,
    tdee: 2000,
  );
  const cat = FoodCategory(
    id: 'plain',
    name: '测试通用',
    oilLevel: 'low',
    oilFactor: 1,
    averagePortions: Portions(grains: 1),
    keywords: [],
  );
  StandardDish dish(
    String id, {
    List<String> tags = const [],
    bool allowed = true,
  }) => StandardDish(
    id: id,
    name: id,
    aliases: [],
    category: 'plain',
    portionsNormal: const Portions(
      grains: 1,
      vegetables: 1,
      fruits: 1,
      protein: 1,
      proteinSoy: 1,
    ),
    cookingOilRatio: 0,
    oilFactor: 1,
    sodiumLevel: 'low',
    searchKeywords: [],
    qualityTags: tags,
    recommendable: allowed,
  );
  test('independent exclusion oracle covers all slots, modes, swap and fallback at 0/1/2 safe candidates', () {
    final risks = [
      'fried',
      'high_sodium',
      'high_oil',
      'high_sugar',
      'alcohol',
      'sugary_drink',
    ];
    for (final n in [0, 1, 2, 5]) {
      final catalog = FoodDatabase(
        dishes: [
          for (final tag in risks) dish('blocked_$tag', tags: [tag, 'light']),
          dish('not_allowed', allowed: false),
          for (var i = 0; i < n; i++) dish('safe_$i'),
        ],
        categories: [cat],
      );
      for (final light in [false, true]) {
        final excluded = <String>{};
        for (var round = 0; round < 3; round++) {
          final r = RecommendationEngine(catalog).recommend(
            todayMeals: [
              MealRecord(
                mealId: 'observed',
                mealType: 'lunch',
                timestamp: now,
                portionsTotal: const Portions(grains: 0.1),
              ),
            ],
            dailyIntake: target,
            now: now,
            lastMealType: 'lunch',
            balance: BalanceReport(
              byCategory: {'oil': CategoryBalance(surplus: light ? 3 : 0)},
              asOf: now,
            ),
            excludeDishNames: excluded,
          );
          final output = [...r.primary, ...r.alternatives];
          for (final s in output) {
            expect(s.dishName, startsWith('safe_'));
            expect(excluded, isNot(contains(s.dishName)));
          }
          expect(output.length, lessThanOrEqualTo(n));
          if (n < 3) expect(r.reasonCodes, contains('insufficient_candidates'));
          excluded.addAll(output.map((s) => s.dishName));
        }
      }
    }
  });
  test('formal catalog audit and fixed-input 7/28-day simulations', () {
    final catalog = FoodDatabase.fromJson(
      dishesJson: File('assets/data/dishes.json').readAsStringSync(),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
    expect(catalog.dishes, hasLength(1004));
    final counts = <String, int>{}, reasons = <String, int>{};
    final categories = <String, Map<String, int>>{};
    final rows = <Map<String, dynamic>>[];
    final auditWatch = Stopwatch()..start();
    for (final d in catalog.dishes) {
      final result = RecommendationSafety.evaluate(
        d,
        catalog.categoryForDish(d),
      );
      counts.update(result.eligibility.name, (v) => v + 1, ifAbsent: () => 1);
      final byCategory = categories.putIfAbsent(d.category, () => {});
      byCategory.update(
        result.eligibility.name,
        (v) => v + 1,
        ifAbsent: () => 1,
      );
      for (final code in result.reasonCodes) {
        reasons.update(code, (v) => v + 1, ifAbsent: () => 1);
      }
      rows.add({
        'id': d.id,
        'name': d.name,
        'category': d.category,
        ...result.toJson(),
        'legacyRecommendableConflict':
            d.recommendable && result.eligibility == Eligibility.ineligible,
        'lightConflict':
            d.qualityTags.contains('light') &&
            result.eligibility != Eligibility.eligible,
      });
    }
    auditWatch.stop();
    expect(counts['eligible'], greaterThan(0));
    final simulations = <Map<String, dynamic>>[];
    for (final scenario in [
      'persistent_imbalance',
      'balanced',
      'missing',
      'unknown',
      'exhausted',
      'risk_conflict',
    ]) {
      final random = Random(42);
      final records = <MealRecord>[];
      for (var i = 0; i < 28; i++) {
        final date = DateTime(2026, 3, 1 - i, 12);
        if (scenario == 'missing' && i % 2 == 0) continue;
        records.add(
          MealRecord(
            mealId: '$scenario-$i',
            mealType: 'lunch',
            timestamp: date,
            dishes: scenario == 'unknown'
                ? [
                    const MealDish(
                      name: 'unknown',
                      contributionsKnown: false,
                      food: FoodObservation(facts: FoodFacts(name: 'unknown')),
                    ),
                  ]
                : const [],
            portionsTotal: scenario == 'unknown'
                ? null
                : scenario == 'persistent_imbalance'
                ? Portions(grains: 5 + random.nextDouble(), protein: 4)
                : target.portions,
          ),
        );
      }
      final w7 = RecordWindow.build(records, days: 7, asOf: now),
          w28 = RecordWindow.build(records, days: 28, asOf: now);
      if (scenario == 'unknown') {
        expect(w7.partialDays, 7);
        expect(w7.knownDays, isEmpty);
      }
      if (scenario == 'missing') {
        expect(w7.missingDays, 4);
        expect(w7.todayKnown, false);
      }
      if (scenario == 'balanced') {
        expect(w28.recordedDays, 28);
        expect(w28.knownSubtotal.grains, 140);
      }
      final candidateDb = scenario == 'exhausted'
          ? FoodDatabase(dishes: [], categories: [cat])
          : scenario == 'risk_conflict'
          ? FoodDatabase(
              dishes: [
                dish('blocked', tags: ['fried', 'light']),
              ],
              categories: [cat],
            )
          : catalog;
      final result = RecommendationEngine(candidateDb).recommend(
        todayMeals: w7.meals
            .where((m) => localDay(m.timestamp) == localDay(now))
            .toList(),
        dailyIntake: target,
        now: now,
        lastMealType: 'lunch',
        balance: BalanceLedger.compute(
          intakeByDay: w7.knownDays,
          weeklyTarget: IntakeCalculator.weeklyTargetFromDaily(target),
          now: now,
        ),
      );
      final output = [...result.primary, ...result.alternatives];
      if ({'exhausted', 'risk_conflict'}.contains(scenario)) {
        expect(output, isEmpty);
      }
      if ({'unknown', 'missing'}.contains(scenario)) {
        for (final s in output) {
          expect(s.servings, isNull);
        }
      }
      simulations.add({
        'scenario': scenario,
        'seed': 42,
        'inputs': records.map((m) => m.toJson()).toList(),
        'window7': w7.toJson(),
        'window28': w28.toJson(),
        'recommendation_built': {
          'reason': result.reason,
          'reasonCodes': result.reasonCodes,
          'dishes': [
            for (final s in output)
              {
                'name': s.dishName,
                'slotCategory': s.slotCategory,
                'primaryCategory': s.primaryCategory,
                'servings': s.servings,
              },
          ],
        },
      });
    }
    final history = [
      for (var i = 0; i < 2800; i++)
        MealRecord(
          mealId: 'perf$i',
          mealType: 'lunch',
          timestamp: DateTime(2026, 3, 1 - i % 28),
          portionsTotal: target.portions,
        ),
    ];
    final watch = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      RecordWindow.build(history, days: 28, asOf: now).knownDays;
    }
    watch.stop();
    final dir = Directory('dev-docs/p3-evidence')..createSync(recursive: true);
    File('${dir.path}/candidate-audit.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'policyVersion': RecommendationSafety.version,
        'total': rows.length,
        'eligibility_evaluated': counts,
        'byCategory': categories,
        'byReason': reasons,
        'candidates': rows,
        'conflicts': rows
            .where(
              (r) =>
                  r['legacyRecommendableConflict'] == true ||
                  r['lightConflict'] == true,
            )
            .toList(),
      }),
    );
    File('${dir.path}/simulation.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'synthetic mechanisms only, not evidence of user improvement',
        'scenarios': simulations,
        'performance': {
          'host': Platform.operatingSystem,
          'mode': 'flutter test JIT',
          'candidate_count': 1004,
          'audit_microseconds': auditWatch.elapsedMicroseconds,
          'history_records': 2800,
          'window_rebuilds': 10,
          'elapsed_microseconds': watch.elapsedMicroseconds,
        },
      }),
    );
  });
}
