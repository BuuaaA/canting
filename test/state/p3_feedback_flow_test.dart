import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:canting/core_engine.dart';
import 'package:canting/core/exposure.dart';
import 'package:canting/core/models/local_food.dart';
import 'package:canting/data/meal_repository.dart';
import 'package:canting/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

MealRecord riskMeal(
  String id,
  DateTime date, {
  String sugar = 'low',
  int rows = 1,
}) => MealRecord(
  mealId: id,
  mealType: 'lunch',
  timestamp: date,
  dishes: List.generate(
    rows,
    (_) => MealDish(
      name: '合成饮品',
      quantity: 2,
      contributionsKnown: false,
      food: FoodObservation(
        facts: const FoodFacts(name: '合成饮品', category: 'milk_tea'),
        spec: OrderSpec(sugar: sugar),
        confirmed: true,
      ),
    ),
  ),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late DatabaseHelper db;
  late AppState state;
  late Directory temp;
  late DateTime now;
  Future<void> open() async {
    db = DatabaseHelper(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: '${temp.path}/feedback.db',
    );
    await db.initialize(
      seedData: FoodDatabase.fromJson(
        dishesJson: File('assets/data/dishes.json').readAsStringSync(),
        categoriesJson: File('assets/data/categories.json').readAsStringSync(),
      ),
    );
    state = AppState(
      databaseHelper: db,
      clock: () => now,
      guidelines: DietaryGuidelines.fromJson(
        jsonDecode(
          File('assets/data/dietary_guidelines.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      ),
    );
    await state.loadFromDatabase();
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('canting-p3-');
    now = DateTime(2026, 3, 1, 12);
    await open();
  });
  tearDown(() async {
    state.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });
  test('real save restart edit date move delete rebuilds windows and keeps snapshot/receipt', () async {
    expect(
      await state.saveMeal(
        riskMeal('first', now.subtract(const Duration(days: 1))),
      ),
      isNull,
    );
    final prompt = await state.saveMeal(riskMeal('second', now, rows: 2));
    expect(prompt!.counts, {'sugary_drink': 2});
    File('dev-docs/p3-evidence/feedback-events.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'exposure_evaluated': {
          'mealId': prompt.mealId,
          'counts': prompt.counts,
        },
        'prompt_presented': {
          'source': 'AppState save result; UI presentation separately asserted in production page test',
          'mealId': prompt.mealId,
        },
        'prompt_suppressed': {'backdated_first_save': true},
        'scope': 'synthetic SQLite test only',
      }),
    );
    expect(state.windowFor(now, 7)!.partialDays, 2);
    expect(state.balanceReport!.isEmpty, true);
    expect(state.recommendationFor(now)!.primary.single.servings, isNull);
    final before = await MealRepository(database: () => db.database)
        .getMealById('first');
    state.dispose();
    await db.close();
    await open();
    expect(state.windowFor(now, 7)!.recordedDays, 2);
    expect(
      await state.saveMeal(riskMeal('second', now, sugar: 'none')),
      isNull,
    );
    expect(Exposure.counts(state.windowFor(now, 7)!.meals), {
      'sugary_drink': 1,
    });
    expect(
      (await MealRepository(database: () => db.database).getMealById('first'))!
          .toJson(),
      before!.toJson(),
    );
    await state.saveMeal(riskMeal('first', DateTime(2025, 1, 1)));
    expect(state.windowFor(now, 7)!.recordedDays, 1);
    await state.deleteMeal('second');
    expect(state.windowFor(now, 7)!.recordedDays, 0);
    expect(state.balanceReport!.isEmpty, true);
  });
  test('mute exact expiry survives restart export clear and never changes current spec', () async {
    await state.saveMeal(riskMeal('a', now));
    await state.saveExposurePreferences({
      'muted_sugary_drink': now
          .add(const Duration(days: 7))
          .toUtc()
          .toIso8601String(),
      'next_time_preference': 'no_added_sugar',
    });
    expect(await state.saveMeal(riskMeal('b', now, sugar: 'high')), isNull);
    final saved = await MealRepository(database: () => db.database)
        .getMealById('b');
    expect(saved!.dishes.single.food!.spec.sugar, 'high');
    state.dispose();
    await db.close();
    await open();
    expect(
      (await state.exposurePreferences())['next_time_preference'],
      'no_added_sugar',
    );
    expect(
      jsonDecode(await state.exportAllJson())['p3_exposure_state'],
      isNotEmpty,
    );
    now = now.add(const Duration(days: 7));
    await state.saveMeal(riskMeal('c', now.subtract(const Duration(days: 1))));
    expect(
      (await state.saveMeal(riskMeal('d', now)))!.counts['sugary_drink'],
      2,
    );
    await state.clearAllData();
    expect(await state.exposurePreferences(), isEmpty);
    expect(
      jsonDecode(await state.exportAllJson())['p3_exposure_state'],
      isEmpty,
    );
  });
  test(
    'concurrent same ID save at most one prompt, failed save never counts',
    () async {
      await state.saveMeal(riskMeal('a', now));
      final meal = riskMeal('b', now);
      final prompts = await Future.wait([
        state.saveMeal(meal),
        state.saveMeal(meal),
      ]);
      expect(prompts.whereType<ExposurePrompt>(), hasLength(1));
      expect(state.windowFor(now, 7)!.meals, hasLength(2));
      await db.database.execute(
        "CREATE TRIGGER reject_meal BEFORE INSERT ON meal_records BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(state.saveMeal(riskMeal('c', now)), throwsA(anything));
      expect(
        Exposure.counts(state.windowFor(now, 7)!.meals)['sugary_drink'],
        2,
      );
    },
  );
  test(
    'reminder persistence failure never rolls back successful meal',
    () async {
      await state.saveMeal(riskMeal('a', now));
      await db.database.execute(
        "CREATE TRIGGER reject_prompt BEFORE INSERT ON app_meta WHEN NEW.key LIKE 'p3.exposure.shown.%' BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      expect(await state.saveMeal(riskMeal('b', now)), isNull);
      expect(
        await MealRepository(database: () => db.database).getMealById('b'),
        isNotNull,
      );
    },
  );
  test('database failure marks error and removes stale ledger', () async {
    await state.saveMeal(
      MealRecord(
        mealId: 'known',
        mealType: 'lunch',
        timestamp: now,
        portionsTotal: const Portions(grains: 1),
      ),
    );
    expect(state.windowFor(now, 7)!.todayKnown, true);
    await db.close();
    await state.refreshBalanceLedger();
    expect(state.windowFor(now, 7)!.dataStatus, 'error');
    expect(state.balanceReport, isNull);
    expect(state.recommendationFor(now)!.primary.single.servings, isNull);
  });
  test('multiple risk families merge, mute independently, edited/backdated saves never prompt', () async {
    MealRecord mixed(String id) => MealRecord(
      mealId: id,
      mealType: 'lunch',
      timestamp: now,
      dishes: [
        ...riskMeal('template', now).dishes,
        const MealDish(
          name: '合成油炸',
          contributionsKnown: false,
          food: FoodObservation(
            facts: FoodFacts(
              name: '合成油炸',
              category: 'protein',
              preparation: 'fried',
            ),
          ),
        ),
        const MealDish(
          name: '合成酒精',
          contributionsKnown: false,
          food: FoodObservation(
            facts: FoodFacts(name: '合成酒精', category: 'alcohol'),
          ),
        ),
      ],
    );
    expect(await state.saveMeal(mixed('a')), isNull);
    expect((await state.saveMeal(mixed('b')))!.counts.keys.toSet(), {
      'sugary_drink',
      'fried_food',
      'alcohol',
    });
    await state.saveExposurePreferences({
      'muted_fried_food': now
          .add(const Duration(days: 7))
          .toUtc()
          .toIso8601String(),
    });
    expect((await state.saveMeal(mixed('c')))!.counts.keys.toSet(), {
      'sugary_drink',
      'alcohol',
    });
    expect(await state.saveMeal(mixed('c')), isNull);
    await state.deleteMeal('b');
    expect(
      await state.saveMeal(mixed('b')),
      isNull,
      reason: 'persisted event claim survives delete/re-add',
    );
    expect(Exposure.counts(state.windowFor(now, 7)!.meals)['fried_food'], 3);
  });
  test('changing targets and resuming across midnight rebuild authoritative ranges', () async {
    await state.saveMeal(
      MealRecord(
        mealId: 'known',
        mealType: 'lunch',
        timestamp: now,
        portionsTotal: const Portions(grains: 1),
      ),
    );
    final before = state.balanceReport!.balanceFor('grains').deficit;
    await state.updateProfile(
      UserProfile(
        gender: 'female',
        age: 30,
        heightCm: 165,
        weightKg: 55,
        dietGoal: 'balanced',
        activityLevel: 'light',
        breakfastTime: '08:00',
        lunchTime: '12:00',
        dinnerTime: '18:00',
        dayStartTime: '01:00',
        onboardingCompleted: true,
        createdAt: now,
        updatedAt: now,
        dailyIntake: const DailyIntake(
          grains: 7,
          vegetables: 5,
          fruits: 3,
          protein: 4,
          proteinSoy: 2,
          oil: 3,
          bmr: 1500,
          tdee: 2000,
        ),
      ),
    );
    expect(
      state.balanceReport!.balanceFor('grains').deficit,
      greaterThan(before),
    );
    now = now.add(const Duration(days: 7));
    await state.resumeRecords();
    expect(state.windowFor(now, 7)!.meals, isEmpty);
    expect(state.windowFor(now, 28)!.meals, hasLength(1));
    expect(state.recommendationFor(now)!.primary.single.servings, isNull);
  });
  test('v4 existing rows and receipts unchanged on load; risk snapshots survive serialization', () async {
    await state.saveMeal(riskMeal('snapshot', now));
    final raw = (await db.database.query('meal_records')).single['record_json'];
    await db.database.setVersion(4);
    state.dispose();
    await db.close();
    await open();
    expect(
      (await db.database.query('meal_records')).single['record_json'],
      raw,
    );
    final dish = MealDish.fromJson({
      ...const MealDish(name: '测试').toJson(),
      'risk_evidence': {
        'identity': 'sample',
        'source': 'legacy_catalog_snapshot',
        'tags': ['fried'],
      },
    });
    expect(
      dish.copyWith(quantity: 2).toJson()['risk_evidence'],
      dish.toJson()['risk_evidence'],
    );
    expect(
      Exposure.families(
        MealRecord(
          mealId: 'risk',
          mealType: 'lunch',
          timestamp: now,
          dishes: [dish],
        ),
      ),
      {'fried_food'},
    );
  });
  test(
    'in-flight window read cannot suppress a save-triggered rebuild',
    () async {
      await Future.wait([
        state.loadRecordWindows(now),
        state.refreshBalanceLedger(),
      ]);
      expect(state.windowFor(now, 7), isNotNull);
      await Future.wait([
        state.loadRecordWindows(now),
        state.saveMeal(riskMeal('concurrent', now)),
      ]);
      expect(
        state.windowFor(now, 7)!.meals.map((m) => m.mealId),
        contains('concurrent'),
      );
    },
  );
}
