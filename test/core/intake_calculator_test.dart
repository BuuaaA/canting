import 'dart:convert';
import 'dart:io';

import 'package:canting/core/intake_calculator.dart';
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

  group('IntakeCalculator', () {
    final calculator = IntakeCalculator();

    test('uses the Mifflin-St Jeor formula and clamps to the 2400kcal tier', () {
      final result = calculator.calculate(
        guidelines: guidelines,
        gender: 'male',
        heightCm: 175,
        weightKg: 70,
        age: 30,
        activityLevel: 'moderate',
        dietGoal: 'balanced',
      );

      // BMR = 10*70 + 6.25*175 - 5*30 + 5 = 1648.75
      expect(result.bmr, 1648.75);
      // TDEE = 1648.75 * 1.55 = 2555.56，超过最高档 2400，钳制到 2400 档。
      expect(result.tdee, closeTo(2555.5625, 0.0001));
      // 2400kcal 档推荐份数（来自 dietary_guidelines.json）。
      expect(result.grains, 6); // grain_tuber
      expect(result.vegetables, 5); // vegetable
      expect(result.fruits, 3.5); // fruit
      expect(result.protein, 5); // protein_meat_egg
      expect(result.proteinSoy, 2); // soy
      expect(result.oil, 3);
    });

    test('clamps a low TDEE at the 1600kcal guideline tier', () {
      final result = calculator.calculate(
        guidelines: guidelines,
        gender: 'female',
        heightCm: 165,
        weightKg: 60,
        age: 30,
        activityLevel: 'sedentary',
        dietGoal: 'balanced',
      );

      // BMR = 10*60 + 6.25*165 - 5*30 - 161 = 1320.25
      expect(result.bmr, 1320.25);
      // TDEE = 1320.25 * 1.2 = 1584.3，低于最低档 1600，钳制到 1600 档。
      expect(result.tdee, closeTo(1584.3, 0.0001));
      // 1600kcal 档推荐份数（来自 dietary_guidelines.json）。
      expect(result.grains, 4); // grain_tuber
      expect(result.vegetables, 4); // vegetable
      expect(result.fruits, 2); // fruit
      expect(result.protein, 3); // protein_meat_egg
      expect(result.proteinSoy, 1); // soy
      expect(result.oil, 2.5);
    });

    test('interpolates servings between adjacent energy tiers', () {
      final result = calculator.calculate(
        guidelines: guidelines,
        gender: 'female',
        heightCm: 170,
        weightKg: 65,
        age: 28,
        activityLevel: 'light',
        dietGoal: 'balanced',
      );

      // TDEE = (10*65 + 6.25*170 - 5*28 - 161) * 1.375 = 1940.8125，
      // 落在 1800~2000 档之间，插值位置 p = 140.8125/200 ≈ 0.7041。
      expect(result.tdee, closeTo(1940.8125, 0.0001));
      // grain_tuber 在两档都是 5。
      expect(result.grains, 5);
      // vegetable 4.5 → 5。
      expect(result.vegetables, closeTo(4.5 + 0.5 * 0.7040625, 0.001));
      // fruit 2.5 → 3。
      expect(result.fruits, closeTo(2.5 + 0.5 * 0.7040625, 0.001));
      // protein_meat_egg 3.5 → 4。
      expect(result.protein, closeTo(3.5 + 0.5 * 0.7040625, 0.001));
      // soy 1.5 → 2。
      expect(result.proteinSoy, closeTo(1.5 + 0.5 * 0.7040625, 0.001));
      // oil 2.5 → 3。
      expect(result.oil, closeTo(2.5 + 0.5 * 0.7040625, 0.001));

      // 插值结果必须严格落在相邻两档之间。
      expect(result.vegetables, inInclusiveRange(4.5, 5.0));
      expect(result.protein, inInclusiveRange(3.5, 4.0));
      expect(result.proteinSoy, inInclusiveRange(1.5, 2.0));
    });

    test('applies each diet-goal adjustment only to its target group', () {
      DailyIntakeSnapshot calculate(String goal) {
        final value = calculator.calculate(
          guidelines: guidelines,
          gender: 'female',
          heightCm: 170,
          weightKg: 65,
          age: 28,
          activityLevel: 'light',
          dietGoal: goal,
        );
        return DailyIntakeSnapshot(
          grains: value.grains,
          vegetables: value.vegetables,
          protein: value.protein,
        );
      }

      final balanced = calculate('balanced');
      final moreVeg = calculate('more_veg');
      final moreProtein = calculate('more_protein');
      final lessCarb = calculate('less_carb');

      expect(moreVeg.vegetables, closeTo(balanced.vegetables * 1.2, 0.0001));
      expect(moreVeg.grains, balanced.grains);
      expect(moreProtein.protein, closeTo(balanced.protein * 1.2, 0.0001));
      expect(lessCarb.grains, closeTo(balanced.grains * 0.8, 0.0001));
    });

    test('rejects unsupported enum values and non-positive measurements', () {
      expect(
        () => calculator.calculate(
          guidelines: guidelines,
          gender: 'unknown',
          heightCm: 175,
          weightKg: 70,
          age: 30,
          activityLevel: 'light',
          dietGoal: 'balanced',
        ),
        throwsArgumentError,
      );
      expect(
        () => calculator.calculate(
          guidelines: guidelines,
          gender: 'male',
          heightCm: 0,
          weightKg: 70,
          age: 30,
          activityLevel: 'light',
          dietGoal: 'balanced',
        ),
        throwsArgumentError,
      );
    });
  });
}

class DailyIntakeSnapshot {
  const DailyIntakeSnapshot({
    required this.grains,
    required this.vegetables,
    required this.protein,
  });

  final double grains;
  final double vegetables;
  final double protein;
}
