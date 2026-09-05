import 'dart:convert';
import 'dart:io';

import 'package:canting/data/database_helper.dart';
import 'package:canting/data/food_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'food_knowledge_test.dart' show syntheticPackage;

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late DatabaseHelper helper;
  late FoodDatabase seed;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp(
      'canting_knowledge_synthetic_',
    );
    helper = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: '${temp.path}/test.db',
    );
    seed = FoodDatabase.fromJson(
      dishesJson: File('test/fixtures/legacy_dishes_29.json')
          .readAsStringSync(),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
    await helper.initialize(seedData: seed);
    final db = helper.database;
    await db.insert('meal_records', {
      'id': 'history',
      'meal_time': 1,
      'meal_type': 'lunch',
      'record_json': '{"snapshot":{"grains":1.25},"dish_id":"synthetic:1"}',
      'note': '不可覆盖的备注',
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('user_custom_dishes', {
      'dish_id': 'custom',
      'dish_name': '自定义',
      'category': 'custom',
      'json_data': '{"original":true}',
      'created_at': 1,
      'updated_at': 2,
    });
    await db.insert('pet_states', {
      'id': 1,
      'json_data': '{"mood":"happy","growth":7}',
      'updated_at': 3,
    });
    await db.insert('user_profiles', {
      'id': 1,
      'gender': 'female',
      'age': 30,
      'height_cm': 160,
      'weight_kg': 55,
      'diet_goal': 'maintain',
      'activity_level': 'moderate',
      'breakfast_time': '08:00',
      'lunch_time': '12:00',
      'dinner_time': '18:00',
      'day_start_time': '04:00',
      'onboarding_completed': 1,
      'daily_intake_json': '{"grains":5}',
      'created_at': 1,
      'updated_at': 2,
    });
  });
  tearDown(() async {
    await helper.close();
    await temp.delete(recursive: true);
  });

  Future<String> userSnapshot() async => jsonEncode({
    for (final table in [
      'meal_records',
      'user_custom_dishes',
      'pet_states',
      'user_profiles',
    ])
      table: await helper.database.query(table),
  });

  test(
    'initialize conflict rolls back legacy updates too and permits reopen',
    () async {
      final before = await userSnapshot();
      final catalogBefore = jsonEncode(await helper.database.query('dishes'));
      await helper.syncKnowledgePackage(syntheticPackage('synthetic-v1'));
      final changed = seed.dishes.first.toJson()..['dish_name'] = '不应写入';
      final update = FoodDatabase.fromJson(
        dishesJson: jsonEncode({
          'schema_version': 99,
          'dishes': [changed],
        }),
        categoriesJson: File('assets/data/categories.json').readAsStringSync(),
      ).withKnowledgePackage(syntheticPackage('synthetic-v1', name: '冲突包'));
      await helper.close();
      await expectLater(helper.initialize(seedData: update), throwsStateError);
      expect(helper.isOpen, isFalse);
      await helper.initialize();
      expect(jsonEncode(await helper.database.query('dishes')), catalogBefore);
      expect(await userSnapshot(), before);
      expect(
        (await helper.loadFoodDatabase()).schemaVersion,
        seed.schemaVersion,
      );
    },
  );

  test('v2 storage upgrade and synthetic package preserve every user field', () async {
    final before = await userSnapshot();
    // Reconstruct the actual pre-app_meta schema in this disposable fixture DB.
    await helper.database.execute('DROP TABLE app_meta');
    await helper.database.setVersion(2);
    await helper.close();
    await helper.initialize(
      seedData: seed.withKnowledgePackage(syntheticPackage('synthetic-v1')),
    );
    expect(await helper.database.getVersion(), DatabaseHelper.databaseVersion);
    expect(
      (await helper.loadKnowledgePackage())!.contentVersion,
      'synthetic-v1',
    );
    expect(await userSnapshot(), before);
  });

  test('content update with same schema, idempotence, conflict and all user rows survive', () async {
    final before = await userSnapshot();
    final legacy = jsonEncode(await helper.database.query('dishes'));
    final v1 = syntheticPackage('synthetic-v1');
    expect(await helper.syncKnowledgePackage(v1), 1);
    expect(await helper.syncKnowledgePackage(v1), 0);
    final v2 = syntheticPackage('synthetic-v2', name: '新版合成汉堡');
    expect(await helper.syncKnowledgePackage(v2), 1);
    expect(
      (await helper.loadFoodDatabase()).findKnowledgeById('synthetic:1')!.name,
      '新版合成汉堡',
    );
    expect(
      await helper.syncKnowledgePackage(v1),
      0,
    ); // old replay never downgrades
    await expectLater(
      helper.syncKnowledgePackage(
        syntheticPackage('synthetic-v2', name: '冲突内容'),
      ),
      throwsStateError,
    );
    expect((await helper.loadKnowledgePackage())!.digest, v2.digest);
    expect(await userSnapshot(), before);
    expect(jsonEncode(await helper.database.query('dishes')), legacy);
    await helper.close();
    await helper.initialize(seedData: seed.withKnowledgePackage(v2));
    expect((await helper.loadKnowledgePackage())!.digest, v2.digest);
    expect(await userSnapshot(), before);
  });

  test(
    'failure after package write rolls back active package and ledger',
    () async {
      final before = await userSnapshot();
      final v1 = syntheticPackage('synthetic-v1');
      await helper.syncKnowledgePackage(v1);
      await helper.database.execute(
        """CREATE TRIGGER fail_knowledge_ledger BEFORE INSERT ON app_meta
      WHEN NEW.key = 'food_knowledge_digest:synthetic-v2'
      BEGIN SELECT RAISE(ABORT, 'synthetic rollback test'); END""",
      );
      await expectLater(
        helper.syncKnowledgePackage(syntheticPackage('synthetic-v2')),
        throwsA(isA<DatabaseException>()),
      );
      expect((await helper.loadKnowledgePackage())!.digest, v1.digest);
      expect(
        await helper.database.query(
          'app_meta',
          where: 'key = ?',
          whereArgs: ['food_knowledge_digest:synthetic-v2'],
        ),
        isEmpty,
      );
      expect(await userSnapshot(), before);
    },
  );

  test('legacy seed failure rolls back rows and schema marker', () async {
    final before = await userSnapshot();
    final catalogBefore = jsonEncode(await helper.database.query('dishes'));
    await helper.database.execute(
      """CREATE TRIGGER fail_seed_marker BEFORE INSERT ON app_meta
      WHEN NEW.key = 'seed_schema_version' AND NEW.value = '99'
      BEGIN SELECT RAISE(ABORT, 'synthetic seed rollback'); END""",
    );
    final changed = seed.dishes.first.toJson()..['dish_name'] = '合成改名';
    final updated = FoodDatabase.fromJson(
      dishesJson: jsonEncode({
        'schema_version': 99,
        'dishes': [changed],
      }),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
    await expectLater(
      helper.syncSeedCatalog(updated),
      throwsA(isA<DatabaseException>()),
    );
    expect(jsonEncode(await helper.database.query('dishes')), catalogBefore);
    expect((await helper.loadFoodDatabase()).schemaVersion, seed.schemaVersion);
    expect(await userSnapshot(), before);
  });
}
