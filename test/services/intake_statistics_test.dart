import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/core/models/local_food.dart';
import 'package:canting/core/models/meal_draft_v2.dart';
import 'package:canting/services/intake_statistics.dart';
import 'package:canting/services/recognition_contract.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> _read(String name) =>
    jsonDecode(File('dev-docs/recognition-v2/$name.json').readAsStringSync())
        as Map<String, dynamic>;

Future<(AppState, DatabaseHelper, DietaryGuidelines, ServingEstimator)>
_state() async {
  sqfliteFfiInit();
  final helper = DatabaseHelper(
    factory: databaseFactoryFfiNoIsolate,
    databasePath: inMemoryDatabasePath,
  );
  await helper.initialize();
  final guidelines = DietaryGuidelines.fromJson(
    jsonDecode(File('assets/data/dietary_guidelines.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final state = AppState(databaseHelper: helper, guidelines: guidelines);
  await state.loadFromDatabase();
  final estimator = ServingEstimator(
    DishMatcher(FoodDatabase(dishes: [], categories: [])),
    guidelines,
  );
  return (state, helper, guidelines, estimator);
}

MealRecord _riceMeal(
  String id,
  DateTime at,
  ServingEstimator estimator,
  DietaryGuidelines guidelines, {
  double grams = 150,
}) {
  final contract = RecognitionContract(_read('recognition.schema'));
  final example =
      _read('examples')['personal_half_bowl'] as Map<String, dynamic>;
  final draft = MealDraftV2(contract, example, simulated: true)
    ..setIntake(
      'c-rice',
      basis: 'personal_consumed',
      portion: {'value': grams, 'unit': 'g', 'band': 'unknown'},
    );
  return draft.toMeal(
    mealType: 'lunch',
    timestamp: at,
    estimator: estimator,
    policyVersion: guidelines.version,
    knowledgeVersion: 'test-existing-exchange',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real MealDraftV2 input is converted using reviewed guidelines',
    () async {
      final (state, helper, guidelines, estimator) = await _state();
      addTearDown(helper.close);
      final day = DateTime(2026, 9, 11);
      await state.saveMeal(_riceMeal('rice', day, estimator, guidelines));

      final result = await IntakeStatisticsService(state).today(date: day);
      final grain = result.categories['grain']!;
      expect(grain.amount, 50);
      expect(grain.actualKnownByUnit['g'], 150);
      expect(grain.toJson(), isNot(contains('actualKnownSubtotal')));
      expect(result.toJson()['dataRevision'], state.dataRevision);
    },
  );

  test(
    'rolling window keeps missing days and uses zero empty denominator',
    () async {
      final (state, helper, guidelines, estimator) = await _state();
      addTearDown(helper.close);
      final day = DateTime(2026, 9, 11);
      await state.saveMeal(_riceMeal('rice', day, estimator, guidelines));

      final result = await IntakeStatisticsService(state).rolling7d(date: day);
      expect(result.startDate, '2026-09-05');
      expect(result.days, hasLength(7));
      expect(result.days.first.completeness, 'missing');
      expect(result.averages['vegetable']!.average, isNull);
      expect(result.averages['vegetable']!.denominator, 0);
      expect(result.foodVarietyDenominator, 1);
    },
  );

  test(
    'fish counts once per meal only for confirmed positive dishes',
    () async {
      final (state, helper, guidelines, estimator) = await _state();
      addTearDown(helper.close);
      final day = DateTime(2026, 9, 11);
      MealRecord fish(
        String id, {
        required bool confirmed,
        double quantity = 1,
      }) => MealRecord(
        mealId: id,
        mealType: 'lunch',
        timestamp: day,
        dishes: [
          MealDish(
            name: '鱼',
            quantity: quantity,
            food: FoodObservation(
              facts: const FoodFacts(name: '鱼', category: 'fish'),
              confirmed: confirmed,
            ),
          ),
          MealDish(
            name: '鱼',
            quantity: quantity,
            food: FoodObservation(
              facts: const FoodFacts(name: '鱼', category: 'fish'),
              confirmed: confirmed,
            ),
          ),
        ],
      );
      await state.saveMeal(fish('fish-confirmed', confirmed: true));
      await state.saveMeal(fish('fish-unconfirmed', confirmed: false));
      await state.saveMeal(fish('fish-zero', confirmed: true, quantity: 0));
      await state.saveMeal(_riceMeal('rice', day, estimator, guidelines));

      final result = await IntakeStatisticsService(state).rolling7d(date: day);
      expect(result.fishCount, 1);
      expect(result.days.last.fishCount, 1);
      expect(result.fishGrams, isNull);
      expect(result.fishCompleteness, 'partial');
    },
  );

  test('save and delete changes the revision-backed result', () async {
    final (state, helper, guidelines, estimator) = await _state();
    addTearDown(helper.close);
    final day = DateTime(2026, 9, 11);
    final service = IntakeStatisticsService(state);
    final before = await service.today(date: day);
    await state.saveMeal(_riceMeal('rice', day, estimator, guidelines));
    final afterSave = await service.today(date: day);
    expect(afterSave.revision, greaterThan(before.revision));
    expect(afterSave.categories['grain']!.amount, 50);
    await state.deleteMeal('00000000-0000-4000-8000-000000000001');
    final afterDelete = await service.today(date: day);
    expect(afterDelete.revision, greaterThan(afterSave.revision));
    expect(afterDelete.categories['grain']!.completeness, 'missing');
  });
}
