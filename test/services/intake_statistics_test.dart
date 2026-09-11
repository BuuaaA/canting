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
  return _mealWithName(id, at, estimator, guidelines, name: '米饭', grams: grams);
}

MealRecord _mealWithName(
  String id,
  DateTime at,
  ServingEstimator estimator,
  DietaryGuidelines guidelines, {
  required String name,
  required double grams,
  String? category,
}) {
  final contract = RecognitionContract(_read('recognition.schema'));
  final example =
      _read('examples')['personal_half_bowl'] as Map<String, dynamic>;
  example['draftId'] = switch (id) {
    'sweet' => '00000000-0000-4000-8000-000000000004',
    'noodle' => '00000000-0000-4000-8000-000000000005',
    _ => '00000000-0000-4000-8000-000000000001',
  };
  final component =
      (example['products'] as List).first['components'][0]
          as Map<String, dynamic>;
  component['name']['value'] = name;
  if (category != null) {
    component['categoryId'] = {
      'value': category,
      'provenance': 'user_input',
      'reviewStatus': 'accepted',
      'evidenceRefs': <String>[],
    };
  }
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
    'V2 nut actual grams remain known when exchange comparison is unavailable',
    () async {
      final (state, helper, guidelines, estimator) = await _state();
      addTearDown(helper.close);
      final day = DateTime(2026, 9, 11);
      await state.saveMeal(
        _mealWithName(
          'nut',
          day,
          estimator,
          guidelines,
          name: '坚果',
          grams: 30,
          category: 'nut',
        ),
      );
      final result = await IntakeStatisticsService(state).rolling7d(date: day);
      expect(result.nutGrams, 30);
      expect(result.nutCompleteness, 'complete');
    },
  );

  test(
    'ambiguous sweet potato and dry noodle units keep comparison unknown',
    () async {
      final (state, helper, guidelines, estimator) = await _state();
      addTearDown(helper.close);
      final day = DateTime(2026, 9, 11);
      await state.saveMeal(
        _mealWithName(
          'composite',
          day,
          estimator,
          guidelines,
          name: '盖浇饭',
          grams: 400,
        ),
      );
      final compositeOnly = await IntakeStatisticsService(state)
          .rolling7d(date: day);
      expect(compositeOnly.days.last.foodVariety, isNull);
      await state.saveMeal(
        _mealWithName(
          'sweet',
          day,
          estimator,
          guidelines,
          name: '红薯',
          grams: 125,
        ),
      );
      await state.saveMeal(
        _mealWithName(
          'noodle',
          day,
          estimator,
          guidelines,
          name: '面条',
          grams: 75,
        ),
      );

      final result = await IntakeStatisticsService(state).today(date: day);
      expect(result.categories['tuber']!.amount, isNull);
      expect(result.categories['tuber']!.actualKnownByUnit['g'], 125);
      expect(result.categories['grain']!.amount, isNull);
      expect(result.categories['grain']!.actualKnownByUnit['g'], 75);
    },
  );

  test(
    'variety requires traceable complete food facts and excludes legacy keys',
    () async {
      final (state, helper, guidelines, estimator) = await _state();
      addTearDown(helper.close);
      final day = DateTime(2026, 9, 11);
      await state.saveMeal(
        MealRecord(
          mealId: 'legacy-variety',
          mealType: 'dinner',
          timestamp: day,
          dishes: [
            MealDish(
              name: '旧菜',
              food: const FoodObservation(facts: FoodFacts(name: '旧菜')),
            ),
          ],
        ),
      );

      final result = await IntakeStatisticsService(state).rolling7d(date: day);
      expect(
        result.days.last.categories.values.any(
          (c) => c.completeness == 'partial',
        ),
        isTrue,
      );
      expect(result.days.last.foodVariety, isNull);
    },
  );

  test('structure incomplete blocks complete day and variety despite convertible item', () async {
    final (state, helper, guidelines, estimator) = await _state();
    addTearDown(helper.close);
    final day = DateTime(2026, 9, 11);
    final base = _riceMeal('incomplete', day, estimator, guidelines);
    await state.saveMeal(
      MealRecord(
        mealId: base.mealId,
        mealType: base.mealType,
        timestamp: base.timestamp,
        dishes: [...base.dishes, const MealDish(contributionsKnown: false)],
        recognitionSnapshot: base.recognitionSnapshot,
      ),
    );

    final result = await IntakeStatisticsService(state).rolling7d(date: day);
    expect(result.days.last.completeness, 'partial');
    expect(result.days.last.foodVariety, isNull);
  });

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
      expect(result.foodVarietyDenominator, 0);
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
