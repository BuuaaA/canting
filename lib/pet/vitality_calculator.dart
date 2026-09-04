import 'dart:math' as math;

import 'package:canting/core_engine.dart';

/// 饮食质量评级（模块 9 日历配色沿用同一口径）。
enum DietQualityGrade { good, ok, bad, none }

/// 基于最近 3 天饮食质量的宠物活力值计算（模块 7）。
///
/// 单日得分公式（源自 dev-docs/module-07-pet.md）：
///   基础分 60
///   + 蔬菜达标 15 / 蛋白质达标 10 / 主食达标 5 / 水果达标 5 / 大豆坚果达标 5
///   - 油脂超过目标 150% 扣 10
///   + 当日记录满 2 餐加 5
///   钳制到 [15, 100]。
/// 「达标」= 摄入量在目标的 80%~120% 之间。
class VitalityCalculator {
  VitalityCalculator._();

  static const int minimumScore = 15;
  static const int maximumScore = 100;
  static const int baseScore = 60;

  /// 单日饮食质量得分（0-100 区间内，实际下限 15）。
  static int scoreDay({
    required Portions eaten,
    required DailyIntake target,
    required int mealCount,
  }) {
    final targetPortions = target.portions;

    bool isOnTarget(double actual, double goal) {
      if (goal <= 0) {
        // 目标为 0 时视为达标（与 CompletionCalculator 的口径一致）。
        return true;
      }
      final ratio = actual / goal;
      return ratio >= 0.8 && ratio <= 1.2;
    }

    var score = baseScore;
    if (isOnTarget(eaten.vegetables, targetPortions.vegetables)) {
      score += 15;
    }
    if (isOnTarget(eaten.protein, targetPortions.protein)) {
      score += 10;
    }
    if (isOnTarget(eaten.grains, targetPortions.grains)) {
      score += 5;
    }
    if (isOnTarget(eaten.fruits, targetPortions.fruits)) {
      score += 5;
    }
    if (isOnTarget(eaten.proteinSoy, targetPortions.proteinSoy)) {
      score += 5;
    }
    if (targetPortions.oil > 0 && eaten.oil / targetPortions.oil > 1.5) {
      score -= 10;
    }
    if (mealCount >= 2) {
      score += 5;
    }
    return math.max(minimumScore, math.min(maximumScore, score));
  }

  /// 最近 3 天（有记录的天）的平均活力值；一天都没有时返回 null。
  static int? vitalityFromDailyScores(List<int> dayScores) {
    if (dayScores.isEmpty) {
      return null;
    }
    final average =
        dayScores.reduce((left, right) => left + right) / dayScores.length;
    return math.max(
      minimumScore,
      math.min(maximumScore, average.round()),
    );
  }

  /// 日历配色用的质量评级。
  static DietQualityGrade gradeOf(int? score) {
    if (score == null) {
      return DietQualityGrade.none;
    }
    if (score >= 60) {
      return DietQualityGrade.good;
    }
    if (score >= 40) {
      return DietQualityGrade.ok;
    }
    return DietQualityGrade.bad;
  }
}
