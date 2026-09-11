import 'dart:convert';

import 'package:canting/core/models/meal_record.dart';
import 'package:canting/core/models/local_food.dart';
import 'package:canting/data/database_helper.dart';
import 'package:canting/services/intake_statistics.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

MealRecord _v2Meal(
  String id,
  DateTime at,
  String category,
  double amount, {
  String unit = 'g',
  String foodKey = 'food-key',
}) => MealRecord(
  mealId: id,
  mealType: 'lunch',
  timestamp: at,
  recognitionSnapshot: {
    'schemaVersion': 'meal-v2.2',
    'wireVersion': 'recognition-n0.2',
    'simulated': true,
    'editHistory': <dynamic>[],
    'draft': {
      'products': [
        {
          'productId': id,
          'selected': true,
          'nutritionMode': 'aggregate',
          'displayName': {'value': foodKey, 'reviewStatus': 'accepted'},
          'categoryId': {'value': category, 'reviewStatus': 'accepted'},
          'animalSubtype': {
            'value': foodKey == 'fish' ? 'fish' : null,
            'reviewStatus': foodKey == 'fish' ? 'accepted' : 'unreviewed',
          },
          'calculation': {
            'active': true,
            'portionBasis': 'personal_consumed',
            'portion': {
              'value': {'value': amount, 'unit': unit},
              'reviewStatus': 'accepted',
            },
            'notEaten': {'value': false},
          },
        },
      ],
    },
  },
);

Future<(AppState, DatabaseHelper)> _state() async {
  sqfliteFfiInit();
  final helper = DatabaseHelper(
    factory: databaseFactoryFfiNoIsolate,
    databasePath: inMemoryDatabasePath,
  );
  await helper.initialize();
  final state = AppState(databaseHelper: helper);
  await state.loadFromDatabase();
  return (state, helper);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'rolling7d uses local dates, excludes day -7, and preserves revision',
    () async {
      final (state, helper) = await _state();
      addTearDown(helper.close);
      final anchor = DateTime(2026, 9, 11);
      await state.saveMeal(
        _v2Meal('today', anchor, 'vegetable', 300, foodKey: 'cabbage'),
      );
      await state.saveMeal(
        _v2Meal('old', DateTime(2026, 9, 4), 'vegetable', 999),
      );
      final result = await IntakeStatisticsService(state)
          .rolling7d(date: anchor);

      expect(result.startDate, '2026-09-05');
      expect(result.endDate, '2026-09-11');
      expect(result.days, hasLength(7));
      expect(result.days.first.date, '2026-09-05');
      expect(result.days.last.categories['vegetable']!.amount, 300);
      expect(result.averages['vegetable']!.average, 300);
      expect(result.averages['vegetable']!.denominator, 1);
      expect(result.foodVarietyAverage, isNull);
      expect(result.revision, state.dataRevision);
    },
  );

  test(
    'fish is counted once per meal and unknown quantities stay unknown',
    () async {
      final (state, helper) = await _state();
      addTearDown(helper.close);
      final day = DateTime(2026, 9, 11);
      await state.saveMeal(
        _v2Meal('fish-meal', day, 'protein_meat_egg', 120, foodKey: 'fish'),
      );
      await state.saveMeal(
        _v2Meal('fish-meal-2', day, 'protein_meat_egg', 80, foodKey: 'fish'),
      );
      final unknown = MealRecord(
        mealId: 'unknown',
        mealType: 'dinner',
        timestamp: day,
        dishes: [
          MealDish(
            name: '旧记录',
            food: FoodObservation(
              facts: FoodFacts(name: '旧记录', category: 'protein_meat_egg'),
            ),
          ),
        ],
      );
      await state.saveMeal(unknown);

      final result = await IntakeStatisticsService(state).rolling7d(date: day);
      expect(result.fishCount, 2);
      expect(result.fishGrams, 200);
      expect(result.days.last.fishCount, 2);
      expect(
        result.days.last.categories['animal_food']!.completeness,
        'partial',
      );
      expect(result.days.last.categories['animal_food']!.amount, isNull);
    },
  );

  test(
    '90 percent boundary and oil/salt upper bounds do not create a gap',
    () async {
      final (state, helper) = await _state();
      addTearDown(helper.close);
      final day = DateTime(2026, 9, 11);
      await state.saveMeal(_v2Meal('veg', day, 'vegetable', 270));
      await state.saveMeal(_v2Meal('oil', day, 'cooking_oil', 20));
      await state.saveMeal(_v2Meal('salt', day, 'salt', 5));
      final result = await IntakeStatisticsService(state).today(date: day);

      expect(result.categories['vegetable']!.status, 'near');
      expect(result.categories['vegetable']!.gap, 30);
      expect(result.categories['cooking_oil']!.status, 'met');
      expect(result.categories['cooking_oil']!.gap, isNull);
      expect(result.categories['salt']!.status, 'met');
      expect(result.categories['salt']!.gap, isNull);
    },
  );

  test(
    'serialized result is stable for page and recommendation consumers',
    () async {
      final (state, helper) = await _state();
      addTearDown(helper.close);
      final result = await IntakeStatisticsService(state)
          .today(date: DateTime(2026, 9, 11));
      final json = jsonEncode(result.toJson());
      expect(json, contains('dataRevision'));
      expect(json, contains('cooking_oil'));
      expect(json, contains('salt'));
    },
  );
}
