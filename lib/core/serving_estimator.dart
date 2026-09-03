import '../data/food_database.dart';
import 'dish_matcher.dart';
import 'models/dietary_guidelines.dart';
import 'models/portions.dart';

/// 份量估算器：菜名 + 重量 → 份数，以及反向换算。
///
/// 两级换算策略：
/// 1. 食物交换份精确换算：米饭、馒头、豆腐、酸奶等单食物直接查
///    膳食指南的 food_exchange 表（如 150g 熟米饭 = 1 份谷薯）；
/// 2. 菜品整体估算：匹配不到交换表时，走 DishMatcher 找到菜品，
///    用各分类份数 × 该分类每份克重，累加出「一份菜约多少克」。
///
/// 数据全部来自膳食指南 JSON，不做营养素级别的精确计算。
class ServingEstimator {
  ServingEstimator(this._dishMatcher, this._guidelines);

  final DishMatcher _dishMatcher;
  final DietaryGuidelines _guidelines;

  /// 食物交换表中英文键 → 常用中文名。JSON 里键是英文（cooked_rice 等），
  /// 用户输入是中文，这里做一层固定映射。
  static const _exchangeFoodAliases = <String, String>{
    '米饭': 'cooked_rice',
    '白米饭': 'cooked_rice',
    '熟米饭': 'cooked_rice',
    '大米': 'rice_50g_raw',
    '生米': 'rice_50g_raw',
    '面条': 'noodles_raw',
    '挂面': 'noodles_raw',
    '馒头': 'steamed_bun',
    '红薯': 'sweet_potato',
    '地瓜': 'sweet_potato',
    '玉米': 'corn',
    '嫩豆腐': 'soft_tofu',
    '南豆腐': 'soft_tofu',
    '豆腐': 'firm_tofu',
    '老豆腐': 'firm_tofu',
    '北豆腐': 'firm_tofu',
    '豆腐丝': 'tofu_silk',
    '千张': 'tofu_silk',
    '豆浆': 'soy_milk',
    '内酯豆腐': 'silken_tofu',
    '豆腐干': 'dried_tofu',
    '豆干': 'dried_tofu',
    '酸奶': 'yogurt',
    '奶酪': 'cheese',
    '芝士': 'cheese',
    '奶粉': 'milk_powder',
    '牛奶': 'milk_100ml',
    '纯牛奶': 'milk_100ml',
  };

  /// 重量 → 份数。匹配不到任何依据时返回 null，不瞎猜。
  ///
  /// [dishName] 支持交换表食物名（米饭/豆腐/酸奶…）或任意菜品名；
  /// [grams] 必须大于 0。
  ServingEstimate? estimateServings(String dishName, double grams) {
    if (grams <= 0) {
      throw ArgumentError.value(grams, 'grams', 'must be positive');
    }
    final gramsPerServing = _gramsPerServing(dishName);
    if (gramsPerServing == null) {
      return null;
    }
    return ServingEstimate(
      inputName: dishName,
      grams: grams,
      servings: grams / gramsPerServing.gramsPerServing,
      basis: gramsPerServing.basis,
      matchedDishId: gramsPerServing.matchedDishId,
      categoryKey: gramsPerServing.categoryKey,
      gramsPerDishServing: gramsPerServing.gramsPerServing,
    );
  }

  /// 份数 → 重量（反向换算）。匹配不到任何依据时返回 null。
  double? estimateGrams(String dishName, double servings) {
    if (servings <= 0) {
      throw ArgumentError.value(servings, 'servings', 'must be positive');
    }
    final gramsPerServing = _gramsPerServing(dishName);
    if (gramsPerServing == null) {
      return null;
    }
    return servings * gramsPerServing.gramsPerServing;
  }

  _GramsPerServing? _gramsPerServing(String dishName) {
    final normalized = FoodDatabase.normalizeDishName(dishName);
    if (normalized.isEmpty) {
      return null;
    }

    // 1. 食物交换份：精确查中文名映射。
    final exchangeResult = _lookupExchange(normalized);
    if (exchangeResult != null) {
      return exchangeResult;
    }

    // 2. 菜品匹配：按菜品各分类份数累加重量。
    final match = _dishMatcher.match([dishName]).single;
    if (!match.isMatched) {
      return null;
    }
    final dishGrams = _estimateDishGrams(match.portionsNormal);
    if (dishGrams <= 0) {
      return null;
    }
    return _GramsPerServing(
      gramsPerServing: dishGrams,
      basis: EstimateBasis.dishMatch,
      matchedDishId: match.matchedDishId,
      categoryKey: _dominantCategory(match.portionsNormal),
    );
  }

