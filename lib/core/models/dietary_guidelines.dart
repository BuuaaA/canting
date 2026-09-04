/// 中国居民膳食指南（2022）核心数据，来自 assets/data/dietary_guidelines.json。
///
/// 提供「份」的克重参考（serving_reference）和食物交换份（food_exchange），
/// 是 ServingEstimator 做 重量 ↔ 份数 换算的数据来源。
class DietaryGuidelines {
  const DietaryGuidelines({
    required this.version,
    required this.source,
    required this.foodCategories,
    required this.recommendationsByEnergyLevel,
    required this.servingReference,
    required this.foodExchange,
    this.weeklyTargetsByEnergyLevel = const {},
    this.wholeGrain,
    this.addedSugar,
    this.weeklyBalance,
    this.oilSaltLimits,
  });

  final String version;
  final String source;

  /// 膳食指南的六大类食物（谷薯、蔬菜、水果、蛋白质、大豆坚果、油脂盐）。
  final List<GuidelineFoodCategory> foodCategories;

  /// 按能量水平（"1600"~"2400" kcal）的每日推荐摄入量。
  final Map<String, EnergyLevelRecommendation> recommendationsByEnergyLevel;

  /// 每类食物「1 份」对应的克重，键为指南分类 id（如 grain_tuber）。
  final Map<String, ServingReference> servingReference;

  /// 食物交换份：组 id → 基准食物 → {可交换食物: 克重}。
  /// 例：grain_tuber → rice_50g_raw → {cooked_rice: 150}，
  /// 表示 150g 熟米饭等价于 50g 生米（即 1 份谷薯）。
  final Map<String, FoodExchangeGroup> foodExchange;

  /// 六类食物的 7 天周目标（键为指南分类 id），按能量档给出。
  /// 与 daily_intake_recommendation 同源（单日 × 7），供滚动平衡台账使用。
  final Map<String, WeeklyTargets> weeklyTargetsByEnergyLevel;

  /// 全谷物要求（50~150g/日，换算为谷薯类日份数下限）。
  final WholeGrainRequirement? wholeGrain;

  /// 添加糖口径（V1.0 不做追踪，仅记录）。
  final AddedSugarGuidance? addedSugar;

  /// 周平衡原则字段化（窗口天数、盈余/欠账衰减、单餐修正限幅）。
  final WeeklyBalanceConfig? weeklyBalance;

  /// 油盐上限（油日目标份数上界；盐用 high_sodium 标签代理）。
  final OilSaltLimits? oilSaltLimits;

