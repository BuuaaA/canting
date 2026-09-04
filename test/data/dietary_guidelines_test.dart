import 'dart:convert';
import 'dart:io';

import 'package:canting/core/models/dietary_guidelines.dart';
import 'package:test/test.dart';

void main() {
  late DietaryGuidelines guidelines;

  setUpAll(() {
    guidelines = DietaryGuidelines.fromJson(
      (jsonDecode(
            File('assets/data/dietary_guidelines.json').readAsStringSync(),
          )
          as Map)
          .cast<String, dynamic>(),
    );
  });

  group('DietaryGuidelines.fromJson', () {
    test('parses version, source, and the six food categories', () {
      expect(guidelines.version, '2022');
      expect(guidelines.source, contains('中国居民膳食指南'));
      expect(guidelines.foodCategories, hasLength(6));
      expect(guidelines.foodCategories.first.id, 'grain_tuber');
      expect(guidelines.foodCategories.first.name, '谷薯类');
      expect(guidelines.foodCategories.first.isCore, isTrue);
    });

    test('parses serving reference grams per category', () {
      expect(guidelines.gramsPerServingFor('grain_tuber'), 50);
      expect(guidelines.gramsPerServingFor('vegetable'), 80);
      expect(guidelines.gramsPerServingFor('fruit'), 100);
      expect(guidelines.gramsPerServingFor('protein_meat_egg'), 50);
      expect(guidelines.gramsPerServingFor('dairy'), 150);
      expect(guidelines.gramsPerServingFor('soy'), 15);
      // 油脂没有「份」定义。
      expect(guidelines.gramsPerServingFor('oil'), isNull);
    });

    test('parses daily intake ranges by energy level', () {
      final level2000 = guidelines.recommendationsByEnergyLevel['2000'];
      expect(level2000, isNotNull);
      expect(level2000!.energyLevelKcal, 2000);

      final grains = level2000.intakeRanges['grain_tuber']!;
      expect(grains.min, 250);
      expect(grains.max, 300);
      expect(grains.servings, 5);

      // 盐只有上限。
      final salt = level2000.intakeRanges['salt']!;
      expect(salt.min, isNull);
      expect(salt.max, 5);
      expect(salt.servings, isNull);
    });

    test('rejects malformed JSON', () {
      expect(
        () => DietaryGuidelines.fromJson(const {}),
        throwsFormatException,
      );
    });
  });

  group('指南重蒸馏新增区块（2026-09）', () {
    test('weekly_targets：六类 7 天目标 = 单日目标 × 7（与日档同源）', () {
      for (final entry in guidelines.weeklyTargetsByEnergyLevel.entries) {
        final daily = guidelines.recommendationsByEnergyLevel[entry.key]!;
        const mapping = {
          'grain_tuber': 'grain_tuber',
          'vegetable': 'vegetable',
          'fruit': 'fruit',
          'protein_meat_egg': 'protein_meat_egg',
          'soy': 'soy',
          'oil': 'oil',
        };
        for (final category in mapping.keys) {
          final weekly = entry.value.servings[category];
          final expected = daily.intakeRanges[category]!.servings! * 7;
          expect(
            weekly,
            closeTo(expected, 1e-9),
            reason: '${entry.key} $category 周目标应等于单日 × 7',
          );
        }
        // 奶/坚果与日目标口径一致地不进周目标。
        expect(entry.value.servings.containsKey('dairy'), isFalse);
        expect(entry.value.servings.containsKey('nut'), isFalse);
      }
      expect(guidelines.weeklyTargetsByEnergyLevel, hasLength(5));
    });

    test('whole_grain：50~150g/日 → 谷薯 1 份/日下限', () {
      final wholeGrain = guidelines.wholeGrain;
      expect(wholeGrain, isNotNull);
      expect(wholeGrain!.dailyMinGrams, 50);
      expect(wholeGrain.dailyMaxGrams, 150);
      // 谷薯每份 50g → 50g ÷ 50g = 1 份。
      expect(wholeGrain.dailyMinServings, 1.0);
    });

    test('added_sugar：≤50g、最好 <25g，V1.0 不追踪', () {
      final sugar = guidelines.addedSugar;
      expect(sugar, isNotNull);
      expect(sugar!.dailyMaxGrams, 50);
      expect(sugar.dailyIdealMaxGrams, 25);
      expect(sugar.tracked, isFalse);
    });

    test('weekly_balance：7 天窗口 + 衰减参数 + ±30% 限幅', () {
      final balance = guidelines.weeklyBalance;
      expect(balance, isNotNull);
      expect(balance!.windowDays, 7);
      expect(balance.surplusDecay, 0.5);
      expect(balance.deficitDecay, 0.2);
      expect(balance.singleMealCorrectionLimit, 0.3);
    });

    test('oil_salt_limits：油 ≤3 份/日（30g），盐用 high_sodium 代理', () {
      final limits = guidelines.oilSaltLimits;
      expect(limits, isNotNull);
      expect(limits!.oilDailyServingsMax, 3.0);
      expect(limits.saltDailyGramsMax, 5);
      expect(limits.saltTracking, 'high_sodium_tag_proxy');
    });

    test('缺新增区块的旧 JSON 仍可解析（defensive）', () {
      final legacy = DietaryGuidelines.fromJson({
        'version': '2022',
        'source': 'test',
        'food_categories': [
          {
            'id': 'grain_tuber',
            'name': '谷薯类',
          },
        ],
        'daily_intake_recommendation': {
          'by_energy_level': {
            '2000': {
              'grain_tuber': {'min': 250, 'max': 300, 'servings': 5},
            },
          },
        },
        'serving_reference': {
          'grain_tuber': {'per_serving_grams': 50},
        },
        'food_exchange': {
          'g': {
            'rice_50g_raw': {'cooked_rice': 150},
          },
        },
      });
      expect(legacy.weeklyTargetsByEnergyLevel, isEmpty);
      expect(legacy.wholeGrain, isNull);
      expect(legacy.addedSugar, isNull);
      expect(legacy.weeklyBalance, isNull);
      expect(legacy.oilSaltLimits, isNull);
    });
  });

  group('food exchange lookup', () {
    test('finds exchangeable foods with their grams per serving', () {
      final rice = guidelines.findExchangeEntry('cooked_rice');
      expect(rice, isNotNull);
      expect(rice!.groupId, 'grain_tuber');
      expect(rice.gramsPerServing, 150);

      final yogurt = guidelines.findExchangeEntry('yogurt');
      expect(yogurt!.groupId, 'dairy_products');
      expect(yogurt.gramsPerServing, 100);

      final tofu = guidelines.findExchangeEntry('firm_tofu');
      expect(tofu!.groupId, 'soy_products');
      expect(tofu.gramsPerServing, 105);
    });

    test('finds base foods themselves as exchange entries', () {
      final milk = guidelines.findExchangeBase('milk_100ml');
      expect(milk, isNotNull);
      expect(milk!.gramsPerServing, 100);

      final rawRice = guidelines.findExchangeBase('rice_50g_raw');
      expect(rawRice!.gramsPerServing, 50);
    });

    test('returns null for unknown foods', () {
      expect(guidelines.findExchangeEntry('pizza'), isNull);
      expect(guidelines.findExchangeBase('pizza_100g'), isNull);
    });
  });
}