  _GramsPerServing? _lookupExchange(String normalizedInput) {
    final foodKey = _exchangeFoodAliases[normalizedInput];
    if (foodKey == null) {
      return null;
    }
    // 先查交换表里的可交换食物（cooked_rice 等），再查基准食物本身
    // （rice_50g_raw、milk_100ml）。
    final entry =
        _guidelines.findExchangeEntry(foodKey) ??
        _guidelines.findExchangeBase(foodKey);
    if (entry == null) {
      return null;
    }
    return _GramsPerServing(
      gramsPerServing: entry.gramsPerServing,
      basis: EstimateBasis.foodExchange,
      matchedDishId: null,
      categoryKey: entry.groupId,
    );
  }

  /// 一份菜的总克重 ≈ Σ(各分类份数 × 该分类每份克重)。
  /// 油脂在 serving_reference 里没有单独条目，用 2000kcal 档的
  /// 推荐量折算（25g ÷ 2.5 份 = 10g/份）。
  double _estimateDishGrams(Portions portions) {
    var total = 0.0;
    for (final entry in portions.byCategory.entries) {
      final servings = entry.value;
      if (servings <= 0) {
        continue;
      }
      final categoryKey = _appCategoryToGuideline(entry.key);
      final gramsPerServing =
          _guidelines.gramsPerServingFor(categoryKey) ?? _oilGramsPerServing;
      total += servings * gramsPerServing;
    }
    return total;
  }

  /// 主导分类按「克重贡献最大」选取（份数 × 每份克重），而不是份数本身，
  /// 否则油脂份数偏大的菜（如黄焖鸡米饭）会被误判成「油」。
  String _dominantCategory(Portions portions) {
    var best = '';
    var bestGrams = -1.0;
    for (final entry in portions.byCategory.entries) {
      if (entry.value <= 0) {
        continue;
      }
      final categoryKey = _appCategoryToGuideline(entry.key);
      final gramsPerServing =
          _guidelines.gramsPerServingFor(categoryKey) ?? _oilGramsPerServing;
      final grams = entry.value * gramsPerServing;
      if (grams > bestGrams) {
        bestGrams = grams;
        best = entry.key;
      }
    }
    return _appCategoryToGuideline(best);
  }

  /// APP 内部分类 id（grains/vegetables/…）→ 膳食指南分类 id。
  static String _appCategoryToGuideline(String appCategory) =>
      switch (appCategory) {
        'grains' => 'grain_tuber',
        'vegetables' => 'vegetable',
        'fruits' => 'fruit',
        'protein' => 'protein_meat_egg',
        'protein_soy' => 'soy',
        'oil' => 'oil',
        _ => appCategory,
      };

  static const _oilFallbackEnergyLevel = 1800;

  double get _oilGramsPerServing {
    final recommendation =
        _guidelines.recommendationsByEnergyLevel['$_oilFallbackEnergyLevel']
            ?.intakeRanges['oil'];
    if (recommendation == null ||
        recommendation.min == null ||
        recommendation.servings == null ||
        recommendation.servings! <= 0) {
      return 10;
    }
    return recommendation.min! / recommendation.servings!;
  }
}

/// 份量换算依据。
enum EstimateBasis {
  /// 食物交换份精确换算（如 150g 熟米饭 = 1 份谷薯）。
  foodExchange,

  /// 按匹配菜品各分类份数累加估算。
  dishMatch,
}

/// 一次换算依据：每 gramsPerServing 克算 1 份。
class _GramsPerServing {
  const _GramsPerServing({
    required this.gramsPerServing,
    required this.basis,
    required this.matchedDishId,
    required this.categoryKey,
  });

  final double gramsPerServing;
  final EstimateBasis basis;
  final String? matchedDishId;
  final String categoryKey;
}

/// 份量估算结果。
class ServingEstimate {
  const ServingEstimate({
    required this.inputName,
    required this.grams,
    required this.servings,
    required this.basis,
    required this.matchedDishId,
    required this.categoryKey,
    required this.gramsPerDishServing,
  });

  final String inputName;
  final double grams;

  /// 换算出的份数。
  final double servings;

  /// 换算依据：食物交换份精确换算，或按匹配菜品各分类份数估算。
  final EstimateBasis basis;
  final String? matchedDishId;

  /// 使用的膳食指南分类 id（grain_tuber、soy_products…）。
  final String categoryKey;

  /// 每 1 份对应的克重。
  final double gramsPerDishServing;
}
