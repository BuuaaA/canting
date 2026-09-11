import 'dart:convert';
import 'dart:io';

import 'package:canting/core/dish_matcher.dart';
import 'package:canting/core/models/dietary_guidelines.dart';
import 'package:canting/core/serving_estimator.dart';
import 'package:canting/data/food_database.dart';
import 'package:test/test.dart';

void main() {
  late ServingEstimator estimator;

  setUpAll(() {
    final database = FoodDatabase.fromJson(
      dishesJson: File('assets/data/dishes.json').readAsStringSync(),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
    final guidelines = DietaryGuidelines.fromJson(
      (jsonDecode(
        File('assets/data/dietary_guidelines.json').readAsStringSync(),
      ) as Map).cast<String, dynamic>(),
    );
    estimator = ServingEstimator(DishMatcher(database), guidelines);
  });

  group('estimateServings (重量 → 份数)', () {
    test('uses the food exchange table for cooked rice', () {
      // 膳食指南：150g 熟米饭 = 50g 生米 = 1 份谷薯。
      final estimate = estimator.estimateServings('米饭', 300)!;

      expect(estimate.servings, closeTo(2.0, 0.0001));
      expect(estimate.basis, EstimateBasis.foodExchange);
      expect(estimate.categoryKey, 'grain_tuber');
      expect(estimate.gramsPerDishServing, 150);
    });

    test('handles fractional servings', () {
      final estimate = estimator.estimateServings('米饭', 200)!;
      expect(estimate.servings, closeTo(200 / 150, 0.0001));
    });

    test('estimates steamed bun, yogurt, tofu, and milk', () {
      expect(
        estimator.estimateServings('馒头', 150)!.servings,
        closeTo(2.0, 0.0001),
      );
      final yogurt = estimator.estimateServings('酸奶', 200)!;
      expect(yogurt.servings, closeTo(2.0, 0.0001));
      expect(yogurt.categoryKey, 'dairy_products');

      expect(
        estimator.estimateServings('豆腐', 105)!.servings,
        closeTo(1.0, 0.0001),
      );

      // 牛奶是交换基准本身：100ml = 1 份。
      expect(
        estimator.estimateServings('牛奶', 200)!.servings,
        closeTo(2.0, 0.0001),
      );
    });

    test('falls back to whole-dish estimation for takeaway dishes', () {
      // 黄焖鸡米饭 correctedPortions:
      // grains 2.0×50 + vegetables 0.3×80 + protein 1.3×50 + oil 2.304×10
      // = 100 + 24 + 65 + 23.04 = 212.04g 每份。
      final estimate = estimator.estimateServings('黄焖鸡米饭', 424.08)!;

      expect(estimate.basis, EstimateBasis.dishMatch);
      expect(estimate.matchedDishId, 'hsm_rice');
      expect(estimate.categoryKey, 'grain_tuber');
      expect(estimate.gramsPerDishServing, closeTo(212.04, 0.0001));
      expect(estimate.servings, closeTo(2.0, 0.0001));
    });

    test('returns null when nothing matches', () {
      expect(estimator.estimateServings('神秘料理', 100), isNull);
      expect(estimator.estimateServings('   ', 100), isNull);
    });

    test('rejects non-positive weights', () {
      expect(() => estimator.estimateServings('米饭', 0), throwsArgumentError);
      expect(() => estimator.estimateServings('米饭', -50), throwsArgumentError);
    });
  });

  group('estimateGrams (份数 → 重量)', () {
    test('reverses the food exchange conversion', () {
      expect(estimator.estimateGrams('米饭', 2)!, closeTo(300, 0.0001));
      expect(estimator.estimateGrams('酸奶', 1.5)!, closeTo(150, 0.0001));
    });

    test('reverses whole-dish estimation', () {
      expect(estimator.estimateGrams('黄焖鸡米饭', 2)!, closeTo(424.08, 0.0001));
    });

    test('returns null when nothing matches', () {
      expect(estimator.estimateGrams('神秘料理', 2), isNull);
    });

    test('rejects non-positive servings', () {
      expect(() => estimator.estimateGrams('米饭', 0), throwsArgumentError);
    });
  });

  group('round-trip consistency', () {
    test('grams → servings → grams returns the original weight', () {
      for (final (name, grams) in const [
        ('米饭', 210.0),
        ('红薯', 125.0),
        ('豆浆', 350.0),
        ('黄焖鸡米饭', 300.0),
        ('清炒时蔬', 180.0),
      ]) {
        final estimate = estimator.estimateServings(name, grams);
        if (estimate == null) {
          continue;
        }
        final back = estimator.estimateGrams(name, estimate.servings)!;
        expect(back, closeTo(grams, 0.0001), reason: '$name 往返换算不一致');
      }
    });
  });

  group('W5 conventional portion knowledge', () {
    test('150g rice and half reviewed bowl produce review candidates', () {
      final grams = estimator.convertIntake(
        '米饭',
        amount: 150,
        unit: PortionMeasureUnit.g,
      )!;
      expect(grams.effectiveAmount!.min, 150);
      expect(grams.servings!.min, 1);

      final halfBowl = estimator.convertIntake(
        '熟米饭',
        amount: .5,
        unit: PortionMeasureUnit.bowl,
      )!;
      expect(halfBowl.effectiveAmount!.min, 75);
      expect(halfBowl.effectiveAmount!.max, 75);
      expect(halfBowl.servings!.min, .5);
      expect(halfBowl.mapping, 'container:bowl');
    });

    test(
      'known 473ml beverage remains ml and unknown container stays unknown',
      () {
        final drink = estimator.convertIntake(
          '可乐',
          amount: 473,
          unit: PortionMeasureUnit.ml,
        )!;
        expect(drink.effectiveAmount!.min, 473);
        expect(drink.effectiveUnit, PortionMeasureUnit.ml);
        expect(drink.servings, isNull);

        expect(
          estimator.convertIntake(
            '鸡胸肉',
            amount: 1,
            unit: PortionMeasureUnit.bowl,
          ),
          isNull,
        );
      },
    );

    test('size, allocation, consumption and not-eaten remain separate', () {
      final result = estimator.convertIntake(
        '馒头',
        amount: 1,
        unit: PortionMeasureUnit.serving,
        size: PortionSize.large,
        allocationRatio: .5,
        consumedRatio: .75,
      )!;
      expect(result.suppliedAmount.min, 97.5);
      expect(result.effectiveAmount!.min, closeTo(36.5625, .0001));

      final none = estimator.convertIntake(
        '馒头',
        amount: 1,
        unit: PortionMeasureUnit.serving,
        notEaten: true,
      )!;
      expect(none.effectiveAmount!.min, 0);
      expect(none.notEaten, isTrue);

      expect(ConsumptionChoice.values.map((choice) => choice.ratio), [
        1,
        .75,
        .5,
        .25,
        0,
        null,
      ]);
      final uncertain = estimator.convertIntake(
        '馒头',
        amount: 1,
        unit: PortionMeasureUnit.serving,
        consumedRatio: ConsumptionChoice.uncertain.ratio,
      )!;
      expect(uncertain.effectiveAmount, isNull);
      expect(uncertain.servings, isNull);
    });

    test('oil and salt stay unknown without recipe evidence', () {
      final meal = estimator.knowledgeFor('盖浇饭')!;
      expect(meal.oilGrams, isNull);
      expect(meal.saltGrams, isNull);
      expect(meal.components, isNotEmpty);
      expect(meal.nutritionStatus, NutritionAvailability.basicUnknown);
    });

    test('knowledge version and reviewed facts are frozen', () {
      final rice = estimator.knowledgeFor('米饭')!;
      expect(estimator.knowledgeVersion, 'conventional-portions-2026.09-v1');
      expect(rice.reviewStatus, PortionReviewStatus.reviewed);
      expect(() => rice.aliases.add('篡改'), throwsUnsupportedError);
      expect(() => estimator.knowledge.add(rice), throwsUnsupportedError);
    });
  });
}
