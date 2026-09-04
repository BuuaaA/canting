import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:canting/core_engine.dart';
import 'package:canting/data/custom_dish_repository.dart';
import 'package:canting/data/meal_repository.dart';
import 'package:canting/data/pet_repository.dart';
import 'package:canting/data/user_repository.dart';
import 'package:canting/native/ios_native_bridge.dart';
import 'package:canting/pet.dart';
import 'package:canting/platform/android_native_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RecognitionDraft {
  const RecognitionDraft({
    required this.imageUri,
    this.merchant = '',
    this.dishes = const [],
    this.isLoading = true,
    this.error,
  });

  final String imageUri;
  final String merchant;
  final List<MealDish> dishes;
  final bool isLoading;
  final String? error;

  RecognitionDraft copyWith({
    String? merchant,
    List<MealDish>? dishes,
    bool? isLoading,
    String? error,
  }) => RecognitionDraft(
    imageUri: imageUri,
    merchant: merchant ?? this.merchant,
    dishes: dishes ?? this.dishes,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}

class AppState extends ChangeNotifier {
  AppState({
    PetEngine? petEngine,
    AndroidNativeBridge? androidNativeBridge,
    DatabaseHelper? databaseHelper,
    this.guidelines,
  }) : _petEngine = petEngine ?? PetEngine(),
       _androidNativeBridge = androidNativeBridge ?? AndroidNativeBridge(),
       _databaseHelper = databaseHelper ?? DatabaseHelper.instance {
    _pet = _petEngine.createPet(petType: 'cat', petName: '小挑食');
    _dialogue = _dailyDialogue();
    _selectedDate = DateTime.now();
    _scheduleWidgetSync();
  }

  static const _dailyIntakeFallback = DailyIntake(
    grains: 5,
    vegetables: 4,
    fruits: 2.5,
    protein: 4,
    proteinSoy: 1,
    oil: 2.5,
    bmr: 1450,
    tdee: 1740,
  );

  final PetEngine _petEngine;
  final AndroidNativeBridge _androidNativeBridge;
  final DatabaseHelper _databaseHelper;

  /// 膳食指南数据，main() 启动时从 JSON 加载；测试可为 null。
  DietaryGuidelines? guidelines;

  late final UserRepository _userRepo = UserRepository(
    database: () => _databaseHelper.database,
  );
  late final MealRepository _mealRepo = MealRepository(
    database: () => _databaseHelper.database,
  );
  late final PetRepository _petRepo = PetRepository(
    database: () => _databaseHelper.database,
  );
  late final CustomDishRepository _customDishRepo = CustomDishRepository(
    database: () => _databaseHelper.database,
  );

  /// 菜品匹配引擎：标准菜库 + 用户自定义菜品（自定义优先）。
  /// 在 loadFromDatabase 中装配；未加载或缺少膳食指南数据时为 null。
  DishMatcher? _dishMatcher;
  ServingEstimator? _servingEstimator;

  /// 标准菜库快照，供推荐引擎等需要全量菜谱的模块使用。
  FoodDatabase? _foodDatabase;

  DishMatcher? get dishMatcher => _dishMatcher;
  ServingEstimator? get servingEstimator => _servingEstimator;

  late PetData _pet;
  late String _dialogue;
  late DateTime _selectedDate;
  RecognitionDraft? _recognitionDraft;
  Future<void> _widgetSync = Future.value();
  GrowthStage? _pendingEvolutionFrom;

  /// Meals grouped by day key ("y-M-d"). A missing key means "not loaded
  /// from the database yet"; an empty list means "loaded, no records".
  final Map<String, List<MealRecord>> _mealsByDay = {};

  UserProfile? profile;
  bool petAreaCollapsed = false;
  bool mealReminder = false;
  bool gapReminder = false;

  static const completion = CompletionResult(
    overall: 0.65,
    byCategory: {
      'grains': 0.68,
      'vegetables': 0.42,
      'fruits': 0.28,
      'protein': 0.82,
      'protein_soy': 0.55,
      'oil': 0.92,
    },
    biggestGap: 'fruits',
    sodiumLevel: 'mid',
  );

  PetData get pet => _pet;
  String get petDialogue => _dialogue;
  DateTime get selectedDate => _selectedDate;
  RecognitionDraft? get recognitionDraft => _recognitionDraft;
  GrowthStage? get pendingEvolutionFrom => _pendingEvolutionFrom;

  bool get onboardingComplete => profile?.onboardingCompleted ?? false;

  DailyIntake get dailyIntake => profile?.dailyIntake ?? _dailyIntakeFallback;

