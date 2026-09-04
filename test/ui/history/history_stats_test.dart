import 'package:canting/core_engine.dart';
import 'package:canting/pet/vitality_calculator.dart';
import 'package:canting/ui/history/calendar_view.dart';
import 'package:canting/ui/history/history_stats.dart';
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

MealRecord _meal(
  String id,
  DateTime time, {
  double completionRate = 0.8,
  Portions portions = const Portions(
    grains: 5,
    vegetables: 4,
    fruits: 2.5,
    protein: 4,
    proteinSoy: 1,
    oil: 2.5,
  ),
  List<String> dishNames = const ['测试菜'],
}) => MealRecord(
  mealId: id,
  mealType: 'lunch',
  timestamp: time,
  completionRate: completionRate,
  portionsTotal: portions,
  dishes: [
    for (final name in dishNames) MealDish(name: name, quantity: 1),
  ],
);

void main() {
  final target = _target();

  group('HistoryStats.dayScoresForMeals（日质量得分）', () {
    test('按自然日分组，逐日按当天总量评分', () {
      const full = Portions(
        grains: 5,
        vegetables: 4,
        fruits: 2.5,
        protein: 4,
        proteinSoy: 1,
        oil: 2.5,
      );
      const half = Portions(
        grains: 2.5,
        vegetables: 2,
        fruits: 1.25,
        protein: 2,
        proteinSoy: 0.5,
        oil: 1.25,
      );
      final scores = HistoryStats.dayScoresForMeals([
        _meal('a', DateTime(2026, 9, 1, 12), portions: half),
        _meal('b', DateTime(2026, 9, 1, 18, 30), portions: half),
        _meal('c', DateTime(2026, 9, 2, 12), portions: full),
      ], target);

      // 9/1：两餐合计正好满目标 → 105 → 钳 100；9/2：单餐满目标 → 100。
      expect(scores[DateTime(2026, 9, 1)], 100);
      expect(scores[DateTime(2026, 9, 2)], 100);
      expect(scores, hasLength(2));
    });

    test('油脂翻倍的日子会被扣分', () {
      const doubleOil = Portions(
        grains: 5,
        vegetables: 4,
        fruits: 2.5,
        protein: 4,
        proteinSoy: 1,
        oil: 5,
      );
      final scores = HistoryStats.dayScoresForMeals([
        _meal('a', DateTime(2026, 9, 1, 12), portions: doubleOil),
      ], target);

      // 60 + 40（其余分类全达标）- 10（油 200%）= 90。
      expect(scores[DateTime(2026, 9, 1)], 90);
    });
  });

  group('HistoryStats.dayCompletion（单日完成度）', () {
    test('等于各餐完成度的平均', () {
      expect(
        HistoryStats.dayCompletion([
          _meal('a', DateTime(2026, 9, 1), completionRate: 0.7),
          _meal('b', DateTime(2026, 9, 1, 18), completionRate: 0.9),
        ]),
        0.8,
      );
    });

    test('无记录为 0', () {
      expect(HistoryStats.dayCompletion([]), 0);
    });
  });

  group('HistoryStats.weekStats（周统计口径）', () {
    // 2026-09-04 是周五；所在周为 8/31（周一）~ 9/6（周日）。
    final selected = DateTime(2026, 9, 4);

    test('平均完成度 = 有记录天数的日均完成度的平均', () {
      final stats = HistoryStats.weekStats(
        meals: [
          _meal('a', DateTime(2026, 9, 1), completionRate: 0.6),
          _meal('b', DateTime(2026, 9, 3), completionRate: 0.8),
          _meal('c', DateTime(2026, 9, 3, 19), completionRate: 1.0),
        ],
        target: target,
        selected: selected,
      );

      // 9/1 日均 0.6，9/3 日均 0.9 → 平均 0.75。
      expect(stats.averageCompletion, closeTo(0.75, 0.0001));
    });

    test('食物种类数按整周去重统计', () {
      final stats = HistoryStats.weekStats(
        meals: [
          _meal('a', DateTime(2026, 9, 1), dishNames: ['黄焖鸡米饭', '蒜蓉西兰花']),
          _meal('b', DateTime(2026, 9, 2), dishNames: ['黄焖鸡米饭']),
          _meal('c', DateTime(2026, 9, 3), dishNames: ['西红柿炒蛋', '']),
        ],
        target: target,
        selected: selected,
      );

      // 去重后 3 种，空菜名不计。
      expect(stats.dishVariety, 3);
    });

    test('坚果周进度 = 周内大豆份数 ÷（每日目标 × 7），封顶 1', () {
      final stats = HistoryStats.weekStats(
        meals: [
          _meal(
            'a',
            DateTime(2026, 9, 1),
            portions: const Portions(proteinSoy: 1),
          ),
          _meal(
            'b',
            DateTime(2026, 9, 2),
            portions: const Portions(proteinSoy: 2),
          ),
        ],
        target: target,
        selected: selected,
      );

      expect(stats.soyServings, 3);
      expect(stats.soyWeeklyTarget, 7);
      expect(stats.soyProgress, closeTo(3 / 7, 0.0001));

      final over = HistoryStats.weekStats(
        meals: [
          for (var i = 0; i < 5; i++)
            _meal(
              'over$i',
              DateTime(2026, 9, 1 + i),
              portions: const Portions(proteinSoy: 5),
            ),
        ],
        target: target,
        selected: selected,
      );
      expect(over.soyProgress, 1);
    });

    test('活力值趋势共 7 格，无记录的天为 null，跨周数据不计入', () {
      final stats = HistoryStats.weekStats(
        meals: [
          _meal('a', DateTime(2026, 8, 31, 12)), // 周一
          _meal('b', DateTime(2026, 9, 2, 12)), // 周三
          _meal('outside', DateTime(2026, 8, 24, 12)), // 上上个月，不在本周
        ],
        target: target,
        selected: selected,
      );

      expect(stats.vitalityTrend, hasLength(7));
      expect(stats.vitalityTrend[0], isNotNull);
      expect(stats.vitalityTrend[1], isNull);
      expect(stats.vitalityTrend[2], isNotNull);
      expect(stats.vitalityTrend[6], isNull);
    });

    test('整周无记录：完成度 0、趋势全 null', () {
      final stats = HistoryStats.weekStats(
        meals: const [],
        target: target,
        selected: selected,
      );

      expect(stats.averageCompletion, 0);
      expect(stats.dishVariety, 0);
      expect(stats.vitalityTrend, everyElement(isNull));
    });
  });

  group('质量评级规则（模块 9 日历配色口径）', () {
    test('≥60 好、40-59 一般、<40 差、null 无记录', () {
      expect(gradeForScore(60), DietQualityGrade.good);
      expect(gradeForScore(59), DietQualityGrade.ok);
      expect(gradeForScore(40), DietQualityGrade.ok);
      expect(gradeForScore(39), DietQualityGrade.bad);
      expect(gradeForScore(null), DietQualityGrade.none);
    });

    test('不同评级对应不同颜色', () {
      final colors = {
        for (final grade in DietQualityGrade.values) grade: qualityColor(grade),
      };
      expect(colors.values.toSet(), hasLength(DietQualityGrade.values.length));
    });
  });
}
