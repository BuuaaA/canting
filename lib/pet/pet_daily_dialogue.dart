import 'dart:math';

import 'pet_dialogues.dart';

/// 当日对话场景（模块 7）：按达标情况 / 缺口类型 / 时段划分。
enum DailyDialogScenario {
  fulfilled,
  gapVegetables,
  gapProtein,
  gapFruits,
  gapGrains,
  gapOil,
  noRecord,
  morning,
  midday,
  afternoon,
  evening,
  night,
}

/// 按当日状态生成宠物台词：每种场景至少 3 条随机。
///
/// 选择优先级（高 → 低）：
///   1. 22 点以后 → 晚安（night）
///   2. 当日无记录 → no_record
///   3. 缺口（蔬菜 / 蛋白 / 水果缺口，油脂 / 主食超标）→ 对应 gap_x
///   4. 全部分类 ≥ 70% → 达标（fulfilled）
///   5. 其余按时段 → morning / midday / afternoon / evening
class PetDailyDialogue {
  PetDailyDialogue({required this.dialogues, Random? random})
    : _random = random ?? Random();

  final PetDialogues dialogues;
  final Random _random;

  static const _scenarioKeys = <DailyDialogScenario, String>{
    DailyDialogScenario.fulfilled: 'fulfilled',
    DailyDialogScenario.gapVegetables: 'gap_vegetables',
    DailyDialogScenario.gapProtein: 'gap_protein',
    DailyDialogScenario.gapFruits: 'gap_fruits',
    DailyDialogScenario.gapGrains: 'gap_grains',
    DailyDialogScenario.gapOil: 'gap_oil',
    DailyDialogScenario.noRecord: 'no_record',
    DailyDialogScenario.morning: 'morning',
    DailyDialogScenario.midday: 'midday',
    DailyDialogScenario.afternoon: 'afternoon',
    DailyDialogScenario.evening: 'evening',
    DailyDialogScenario.night: 'night',
  };

  /// 根据当日数据决定场景。
  static DailyDialogScenario scenarioFor({
    required Map<String, double> completionByCategory,
    required int mealCount,
    required int hour,
  }) {
    if (hour >= 22) {
      return DailyDialogScenario.night;
    }
    if (mealCount == 0) {
      return DailyDialogScenario.noRecord;
    }

    final gapCandidates = <(DailyDialogScenario, double)>[];
    void addLow(DailyDialogScenario scenario, String key) {
      final value = completionByCategory[key];
      if (value != null && value < 0.4) {
        gapCandidates.add((scenario, 0.4 - value));
      }
    }

    void addHigh(DailyDialogScenario scenario, String key) {
      final value = completionByCategory[key];
      if (value != null && value > 1.2) {
        gapCandidates.add((scenario, value - 1.2));
      }
    }

    addLow(DailyDialogScenario.gapVegetables, 'vegetables');
    addLow(DailyDialogScenario.gapProtein, 'protein');
    addLow(DailyDialogScenario.gapFruits, 'fruits');
    addHigh(DailyDialogScenario.gapOil, 'oil');
    addHigh(DailyDialogScenario.gapGrains, 'grains');
    if (gapCandidates.isNotEmpty) {
      var largest = gapCandidates.first;
      for (final candidate in gapCandidates.skip(1)) {
        if (candidate.$2 > largest.$2) {
          largest = candidate;
        }
      }
      return largest.$1;
    }

    final isBalanced =
        completionByCategory.isNotEmpty &&
        completionByCategory.values.every((value) => value >= 0.7);
    if (isBalanced) {
      return DailyDialogScenario.fulfilled;
    }

    if (hour < 11) {
      return DailyDialogScenario.morning;
    }
    if (hour < 14) {
      return DailyDialogScenario.midday;
    }
    if (hour < 18) {
      return DailyDialogScenario.afternoon;
    }
    return DailyDialogScenario.evening;
  }

  /// 从场景对应的文案池里随机取一句。
  String lineFor(String petType, DailyDialogScenario scenario) {
    final key = _scenarioKeys[scenario]!;
    final lines = dialogues.dailyLines(petType, key);
    return lines[_random.nextInt(lines.length)];
  }

  /// 一站式入口：给当日数据直接取一句台词。
  String pickDaily({
    required String petType,
    required Map<String, double> completionByCategory,
    required int mealCount,
    required int hour,
  }) {
    final scenario = scenarioFor(
      completionByCategory: completionByCategory,
      mealCount: mealCount,
      hour: hour,
    );
    return lineFor(petType, scenario);
  }
}