  /// Loads profile, pet, and today's meals from the database. Called once
  /// from main() before runApp.
  Future<void> loadFromDatabase() async {
    profile = await _userRepo.getProfile();
    final persistedPet = await _petRepo.getPet();
    if (persistedPet != null) {
      _pet = persistedPet;
      _applyOfflineDecay();
      _dialogue = _petEngine.getStatusDialogue(
        petType: _pet.petType,
        state: _pet.vitalityState,
      );
      // 模块 7：启动时按最近 3 天饮食质量刷新活力值。
      await refreshPetVitality();
    }
    await _refreshDishMatcher();
    if (onboardingComplete) {
      await _ensureMealsLoaded(DateTime.now());
    }
    if (persistedPet != null) {
      // 模块 7：首页气泡默认台词改用当日场景（缺口/时段）随机文案。
      _dialogue = _dailyDialogue();
    }
    _scheduleWidgetSync();
    notifyListeners();
  }

  /// 模块 7：按最近 3 天（有记录的天）饮食质量重算活力值。
  ///
  /// 只取最近 3 天里有记录的日子求平均；一天都没有时不改动（离线衰减
  /// 已在 [_applyOfflineDecay] 处理）。成长值只增不减，不受影响。
  Future<void> refreshPetVitality({DateTime? now}) async {
    final target = profile?.dailyIntake;
    if (target == null || !_databaseHelper.isOpen) {
      return;
    }
    final reference = now ?? DateTime.now();
    final todayStart = DateTime(reference.year, reference.month, reference.day);
    final start = todayStart.subtract(const Duration(days: 2));
    try {
      final meals = await _mealRepo.getMealsByDateRange(
        start,
        todayStart.add(const Duration(days: 1)),
      );
      final mealsByDay = <DateTime, List<MealRecord>>{};
      for (final meal in meals) {
        final timestamp = meal.timestamp;
        final day = DateTime(
          timestamp.year,
          timestamp.month,
          timestamp.day,
        );
        mealsByDay.putIfAbsent(day, () => []).add(meal);
      }
      if (mealsByDay.isEmpty) {
        return;
      }
      final scores = mealsByDay.values
          .map(
            (dayMeals) => VitalityCalculator.scoreDay(
              eaten: dayMeals.fold(
                Portions.zero,
                (total, meal) => total + meal.portionsTotal,
              ),
              target: target,
              mealCount: dayMeals.length,
            ),
          )
          .toList(growable: false);
      final vitality = VitalityCalculator.vitalityFromDailyScores(scores);
      if (vitality == null || vitality == _pet.vitality) {
        return;
      }
      _pet = _pet.copyWith(
        vitality: vitality,
        lastVitalityUpdate: reference,
      );
      await _petRepo.savePet(_pet);
      _scheduleWidgetSync();
      notifyListeners();
    } catch (error) {
      debugPrint('Unable to refresh pet vitality: $error');
    }
  }

  /// 重新装配 DishMatcher 和 ServingEstimator（标准菜库 + 最新自定义菜品）。
  /// 用户新增/删除自定义菜品后应调用。
  Future<void> refreshDishMatcher() => _refreshDishMatcher();

  Future<void> _refreshDishMatcher() async {
    final guidelines = this.guidelines;
    if (guidelines == null || !_databaseHelper.isOpen) {
      return;
    }
    try {
      final foodDatabase = await _databaseHelper.loadFoodDatabase();
      final customDishes = await _customDishRepo.getAllDishes();
      _dishMatcher = DishMatcher(foodDatabase, customDishes: customDishes);
      _servingEstimator = ServingEstimator(_dishMatcher!, guidelines);
      _foodDatabase = foodDatabase;
    } catch (error) {
      // 匹配引擎装配失败不影响主流程；记录后保持 null。
      debugPrint('Failed to assemble DishMatcher: $error');
    }
  }

  void _applyOfflineDecay() {
    final result = _petEngine.checkOfflineDecay(
      pet: _pet,
      now: DateTime.now(),
    );
    if (result.wasApplied || result.vitalityChange != 0) {
      _pet = result.pet;
      unawaited(_persistPet());
    }
  }

  MealRecord? mealById(String id) {
    for (final meals in _mealsByDay.values) {
      for (final meal in meals) {
        if (meal.mealId == id) return meal;
      }
    }
    return null;
  }

  List<MealRecord> mealsFor(DateTime date) {
    final key = _dayKey(date);
    if (!_mealsByDay.containsKey(key)) {
      unawaited(_ensureMealsLoaded(date));
      return const [];
    }
    final meals = [..._mealsByDay[key]!]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return meals;
  }

