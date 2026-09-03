import 'package:canting/data/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Simulates the schema shipped before module 01: version 1 with only the
/// food-catalog tables and one seeded row.
Future<Database> _openLegacyV1Database(String path) async {
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE categories (
            category_id TEXT PRIMARY KEY,
            category_name TEXT NOT NULL,
            json_data TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE dishes (
            dish_id TEXT PRIMARY KEY,
            dish_name TEXT NOT NULL,
            category TEXT NOT NULL,
            json_data TEXT NOT NULL
          )
        ''');
        await database.insert('categories', {
          'category_id': 'fruit',
          'category_name': '水果',
          'json_data': '{}',
        });
        await database.insert('dishes', {
          'dish_id': 'legacy_dish',
          'dish_name': '老用户的水果',
          'category': 'fruit',
          'json_data': '{}',
        });
      },
    ),
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('migrates a v1 database to v2 without losing catalog rows', () async {
    final baseDirectory = await databaseFactoryFfi.getDatabasesPath();
    final legacyPath = '$baseDirectory/legacy_test.db';
    await databaseFactoryFfi.deleteDatabase(legacyPath);
    final legacy = await _openLegacyV1Database(legacyPath);
    await legacy.close();

    final helper = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: legacyPath,
    );
    addTearDown(helper.close);
    await helper.initialize();

    final database = helper.database;
    expect(await database.getVersion(), DatabaseHelper.databaseVersion);

    // Catalog rows survive the migration.
    final dishes = await database.query('dishes');
    expect(dishes.single['dish_id'], 'legacy_dish');

    // All user-data tables now exist.
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = tables.map((row) => row['name'] as String).toSet();
    expect(tableNames, containsAll([
      'user_profiles',
      'meal_records',
      'pet_states',
      'user_custom_dishes',
    ]));
    final indexes = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );
    final indexNames = indexes.map((row) => row['name'] as String).toSet();
    expect(indexNames, containsAll(['idx_meal_time', 'idx_custom_dishes_name']));
  });

  test('fresh installs create the full v2 schema directly', () async {
    final helper = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(helper.close);
    await helper.initialize();

    final database = helper.database;
    expect(await database.getVersion(), DatabaseHelper.databaseVersion);
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = tables.map((row) => row['name'] as String).toSet();
    expect(tableNames, containsAll([
      'categories',
      'dishes',
      'user_profiles',
      'meal_records',
      'pet_states',
      'user_custom_dishes',
    ]));
  });

  test('user_profiles holds at most one row (CHECK id = 1)', () async {
    final helper = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(helper.close);
    await helper.initialize();

    await helper.database.insert('user_profiles', {
      'id': 1,
      'gender': 'female',
      'age': 28,
      'height_cm': 165.0,
      'weight_kg': 55.0,
      'diet_goal': 'balanced',
      'activity_level': 'light',
      'breakfast_time': '08:00',
      'lunch_time': '12:00',
      'dinner_time': '18:30',
      'day_start_time': '01:00',
      'onboarding_completed': 1,
      'created_at': 0,
      'updated_at': 0,
    });

    expect(
      () => helper.database.insert('user_profiles', {
        'id': 2,
        'gender': 'male',
        'age': 30,
        'height_cm': 175.0,
        'weight_kg': 70.0,
        'diet_goal': 'balanced',
        'activity_level': 'light',
        'breakfast_time': '08:00',
        'lunch_time': '12:00',
        'dinner_time': '18:30',
        'day_start_time': '01:00',
        'onboarding_completed': 1,
        'created_at': 0,
        'updated_at': 0,
      }),
      throwsA(anything),
    );
  });
}
