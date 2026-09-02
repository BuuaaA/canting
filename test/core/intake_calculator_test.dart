import 'package:canting/core/intake_calculator.dart';
import 'package:test/test.dart';

void main() {
  group('IntakeCalculator', () {
    final calculator = IntakeCalculator();

    test('uses the Mifflin-St Jeor formula and upper guideline bounds', () {
      final result = calculator.calculate(
        gender: 'male',
        heightCm: 175,
        weightKg: 70,
        age: 30,
        activityLevel: 'moderate',
        dietGoal: 'balanced',
      );

      expect(result.bmr, 1648.75);
      expect(result.tdee, closeTo(2555.5625, 0.0001));
      expect(result.grains, 8);
      expect(result.vegetables, 5);
      expect(result.fruits, 3.5);
      expect(result.protein, 5);
      expect(result.proteinSoy, 1);
      expect(result.oil, 3);
    });

    test('clamps a low TDEE at lower guideline bounds', () {
      final result = calculator.calculate(
        gender: 'female',
        heightCm: 165,
        weightKg: 60,
        age: 30,
        activityLevel: 'sedentary',
        dietGoal: 'balanced',
      );

      expect(result.bmr, 1320.25);
      expect(result.tdee, closeTo(1584.3, 0.0001));
      expect(result.grains, 5);
      expect(result.vegetables, 3);
      expect(result.fruits, 2);
      expect(result.protein, 3);
      expect(result.oil, 2.5);
    });

    test('applies each diet-goal adjustment only to its target group', () {
      DailyIntakeSnapshot calculate(String goal) {
        final value = calculator.calculate(
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
