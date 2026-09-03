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
    _dialogue = _petEngine.getStatusDialogue(
      petType: _pet.petType,
      state: _pet.vitalityState,
    );
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
    }
    await _refreshDishMatcher();
    if (onboardingComplete) {
      await _ensureMealsLoaded(DateTime.now());
    }
    _scheduleWidgetSync();
    notifyListeners();
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

  Future<void> completeOnboarding({
    required UserProfile profile,
    required String petType,
    required String petName,
  }) async {
    final now = DateTime.now();
    _pet = _petEngine.createPet(petType: petType, petName: petName.trim());
    _dialogue = _petEngine.getStatusDialogue(
      petType: _pet.petType,
      state: _pet.vitalityState,
    );
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
    _dialogue = _petEngine.getStatusDialogue(
      petType: _pet.petType,
      state: _pet.vitalityState,
    );
    notifyListeners();
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

  Future<void> saveMeal(MealRecord meal) async {
    final key = _dayKey(meal.timestamp);
    final dayMeals = [...(_mealsByDay[key] ?? const <MealRecord>[])];
    final index = dayMeals.indexWhere((item) => item.mealId == meal.mealId);
    final isNew = index == -1;

    if (isNew) {
      final result = _petEngine.onMealRecorded(
        pet: _pet,
        completionRate: meal.completionRate,
        completionByCategory: completion.byCategory,
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
      await _mealRepo.addMeal(meal);
    } else {
      await _mealRepo.updateMeal(meal);
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
    await _mealRepo.deleteMeal(id);
    for (final entry in _mealsByDay.entries) {
      if (entry.value.any((meal) => meal.mealId == id)) {
        _mealsByDay[entry.key] = entry.value
            .where((meal) => meal.mealId != id)
            .toList(growable: false);
        break;
      }
    }
    _pet = _pet.copyWith(vitality: math.max(15, _pet.vitality - 2));
    _dialogue = '记录已删除';
    await _petRepo.savePet(_pet);
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
