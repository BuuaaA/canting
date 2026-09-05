import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/data/meal_repository.dart';
import 'package:canting/data/pet_repository.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late DatabaseHelper db;
  late AppState state;
  Future<void> open() async {
    db = DatabaseHelper(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: '${dir.path}/test.db',
    );
    await db.initialize();
    state = AppState(databaseHelper: db);
    await state.loadFromDatabase();
  }

  Future<void> restart() async {
    state.dispose();
    await db.close();
    await open();
  }

  setUp(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('p2-r2-');
    await open();
  });
  tearDown(() async {
    state.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });
  MealRecord meal(String id, {bool known = true, double rate = .8}) =>
      MealRecord(
        mealId: id,
        mealType: 'lunch',
        timestamp: DateTime.now(),
        completionRate: rate,
        dishes: [
          MealDish(
            name: '合成餐',
            contributionsKnown: known,
            portions: const Portions(grains: 2, vegetables: 2, protein: 2),
          ),
        ],
      );
  Future<String> rows(String table) async =>
      jsonEncode(await db.database.query(table, orderBy: 'id'));
  Future<void> unchangedDelete(String id, int before) async {
    await state.deleteMeal(id);
    expect(state.pet.vitality, before);
    expect(
      (await PetRepository(database: () => db.database).getPet())!.vitality,
      before,
    );
  }

  test(
    'R2 uncredited complete meal deletion never subtracts vitality',
    () async {
      await state.saveMeal(meal('unknown', known: false));
      final before = state.pet.vitality;
      await state.saveMeal(meal('complete'));
      expect(state.pet.vitality, before);
      await unchangedDelete('complete', before);
    },
  );
  test('R2 credited meal normal deletion preserves growth', () async {
    await state.saveMeal(meal('complete'));
    expect(state.pet.vitality, 70);
    final growth = state.pet.growth;
    await unchangedDelete('complete', 60);
    expect(state.pet.growth, growth);
  });
  test(
    'R2 restart retains actual reward and repeat deletion is idempotent',
    () async {
      await state.saveMeal(meal('complete'));
      await restart();
      expect(state.pet.vitality, 70);
      await unchangedDelete('complete', 60);
      final pet = await rows('pet_states');
      await unchangedDelete('complete', 60);
      expect(await rows('pet_states'), pet);
    },
  );
  test('R2 restart retains explicitly suppressed reward', () async {
    await state.saveMeal(meal('unknown', known: false));
    await state.saveMeal(meal('complete'));
    await restart();
    await unchangedDelete('complete', 60);
  });
  test('R2 edit known to unknown retains original reward receipt', () async {
    await state.saveMeal(meal('edit'));
    await state.saveMeal(meal('edit', known: false, rate: 0));
    expect(state.pet.vitality, 70);
    await restart();
    await unchangedDelete('edit', 60);
  });
  test('R2 edit unknown to known must not manufacture reward', () async {
    await state.saveMeal(meal('edit', known: false));
    await state.saveMeal(meal('edit'));
    expect(state.pet.vitality, 60);
    await restart();
    await unchangedDelete('edit', 60);
  });
  test('R2 reverse actual capped change rather than nominal reward', () async {
    await PetRepository(database: () => db.database)
        .savePet(state.pet.copyWith(vitality: 98));
    await restart();
    await state.saveMeal(meal('cap'));
    expect(state.pet.vitality, 100);
    await unchangedDelete('cap', 98);
  });
  test('R2 negative actual change reverses symmetrically', () async {
    await state.saveMeal(meal('poor', rate: 0));
    expect(state.pet.vitality, 56);
    await unchangedDelete('poor', 60);
  });
  for (final table in ['pet_states', 'meal_records']) {
    test('R2 failed deletion on $table rolls back DB and memory', () async {
      await state.saveMeal(meal('fail'));
      final meals = await rows('meal_records');
      final pet = await rows('pet_states');
      final before = state.pet.toJson();
      final operation = table == 'pet_states' ? 'INSERT' : 'DELETE';
      await db.database.execute(
        "CREATE TRIGGER fail_delete BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(state.deleteMeal('fail'), throwsA(anything));
      expect(await rows('meal_records'), meals);
      expect(await rows('pet_states'), pet);
      expect(state.pet.toJson(), before);
      expect(state.mealById('fail'), isNotNull);
      await db.database.execute('DROP TRIGGER fail_delete');
      await unchangedDelete('fail', 60);
    });
  }

  test('R2 concurrent repeated deletion reverses only once', () async {
    await state.saveMeal(meal('repeat'));
    await Future.wait([state.deleteMeal('repeat'), state.deleteMeal('repeat')]);
    expect(state.pet.vitality, 60);
    expect(
      (await PetRepository(database: () => db.database).getPet())!.vitality,
      60,
    );
  });
  test('R2 with profile and scored prior day, suppressed deletion does not recalculate', () async {
    final now = DateTime.now();
    final profile = UserProfile(
      gender: 'female',
      age: 28,
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
        grains: 5,
        vegetables: 4,
        fruits: 2.5,
        protein: 4,
        proteinSoy: 1,
        oil: 2.5,
        bmr: 1450,
        tdee: 1740,
      ),
    );
    await state.updateProfile(profile);
    await state.saveMeal(meal('unknown', known: false));
    await state.saveMeal(meal('complete'));
    await MealRepository(database: () => db.database).addMeal(
      MealRecord(
        mealId: 'yesterday',
        mealType: 'lunch',
        timestamp: now.subtract(const Duration(days: 1)),
        dishes: const [
          MealDish(
            name: '合成均衡餐',
            portions: Portions(
              grains: 5,
              vegetables: 4,
              fruits: 2.5,
              protein: 4,
              proteinSoy: 1,
              oil: 2.5,
            ),
          ),
        ],
      ),
    );
    expect(state.pet.vitality, 60);
    await unchangedDelete('complete', 60);
  });
  test(
    'R2 editing and export retain receipt; legacy edit stays absent',
    () async {
      await state.saveMeal(meal('receipt'));
      final repo = MealRepository(database: () => db.database);
      final receipt = (await repo.getMealById('receipt'))!
          .toJson()['pet_effect'];
      expect(receipt, containsPair('vitality_delta', 10));
      await state.saveMeal(meal('receipt', known: false));
      expect(
        (await repo.getMealById('receipt'))!.toJson()['pet_effect'],
        receipt,
      );
      final export = await state.exportAllJson();
      expect(export, contains('pet_effect'));
      await repo.addMeal(meal('old'));
      await state.saveMeal(meal('old', known: false));
      expect(
        (await repo.getMealById('old'))!.toJson().containsKey('pet_effect'),
        false,
      );
    },
  );
  test('R2 failed save cannot leave meal or reward', () async {
    final before = state.pet.toJson();
    await db.database.execute(
      "CREATE TRIGGER fail_save BEFORE INSERT ON pet_states BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    await expectLater(state.saveMeal(meal('fail')), throwsA(anything));
    expect(await db.database.query('meal_records'), isEmpty);
    expect(await db.database.query('pet_states'), isEmpty);
    expect(state.pet.toJson(), before);
  });
  test(
    'R2 old v4 JSON remains unchanged on open, has no invented reward',
    () async {
      final repo = MealRepository(database: () => db.database);
      await repo.addMeal(meal('legacy'));
      // Explicitly remove any new optional field to reproduce pre-fix stored JSON.
      final row = (await db.database.query('meal_records')).single;
      final j = jsonDecode(row['record_json'] as String) as Map;
      j.remove('pet_effect');
      await db.database.update(
        'meal_records',
        {'record_json': jsonEncode(j)},
        where: 'id = ?',
        whereArgs: ['legacy'],
      );
      await PetRepository(database: () => db.database).savePet(state.pet);
      final before = await rows('meal_records');
      await restart();
      expect(await rows('meal_records'), before);
      expect(await db.database.getVersion(), 4);
      await unchangedDelete('legacy', 60);
    },
  );
}
