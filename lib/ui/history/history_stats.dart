import 'package:canting/core_engine.dart';
import 'package:canting/pet/vitality_calculator.dart';

/// 一周的统计口径（模块 9）：平均完成度、食物种类数、坚果周进度、活力值趋势。
class WeekStats {
  const WeekStats({
    required this.averageCompletion,
    required this.dishVariety,
    required this.soyServings,
    required this.soyWeeklyTarget,
    required this.vitalityTrend,
  });

  /// 当周有记录餐食的平均完成度（0-1）；无记录时为 0。
  final double averageCompletion;

  /// 当周出现的不同菜名数量。
  final int dishVariety;

  /// 当周大豆坚果总份数。
  final double soyServings;

  /// 坚果周目标 = 每日目标 × 7。
  final double soyWeeklyTarget;

  /// 周一 → 周日，共 7 个格子；无记录的天为 null。
  final List<int?> vitalityTrend;

  /// 坚果周进度（0-1，封顶 1）。
  double get soyProgress => soyWeeklyTarget <= 0
      ? 0
      : (soyServings / soyWeeklyTarget).clamp(0.0, 1.0);
}

/// 历史页的纯计算助手。
class HistoryStats {
  HistoryStats._();

  /// 把餐食按自然日分组，逐日算饮食质量得分（同模块 7 活力值口径）。
  static Map<DateTime, int> dayScoresForMeals(
    List<MealRecord> meals,
    DailyIntake target,
  ) {
    final byDay = <DateTime, List<MealRecord>>{};
    for (final meal in meals) {
      final timestamp = meal.timestamp;
      byDay
          .putIfAbsent(
            DateTime(timestamp.year, timestamp.month, timestamp.day),
            () => [],
          )
          .add(meal);
    }
    return byDay.map(
      (day, dayMeals) => MapEntry(
        day,
        VitalityCalculator.scoreDay(
          eaten: dayMeals.fold(
            Portions.zero,
            (total, meal) => total + meal.portionsTotal,
          ),
          target: target,
          mealCount: dayMeals.length,
        ),
      ),
    );
  }

  /// 当天单餐的平均完成度（无记录时 0）。
  static double dayCompletion(List<MealRecord> meals) {
    if (meals.isEmpty) {
      return 0;
    }
    return meals
            .map((meal) => meal.completionRate)
            .reduce((left, right) => left + right) /
        meals.length;
  }

  /// 计算包含 [selected] 那一周（周一起算）的统计。
  static WeekStats weekStats({
    required List<MealRecord> meals,
    required DailyIntake target,
    required DateTime selected,
  }) {
    final selectedDay = DateTime(selected.year, selected.month, selected.day);
    final weekStart = selectedDay.subtract(
      Duration(days: selectedDay.weekday - 1),
    );

    final mealsByDay = <DateTime, List<MealRecord>>{};
    final dishNames = <String>{};
    var soyServings = 0.0;
    for (final meal in meals) {
      final timestamp = meal.timestamp;
      final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
      final inWeek = !day.isBefore(weekStart) &&
          day.isBefore(weekStart.add(const Duration(days: 7)));
      if (inWeek) {
        mealsByDay.putIfAbsent(day, () => []).add(meal);
        soyServings += meal.portionsTotal.proteinSoy;
      }
      for (final dish in meal.dishes) {
        final name = dish.name.trim();
        if (name.isNotEmpty) {
          dishNames.add(name);
        }
      }
    }

    final averageCompletion = mealsByDay.isEmpty
        ? 0.0
        : mealsByDay.values
                  .map(dayCompletion)
                  .reduce((left, right) => left + right) /
              mealsByDay.length;

    final trend = List<int?>.filled(7, null);
    for (var offset = 0; offset < 7; offset++) {
      final day = weekStart.add(Duration(days: offset));
      final dayMeals = mealsByDay[day];
      if (dayMeals == null || dayMeals.isEmpty) {
        continue;
      }
      trend[offset] = VitalityCalculator.scoreDay(
        eaten: dayMeals.fold(
          Portions.zero,
          (total, meal) => total + meal.portionsTotal,
        ),
        target: target,
        mealCount: dayMeals.length,
      );
    }

    return WeekStats(
      averageCompletion: averageCompletion,
      dishVariety: dishNames.length,
      soyServings: soyServings,
      soyWeeklyTarget: target.proteinSoy * 7,
      vitalityTrend: trend,
    );
  }
}
