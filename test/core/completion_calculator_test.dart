import 'package:canting/core/completion_calculator.dart';
import 'package:canting/core/models/daily_intake.dart';
import 'package:canting/core/models/portions.dart';
import 'package:test/test.dart';

void main() {
  const target = DailyIntake(
    grains: 6,
    vegetables: 4,
    fruits: 2,
    protein: 4,
    proteinSoy: 1,
    oil: 2.5,
    bmr: 1500,
    tdee: 2000,
  );
  final calculator = CompletionCalculator();

  group('CompletionCalculator', () {
    test('averages all six capped category completion rates', () {
      final result = calculator.calculate(
        eatenPortions: const Portions(
          grains: 3,
          vegetables: 2,
          fruits: 1,
          protein: 2,
          proteinSoy: 0.5,
          oil: 1.25,
        ),
        dailyIntake: target,
        sodiumLevel: 'low',
      );

      expect(result.overall, 0.5);
      expect(result.byCategory.values, everyElement(0.5));
      expect(result.biggestGap, 'grains');
      expect(result.sodiumLevel, 'low');
    });

    test('caps overconsumption at one and reports no gap when complete', () {
      final result = calculator.calculate(
        eatenPortions: const Portions(
          grains: 8,
          vegetables: 6,
          fruits: 3,
          protein: 5,
          proteinSoy: 2,
          oil: 4,
        ),
        dailyIntake: target,
      );

      expect(result.overall, 1);
      expect(result.byCategory.values, everyElement(1));
      expect(result.biggestGap, isNull);
    });

    test('caps overall completion at 70% when one group is below 30%', () {
      final result = calculator.calculate(
        eatenPortions: const Portions(
          grains: 6,
          vegetables: 4,
          fruits: 0.4,
          protein: 4,
          proteinSoy: 1,
          oil: 2.5,
        ),
        dailyIntake: target,
        sodiumLevel: 'high',
      );

      expect(result.byCategory['fruits'], closeTo(0.2, 0.0001));
      expect(result.overall, 0.7);
      expect(result.biggestGap, 'fruits');
      expect(result.sodiumLevel, 'high');
    });

    test('rejects a sodium value outside the MVP levels', () {
      expect(
        () => calculator.calculate(
          eatenPortions: Portions.zero,
          dailyIntake: target,
          sodiumLevel: 'very_high',
        ),
        throwsArgumentError,
      );
    });
  });
}
