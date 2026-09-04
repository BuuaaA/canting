import 'dart:convert';
import 'dart:io';

import 'package:canting/data/database_helper.dart';
import 'package:canting/data/food_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// 数据迁移验收：从旧版 29 道种子库升级 → 菜数变为新库数量、用户数据无损。
void main() {
  sqfliteFfiInit();

  late FoodDatabase newSeed;
  late List<Map<String, dynamic>> legacyDishes;

  setUpAll(() {
    newSeed = FoodDatabase.fromJson(
      dishesJson: File('assets/data/dishes.json').readAsStringSync(),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
    legacyDishes =
        (jsonDecode(File('test/fixtures/legacy_dishes_29.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>();
  });

  final tempDirs = <Directory>[];
  Future<Directory> makeTempDir(String prefix) async {
    final dir = await Directory.systemTemp.createTemp(prefix);
    tempDirs.add(dir);
    return dir;
  }

  tearDownAll(() async {
    // 数据库句柄可能延迟释放，容忍清理失败
    for (final dir in tempDirs) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // ignore
      }
    }
  });

  /// 构造旧版 v2 数据库：29 道菜 + 用户数据（v1→v2 迁移后的形态）。
  Future<String> createLegacyDatabase(Directory tempDir) async {
    final dbPath = '${tempDir.path}/canting_food.db';
    final database = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE categories (
              category_id TEXT PRIMARY KEY,
              category_name TEXT NOT NULL,
              json_data TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE dishes (
              dish_id TEXT PRIMARY KEY,
              dish_name TEXT NOT NULL,
              category TEXT NOT NULL,
              json_data TEXT NOT NULL,
              FOREIGN KEY (category) REFERENCES categories(category_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE user_profiles (
              id INTEGER PRIMARY KEY DEFAULT 1,
              gender TEXT NOT NULL,
              age INTEGER NOT NULL,
              height_cm REAL NOT NULL,
              weight_kg REAL NOT NULL,
              diet_goal TEXT NOT NULL,
              activity_level TEXT NOT NULL,
              breakfast_time TEXT NOT NULL,
              lunch_time TEXT NOT NULL,
              dinner_time TEXT NOT NULL,
              day_start_time TEXT NOT NULL,
              onboarding_completed INTEGER NOT NULL DEFAULT 0,
              daily_intake_json TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              CHECK (id = 1)
            )
          ''');
          await db.execute('''
            CREATE TABLE meal_records (
              id TEXT PRIMARY KEY,
              meal_time INTEGER NOT NULL,
              meal_type TEXT NOT NULL,
              record_json TEXT NOT NULL,
              note TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE pet_states (
              id INTEGER PRIMARY KEY DEFAULT 1,
              json_data TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              CHECK (id = 1)
            )
          ''');
          await db.execute('''
            CREATE TABLE user_custom_dishes (
              dish_id TEXT PRIMARY KEY,
              dish_name TEXT NOT NULL,
              category TEXT NOT NULL,
              json_data TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        },
      ),
    );

    final batch = database.batch();
    for (final dish in legacyDishes) {
      batch.insert('dishes', {
        'dish_id': dish['dish_id'],
        'dish_name': dish['dish_name'],
        'category': dish['category'],
        'json_data': jsonEncode(dish),
      });
    }
    final categoryIds = legacyDishes.map((d) => d['category'] as String).toSet();
    for (final categoryId in categoryIds) {
      batch.insert('categories', {
        'category_id': categoryId,
        'category_name': categoryId,
        'json_data': jsonEncode({'category_id': categoryId}),
      });
    }
    batch.insert('user_profiles', {
      'id': 1,
      'gender': 'male',
      'age': 30,
      'height_cm': 175.0,
      'weight_kg': 70.0,
      'diet_goal': 'balanced',
      'activity_level': 'moderate',
      'breakfast_time': '07:30',
      'lunch_time': '12:00',
      'dinner_time': '18:30',
      'day_start_time': '05:00',
      'onboarding_completed': 1,
      'created_at': 1700000000000,
      'updated_at': 1700000000000,
    });
    batch.insert('meal_records', {
      'id': 'legacy-meal-1',
      'meal_time': 1700000000000,
      'meal_type': 'lunch',
      'record_json': '{"dishes":[]}',
      'note': '旧备注',
      'created_at': 1700000000000,
      'updated_at': 1700000000000,
    });
    batch.insert('user_custom_dishes', {
      'dish_id': 'my_home_dish',
      'dish_name': '妈妈的拿手菜',
      'category': 'stir_fry',
      'json_data': '{"dish_id":"my_home_dish"}',
      'created_at': 1700000000000,
      'updated_at': 1700000000000,
    });
    await batch.commit(noResult: true);
    await database.close();
    return dbPath;
  }

  test('旧版 29 道库升级：菜数变为新库数量，用户数据无损', () async {
    final tempDir = await makeTempDir('canting_migration');
    final dbPath = await createLegacyDatabase(tempDir);

    final helper = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: dbPath,
    );
    await helper.initialize(seedData: newSeed);

    final dishes = await helper.getAllDishes();
    expect(dishes.length, newSeed.dishes.length, reason: '升级后菜数应等于新库');
    expect(dishes.length, greaterThanOrEqualTo(1000));

    // 旧菜获得新契约字段
    final hsmRice = await helper.getDishById('hsm_rice');
    expect(hsmRice, isNotNull);
    expect(hsmRice!.recommendable, isFalse);
    expect(hsmRice.qualityTags, contains('high_sodium'));
    expect(hsmRice.aliases, contains('黄焖鸡'));

    // 新菜已入库
    expect(await helper.getDishById('cola'), isNotNull);
    expect(await helper.getDishById('multigrain_rice'), isNotNull);

    // 用户数据无损
    final db = helper.database;
    expect(await db.query('meal_records'), hasLength(1));
    expect(
      (await db.query('user_custom_dishes')).single['dish_name'],
      '妈妈的拿手菜',
    );
    expect(
      (await db.query('user_profiles')).single['diet_goal'],
      'balanced',
    );

    // 种子版本已记录
    final meta = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: [DatabaseHelper.seedSchemaVersionKey],
    );
    expect(meta.single['value'], '2');

    await helper.close();
  });

  test('旧库独有的菜不删除；再次 initialize 不覆盖同版本数据', () async {
    final tempDir = await makeTempDir('canting_migration');
    final dbPath = await createLegacyDatabase(tempDir);

    final helper = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: dbPath,
    );
    await helper.initialize(seedData: newSeed);

    // 模拟旧库独有菜（新库无此 dish_id）：手动补插（完整旧格式 json）
    final db = helper.database;
    await db.insert('dishes', {
      'dish_id': 'old_only_dish',
      'dish_name': '旧库独有菜',
      'category': 'stir_fry',
      'json_data': jsonEncode({
        'dish_id': 'old_only_dish',
        'dish_name': '旧库独有菜',
        'aliases': <String>['独有菜'],
        'category': 'stir_fry',
        'portions_normal': {
          'grains': 0.0,
          'vegetables': 1.5,
          'fruits': 0.0,
          'protein': 0.5,
          'protein_soy': 0.0,
          'oil_base': 1.0,
        },
        'cooking_oil_ratio': 0.5,
        'oil_factor': 1.2,
        'sodium_level': 'mid',
        'search_keywords': <String>['独有菜'],
        'tags': <String>['lunch'],
      }),
    });

    // 用户改过一道菜的名字（json_data 与列同步改），再 initialize 不应被种子覆盖
    final row = (await db.query(
      'dishes',
      where: 'dish_id = ?',
      whereArgs: ['hsm_rice'],
    ))
        .single;
    final renamedJson =
        (jsonDecode(row['json_data']! as String) as Map).cast<String, dynamic>()
          ..['dish_name'] = '用户改过名';
    await db.update(
      'dishes',
      {'dish_name': '用户改过名', 'json_data': jsonEncode(renamedJson)},
      where: 'dish_id = ?',
      whereArgs: ['hsm_rice'],
    );

    await helper.initialize(seedData: newSeed);

    expect(await helper.getDishById('old_only_dish'), isNotNull,
        reason: '旧库独有菜应保留');
    expect((await helper.getDishById('hsm_rice'))?.name, '用户改过名',
        reason: '同版本重新打开不应覆盖用户数据');
    expect((await helper.getAllDishes()).length, newSeed.dishes.length + 1);

    await helper.close();
  });

  test('全新安装：空库走 replaceAll 并记录种子版本', () async {
    final tempDir = await makeTempDir('canting_fresh');

    final helper = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: '${tempDir.path}/fresh.db',
    );
    await helper.initialize(seedData: newSeed);

    expect((await helper.getAllDishes()).length, newSeed.dishes.length);
    final meta = await helper.database.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: [DatabaseHelper.seedSchemaVersionKey],
    );
    expect(meta.single['value'], '2');

    await helper.close();
  });

  test('meta 版本被清（模拟更老客户端）→ 触发重新同步且幂等', () async {
    final tempDir = await makeTempDir('canting_meta');

    final helper = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: '${tempDir.path}/meta.db',
    );
    await helper.initialize(seedData: newSeed);

    // 清掉 meta 行模拟无版本记录的库
    await helper.database
        .delete('app_meta', where: 'key = ?', whereArgs: ['seed_schema_version']);
    await helper.close();

    final helper2 = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: '${tempDir.path}/meta.db',
    );
    await helper2.initialize(seedData: newSeed);
    expect((await helper2.getAllDishes()).length, newSeed.dishes.length,
        reason: '重新同步后菜数不变（upsert 幂等）');
    expect(
      await helper2.database.query('user_custom_dishes'),
      isEmpty,
    );

    await helper2.close();
  });
}
