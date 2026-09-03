import 'dart:convert';
import 'dart:math' as math;

import 'package:canting/core_engine.dart';
import 'package:canting/native/ios_native_bridge.dart';
import 'package:canting/pet.dart';
import 'package:canting/platform/android_native_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MockDish {
  const MockDish({
    required this.name,
    this.quantity = 1,
    this.portionSize = 'normal',
  });

  final String name;
  final int quantity;
  final String portionSize;

  MockDish copyWith({String? name, int? quantity, String? portionSize}) =>
      MockDish(
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        portionSize: portionSize ?? this.portionSize,
      );
}

class MockMeal {
  const MockMeal({
    required this.id,
    required this.merchant,
    required this.mealType,
    required this.time,
    required this.dishes,
    required this.completionRate,
  });

  final String id;
  final String merchant;
  final String mealType;
  final DateTime time;
  final List<MockDish> dishes;
  final double completionRate;

  MockMeal copyWith({
    String? merchant,
    String? mealType,
    DateTime? time,
    List<MockDish>? dishes,
    double? completionRate,
  }) => MockMeal(
    id: id,
    merchant: merchant ?? this.merchant,
    mealType: mealType ?? this.mealType,
    time: time ?? this.time,
    dishes: dishes ?? this.dishes,
    completionRate: completionRate ?? this.completionRate,
  );
}

class SetupProfile {
  const SetupProfile({
    required this.gender,
    required this.heightCm,
    required this.weightKg,
    required this.age,
    required this.activityLevel,
    required this.dietGoal,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    required this.dayBoundaryHour,
  });

