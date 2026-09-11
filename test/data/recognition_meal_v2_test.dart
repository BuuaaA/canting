import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/core/models/meal_draft_v2.dart';
import 'package:canting/data/meal_repository.dart';
import 'package:canting/services/recognition_contract.dart';
import 'package:canting/services/recognition_adapter.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> read(String name) =>
    jsonDecode(File('dev-docs/recognition-v2/$name.json').readAsStringSync())
        as Map<String, dynamic>;
Map<String, dynamic> portion(num? value, String unit) => {
  'value': value,
  'unit': unit,
  'band': unit == 'ordinal' ? 'small' : 'unknown',
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final contract = RecognitionContract(read('recognition.schema'));
  Map<String, dynamic> half() =>
      read('examples')['personal_half_bowl'] as Map<String, dynamic>;
  MealDraftV2 draft() => MealDraftV2(contract, half(), simulated: true);
  final guidelines = DietaryGuidelines.fromJson(
    jsonDecode(File('assets/data/dietary_guidelines.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final estimator = ServingEstimator(
    DishMatcher(FoodDatabase(dishes: [], categories: [])),
    guidelines,
  );
  MealRecord freeze(MealDraftV2 d) => d.toMeal(
    mealType: 'lunch',
    timestamp: DateTime(2026, 9, 7),
    estimator: estimator,
    policyVersion: guidelines.version,
    knowledgeVersion: 'test-existing-exchange',
  );

  test(
    'R1 schema and semantic bounds match per unit, quantities stay capped',
    () {
      for (final unit in ['bowl', 'cup', 'serving', 'g', 'ml']) {
        final maximum = ['g', 'ml'].contains(unit) ? 10000 : 99;
        for (final value in [0.5, 99, maximum]) {
          final d = half();
          d['products'][0]['components'][0]['calculation']['portion']['value'] =
              portion(value, unit);
          contract.validate('Draft', d);
          contract.draft(d);
        }
        for (final value in [
          0,
          -1,
          maximum + 0.01,
          double.nan,
          double.infinity,
          double.negativeInfinity,
        ]) {
          final d = half();
          d['products'][0]['components'][0]['calculation']['portion']['value'] =
              portion(value, unit);
          expect(() => contract.validate('Draft', d), throwsFormatException);
          expect(() => contract.draft(d), throwsFormatException);
        }
      }
      final d = draft()
        ..setIntake(
          'c-rice',
          basis: 'personal_consumed',
          portion: portion(473, 'ml'),
        );
      expect(contract.effectiveAmounts(d.draft)['c-rice'], 473);
      d.setIntake('c-rice', basis: 'personal_consumed');
      expect(contract.effectiveAmounts(d.draft)['c-rice'], isNull);
      expect(
        () => d.editFact('p-meal', 'purchaseQuantity', 100),
        throwsFormatException,
      );
      expect(
        () => d.editFact('p-meal', 'purchaseQuantity', 1.5),
        throwsFormatException,
      );
      d.editFact('p-meal', 'purchaseQuantity', 99);
    },
  );

  test(
    'accept preserves inference; input histories and failed edits are atomic',
    () {
      final d = draft();
      d.reviewFact('c-rice', 'name');
      expect(
        d.draft['products'][0]['components'][0]['name']['provenance'],
        'name_inference',
      );
      d.editFact('c-rice', 'name', '白米饭');
      expect(d.history.last['before']['name']['value'], '米饭');
      expect(d.history.last['after']['name']['provenance'], 'user_input');
      final before = jsonEncode(d.draft);
      expect(
        () => d.setIntake(
          'c-rice',
          basis: 'personal_consumed',
          portion: portion(100, 'bowl'),
        ),
        throwsFormatException,
      );
      expect(jsonEncode(d.draft), before);
      expect(d.history.length, 2);
      final copy = d.draft;
      copy['products'].clear();
      expect(d.draft['products'], isNotEmpty);
    },
  );

  test('basis, not eaten, unknown and ordinal never invent a scalar', () {
    final d = draft();
    expect(contract.effectiveAmounts(d.draft)['c-rice'], .5);
    expect(freeze(d).portionsTotal.grains, .5);
    expect(
      freeze(d).recognitionSnapshot!['contributions']['c-rice']['mapping'],
      'container:bowl',
    );
    for (final basis in ['served_total', 'per_product_unit']) {
      d.setIntake(
        'c-rice',
        basis: basis,
        portion: portion(150, 'g'),
        allocation: .5,
        consumed: .5,
      );
      expect(
        freeze(d).portionsTotal.grains,
        basis == 'served_total' ? .25 : .5,
      );
    }
    d.setIntake(
      'c-rice',
      basis: 'personal_consumed',
      portion: portion(150, 'g'),
      allocation: .5,
      consumed: .5,
    );
    expect(freeze(d).portionsTotal.grains, 1);
    expect(
      d.draft['products'][0]['components'][0]['calculation']['consumedRatio']['value'],
      isNull,
    );
    d.setIntake('c-rice', basis: 'personal_consumed', notEaten: true);
    expect(freeze(d).structureComplete, true);
    expect(freeze(d).portionsTotal.grains, 0);
    d.setIntake(
      'c-rice',
      basis: 'personal_consumed',
      portion: portion(null, 'ordinal'),
    );
    expect(freeze(d).structureComplete, false);
    expect(
      freeze(d).recognitionSnapshot!['contributions']['c-rice']['portions'],
      isNull,
    );
  });

  test('parent switching and partially known children never double count', () {
    final input = half();
    final child = jsonDecode(
      jsonEncode(input['products'][0]['components'][0]),
    ) as Map<String, dynamic>;
    child['componentId'] = 'c-unknown';
    child['name'] = MealDraftV2.fact('未知炒菜');
    child['calculation']['portion'] = MealDraftV2.fact(null);
    input['products'][0]['components'].add(child);
    final d = MealDraftV2(contract, input, simulated: true)
      ..setIntake(
        'c-rice',
        basis: 'personal_consumed',
        portion: portion(150, 'g'),
      );
    var meal = freeze(d);
    expect(meal.portionsTotal.grains, 1);
    expect(meal.structureComplete, false);
    expect(meal.recognitionSnapshot!['completeness'], 'partial');
    d.editFact('p-meal', 'displayName', '米饭');
    d.setIntake(
      'p-meal',
      basis: 'personal_consumed',
      portion: portion(300, 'g'),
    );
    d.setMode('p-meal', 'aggregate');
    meal = freeze(d);
    expect(meal.portionsTotal.grains, 2);
    expect(meal.recognitionSnapshot!['contributions'].keys.toList(), [
      'p-meal',
    ]);
    d.setMode('p-meal', 'children');
    expect(freeze(d).portionsTotal.grains, 1);
    d.select('p-meal', false);
    expect(() => freeze(d), throwsFormatException);
  });

  test('saved snapshot roundtrip retains source/history and rejects unknown versions', () {
    final d = draft()..editFact('c-rice', 'name', '白米饭');
    final original = freeze(d);
    final restored = MealRecord.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    final editing = MealDraftV2.fromMeal(contract, restored)
      ..editFact('c-rice', 'name', '熟米饭');
    expect(editing.history.length, 2);
    expect(restored.recognitionSnapshot!['editHistory'].length, 1);
    expect(restored.toJson(), original.toJson());
    final bad = restored.toJson()..['record_version'] = 99;
    expect(() => MealRecord.fromJson(bad), throwsFormatException);
    expect(
      () => MealDraftV2(contract, half(), simulated: false),
      throwsFormatException,
    );
    final old = read('n0.1-examples');
    final oldContract = RecognitionContract(read('n0.1-recognition.schema'));
    oldContract.request(old['request']);
    for (final key in [
      'screenshot',
      'food_photo',
      'personal_half_bowl',
      'empty_food',
    ]) {
      contract.draft(old[key]);
    }
    expect(() => contract.request(old['request']), throwsFormatException);
  });

  test('component editing remains versioned and product display is not legacy rows', () {
    final d = draft()..addComponent('p-meal', '未知炒菜');
    var graph = d.draft;
    expect(graph['products'][0]['nutritionMode'], 'children');
    expect(graph['products'][0]['components'], hasLength(2));
    final addedId =
        graph['products'][0]['components'][1]['componentId'] as String;
    d.editFact(addedId, 'name', '青椒炒肉');
    d.removeComponent('p-meal', addedId);
    graph = d.draft;
    expect(graph['products'][0]['components'], hasLength(1));
    final meal = freeze(d);
    expect(meal.productCount, 1);
    expect(meal.displayProductNames, ['盖浇饭套餐']);
    expect(meal.dishes.length, greaterThanOrEqualTo(1));
  });

  group('actual SQLite and AppState', () {
    late Directory dir;
    late DatabaseHelper db;
    late AppState state;
    Future<void> open() async {
      db = DatabaseHelper(
        factory: databaseFactoryFfiNoIsolate,
        databasePath: '${dir.path}/meals.db',
      );
      await db.initialize();
      state = AppState(databaseHelper: db, guidelines: guidelines);
      await state.loadFromDatabase();
    }

    setUp(() async {
      sqfliteFfiInit();
      dir = await Directory.systemTemp.createTemp('n1-meal-');
      await open();
    });
    tearDown(() async {
      state.dispose();
      await db.close();
      await dir.delete(recursive: true);
    });
    Future<void> restart() async {
      state.dispose();
      await db.close();
      await open();
    }

    Future<void> save(MealDraftV2 d) => state.saveRecognitionMeal(
      d,
      mealType: 'lunch',
      timestamp: DateTime.now(),
    );
    Future<MealRecord> saved(MealDraftV2 d) async =>
        (await MealRepository(database: () => db.database)
            .getMealById(d.draftId))!;

    test('mock response to confirmed graph to real transaction survives restart and duplicate save', () async {
      final examples = read('examples');
      final request = examples['request'] as Map<String, dynamic>;
      final config = Map<String, dynamic>.from(examples['provider'] as Map)
        ..['mode'] = 'mock';
      final response = await RecognitionAdapter(contract).recognize(
        request,
        config,
        mockResult: examples['screenshot'] as Map<String, dynamic>,
      );
      final d = MealDraftV2.fromResponse(contract, request, response);
      d.select('p-meal', true);
      d.setMode('p-meal', 'children');
      d.select('c-rice', true);
      d.reviewFact('c-rice', 'name');
      d.setIntake(
        'c-rice',
        basis: 'personal_consumed',
        portion: portion(150, 'g'),
      );
      await Future.wait([save(d), save(d)]);
      final original = (await saved(d)).toJson();
      expect((await saved(d)).portionsTotal.grains, 1);
      expect(
        (await saved(d)).completionRate,
        CompletionCalculator()
            .calculate(
              eatenPortions: const Portions(grains: 1),
              dailyIntake: state.dailyIntake,
            )
            .overall,
      );
      expect((await saved(d)).simulated, true);
      expect((await saved(d)).recognitionSnapshot!['editHistory'], isNotEmpty);
      await restart();
      d.setIntake(
        'c-rice',
        basis: 'personal_consumed',
        portion: portion(300, 'g'),
      );
      await save(d);
      expect((await db.database.query('meal_records')).length, 1);
      expect((await saved(d)).toJson(), original);
      final export = jsonDecode(await state.exportAllJson());
      final exportedMeal = jsonDecode(export['meal_records'][0]['record_json']);
      expect(exportedMeal['recognition_v2']['simulated'], true);
      expect(
        exportedMeal['recognition_v2']['draft']['products'][0]['components'],
        isNotEmpty,
      );
      await state.clearAllData();
      expect(await db.database.query('meal_records'), isEmpty);
      await restart();
      expect(await db.database.query('meal_records'), isEmpty);
    });

    test(
      'failed save rolls back graph, pet and record; retry succeeds',
      () async {
        final d = draft()
          ..setIntake(
            'c-rice',
            basis: 'personal_consumed',
            portion: portion(150, 'g'),
          );
        await db.database.execute(
          "CREATE TRIGGER fail_pet BEFORE INSERT ON pet_states BEGIN SELECT RAISE(ABORT, 'injected disk failure'); END",
        );
        await expectLater(save(d), throwsA(isA<DatabaseException>()));
        expect(await db.database.query('meal_records'), isEmpty);
        expect(await db.database.query('pet_states'), isEmpty);
        await db.database.execute('DROP TRIGGER fail_pet');
        await save(d);
        await restart();
        expect((await saved(d)).portionsTotal.grains, 1);
      },
    );

    test('v4 upgrade preserves raw old snapshot, backup and deletion clears backup', () async {
      final old =
          MealRecord(
              mealId: 'legacy',
              mealType: 'dinner',
              timestamp: DateTime.now(),
              portionsTotal: const Portions(grains: 7),
              dishes: [
                const MealDish(name: '旧套餐', portions: Portions(grains: 2)),
              ],
            ).toJson()
            ..remove('record_version')
            ..remove('nutrition_mode');
      final raw = jsonEncode(old);
      await db.database.insert('meal_records', {
        'id': 'legacy',
        'meal_time': DateTime.now().millisecondsSinceEpoch,
        'meal_type': 'dinner',
        'record_json': raw,
        'created_at': 1,
        'updated_at': 1,
      });
      await db.database.execute('DROP INDEX idx_meal_draft');
      await db.database.execute(
        'ALTER TABLE meal_records DROP COLUMN draft_id',
      );
      await db.database.execute(
        'ALTER TABLE meal_records DROP COLUMN record_version',
      );
      await db.database.setVersion(4);
      await restart();
      expect(await db.database.getVersion(), 5);
      expect(
        (await db.database.query('meal_records')).single['record_json'],
        raw,
      );
      final legacy = (await MealRepository(database: () => db.database)
          .getMealById('legacy'))!;
      expect(legacy.nutritionMode, 'legacy_aggregate');
      expect(legacy.portionsTotal.grains, 7);
      expect(legacy.recognitionSnapshot, isNull);
      final backupPath = '${dir.path}/meals.db.pre-v5.db';
      final backup = await databaseFactoryFfiNoIsolate.openDatabase(backupPath);
      expect(await backup.getVersion(), 4);
      expect((await backup.query('meal_records')).single['record_json'], raw);
      await backup.close();
      await state.clearData();
      expect(await File(backupPath).exists(), false);
      expect(await db.database.query('meal_records'), isEmpty);
    });

    test('migration failure rolls back all DDL and permits old version read and retry', () async {
      await db.database.execute('DROP INDEX idx_meal_draft');
      await db.database.execute(
        'ALTER TABLE meal_records DROP COLUMN draft_id',
      );
      await db.database.execute(
        'ALTER TABLE meal_records DROP COLUMN record_version',
      );
      await db.database.execute(
        'CREATE INDEX idx_meal_draft ON meal_records(meal_type)',
      );
      await db.database.setVersion(4);
      state.dispose();
      await db.close();
      await expectLater(db.initialize(), throwsA(isA<DatabaseException>()));
      expect(db.isOpen, false);
      final old = await databaseFactoryFfiNoIsolate.openDatabase(
        '${dir.path}/meals.db',
      );
      expect(await old.getVersion(), 4);
      expect(
        (await old.rawQuery('PRAGMA table_info(meal_records)'))
            .map((c) => c['name']),
        isNot(contains('record_version')),
      );
      await old.execute('DROP INDEX idx_meal_draft');
      await old.close();
      await open();
      expect(await db.database.getVersion(), 5);
    });
  });
}
