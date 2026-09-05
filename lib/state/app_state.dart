import 'package:canting/core/exposure.dart';
import 'package:canting/data/exposure_repository.dart';
import 'package:canting/core/record_window.dart';
import 'package:canting/core/models/local_food.dart';
import 'package:canting/core/local_food_matcher.dart';
import 'package:canting/data/local_food_repository.dart';

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
    this.requestId = 0,
    this.warning,
    this.merchant = '',
    this.dishes = const [],
    this.isLoading = true,
    this.error,
  });

  final String imageUri;
  final int requestId;
  final String? warning;
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
    requestId: requestId,
    warning: warning,
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
    DateTime Function()? clock,
    this.persistNotificationSwitches,
  }) : clock = clock ?? DateTime.now,
       _petEngine = petEngine ?? PetEngine(),
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

  late final ExposureRepository _exposureRepo = ExposureRepository(
    () => _databaseHelper.database,
  );
  Future<Map<String, dynamic>> exposurePreferences() =>
      _exposureRepo.preferences();
  Future<void> saveExposurePreferences(Map<String, dynamic> prefs) =>
      _exposureRepo.savePreferences(prefs);
  Future<void> clearExposurePreferences() => _exposureRepo.clearPreferences();
  final DateTime Function() clock;
  final Map<String, RecordWindow> _windows = {};
  final Set<String> _windowLoads = {};
  final Map<String, Completer<void>> _windowWaiters = {};
  int dataRevision = 0;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  RecordWindow? windowFor(DateTime date, int days) =>
      _windows['${_dayKey(date)}:$days'];
  Future<void> resumeRecords() async {
    _mealsByDay.clear();
    await refreshBalanceLedger();
  }

  final PetEngine _petEngine;
  final AndroidNativeBridge _androidNativeBridge;
  final DatabaseHelper _databaseHelper;

  /// 膳食指南数据，main() 启动时从 JSON 加载；测试可为 null。
  DietaryGuidelines? guidelines;

  /// 提醒开关落盘回调（main 注入 SharedPreferences 实现；测试可为 null）。
  /// setMealReminder / setGapReminder / clearData / clearAllData 变更开关时触发。
  void Function({bool? mealReminder, bool? gapReminder})?
  persistNotificationSwitches;

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

  late final LocalFoodRepository _localFoodRepo = LocalFoodRepository(
    () => _databaseHelper.database,
  );
  List<LocalFoodProfile> _localFoods = [];
  List<LocalFoodProfile> get localFoods => List.unmodifiable(_localFoods);
  MealDish resolveFood(MealDish dish, {String brand = ''}) =>
      LocalFoodMatcher(_dishMatcher, _localFoods).resolve(dish, brand: brand);
  bool structureCompleteFor(DateTime date) =>
      mealsFor(date).every((m) => m.structureComplete);
  Future<void> editLocalFood(String oldKey, LocalFoodProfile value) async {
    await _localFoodRepo.edit(oldKey, value);
    _localFoods = await _localFoodRepo.all();
    notifyListeners();
  }

  Future<void> deleteLocalFood(String key) async {
    await _localFoodRepo.delete(key);
    _localFoods = await _localFoodRepo.all();
    notifyListeners();
  }

  Future<String> exportAllJson() async {
    final db = _databaseHelper.database;
    return db.transaction(
      (txn) async => const JsonEncoder.withIndent('  ').convert({
        'schema_version': 2,
        'p3_exposure_state': await txn.query(
          'app_meta',
          where: 'key LIKE ?',
          whereArgs: ['p3.exposure.%'],
        ),
        for (final table in [
          'user_food_profiles',
          'user_custom_dishes',
          'meal_records',
          'user_profiles',
          'pet_states',
        ])
          table: await txn.query(table),
      }),
    );
  }

  /// 菜品匹配引擎：标准菜库 + 用户自定义菜品（自定义优先）。
  /// 在 loadFromDatabase 中装配；未加载或缺少膳食指南数据时为 null。
  DishMatcher? _dishMatcher;
  ServingEstimator? _servingEstimator;

  /// 标准菜库快照，供推荐引擎等需要全量菜谱的模块使用。
  FoodDatabase? _foodDatabase;

  /// 7 天滚动平衡台账（模块：指南重蒸馏与滚动平衡推荐引擎）。
  /// 由 [refreshBalanceLedger] 按最近 7 天记录重建；null = 尚未计算。
  BalanceReport? _balanceReport;

  BalanceReport? get balanceReport => _balanceReport;

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
    _localFoods = await _localFoodRepo.all();
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
    await refreshBalanceLedger();
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
    try {
      final vitality = await _recentVitality(_mealRepo, reference);
      if (vitality == null || vitality == _pet.vitality) {
        return;
      }
      _pet = _pet.copyWith(vitality: vitality, lastVitalityUpdate: reference);
      await _petRepo.savePet(_pet);
      _scheduleWidgetSync();
      notifyListeners();
    } catch (error) {
      debugPrint('Unable to refresh pet vitality: $error');
    }
  }

  Future<int?> _recentVitality(
    MealRepository mealsRepository,
    DateTime reference,
  ) async {
    final target = profile?.dailyIntake;
    if (target == null) return null;
    final todayStart = DateTime(reference.year, reference.month, reference.day);
    final start = todayStart.subtract(const Duration(days: 2));
    final meals = await mealsRepository.getMealsByDateRange(
      start,
      todayStart.add(const Duration(days: 1)),
    );
    final mealsByDay = <DateTime, List<MealRecord>>{};
    for (final meal in meals) {
      final timestamp = meal.timestamp;
      final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
      mealsByDay.putIfAbsent(day, () => []).add(meal);
    }
    if (mealsByDay.isEmpty) {
      return null;
    }
    final scores = mealsByDay.values
        .where((dayMeals) => dayMeals.every((m) => m.structureComplete))
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
    return VitalityCalculator.vitalityFromDailyScores(scores);
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
    final result = _petEngine.checkOfflineDecay(pet: _pet, now: DateTime.now());
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

  /// 读取记录的用户备注（meal_records.note 列，不属于模块间 JSON）。
  Future<String?> mealNote(String mealId) => _mealRepo.getNote(mealId);

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

  static String _dayKey(DateTime date) =>
      '${date.year}-${date.month}-${date.day}';

  /// 模块 9：按区间只读查询餐食记录（[start, end)），供历史页
  /// 日历 / 周统计一次取整月数据使用，不写入本地缓存。
  Future<List<MealRecord>> queryMealsInRange(DateTime start, DateTime end) {
    return _mealRepo.getMealsByDateRange(start, end);
  }

  /// 当日真实完成度：已记录份数 ÷ 每日目标（IntakeCalculator 结果）。
  /// 没有记录时各分类均为 0，整体完成度也为 0。
  CompletionResult completionFor(DateTime date) {
    final eaten = mealsFor(date)
        .fold(Portions.zero, (total, meal) => total + meal.portionsTotal);
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
    final resolvedDishes = dishes
        .where((dish) => dish.name.trim().isNotEmpty)
        .map((dish) {
          if (dish.food != null || !dish.contributionsKnown) return dish;
          final hasPortions = dish.portions.byCategory.values.any(
            (value) => value != 0,
          );
          if (hasPortions || dish.matchedDishId != null) return dish;
          return resolveFood(dish, brand: merchant ?? '');
        })
        .map((dish) {
          if (mealId != null ||
              dish.food != null ||
              dish.riskEvidence != null ||
              dish.matchedDishId == null) {
            return dish;
          }
          final source = _foodDatabase?.findDishById(dish.matchedDishId!);
          if (source == null) return dish;
          return MealDish.fromJson({
            ...dish.toJson(),
            'risk_evidence': {
              'identity': source.id,
              'source': 'legacy_catalog_snapshot',
              'policy_version': 'p3-v1',
              'tags': [
                ...source.qualityTags,
                if (source.category == 'fried') 'fried',
              ],
              'category': source.category,
            },
          });
        })
        .toList(growable: false);
    final meal = MealRecord(
      mealId: mealId ?? 'meal-${DateTime.now().microsecondsSinceEpoch}',
      mealType: mealType,
      timestamp: timestamp,
      merchant: merchant,
      dishes: resolvedDishes,
    );
    final dayEaten = mealsFor(timestamp)
        .fold(Portions.zero, (total, item) => total + item.portionsTotal);
    return MealRecord(
      mealId: meal.mealId,
      mealType: meal.mealType,
      timestamp: meal.timestamp,
      merchant: meal.merchant,
      dishes: meal.dishes,
      completionRate:
          !meal.structureComplete || !structureCompleteFor(timestamp)
          ? 0
          : CompletionCalculator()
                .calculate(
                  eatenPortions: dayEaten + meal.portionsTotal,
                  dailyIntake: dailyIntake,
                )
                .overall,
    );
  }

  /// 重建 7 天滚动平衡台账（推荐引擎与宠物台词共用）。
  /// 启动、记录/删除餐食后调用；查询失败标记 error 并取消补偿。
  Future<void> refreshBalanceLedger({DateTime? reference}) async {
    _windows.clear();
    _balanceReport = null;
    dataRevision++;
    await loadRecordWindows(reference ?? clock());
  }

  Future<void> loadRecordWindows(DateTime reference) async {
    final key = _dayKey(reference);
    final pending = _windowWaiters[key];
    if (pending != null) {
      await pending.future;
      if (windowFor(reference, 7) == null) await loadRecordWindows(reference);
      return;
    }
    _windowLoads.add(key);
    _windowWaiters[key] = Completer<void>();
    final revision = dataRevision;
    final today = localDay(reference);
    try {
      final meals = await _mealRepo.getMealsByDateRange(
        DateTime(today.year, today.month, today.day - 27),
        DateTime(today.year, today.month, today.day + 1),
      );
      if (revision != dataRevision) return;
      for (final days in [7, 28]) {
        _windows['$key:$days'] = RecordWindow.build(
          meals,
          days: days,
          asOf: reference,
        );
      }
      _mealsByDay[key] = meals
          .where((m) => localDay(m.timestamp) == today)
          .toList();
      if (today == localDay(clock())) {
        _balanceReport = BalanceLedger.compute(
          intakeByDay: _windows['$key:7']!.knownDays,
          weeklyTarget: IntakeCalculator.weeklyTargetFromDaily(dailyIntake),
          now: reference,
        );
      }
    } catch (_) {
      if (revision != dataRevision) return;
      for (final days in [7, 28]) {
        _windows['$key:$days'] = RecordWindow.build(
          [],
          days: days,
          asOf: reference,
          status: 'error',
        );
      }
      _balanceReport = null;
    } finally {
      _windowLoads.remove(key);
      _windowWaiters.remove(key)?.complete();
      if (!_disposed) notifyListeners();
    }
  }

  /// 下一餐推荐：基于当日已记录餐食、目标缺口与 7 天滚动台账。
  ///
  /// [excludeDishNames] 供「换一批」使用：引擎把已展示的菜从候选里
  /// 去掉后按同样的规则补位（每槽位只取 1 道）。
  Recommendation? recommendationFor(
    DateTime date, {
    Set<String> excludeDishNames = const {},
  }) {
    final foodDatabase = _foodDatabase;
    if (foodDatabase == null) {
      return null;
    }
    final window = windowFor(date, 7);
    if (window == null && !_windowLoads.contains(_dayKey(date))) {
      scheduleMicrotask(() => loadRecordWindows(date));
    }
    final meals =
        window?.meals
            .where((m) => localDay(m.timestamp) == localDay(date))
            .toList() ??
        <MealRecord>[];
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
    final rawNow = clock();
    final now = DateTime(
      rawNow.year,
      rawNow.month,
      rawNow.day,
      rawNow.hour,
      rawNow.minute,
    );
    return RecommendationEngine(foodDatabase).recommend(
      todayMeals: meals,
      dailyIntake: dailyIntake,
      now: now,
      lastMealType: lastMealType,
      balance: window == null
          ? null
          : BalanceLedger.compute(
              intakeByDay: window.knownDays,
              weeklyTarget: IntakeCalculator.weeklyTargetFromDaily(dailyIntake),
              now: date,
            ),
      dataAvailable: window?.dataStatus == 'ready',
      excludeDishNames: excludeDishNames,
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
        (dish) =>
            !seenNames.contains(FoodDatabase.normalizeDishName(dish.name)),
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
    if (!match.shouldAutoAdd) return null;
    final id = match.matchedDishId;
    if (id == null) {
      return null;
    }
    final base =
        _foodDatabase?.dishes.where((dish) => dish.id == id).firstOrNull ??
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
                proteinSoy: appCategory == 'protein_soy'
                    ? estimate.servings
                    : 0,
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
    return _categoryFallbackLink(
      dishName,
      grams: grams,
      categoryId: categoryId,
    );
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
          guidelines.gramsPerServingFor(_appCategoryToGuideline(entry.key)) ??
          10;
      total += entry.value * gramsPerServing;
    }
    return total <= 0 ? null : total;
  }

  /// APP 内部分类 id → 膳食指南分类 id（与 ServingEstimator 同映射）。
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
  /// 7 天台账有盈余衰减趋势时优先用滚动调控台词（「昨天吃得很香，
  /// 今天咱们清爽一点？」），否则走当日场景随机文案。
  String _dailyDialogue() {
    final now = DateTime.now();
    final ledger = _balanceReport;
    if (ledger != null) {
      final rolling = _petEngine.rollingBalanceDialogue(
        report: ledger,
        petType: _pet.petType,
      );
      if (rolling.isNotEmpty) {
        return rolling;
      }
    }
    return PetDailyDialogue(dialogues: _petEngine.dialogues).pickDaily(
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
    persistNotificationSwitches?.call(mealReminder: value);
    notifyListeners();
  }

  void setGapReminder(bool value) {
    gapReminder = value;
    persistNotificationSwitches?.call(gapReminder: value);
    notifyListeners();
  }

  int _recognitionSequence = 0;
  bool recognitionEdited = false;
  Future<bool> Function()? confirmRecognitionReplacement;
  void markRecognitionEdited() {
    recognitionEdited = true;
    // Manual editing invalidates in-flight callbacks without discarding the page.
    if (_recognitionDraft?.isLoading == true) {
      _recognitionDraft = _recognitionDraft!.copyWith(isLoading: false);
      notifyListeners();
    }
  }

  Future<bool> mayReplaceRecognition() async {
    final confirm = confirmRecognitionReplacement;
    if (confirm != null) return await confirm();
    return !recognitionEdited;
  }

  void startSharedRecognition(String imageUri) {
    recognitionEdited = false;
    _recognitionDraft = RecognitionDraft(
      imageUri: imageUri,
      requestId: ++_recognitionSequence,
    );
    notifyListeners();
  }

  void completeSharedRecognition({
    required String imageUri,
    required String merchant,
    required List<MealDish> dishes,
    int? requestId,
    String? warning,
  }) {
    if (_recognitionDraft?.imageUri != imageUri ||
        _recognitionDraft?.isLoading != true ||
        recognitionEdited ||
        (requestId != null && _recognitionDraft?.requestId != requestId)) {
      return;
    }
    _recognitionDraft = RecognitionDraft(
      imageUri: imageUri,
      requestId: _recognitionDraft!.requestId,
      warning: warning,
      merchant: merchant,
      dishes: List.unmodifiable(
        dishes.map((d) => resolveFood(d, brand: merchant)),
      ),
      isLoading: false,
    );
    notifyListeners();
  }

  void failSharedRecognition({
    required String imageUri,
    required String message,
    int? requestId,
  }) {
    if (_recognitionDraft?.imageUri != imageUri ||
        _recognitionDraft?.isLoading != true ||
        recognitionEdited ||
        (requestId != null && _recognitionDraft?.requestId != requestId)) {
      return;
    }
    _recognitionDraft = RecognitionDraft(
      imageUri: imageUri,
      requestId: _recognitionDraft!.requestId,
      isLoading: false,
      error: message,
    );
    notifyListeners();
  }

  void clearSharedRecognition({int? requestId}) {
    if (requestId != null && _recognitionDraft?.requestId != requestId) return;
    recognitionEdited = false;
    _recognitionDraft = null;
  }

  void clearPendingEvolution() {
    _pendingEvolutionFrom = null;
    notifyListeners();
  }

  final Map<String, Future<ExposurePrompt?>> _savingMeals = {};
  Future<ExposurePrompt?> saveMeal(
    MealRecord meal, {
    String? note,
    String? source,
  }) async {
    final pending = _savingMeals[meal.mealId];
    if (pending != null) {
      await pending;
      return null;
    }
    final future = _saveMeal(meal, note: note, source: source);
    _savingMeals[meal.mealId] = future;
    try {
      return await future;
    } finally {
      _savingMeals.remove(meal.mealId);
    }
  }

  Future<ExposurePrompt?> _saveMeal(
    MealRecord meal, {
    String? note,
    String? source,
  }) async {
    await _ensureMealsLoaded(meal.timestamp);
    final key = _dayKey(meal.timestamp);
    final dayMeals = [...(_mealsByDay[key] ?? const <MealRecord>[])];
    final index = dayMeals.indexWhere((item) => item.mealId == meal.mealId);
    final existing = await _mealRepo.getMealById(meal.mealId);
    final isNew = existing == null;
    // Caller-supplied snapshots cannot manufacture or replace reward receipts.
    var effect = existing?.petEffect;
    if (isNew) {
      effect = MealPetEffect(
        evaluated: false,
        vitalityDelta: 0,
        recordedAt: DateTime.now(),
      );
    }

    var nextPet = _pet;
    var nextDialogue = _dialogue;
    GrowthStage? nextEvolution = _pendingEvolutionFrom;
    if (isNew &&
        meal.structureComplete &&
        dayMeals.every((m) => m.structureComplete)) {
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
      final mealLog = result.logs.firstWhere(
        (log) => log.relatedMealId == meal.mealId && log.isActiveMealEffect,
      );
      effect = MealPetEffect(
        evaluated: true,
        vitalityDelta: mealLog.changeValue,
        recordedAt: mealLog.timestamp,
      );
      nextPet = result.pet;
      nextDialogue = result.dialogue;
      nextEvolution = result.previousGrowthStage;
    } else if (!isNew) {
      if (index >= 0) {
        dayMeals[index] = meal;
      } else {
        dayMeals.add(meal);
      }
      nextDialogue = '这顿修改好啦';
    } else {
      nextDialogue = '已记录，饮食结构估算不完整';
    }

    meal = meal.withPetEffect(effect);
    if (!isNew) {
      final editedIndex = dayMeals.indexWhere((m) => m.mealId == meal.mealId);
      dayMeals[editedIndex] = meal;
    }
    await _databaseHelper.database.transaction((txn) async {
      final meals = MealRepository(database: () => txn);
      if (isNew) {
        await meals.addMeal(meal, note: note, source: source);
      } else {
        await meals.updateMeal(meal, note: note);
      }
      // Existing snapshots never rewrite personal memory on a plain history save.
      if (isNew) {
        for (final dish in meal.dishes) {
          if (dish.food != null) {
            await LocalFoodRepository.remember(txn, dish.food!);
          }
        }
      }
      if (isNew) await PetRepository(database: () => txn).savePet(nextPet);
    });
    _pet = nextPet;
    _dialogue = nextDialogue;
    _pendingEvolutionFrom = nextEvolution;
    _localFoods = await _localFoodRepo.all();

    for (final otherKey in _mealsByDay.keys.toList()) {
      if (otherKey != key) {
        _mealsByDay[otherKey] = _mealsByDay[otherKey]!
            .where((m) => m.mealId != meal.mealId)
            .toList();
      }
    }
    _mealsByDay[key] = isNew ? [meal, ...dayMeals] : dayMeals;
    await refreshBalanceLedger();
    _scheduleWidgetSync();
    _scheduleMealRecordSync(meal);
    notifyListeners();
    if (isNew) {
      try {
        return await _exposureRepo.claim(meal, clock());
      } catch (_) {
        return null;
      } // Reminder failure cannot turn a committed meal into a failed save.
    }
    return null;
  }

  Future<void> deleteMeal(String id) async {
    // Authoritative read and all writes share a transaction. A second delete is a no-op.
    final updatedPet = await _databaseHelper.database.transaction((txn) async {
      final meals = MealRepository(database: () => txn);
      final meal = await meals.getMealById(id);
      if (meal == null) return null;
      final pets = PetRepository(database: () => txn);
      var next = await pets.getPet() ?? _pet;
      await meals.deleteMeal(id);
      final effect = meal.petEffect;
      if (effect?.evaluated == true) {
        next = next.copyWith(
          vitality: PetStateMachine.clampVitality(
            next.vitality - effect!.vitalityDelta,
          ),
        );
      }
      // Keep the established legacy recalculation; never fabricate a legacy reward.
      // An explicitly suppressed new effect must not cause quality evaluation on delete.
      if (effect?.evaluated == true ||
          (effect == null && meal.structureComplete)) {
        final now = DateTime.now();
        final recalculated = await _recentVitality(meals, now);
        if (recalculated != null && recalculated != next.vitality) {
          next = next.copyWith(vitality: recalculated, lastVitalityUpdate: now);
        }
      }
      await pets.savePet(next);
      return next;
    });
    if (updatedPet == null) return;
    _pet = updatedPet;
    for (final key in _mealsByDay.keys.toList()) {
      _mealsByDay[key] = _mealsByDay[key]!
          .where((meal) => meal.mealId != id)
          .toList(growable: false);
    }
    _dialogue = '记录已删除';
    await refreshBalanceLedger();
    _scheduleWidgetSync();
    notifyListeners();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'local_food_profiles': _localFoods.map((p) => p.toJson()).toList(),
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
    await refreshBalanceLedger();
    mealReminder = false;
    gapReminder = false;
    persistNotificationSwitches?.call(mealReminder: false, gapReminder: false);
    _scheduleWidgetSync();
    notifyListeners();
  }

  /// 保存编辑后的个人档案（模块 10 个人信息编辑）。
  /// 调用方先用 ProfileUpdate.apply 重算好每日目标快照再传入。
  Future<void> updateProfile(UserProfile updated) async {
    profile = updated;
    await _userRepo.saveProfile(updated);
    await refreshBalanceLedger();
    _scheduleWidgetSync();
    notifyListeners();
  }

  /// 清除全部数据（模块 10 数据管理）：餐食记录、宠物、个人档案、
  /// 自定义菜品全部删除，回到 onboarding 首页重新设置。
  Future<void> clearAllData() async {
    await _databaseHelper.database.transaction((txn) async {
      await txn.delete(
        'app_meta',
        where: 'key LIKE ?',
        whereArgs: ['p3.exposure.%'],
      );
      for (final table in [
        'meal_records',
        'pet_states',
        'user_profiles',
        'user_custom_dishes',
        'user_food_profiles',
      ]) {
        await txn.delete(table);
      }
    });
    _localFoods = [];
    _recognitionDraft = null;
    _mealsByDay.clear();
    profile = null;
    _balanceReport = null;
    _windows.clear();
    dataRevision++;
    mealReminder = false;
    gapReminder = false;
    persistNotificationSwitches?.call(mealReminder: false, gapReminder: false);
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
      'today_completion_rate': todayMeals.every((m) => m.structureComplete)
          ? averageCompletion
          : null,
      'structure_complete': todayMeals.every((m) => m.structureComplete),
      'next_meal_summary':
          !todayMeals.isNotEmpty ||
              !todayMeals.every((m) => m.structureComplete)
          ? '$dinnerTime 常规搭配，记录不足'
          : '$dinnerTime 基于已记录餐食估算建议',
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
              'match_confidence': null,
              'match_score': dish.food == null ? dish.matchConfidence : null,
            },
          )
          .toList(growable: false),
      'completion_rate': meal.structureComplete ? meal.completionRate : null,
      'structure_complete': meal.structureComplete,
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