  final String gender;
  final int heightCm;
  final double weightKg;
  final int age;
  final String activityLevel;
  final String dietGoal;
  final TimeOfDay breakfast;
  final TimeOfDay lunch;
  final TimeOfDay dinner;
  final int dayBoundaryHour;
}

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
  final List<MockDish> dishes;
  final bool isLoading;
  final String? error;

  RecognitionDraft copyWith({
    String? merchant,
    List<MockDish>? dishes,
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
  AppState({PetEngine? petEngine, AndroidNativeBridge? androidNativeBridge})
    : _petEngine = petEngine ?? PetEngine(),
      _androidNativeBridge = androidNativeBridge ?? AndroidNativeBridge() {
    final now = DateTime.now();
    _pet = _petEngine.createPet(petType: 'cat', petName: '小挑食');
    _dialogue = _petEngine.getStatusDialogue(
      petType: _pet.petType,
      state: _pet.vitalityState,
    );
    _selectedDate = DateTime(now.year, now.month, now.day);
    _meals = [
      MockMeal(
        id: 'meal-lunch',
        merchant: '邻里小馆',
        mealType: 'lunch',
        time: DateTime(now.year, now.month, now.day, 12, 18),
        dishes: const [
          MockDish(name: '杂粮饭'),
          MockDish(name: '番茄炒蛋'),
          MockDish(name: '清炒时蔬', portionSize: 'small'),
        ],
        completionRate: 0.72,
      ),
      MockMeal(
        id: 'meal-breakfast',
        merchant: '晨光早餐',
        mealType: 'breakfast',
        time: DateTime(now.year, now.month, now.day, 8, 5),
        dishes: const [
          MockDish(name: '全麦三明治'),
          MockDish(name: '无糖豆浆'),
        ],
        completionRate: 0.58,
      ),
    ];
    _scheduleWidgetSync();
  }

  final PetEngine _petEngine;
  final AndroidNativeBridge _androidNativeBridge;
  late PetData _pet;
  late String _dialogue;
  late DateTime _selectedDate;
  late List<MockMeal> _meals;
  RecognitionDraft? _recognitionDraft;
  Future<void> _widgetSync = Future.value();
  GrowthStage? _pendingEvolutionFrom;

  bool onboardingComplete = false;
  bool petAreaCollapsed = false;
  bool mealReminder = false;
  bool gapReminder = false;
  SetupProfile? profile;

  static const dailyIntake = DailyIntake(
    grains: 5,
    vegetables: 4,
    fruits: 2.5,
    protein: 4,
    proteinSoy: 1,
    oil: 2.5,
    bmr: 1450,
    tdee: 1740,
  );

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
  List<MockMeal> get meals => List.unmodifiable(_meals);
  RecognitionDraft? get recognitionDraft => _recognitionDraft;
  GrowthStage? get pendingEvolutionFrom => _pendingEvolutionFrom;

  List<MockMeal> mealsFor(DateTime date) =>
      _meals
          .where(
            (meal) =>
                meal.time.year == date.year &&
                meal.time.month == date.month &&
                meal.time.day == date.day,
          )
          .toList(growable: false)
        ..sort((a, b) => b.time.compareTo(a.time));

  void completeOnboarding({
    required SetupProfile setupProfile,
    required String petType,
    required String petName,
  }) {
    profile = setupProfile;
    _pet = _petEngine.createPet(petType: petType, petName: petName.trim());
    _dialogue = _petEngine.getStatusDialogue(
      petType: _pet.petType,
      state: _pet.vitalityState,
    );
    onboardingComplete = true;
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
    _scheduleWidgetSync();
    notifyListeners();
  }

  void selectDate(DateTime date) {
    _selectedDate = DateTime(date.year, date.month, date.day);
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
    required List<MockDish> dishes,
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

  void saveMeal(MockMeal meal) {
    final index = _meals.indexWhere((item) => item.id == meal.id);
    if (index == -1) {
      _meals = [meal, ..._meals];
      final result = _petEngine.onMealRecorded(
        pet: _pet,
        completionRate: meal.completionRate,
        completionByCategory: completion.byCategory,
        mealId: meal.id,
      );
      _pet = result.pet;
      _dialogue = result.dialogue;
      _pendingEvolutionFrom = result.previousGrowthStage;
    } else {
      _meals = [..._meals]..[index] = meal;
      _dialogue = '这顿修改好啦';
    }
    _scheduleWidgetSync();
    _scheduleMealRecordSync(meal);
    notifyListeners();
  }

  void deleteMeal(String id) {
    _meals = _meals.where((meal) => meal.id != id).toList(growable: false);
    _pet = _pet.copyWith(vitality: math.max(15, _pet.vitality - 2));
    _dialogue = '记录已删除';
    _scheduleWidgetSync();
    notifyListeners();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'profile': {
      'gender': profile?.gender ?? 'female',
      'height_cm': profile?.heightCm ?? 165,
      'weight_kg': profile?.weightKg ?? 55,
      'age': profile?.age ?? 28,
      'activity_level': profile?.activityLevel ?? 'light',
      'diet_goal': profile?.dietGoal ?? 'balanced',
    },
    'pet': _pet.toJson(),
    'meals': _meals
        .map(
          (meal) => {
            'id': meal.id,
            'merchant': meal.merchant,
            'meal_type': meal.mealType,
            'time': meal.time.toIso8601String(),
            'dishes': meal.dishes.map((dish) => dish.name).toList(),
          },
        )
        .toList(),
  });

  void clearData() {
    _meals = [];
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
    final dinner = profile?.dinner ?? const TimeOfDay(hour: 18, minute: 30);
    final status = <String, Object?>{
      ..._pet.toWidgetJson(),
      'today_meal_count': todayMeals.length,
      'today_completion_rate': averageCompletion,
      'next_meal_summary':
          _pet.nextMealSummary ??
          '${dinner.hour.toString().padLeft(2, '0')}:'
              '${dinner.minute.toString().padLeft(2, '0')} 补蔬菜',
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

  void _scheduleMealRecordSync(MockMeal meal) {
    final record = <String, Object?>{
      'meal_id': meal.id,
      'meal_type': meal.mealType,
      'timestamp': meal.time.toIso8601String(),
      'dishes': meal.dishes
          .map(
            (dish) => <String, Object?>{
              'name': dish.name,
              'quantity': dish.quantity,
              'portion_size': dish.portionSize,
              'matched_dish_id': null,
              'match_confidence': 0.0,
            },
          )
          .toList(growable: false),
      'completion_rate': meal.completionRate,
      'sodium_level': completion.sodiumLevel,
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