  factory DietaryGuidelines.fromJson(Map<String, dynamic> json) {
    final categoryRoot = json['food_categories'];
    if (categoryRoot is! List) {
      throw const FormatException(
        'dietary guidelines: food_categories must be an array',
      );
    }

    final servingRoot = json['serving_reference'];
    if (servingRoot is! Map) {
      throw const FormatException(
        'dietary guidelines: serving_reference must be an object',
      );
    }

    final energyRoot =
        json['daily_intake_recommendation']?['by_energy_level'];
    if (energyRoot is! Map) {
      throw const FormatException(
        'dietary guidelines: by_energy_level must be an object',
      );
    }

    final exchangeRoot = json['food_exchange'];
    if (exchangeRoot is! Map) {
      throw const FormatException(
        'dietary guidelines: food_exchange must be an object',
      );
    }

    return DietaryGuidelines(
      version: json['version'] as String? ?? '',
      source: json['source'] as String? ?? '',
      foodCategories: categoryRoot
          .map(
            (item) => GuidelineFoodCategory.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(growable: false),
      recommendationsByEnergyLevel: energyRoot.map(
        (key, value) => MapEntry(
          key,
          EnergyLevelRecommendation.fromJson(
            key,
            (value! as Map).cast<String, dynamic>(),
          ),
        ),
      ),
      // 跳过 _comment 这类说明性字段（值不是对象）。
      servingReference: {
        for (final entry in servingRoot.entries)
          if (entry.value is Map)
            entry.key as String: ServingReference.fromJson(
              entry.key as String,
              (entry.value as Map).cast<String, dynamic>(),
            ),
      },
      foodExchange: exchangeRoot.map(
        (key, value) => key is String && value is Map
            ? MapEntry(
                key,
                FoodExchangeGroup.fromJson(
                  key,
                  value.cast<String, dynamic>(),
                ),
              )
            : throw FormatException('invalid food_exchange group for $key'),
      ),
      // 以下为指南重蒸馏新增区块（2026-09）：缺区块时保持空/ null，
      // 旧版 JSON 仍可解析。
      weeklyTargetsByEnergyLevel: _parseWeeklyTargets(
        json['weekly_targets'],
      ),
      wholeGrain: json['whole_grain'] is Map
          ? WholeGrainRequirement.fromJson(
              (json['whole_grain'] as Map).cast<String, dynamic>(),
            )
          : null,
      addedSugar: json['added_sugar'] is Map
          ? AddedSugarGuidance.fromJson(
              (json['added_sugar'] as Map).cast<String, dynamic>(),
            )
          : null,
      weeklyBalance: json['weekly_balance'] is Map
          ? WeeklyBalanceConfig.fromJson(
              (json['weekly_balance'] as Map).cast<String, dynamic>(),
            )
          : null,
      oilSaltLimits: json['oil_salt_limits'] is Map
          ? OilSaltLimits.fromJson(
              (json['oil_salt_limits'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
  }

  /// 解析 weekly_targets（跳过 _comment；结构非法时抛 FormatException，
  /// 区块整体缺失时返回空表以兼容旧 JSON）。
  static Map<String, WeeklyTargets> _parseWeeklyTargets(dynamic root) {
    if (root == null) {
      return const {};
    }
    if (root is! Map) {
      throw const FormatException(
        'dietary guidelines: weekly_targets must be an object',
      );
    }
    final energyRoot = root['by_energy_level'];
    if (energyRoot == null) {
      return const {};
    }
    if (energyRoot is! Map) {
      throw const FormatException(
        'dietary guidelines: weekly_targets.by_energy_level must be an object',
      );
    }
    return {
      for (final entry in energyRoot.entries)
        if (entry.key is String && entry.value is Map)
          entry.key as String: WeeklyTargets.fromJson(
            entry.key as String,
            (entry.value as Map).cast<String, dynamic>(),
          ),
    };
  }

  /// 某类食物「1 份」的克重；指南未定义（如油脂）时返回 null。
  double? gramsPerServingFor(String categoryId) =>
      servingReference[categoryId]?.perServingGrams;

  /// 在所有交换组中查找食物键（如 cooked_rice）所属的基准条目。
  FoodExchangeEntry? findExchangeEntry(String foodKey) {
    for (final group in foodExchange.values) {
      for (final base in group.bases.values) {
        final grams = base.exchangeGrams[foodKey];
        if (grams != null) {
          return FoodExchangeEntry(
            groupId: group.id,
            baseKey: base.baseKey,
            foodKey: foodKey,
            gramsPerServing: grams,
          );
        }
      }
    }
    return null;
  }

  /// 基准食物本身（如 milk_100ml）也可作为交换条目，基准克重即每份克重。
  FoodExchangeEntry? findExchangeBase(String baseKey) {
    for (final group in foodExchange.values) {
      final base = group.bases[baseKey];
      if (base != null) {
        return FoodExchangeEntry(
          groupId: group.id,
          baseKey: base.baseKey,
          foodKey: baseKey,
          gramsPerServing: base.baseReferenceGrams,
        );
      }
    }
    return null;
  }
}

/// 膳食指南的食物分类（六大类）。
class GuidelineFoodCategory {
  const GuidelineFoodCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.isCore,
    required this.displayPriority,
    this.subCategories = const [],
    this.note,
  });

  final String id;
  final String name;
  final String description;
  final bool isCore;
  final int displayPriority;
  final List<String> subCategories;
  final String? note;

  factory GuidelineFoodCategory.fromJson(Map<String, dynamic> json) =>
      GuidelineFoodCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        isCore: json['is_core'] as bool? ?? true,
        displayPriority: (json['display_priority'] as num?)?.toInt() ?? 99,
        subCategories: json['sub_categories'] == null
            ? const []
            : List<String>.from(json['sub_categories'] as List),
        note: json['note'] as String?,
      );
}

/// 某一能量水平下的每日推荐摄入量。
class EnergyLevelRecommendation {
  const EnergyLevelRecommendation({
    required this.energyLevelKcal,
    required this.intakeRanges,
  });

  /// 能量水平，如 1600、1800、2000。
  final int energyLevelKcal;

  /// 分类 id → 摄入范围（盐只有上限，没有 min/servings）。
  final Map<String, IntakeRange> intakeRanges;

  factory EnergyLevelRecommendation.fromJson(
    String energyKey,
    Map<String, dynamic> json,
  ) {
    final level = int.tryParse(energyKey);
    if (level == null) {
      throw FormatException(
        'invalid energy level key in dietary guidelines: $energyKey',
      );
    }
    return EnergyLevelRecommendation(
      energyLevelKcal: level,
      intakeRanges: json.map(
        (key, value) => MapEntry(
          key,
          IntakeRange.fromJson((value! as Map).cast<String, dynamic>()),
        ),
      ),
    );
  }
}

/// 一类食物的每日推荐摄入范围，单位 g（盐只有 max）。
class IntakeRange {
  const IntakeRange({this.min, this.max, this.servings});

  final double? min;
  final double? max;
  final double? servings;

  factory IntakeRange.fromJson(Map<String, dynamic> json) => IntakeRange(
    min: (json['min'] as num?)?.toDouble(),
    max: (json['max'] as num?)?.toDouble(),
    servings: (json['servings'] as num?)?.toDouble(),
  );
}

/// 一类食物「1 份」的克重参考和常见例子。
class ServingReference {
  const ServingReference({
    required this.categoryId,
    required this.perServingGrams,
    required this.examples,
  });

  final String categoryId;
  final double perServingGrams;
  final List<String> examples;

  factory ServingReference.fromJson(
    String categoryId,
    Map<String, dynamic> json,
  ) => ServingReference(
    categoryId: categoryId,
    perServingGrams: (json['per_serving_grams'] as num).toDouble(),
    examples: json['examples'] == null
        ? const []
        : List<String>.from(json['examples'] as List),
  );
}

/// 一个食物交换组（如 soy_products、grain_tuber）。
class FoodExchangeGroup {
  const FoodExchangeGroup({required this.id, required this.bases});

  final String id;

  /// 基准食物 → 交换表。基准键如 soy_25g、rice_50g_raw、milk_100ml。
  final Map<String, FoodExchangeBase> bases;

  factory FoodExchangeGroup.fromJson(
    String id,
    Map<String, dynamic> json,
  ) => FoodExchangeGroup(
    id: id,
    bases: json.map(
      (key, value) => MapEntry(
        key,
        FoodExchangeBase.fromJson(
          key,
          (value! as Map).cast<String, dynamic>(),
        ),
      ),
    ),
  );
}

/// 以某基准食物为 1 份的交换表。
class FoodExchangeBase {
  const FoodExchangeBase({
    required this.baseKey,
    required this.baseReferenceGrams,
    required this.exchangeGrams,
  });

  final String baseKey;

  /// 从基准键解析出的基准克重（soy_25g → 25，milk_100ml → 100）。
  final double baseReferenceGrams;

  /// 可交换食物 → 等价克重。例：cooked_rice → 150。
  final Map<String, double> exchangeGrams;

  factory FoodExchangeBase.fromJson(
    String baseKey,
    Map<String, dynamic> json,
  ) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(baseKey);
    if (match == null) {
      throw FormatException(
        'cannot parse reference grams from exchange base key: $baseKey',
      );
    }
    return FoodExchangeBase(
      baseKey: baseKey,
      baseReferenceGrams: double.parse(match.group(1)!),
      exchangeGrams: json.map(
        (key, value) => MapEntry(key, (value! as num).toDouble()),
      ),
    );
  }
}

/// 一次交换查找的结果：食物 foodKey 每 gramsPerServing 克算 1 份。
class FoodExchangeEntry {
  const FoodExchangeEntry({
    required this.groupId,
    required this.baseKey,
    required this.foodKey,
    required this.gramsPerServing,
  });

