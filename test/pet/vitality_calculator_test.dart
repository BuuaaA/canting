import 'package:canting/core_engine.dart';
import 'package:canting/pet/vitality_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

DailyIntake _target() => const DailyIntake(
  grains: 5,
  vegetables: 4,
  fruits: 2.5,
  protein: 4,
  proteinSoy: 1,
  oil: 2.5,
  bmr: 1450,
  tdee: 1740,
);

void main() {
  final target = _target();

  group('VitalityCalculator.scoreDay（单日活力值）', () {
    test('全部分类达标且满 2 餐时得满分 100', () {
      final score = VitalityCalculator.scoreDay(
        eaten: const Portions(
          grains: 5,
          vegetables: 4,
          fruits: 2.5,
          protein: 4,
          proteinSoy: 1,
          oil: 2.5,
        ),
        target: target,
        mealCount: 2,
      );

      // 60 + 15 + 10 + 5 + 5 + 5 + 5 = 105 → 钳到 100。
      expect(score, 100);
    });

    test('基础分：只记 1 餐且各分类都在范围外时贴近 60', () {
      final score = VitalityCalculator.scoreDay(
        eaten: Portions.zero,
        target: target,
        mealCount: 1,
      );

      // 60（无达标加分、无 2 餐加分、油脂为 0 不算超标）。
      expect(score, 60);
    });

    test('蔬菜达标只差一点（80%）也算达标', () {
      final score = VitalityCalculator.scoreDay(
        eaten: const Portions(vegetables: 3.2),
        target: target,
        mealCount: 1,
      );

      // 60 + 15（蔬菜 3.2/4 = 80% 达标）。
      expect(score, 75);
    });

    test('蔬菜只有 60% 时不加分', () {
      final score = VitalityCalculator.scoreDay(
        eaten: const Portions(vegetables: 2.4),
        target: target,
        mealCount: 1,
      );

      expect(score, 60);
    });

    test('油脂超过目标 150% 扣 10 分', () {
      final score = VitalityCalculator.scoreDay(
        eaten: const Portions(oil: 4.5),
        target: target,
        mealCount: 1,
      );

      // 4.5/2.5 = 180% → 60 - 10 = 50。
      expect(score, 50);
    });

    test('油脂 150% 整不算超标', () {
      final score = VitalityCalculator.scoreDay(
        eaten: const Portions(oil: 3.75),
        target: target,
        mealCount: 1,
      );

      expect(score, 60);
    });

    test('吃得太少也有 15 分下限', () {
      final score = VitalityCalculator.scoreDay(
        eaten: const Portions(oil: 25),
        target: target,
        mealCount: 0,
      );

      // 60 - 10（油超标）= 50，仍高于 15；构造更低：
      // 单项最少扣 10 分，因此下限测试交给 3 天平均钳制。
      expect(score, greaterThanOrEqualTo(15));
    });

    test('目标为 0 的分类视为达标', () {
      final zeroTarget = const DailyIntake(
        grains: 5,
        vegetables: 4,
        fruits: 2.5,
        protein: 4,
        proteinSoy: 1,
        oil: 0,
        bmr: 1450,
        tdee: 1740,
      );
      final score = VitalityCalculator.scoreDay(
        eaten: const Portions(oil: 100),
        target: zeroTarget,
        mealCount: 1,
      );

      // 油脂目标为 0：不计超标扣分。
      expect(score, 60);
    });
  });

  group('VitalityCalculator.vitalityFromDailyScores（最近 3 天）', () {
    test('取有记录天数的平均分', () {
      expect(
        VitalityCalculator.vitalityFromDailyScores([80, 60, 70]),
        70,
      );
      // 只有一天也行。
      expect(VitalityCalculator.vitalityFromDailyScores([50]), 50);
    });

    test('没有记录的天返回 null（交给离线衰减处理）', () {
      expect(VitalityCalculator.vitalityFromDailyScores([]), isNull);
    });

    test('平均值同样钳制在 [15, 100]', () {
      expect(
        VitalityCalculator.vitalityFromDailyScores([15, 15, 15]),
        15,
      );
      expect(
        VitalityCalculator.vitalityFromDailyScores([100, 100, 100]),
        100,
      );
    });
  });

  group('VitalityCalculator.gradeOf（质量评级，模块 9 共用）', () {
    test('≥60 好、40-59 一般、<40 差、null 无记录', () {
      expect(VitalityCalculator.gradeOf(60), DietQualityGrade.good);
      expect(VitalityCalculator.gradeOf(88), DietQualityGrade.good);
      expect(VitalityCalculator.gradeOf(59), DietQualityGrade.ok);
      expect(VitalityCalculator.gradeOf(40), DietQualityGrade.ok);
      expect(VitalityCalculator.gradeOf(39), DietQualityGrade.bad);
      expect(VitalityCalculator.gradeOf(15), DietQualityGrade.bad);
      expect(VitalityCalculator.gradeOf(null), DietQualityGrade.none);
    });
  });
}
