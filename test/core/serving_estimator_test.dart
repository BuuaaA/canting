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
          )
          as Map)
          .cast<String, dynamic>(),
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
      expect(
        () => estimator.estimateServings('米饭', 0),
        throwsArgumentError,
      );
      expect(
        () => estimator.estimateServings('米饭', -50),
        throwsArgumentError,
      );
    });
  });

  group('estimateGrams (份数 → 重量)', () {
    test('reverses the food exchange conversion', () {
      expect(estimator.estimateGrams('米饭', 2)!, closeTo(300, 0.0001));
      expect(estimator.estimateGrams('酸奶', 1.5)!, closeTo(150, 0.0001));
    });

    test('reverses whole-dish estimation', () {
      expect(
        estimator.estimateGrams('黄焖鸡米饭', 2)!,
        closeTo(424.08, 0.0001),
      );
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
}