  final String groupId;
  final String baseKey;
  final String foodKey;
  final double gramsPerServing;
}

/// 某能量档下六类食物的 7 天周目标（指南分类 id → 份数）。
class WeeklyTargets {
  const WeeklyTargets({required this.energyLevelKcal, required this.servings});

  /// 能量水平，如 1600、1800、2000。
  final int energyLevelKcal;

  /// 指南分类 id（grain_tuber/vegetable/fruit/protein_meat_egg/soy/oil）
  /// → 7 天目标份数。奶（dairy）、坚果（nut）与日目标口径一致地不计入。
  final Map<String, double> servings;

  factory WeeklyTargets.fromJson(
    String energyKey,
    Map<String, dynamic> json,
  ) {
    final level = int.tryParse(energyKey);
    if (level == null) {
      throw FormatException(
        'invalid energy level key in weekly_targets: $energyKey',
      );
    }
    return WeeklyTargets(
      energyLevelKcal: level,
      servings: {
        for (final entry in json.entries)
          if (entry.value is Map)
            entry.key: ((entry.value as Map)['servings'] as num).toDouble(),
      },
    );
  }
}

/// 全谷物要求：指南推荐全谷物和杂豆类 50~150g/日。
class WholeGrainRequirement {
  const WholeGrainRequirement({
    required this.dailyMinGrams,
    required this.dailyMaxGrams,
    required this.dailyMinServings,
  });

