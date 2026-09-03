import 'models/daily_intake.dart';
import 'models/dietary_guidelines.dart';

/// Calculates a user's recommended daily food-group portions.
///
/// 能量公式（Mifflin-St Jeor + 活动系数）是生理学常数，保留在代码里；
/// 各食物分类的推荐份数全部来自膳食指南 JSON 的能量档表
/// （recommendationsByEnergyLevel），按 TDEE 在相邻档位间线性插值，
/// 超出 1600~2400kcal 范围时钳制到最近档位。
class IntakeCalculator {
  static const Map<String, double> _activityFactors = {
    'sedentary': 1.2,
    'light': 1.375,
    'moderate': 1.55,
    'heavy': 1.725,
  };

  static const Set<String> _dietGoals = {
    'balanced',
    'more_veg',
    'more_protein',
    'less_carb',
  };

  /// APP 内部分类 → 膳食指南 JSON 的分类 id。
  ///
  /// 口径说明：
  /// - protein（鱼肉蛋奶）只取 protein_meat_egg（肉蛋鱼）。奶及奶制品
  ///   （dairy，每日 2 份）不计入：外卖菜品库几乎不含奶制品，计入会使
  ///   目标无法达到。
  /// - proteinSoy（大豆坚果）只取 soy（大豆）。坚果（nut，每日 1 份）
  ///   不计入：菜品份数归属中坚果不独立计份（如宫保鸡丁的花生计入整菜），
  ///   计入会虚高目标。
  static const _guidelineCategory = <String, String>{
    'grains': 'grain_tuber',
    'vegetables': 'vegetable',
    'fruits': 'fruit',
    'protein': 'protein_meat_egg',
    'proteinSoy': 'soy',
    'oil': 'oil',
  };

  DailyIntake calculate({
    required DietaryGuidelines guidelines,
    required String gender,
    required int heightCm,
    required double weightKg,
    required int age,
    required String activityLevel,
    required String dietGoal,
  }) {
    _validateInputs(
      gender: gender,
      heightCm: heightCm,
      weightKg: weightKg,
      age: age,
      activityLevel: activityLevel,
      dietGoal: dietGoal,
    );

    final genderConstant = gender == 'male' ? 5 : -161;
    final bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + genderConstant;
    final tdee = bmr * _activityFactors[activityLevel]!;

    // 从膳食指南能量档表查推荐份数，TDEE 在相邻档位间线性插值。
    var grains = _servingsAt(guidelines, tdee, _guidelineCategory['grains']!);
    var vegetables = _servingsAt(
      guidelines,
      tdee,
      _guidelineCategory['vegetables']!,
    );
    final fruits = _servingsAt(guidelines, tdee, _guidelineCategory['fruits']!);
    var protein = _servingsAt(
      guidelines,
      tdee,
      _guidelineCategory['protein']!,
    );
    final proteinSoy = _servingsAt(
      guidelines,
      tdee,
      _guidelineCategory['proteinSoy']!,
    );
    final oil = _servingsAt(guidelines, tdee, _guidelineCategory['oil']!);

    switch (dietGoal) {
      case 'more_veg':
        vegetables *= 1.2;
        break;
      case 'more_protein':
        protein *= 1.2;
        break;
      case 'less_carb':
        grains *= 0.8;
        break;
      case 'balanced':
        break;
    }

    return DailyIntake(
      grains: grains,
      vegetables: vegetables,
      fruits: fruits,
      protein: protein,
      proteinSoy: proteinSoy,
      oil: oil,
      bmr: bmr,
      tdee: tdee,
    );
  }

  /// 按 TDEE 在膳食指南能量档之间插值取某分类的推荐份数。
  /// TDEE 超出档位范围时钳制到最低/最高档。
  double _servingsAt(
    DietaryGuidelines guidelines,
    double tdee,
    String guidelineCategory,
  ) {
    final levels = guidelines.recommendationsByEnergyLevel.values.toList()
      ..sort((a, b) => a.energyLevelKcal.compareTo(b.energyLevelKcal));
    if (levels.isEmpty) {
      throw StateError(
        'dietary guidelines have no energy-level recommendations',
      );
    }

    double servingsOf(EnergyLevelRecommendation level) {
      final range = level.intakeRanges[guidelineCategory];
      final servings = range?.servings;
      if (servings == null) {
        throw StateError(
          'dietary guidelines: category "$guidelineCategory" has no servings '
          'at ${level.energyLevelKcal}kcal',
        );
      }
      return servings;
    }

    if (tdee <= levels.first.energyLevelKcal) {
      return servingsOf(levels.first);
    }
    if (tdee >= levels.last.energyLevelKcal) {
      return servingsOf(levels.last);
    }
    for (var i = 0; i < levels.length - 1; i++) {
      final lower = levels[i];
      final upper = levels[i + 1];
      if (tdee >= lower.energyLevelKcal && tdee <= upper.energyLevelKcal) {
        final position =
            (tdee - lower.energyLevelKcal) /
            (upper.energyLevelKcal - lower.energyLevelKcal);
        return servingsOf(lower) +
            (servingsOf(upper) - servingsOf(lower)) * position;
      }
    }
    return servingsOf(levels.last);
  }

  static void _validateInputs({
    required String gender,
    required int heightCm,
    required double weightKg,
    required int age,
    required String activityLevel,
    required String dietGoal,
  }) {
    if (gender != 'male' && gender != 'female') {
      throw ArgumentError.value(gender, 'gender', 'must be male or female');
    }
    if (heightCm <= 0) {
      throw ArgumentError.value(heightCm, 'heightCm', 'must be positive');
    }
    if (!weightKg.isFinite || weightKg <= 0) {
      throw ArgumentError.value(weightKg, 'weightKg', 'must be positive');
    }
    if (age <= 0) {
      throw ArgumentError.value(age, 'age', 'must be positive');
    }
    if (!_activityFactors.containsKey(activityLevel)) {
      throw ArgumentError.value(
        activityLevel,
        'activityLevel',
        'unsupported activity level',
      );
    }
    if (!_dietGoals.contains(dietGoal)) {
      throw ArgumentError.value(dietGoal, 'dietGoal', 'unsupported diet goal');
    }
  }
}