  Future<void> _ensureMealsLoaded(DateTime date) async {
    if (!_databaseHelper.isOpen) return;
    final key = _dayKey(date);
    if (_mealsByDay.containsKey(key)) return;
    try {
      final meals = await _mealRepo.getMealsByDate(date);
      // A save may have landed while loading; keep the newer cache.
      if (!_mealsByDay.containsKey(key)) {
        _mealsByDay[key] = meals;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Unable to load meals for $key: $error');
    }
  }

  static String _dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  /// 模块 9：按区间只读查询餐食记录（[start, end)），供历史页
  /// 日历 / 周统计一次取整月数据使用，不写入本地缓存。
  Future<List<MealRecord>> queryMealsInRange(DateTime start, DateTime end) {
    return _mealRepo.getMealsByDateRange(start, end);
  }

  /// 当日真实完成度：已记录份数 ÷ 每日目标（IntakeCalculator 结果）。
  /// 没有记录时各分类均为 0，整体完成度也为 0。
  CompletionResult completionFor(DateTime date) {
    final eaten = mealsFor(date).fold(
      Portions.zero,
      (total, meal) => total + meal.portionsTotal,
    );
    return CompletionCalculator().calculate(
      eatenPortions: eaten,
      dailyIntake: dailyIntake,
    );
  }

  /// 构建可落库的餐食记录：
  /// - 对没有份数的菜，用 DishMatcher 匹配菜品并应用分量系数
  ///   （小份 0.8 / 常规 1.0 / 大份 1.3）；
  /// - 已带份数的菜（如详细模式手填）保持用户输入；
  /// - 用当日真实结构计算这餐的完成度，供宠物活力值使用。
  MealRecord buildMealRecord({
    required String mealType,
    required DateTime timestamp,
    required List<MealDish> dishes,
    String? merchant,
    String? mealId,
  }) {
    final matcher = _dishMatcher;
    final resolvedDishes = dishes
        .where((dish) => dish.name.trim().isNotEmpty)
        .map((dish) {
          final hasPortions = dish.portions.byCategory.values.any(
            (value) => value != 0,
          );
          if (matcher == null || hasPortions) {
            return dish;
          }
          final match = matcher.match([dish.name.trim()]).single;
          return MealDish(
            name: dish.name,
            quantity: dish.quantity,
            portionSize: dish.portionSize,
            matchedDishId: match.matchedDishId,
            matchConfidence: match.confidence,
            portions: matcher.calculatePortions(match, dish.portionSize),
          );
        })
        .toList(growable: false);
    final meal = MealRecord(
      mealId:
          mealId ?? 'meal-${DateTime.now().microsecondsSinceEpoch}',
      mealType: mealType,
      timestamp: timestamp,
      merchant: merchant,
      dishes: resolvedDishes,
    );
    final dayEaten = mealsFor(timestamp).fold(
      Portions.zero,
      (total, item) => total + item.portionsTotal,
    );
    return MealRecord(
      mealId: meal.mealId,
      mealType: meal.mealType,
      timestamp: meal.timestamp,
      merchant: meal.merchant,
      dishes: meal.dishes,
      completionRate: CompletionCalculator()
          .calculate(
            eatenPortions: dayEaten + meal.portionsTotal,
            dailyIntake: dailyIntake,
          )
          .overall,
    );
  }

  /// 下一餐推荐：基于当日已记录餐食与目标缺口。
  ///
  /// [excludeDishNames] 供「换一批」使用：把已展示过的菜从结果里去掉，
  /// 再从缺口最大的分类候选菜中补足到 3 道。
  Recommendation? recommendationFor(
    DateTime date, {
    Set<String> excludeDishNames = const {},
  }) {
    final foodDatabase = _foodDatabase;
    if (foodDatabase == null) {
      return null;
    }
    final meals = mealsFor(date);
    final lastMealType = meals.isEmpty
        ? ''
        : meals
              .reduce(
                (latest, meal) =>
                    meal.timestamp.isAfter(latest.timestamp) ? meal : latest,
              )
              .mealType;
    // 归整到分钟：同一分钟内的多次调用（如「换一批」）得到相同的
    // suggestedTime，展示层本来就只显示到分钟。
    final rawNow = DateTime.now();
    final now = DateTime(rawNow.year, rawNow.month, rawNow.day, rawNow.hour,
        rawNow.minute);
    final base = RecommendationEngine(foodDatabase).recommend(
      todayMeals: meals,
      dailyIntake: dailyIntake,
      now: now,
      lastMealType: lastMealType,
    );
    if (excludeDishNames.isEmpty) {
      return base;
    }

    final suggestions = [
      ...base.primary,
      ...base.alternatives,
    ].where((item) => !excludeDishNames.contains(item.dishName)).toList();

    // 与引擎同口径的缺口排序：缺口比例大者优先补位。
    final eaten = meals.fold(Portions.zero, (total, meal) => total + meal.portionsTotal);
    final target = dailyIntake.portions;
    final rankedGroups = [
      for (final group in const [
        'grains',
        'vegetables',
        'fruits',
        'protein',
        'protein_soy',
      ])
        (
          group,
          target.valueFor(group) <= 0
              ? 0.0
              : (target.valueFor(group) - eaten.valueFor(group)) /
                    target.valueFor(group),
        ),
    ]..sort((left, right) => right.$2.compareTo(left.$2));

    final usedNames = suggestions.map((item) => item.dishName).toSet();
    for (final (group, _) in rankedGroups) {
      if (suggestions.length >= 3) {
        break;
      }
      final candidates = foodDatabase.dishesForNutrient(group).toList()
        ..sort(
          (left, right) => right.correctedPortions
              .valueFor(group)
              .compareTo(left.correctedPortions.valueFor(group)),
        );
      for (final dish in candidates) {
        if (suggestions.length >= 3) {
          break;
        }
        if (usedNames.contains(dish.name) ||
            excludeDishNames.contains(dish.name)) {
          continue;
        }
        usedNames.add(dish.name);
        final category = foodDatabase.categoryForDish(dish)!;
        suggestions.add(
          DishSuggestion(
            dishName: dish.name,
            searchKeyword: dish.searchKeywords.firstOrNull ?? dish.name,
            primaryCategory: group,
            oilLevel: category.oilLevel,
          ),
        );
      }
    }

    return Recommendation(
      suggestedTime: base.suggestedTime,
      suggestedMealType: base.suggestedMealType,
      primary: suggestions.take(1).toList(growable: false),
      alternatives: suggestions.skip(1).toList(growable: false),
      reason: base.reason,
    );
  }

  /// 手动添加搜索：自定义菜在前（按使用次数降序），标准菜在后；
  /// 与自定义菜同名的标准菜去重（自定义副本内容相同，优先展示自定义）。
  Future<List<StandardDish>> searchDishesForManualAdd(String query) async {
    if (!_databaseHelper.isOpen) {
      return const [];
    }
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    final usage = await _customDishRepo.usageCountsByName();
    final custom = await _customDishRepo.searchDishes(trimmed);
    final standard = await _databaseHelper.searchDishes(trimmed);

    int usageOf(StandardDish dish) =>
        usage[FoodDatabase.normalizeDishName(dish.name)] ?? 0;
    final sortedCustom = [...custom]
      ..sort((left, right) {
        final usageOrder = usageOf(right).compareTo(usageOf(left));
        if (usageOrder != 0) {
          return usageOrder;
        }
        return left.name.compareTo(right.name);
      });

    final seenNames = sortedCustom
        .map((dish) => FoodDatabase.normalizeDishName(dish.name))
        .toSet();
    return [
      ...sortedCustom,
      ...standard.where(
        (dish) => !seenNames.contains(FoodDatabase.normalizeDishName(dish.name)),
      ),
    ];
  }

  /// 某道菜的使用数据（使用次数 + 分量偏好）；没有记录返回 null。
  Future<CustomDishUsage?> manualDishUsage(String dishName) =>
      _customDishRepo.getUsageByName(dishName);

  /// 菜品分类列表（手动添加详细模式的分类选择用）。
  List<FoodCategory> get dishCategories =>
      _foodDatabase?.categories ?? const [];

  /// 登记手动添加的菜（模块 15 数据飞轮）：
  /// - 新菜名写入 user_custom_dishes，已有菜累计使用次数；
  /// - 记住用户这次用的分量（preferred_portion），下次默认带出；
  /// - 标准库命中的菜复制一份同内容副本进自定义表（用于计数与偏好，
  ///   不改变匹配结果）；全新菜名需要详细模式提供分类与克重。
  Future<void> registerManualDish({
    required String name,
    required String portionSize,
    Portions? manualPortions,
    String? category,
    bool homemade = false,
  }) async {
    if (!_databaseHelper.isOpen) {
      return;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final existing = await _customDishRepo.getUsageByName(trimmed);
    final nextCount = (existing?.usageCount ?? 0) + 1;

    StandardDish? dish;
    if (existing != null) {
      dish = existing.dish;
    } else {
      dish = await _baseDishForManual(trimmed);
      dish ??= _newCustomDish(
        name: trimmed,
        portions: manualPortions,
        category: category,
        homemade: homemade,
      );
    }
    if (dish == null) {
      // 没有匹配、也没有分类+克重依据的菜名：V1.0 不登记（不瞎猜份数）。
      return;
    }
    await _customDishRepo.upsertDishWithMeta(
      dish,
      usageCount: nextCount,
      preferredPortion: portionSize,
    );
    await refreshDishMatcher();
  }

  /// 标准库/自定义表中与菜名匹配的菜品，复制成「用户名字」的自定义
  /// 副本（用于计数与偏好；别名清空，避免遮蔽标准菜本名的匹配）。
  Future<StandardDish?> _baseDishForManual(String name) async {
    final matcher = _dishMatcher;
    if (matcher == null) {
      return null;
    }
    final match = matcher.match([name]).single;
    final id = match.matchedDishId;
    if (id == null) {
      return null;
    }
    final base = _foodDatabase?.dishes
            .where((dish) => dish.id == id)
            .firstOrNull ??
        await _customDishRepo.getDishById(id);
    if (base == null) {
      return null;
    }
    return StandardDish(
      id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      aliases: const [],
      category: base.category,
      portionsNormal: base.portionsNormal,
      cookingOilRatio: base.cookingOilRatio,
      oilFactor: base.oilFactor,
      sodiumLevel: base.sodiumLevel,
      searchKeywords: [name],
      tags: base.tags,
    );
  }

  StandardDish? _newCustomDish({
    required String name,
    required Portions? portions,
    required String? category,
    required bool homemade,
  }) {
    if (portions == null || category == null) {
      return null;
    }
    return StandardDish(
      id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      aliases: const [],
      category: category,
      portionsNormal: portions,
      cookingOilRatio: 0,
      oilFactor: 1,
      sodiumLevel: 'mid',
      searchKeywords: [name],
      tags: homemade ? const ['homemade'] : const [],
    );
  }

  /// 详细模式：克重 → 份数与份数结构。关联失败返回 null。
  ///
  /// 三级依据：食物交换份精确换算（米饭/豆腐等单一食物）→ 匹配菜品的
  /// 正常份结构按份数缩放 → 按菜品分类平均结构兜底（新菜，需选分类）。
  ManualServingLink? resolveManualServings(
    String dishName, {
    required double grams,
    String? categoryId,
  }) {
    if (grams <= 0) {
      return null;
    }
    final estimator = _servingEstimator;
    final matcher = _dishMatcher;
    if (estimator != null) {
      final estimate = estimator.estimateServings(dishName, grams);
      if (estimate != null) {
        if (estimate.basis == EstimateBasis.foodExchange) {
          final appCategory = _guidelineCategoryToApp(estimate.categoryKey);
          if (appCategory != null) {
            return ManualServingLink(
              servings: estimate.servings,
              portions: Portions(
                grains: appCategory == 'grains' ? estimate.servings : 0,
                vegetables: appCategory == 'vegetables' ? estimate.servings : 0,
                fruits: appCategory == 'fruits' ? estimate.servings : 0,
                protein: appCategory == 'protein' ? estimate.servings : 0,
                proteinSoy: appCategory == 'protein_soy' ? estimate.servings : 0,
                oil: appCategory == 'oil' ? estimate.servings : 0,
              ),
            );
          }
          // 奶/坚果等不进六类目标的交换食物（与 IntakeCalculator 口径
          // 一致）落到下方分类兜底。
        } else if (matcher != null) {
          final match = matcher.match([dishName.trim()]).single;
          if (match.isMatched) {
            return ManualServingLink(
              servings: estimate.servings,
              portions: match.portionsNormal.scale(estimate.servings),
              matchedDishId: match.matchedDishId,
              categoryId: match.category,
            );
          }
        }
      }
    }
    return _categoryFallbackLink(dishName, grams: grams, categoryId: categoryId);
  }

  /// 详细模式：份数 → 克重（与 [resolveManualServings] 同源反向）。
  double? resolveManualGrams(
    String dishName, {
    required double servings,
    String? categoryId,
  }) {
    if (servings <= 0) {
      return null;
    }
    final estimator = _servingEstimator;
    if (estimator != null) {
      final unitGrams = estimator.estimateGrams(dishName, 1);
      if (unitGrams != null) {
        return unitGrams * servings;
      }
    }
    final normalGrams = _gramsPerDishServingForCategory(categoryId);
    if (normalGrams != null && normalGrams > 0) {
      return normalGrams * servings;
    }
    return null;
  }

  /// 分类兜底：按分类平均结构估算「一份该类菜约多少克」，再按克重缩放。
  ManualServingLink? _categoryFallbackLink(
    String dishName, {
    required double grams,
    required String? categoryId,
  }) {
    final normalGrams = _gramsPerDishServingForCategory(categoryId);
    final foodDatabase = _foodDatabase;
    if (normalGrams == null ||
        normalGrams <= 0 ||
        foodDatabase == null ||
        categoryId == null) {
      return null;
    }
    final category = foodDatabase.categories
        .where((item) => item.id == categoryId)
        .firstOrNull;
    if (category == null) {
      return null;
    }
    final servings = grams / normalGrams;
    return ManualServingLink(
      servings: servings,
      portions: category.averagePortions.scale(servings),
      categoryId: category.id,
    );
  }

  /// 一份该分类的标准菜约多少克（Σ 分类份数 × 每份克重，与
  /// ServingEstimator 同口径；油脂无交换条目按 10g/份）。
  double? _gramsPerDishServingForCategory(String? categoryId) {
    final guidelines = this.guidelines;
    final foodDatabase = _foodDatabase;
    if (categoryId == null || guidelines == null || foodDatabase == null) {
      return null;
    }
    final category = foodDatabase.categories
        .where((item) => item.id == categoryId)
        .firstOrNull;
    if (category == null) {
      return null;
    }
    var total = 0.0;
    for (final entry in category.averagePortions.byCategory.entries) {
      if (entry.value <= 0) {
        continue;
      }
      final gramsPerServing =
          guidelines.gramsPerServingFor(
            _appCategoryToGuideline(entry.key),
          ) ??
          10;
      total += entry.value * gramsPerServing;
    }
    return total <= 0 ? null : total;
  }

  /// APP 内部分类 id → 膳食指南分类 id（与 ServingEstimator 同映射）。
  static String _appCategoryToGuideline(String appCategory) => switch (
      appCategory) {
    'grains' => 'grain_tuber',
    'vegetables' => 'vegetable',
    'fruits' => 'fruit',
    'protein' => 'protein_meat_egg',
    'protein_soy' => 'soy',
    'oil' => 'oil',
    _ => appCategory,
  };

  /// 膳食指南分类 id → APP 内部分类 id；奶/坚果等无归属的分类返回 null
  /// （与 IntakeCalculator「不进目标」口径一致）。
  static String? _guidelineCategoryToApp(String guidelineCategory) =>
      switch (guidelineCategory) {
        'grain_tuber' => 'grains',
        'vegetable' => 'vegetables',
        'fruit' => 'fruits',
        'protein_meat_egg' => 'protein',
        'soy' => 'protein_soy',
        'oil' => 'oil',
        _ => null,
      };

  Future<void> completeOnboarding({
    required UserProfile profile,
    required String petType,
    required String petName,
  }) async {
    final now = DateTime.now();
    _pet = _petEngine.createPet(petType: petType, petName: petName.trim());
    _dialogue = _dailyDialogue();
    this.profile = profile.copyWith(createdAt: now, updatedAt: now);
    await _userRepo.saveProfile(this.profile!);
    await _petRepo.savePet(_pet);
    _scheduleWidgetSync();
    notifyListeners();
  }

  void togglePetArea() {
    petAreaCollapsed = !petAreaCollapsed;
    notifyListeners();
  }

  bool tapPet() {
    final result = _petEngine.onPetTap(pet: _pet, now: DateTime.now());
    if (!result.wasApplied) {
      _dialogue = '休息一下再摸摸';
      notifyListeners();
      return false;
    }
    _pet = result.pet;
    _dialogue = '嘿嘿～';
    _pendingEvolutionFrom = result.previousGrowthStage;
    unawaited(_persistPet());
    _scheduleWidgetSync();
    notifyListeners();
    return true;
  }

  void restorePetDialogue() {
    _dialogue = _dailyDialogue();
    notifyListeners();
  }

  /// 模块 7：按当日达标情况 / 缺口 / 时段生成首页气泡默认台词。
  String _dailyDialogue() {
    final now = DateTime.now();
    return PetDailyDialogue(
      dialogues: _petEngine.dialogues,
    ).pickDaily(
      petType: _pet.petType,
      completionByCategory: completionFor(now).byCategory,
      mealCount: mealsFor(now).length,
      hour: now.hour,
    );
  }

  void renamePet(String name) {
    final normalized = name.trim();
    if (normalized.runes.isEmpty || normalized.runes.length > 6) return;
    _pet = _pet.copyWith(petName: normalized);
    unawaited(_persistPet());
    _scheduleWidgetSync();
    notifyListeners();
  }

  Future<void> _persistPet() async {
    try {
      await _petRepo.savePet(_pet);
    } catch (error) {
      debugPrint('Unable to persist pet state: $error');
    }
  }

  void selectDate(DateTime date) {
    _selectedDate = DateTime(date.year, date.month, date.day);
    if (onboardingComplete) {
      unawaited(_ensureMealsLoaded(_selectedDate));
    }
    notifyListeners();
  }

  int? vitalityForDate(DateTime date) {
    final now = DateTime.now();
    if (date.isAfter(DateTime(now.year, now.month, now.day))) return null;
    if (date.day % 6 == 0) return null;
    const values = [88, 74, 61, 46, 32, 20];
    return values[(date.day + date.month) % values.length];
  }

  double completionForDate(DateTime date) {
    final vitality = vitalityForDate(date);
    if (vitality == null) return 0;
    return math.min(0.98, math.max(0.28, vitality / 100 + 0.05));
  }

  void setMealReminder(bool value) {
    mealReminder = value;
    notifyListeners();
  }

  void setGapReminder(bool value) {
    gapReminder = value;
    notifyListeners();
  }

  void startSharedRecognition(String imageUri) {
    _recognitionDraft = RecognitionDraft(imageUri: imageUri);
    notifyListeners();
  }

  void completeSharedRecognition({
    required String imageUri,
    required String merchant,
    required List<MealDish> dishes,
  }) {
    if (_recognitionDraft?.imageUri != imageUri) return;
    _recognitionDraft = RecognitionDraft(
      imageUri: imageUri,
      merchant: merchant,
      dishes: List.unmodifiable(dishes),
      isLoading: false,
    );
    notifyListeners();
  }

  void failSharedRecognition({
    required String imageUri,
    required String message,
  }) {
    if (_recognitionDraft?.imageUri != imageUri) return;
    _recognitionDraft = RecognitionDraft(
      imageUri: imageUri,
      isLoading: false,
      error: message,
    );
    notifyListeners();
  }

  void clearSharedRecognition() {
    _recognitionDraft = null;
  }

  void clearPendingEvolution() {
    _pendingEvolutionFrom = null;
    notifyListeners();
  }

  Future<void> saveMeal(MealRecord meal, {String? note, String? source}) async {
    final key = _dayKey(meal.timestamp);
    final dayMeals = [...(_mealsByDay[key] ?? const <MealRecord>[])];
    final index = dayMeals.indexWhere((item) => item.mealId == meal.mealId);
    final isNew = index == -1;

    if (isNew) {
      // 当日真实膳食结构（含本餐），供宠物引擎评估这餐的质量。
      final dayEaten = dayMeals.fold(
        Portions.zero,
        (total, item) => total + item.portionsTotal,
      );
      final dayCompletion = CompletionCalculator().calculate(
        eatenPortions: dayEaten + meal.portionsTotal,
        dailyIntake: dailyIntake,
      );
      final result = _petEngine.onMealRecorded(
        pet: _pet,
        completionRate: meal.completionRate,
        completionByCategory: dayCompletion.byCategory,
        mealId: meal.mealId,
      );
      _pet = result.pet;
      _dialogue = result.dialogue;
      _pendingEvolutionFrom = result.previousGrowthStage;
    } else {
      dayMeals[index] = meal;
      _dialogue = '这顿修改好啦';
    }

    if (isNew) {
      await _mealRepo.addMeal(meal, note: note, source: source);
    } else {
      await _mealRepo.updateMeal(meal, note: note);
    }
    if (isNew) {
      await _petRepo.savePet(_pet);
    }

    _mealsByDay[key] = isNew ? [meal, ...dayMeals] : dayMeals;
    _scheduleWidgetSync();
    _scheduleMealRecordSync(meal);
    notifyListeners();
  }

  Future<void> deleteMeal(String id) async {
    // 先取出记录：删除后要按它记录时的规则回退活力值。
    final meal = mealById(id) ?? await _mealRepo.getMealById(id);
    await _mealRepo.deleteMeal(id);
    for (final entry in _mealsByDay.entries) {
      if (entry.value.any((meal) => meal.mealId == id)) {
        _mealsByDay[entry.key] = entry.value
            .where((meal) => meal.mealId != id)
            .toList(growable: false);
        break;
      }
    }
    if (meal != null) {
      // 活力值按记录时的同一规则反向回退；成长值只增不减，不回退。
      final delta = PetStateMachine.vitalityChangeForCompletion(
        meal.completionRate,
      );
      if (delta != 0) {
        _pet = _pet.copyWith(
          vitality: math.max(0, math.min(100, _pet.vitality - delta)).toInt(),
        );
        await _petRepo.savePet(_pet);
      }
    }
    _dialogue = '记录已删除';
    _scheduleWidgetSync();
    notifyListeners();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'profile': profile?.toJson(),
    'pet': _pet.toJson(),
    'meals': _mealsByDay.values
        .expand((meals) => meals)
        .map((meal) => meal.toJson())
        .toList(),
  });

  Future<void> clearData() async {
    await _mealRepo.deleteAllMeals();
    _mealsByDay.clear();
    mealReminder = false;
    gapReminder = false;
    _scheduleWidgetSync();
    notifyListeners();
  }

  /// 保存编辑后的个人档案（模块 10 个人信息编辑）。
  /// 调用方先用 ProfileUpdate.apply 重算好每日目标快照再传入。
  Future<void> updateProfile(UserProfile updated) async {
    profile = updated;
    await _userRepo.saveProfile(updated);
    _scheduleWidgetSync();
    notifyListeners();
  }

  /// 清除全部数据（模块 10 数据管理）：餐食记录、宠物、个人档案、
  /// 自定义菜品全部删除，回到 onboarding 首页重新设置。
  Future<void> clearAllData() async {
    await _mealRepo.deleteAllMeals();
    await _petRepo.deletePet();
    if (_databaseHelper.isOpen) {
      await _databaseHelper.database.delete('user_profiles');
      await _databaseHelper.database.delete('user_custom_dishes');
    }
    _mealsByDay.clear();
    profile = null;
    mealReminder = false;
    gapReminder = false;
    _pet = _petEngine.createPet(petType: _pet.petType, petName: '小挑食');
    _dialogue = _dailyDialogue();
    await _refreshDishMatcher();
    _scheduleWidgetSync();
    notifyListeners();
  }

  void _scheduleWidgetSync() {
    final now = DateTime.now();
    final todayMeals = mealsFor(now);
    final averageCompletion = todayMeals.isEmpty
        ? 0.0
        : todayMeals
                  .map((meal) => meal.completionRate)
                  .reduce((left, right) => left + right) /
              todayMeals.length;
    final dinnerTime = profile?.dinnerTime ?? '18:30';
    final status = <String, Object?>{
      ..._pet.toWidgetJson(),
      'today_meal_count': todayMeals.length,
      'today_completion_rate': averageCompletion,
      'next_meal_summary': _pet.nextMealSummary ?? '$dinnerTime 补蔬菜',
    };

    _widgetSync = _widgetSync.then((_) async {
      try {
        await IOSNativeBridge.instance.savePetStatus(status);
      } on PlatformException catch (error) {
        debugPrint('Unable to update iOS widget: ${error.message}');
      } catch (error) {
        debugPrint('Unable to update iOS widget: $error');
      }
      try {
        await _androidNativeBridge.savePetStatus(status);
      } on PlatformException catch (error) {
        debugPrint('Unable to update Android widget: ${error.message}');
      } on MissingPluginException catch (error) {
        debugPrint('Android widget channel is unavailable: $error');
      }
    });
  }

  void _scheduleMealRecordSync(MealRecord meal) {
    final record = <String, Object?>{
      'meal_id': meal.mealId,
      'meal_type': meal.mealType,
      'timestamp': meal.timestamp.toIso8601String(),
      'dishes': meal.dishes
          .map(
            (dish) => <String, Object?>{
              'name': dish.name,
              'quantity': dish.quantity,
              'portion_size': dish.portionSize,
              'matched_dish_id': dish.matchedDishId,
              'match_confidence': dish.matchConfidence,
            },
          )
          .toList(growable: false),
      'completion_rate': meal.completionRate,
      'sodium_level': meal.sodiumLevel,
    };
    _widgetSync = _widgetSync.then((_) async {
      try {
        await _androidNativeBridge.saveMealRecord(record);
      } on PlatformException catch (error) {
        debugPrint('Unable to save Android shared meal: ${error.message}');
      } on MissingPluginException catch (error) {
        debugPrint('Android shared data channel is unavailable: $error');
      }
    });
  }
}

/// 详细模式的克重↔份数换算结果。
class ManualServingLink {
  const ManualServingLink({
    required this.servings,
    required this.portions,
    this.matchedDishId,
    this.categoryId,
  });

  /// 换算出的份数（以「一份正常菜」为单位）。
  final double servings;

  /// 这份量的结构（已含克重换算，未再乘小/大份系数）。
  final Portions portions;

  /// 命中的菜品 id；按分类兜底时为 null。
  final String? matchedDishId;

  /// 使用的菜品分类 id（分类兜底时必填，菜品命中时为命中的分类）。
  final String? categoryId;
}
