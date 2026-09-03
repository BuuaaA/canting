import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../core/models/food_data.dart';
import 'food_database.dart';

/// Owns all SQLite operations for the local food catalog and user data.
class DatabaseHelper {
  DatabaseHelper({DatabaseFactory? factory, this.databasePath})
    : _factory = factory ?? databaseFactory,
      assert(databasePath == null || databasePath.isNotEmpty);

  /// Shared instance for the running app; tests build isolated copies instead.
  static final DatabaseHelper instance = DatabaseHelper();

  static const databaseVersion = 2;
  static const defaultDatabaseName = 'canting_food.db';

  final DatabaseFactory _factory;
  final String? databasePath;
  Database? _database;

  bool get isOpen => _database?.isOpen ?? false;

  /// The open database. Throws if [initialize] has not completed.
  Database get database => _requireDatabase();

  /// Opens the database and inserts [seedData] only when the dish table is empty.
  Future<void> initialize({FoodDatabase? seedData}) async {
    if (isOpen) {
      return;
    }

    final resolvedPath =
        databasePath ??
        path.join(await _factory.getDatabasesPath(), defaultDatabaseName);
    final database = await _factory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    _database = database;

    if (seedData != null && await _dishCount(database) == 0) {
      await replaceAll(seedData);
    }
  }

  Future<FoodDatabase> loadFoodDatabase() async => FoodDatabase(
    dishes: await getAllDishes(),
    categories: await getAllCategories(),
  );

  Future<List<StandardDish>> getAllDishes() async {
    final rows = await _requireDatabase().query(
      'dishes',
      orderBy: 'dish_name COLLATE NOCASE',
    );
    return rows.map(_dishFromRow).toList(growable: false);
  }

  Future<List<FoodCategory>> getAllCategories() async {
    final rows = await _requireDatabase().query(
      'categories',
      orderBy: 'category_id',
    );
    return rows.map(_categoryFromRow).toList(growable: false);
  }

  Future<StandardDish?> getDishById(String id) async {
    final rows = await _requireDatabase().query(
      'dishes',
      where: 'dish_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _dishFromRow(rows.single);
  }

  Future<List<StandardDish>> searchDishes(String query) async {
    final normalizedQuery = FoodDatabase.normalizeDishName(query);
    if (normalizedQuery.isEmpty) {
      return const [];
    }
    final dishes = await getAllDishes();
    return dishes
        .where((dish) {
          final terms = [
            dish.name,
            ...dish.aliases,
            ...dish.searchKeywords,
          ].map(FoodDatabase.normalizeDishName);
          return terms.any(
            (term) =>
                term.contains(normalizedQuery) ||
                normalizedQuery.contains(term),
          );
        })
        .toList(growable: false);
  }

  Future<void> replaceAll(FoodDatabase data) async {
    final database = _requireDatabase();
    await database.transaction((transaction) async {
      await transaction.delete('dishes');
      await transaction.delete('categories');

      final batch = transaction.batch();
      for (final category in data.categories) {
        batch.insert(
          'categories',
          _categoryRow(category),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final dish in data.dishes) {
        batch.insert(
          'dishes',
          _dishRow(dish),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsertCategory(FoodCategory category) async {
    await _requireDatabase().insert(
      'categories',
      _categoryRow(category),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertDish(StandardDish dish) async {
    final database = _requireDatabase();
    final categoryRows = await database.query(
      'categories',
      columns: ['category_id'],
      where: 'category_id = ?',
      whereArgs: [dish.category],
      limit: 1,
    );
    if (categoryRows.isEmpty) {
      throw StateError(
        'Cannot save dish ${dish.id}: category ${dish.category} is missing',
      );
    }
    await database.insert(
      'dishes',
      _dishRow(dish),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> deleteDish(String id) async =>
      await _requireDatabase().delete(
        'dishes',
        where: 'dish_id = ?',
        whereArgs: [id],
      ) >
      0;

  Future<void> close() async {
    final database = _database;
    _database = null;
    if (database != null && database.isOpen) {
      await database.close();
    }
  }

  /// Full schema for fresh installs; runs once when the database file is
  /// created. Must stay in sync with [_migrations].
  static Future<void> _createSchema(Database database, int version) async {
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
        json_data TEXT NOT NULL,
        FOREIGN KEY (category) REFERENCES categories(category_id)
      )
    ''');
    await database.execute(
      'CREATE INDEX dishes_category_idx ON dishes(category)',
    );
    await database.execute('CREATE INDEX dishes_name_idx ON dishes(dish_name)');
    await _createUserDataTables(database);
  }

  /// Incremental schema changes keyed by the version they migrate TO.
  /// To ship schema v3: bump [databaseVersion] and add `3: _migrateV2ToV3`.
  static final _migrations = <int, Future<void> Function(Database)>{
    2: _migrateV1ToV2,
  };

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    for (var version = oldVersion + 1; version <= newVersion; version++) {
      final migration = _migrations[version];
      if (migration != null) {
        await migration(database);
      }
    }
  }

  /// v1 shipped only the food catalog; v2 adds the user-data tables without
  /// touching existing rows.
  static Future<void> _migrateV1ToV2(Database database) async {
    await _createUserDataTables(database);
  }

  static Future<void> _createUserDataTables(Database database) async {
    await database.execute('''
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
    await database.execute('''
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
    await database.execute(
      'CREATE INDEX idx_meal_time ON meal_records(meal_time)',
    );
    await database.execute('''
      CREATE TABLE pet_states (
        id INTEGER PRIMARY KEY DEFAULT 1,
        json_data TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        CHECK (id = 1)
      )
    ''');
    await database.execute('''
      CREATE TABLE user_custom_dishes (
        dish_id TEXT PRIMARY KEY,
        dish_name TEXT NOT NULL,
        category TEXT NOT NULL,
        json_data TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX idx_custom_dishes_name ON user_custom_dishes(dish_name)',
    );
  }

  static Future<int> _dishCount(Database database) async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM dishes',
    );
    return (rows.single['count'] as num).toInt();
  }

  Database _requireDatabase() {
    final database = _database;
    if (database == null || !database.isOpen) {
      throw StateError('DatabaseHelper.initialize must be called first');
    }
    return database;
  }

  static Map<String, Object?> _dishRow(StandardDish dish) => {
    'dish_id': dish.id,
    'dish_name': dish.name,
    'category': dish.category,
    'json_data': jsonEncode(dish.toJson()),
  };

  static Map<String, Object?> _categoryRow(FoodCategory category) => {
    'category_id': category.id,
    'category_name': category.name,
    'json_data': jsonEncode(category.toJson()),
  };

  static StandardDish _dishFromRow(Map<String, Object?> row) =>
      StandardDish.fromJson(
        (jsonDecode(row['json_data']! as String) as Map)
            .cast<String, dynamic>(),
      );

  static FoodCategory _categoryFromRow(Map<String, Object?> row) =>
      FoodCategory.fromJson(
        (jsonDecode(row['json_data']! as String) as Map)
            .cast<String, dynamic>(),
      );
}