  final double dailyMinGrams;
  final double dailyMaxGrams;

  /// 按谷薯每份 50g 换算的日份数下限（50g ÷ 50g = 1 份）。
  final double dailyMinServings;

  factory WholeGrainRequirement.fromJson(Map<String, dynamic> json) =>
      WholeGrainRequirement(
        dailyMinGrams: (json['daily_min_grams'] as num).toDouble(),
        dailyMaxGrams: (json['daily_max_grams'] as num).toDouble(),
        dailyMinServings: (json['daily_min_servings'] as num).toDouble(),
      );
}

/// 添加糖口径（V1.0 不追踪，仅记录，见 JSON 注释）。
class AddedSugarGuidance {
  const AddedSugarGuidance({
    required this.dailyMaxGrams,
    required this.dailyIdealMaxGrams,
    required this.tracked,
  });

  final double dailyMaxGrams;
  final double dailyIdealMaxGrams;
  final bool tracked;

  factory AddedSugarGuidance.fromJson(Map<String, dynamic> json) =>
      AddedSugarGuidance(
        dailyMaxGrams: (json['daily_max_grams'] as num).toDouble(),
        dailyIdealMaxGrams: (json['daily_ideal_max_grams'] as num).toDouble(),
        tracked: json['tracked'] as bool? ?? false,
      );
}

/// 周平衡原则字段化：7 天滚动窗口 + 衰减参数 + 单餐修正限幅。
class WeeklyBalanceConfig {
  const WeeklyBalanceConfig({
    required this.windowDays,
    required this.surplusDecay,
    required this.deficitDecay,
    required this.singleMealCorrectionLimit,
  });

  final int windowDays;

  /// 盈余（吃超）次日衰减比例：0.5 表示吃超 2 份次日剩 1 份。
  final double surplusDecay;

  /// 欠账（不足）每日衰减比例：0.2 表示欠 3 份次日仍欠 2.4 份，
  /// 长期不足会持续累积影响推荐。
  final double deficitDecay;

  /// 引擎单餐修正量限幅：单餐推荐份数最多比常规推荐 ±30%。
  final double singleMealCorrectionLimit;

  factory WeeklyBalanceConfig.fromJson(Map<String, dynamic> json) =>
      WeeklyBalanceConfig(
        windowDays: (json['window_days'] as num).toInt(),
        surplusDecay: (json['surplus_decay'] as num).toDouble(),
        deficitDecay: (json['deficit_decay'] as num).toDouble(),
        singleMealCorrectionLimit:
            (json['single_meal_correction_limit'] as num).toDouble(),
      );
}

/// 油盐上限：油 25~30g/日 → 日目标份数上界；盐不追踪份数，
/// 用菜品 high_sodium 标签做代理（清淡模式下硬排除）。
class OilSaltLimits {
  const OilSaltLimits({
    required this.oilDailyServingsMax,
    required this.saltDailyGramsMax,
    required this.saltTracking,
  });

  final double oilDailyServingsMax;
  final double saltDailyGramsMax;

  /// 固定为 high_sodium_tag_proxy。
  final String saltTracking;

  factory OilSaltLimits.fromJson(Map<String, dynamic> json) =>
      OilSaltLimits(
        oilDailyServingsMax: (json['oil_daily_servings_max'] as num).toDouble(),
        saltDailyGramsMax: (json['salt_daily_grams_max'] as num).toDouble(),
        saltTracking: json['salt_tracking'] as String? ?? '',
      );
}
