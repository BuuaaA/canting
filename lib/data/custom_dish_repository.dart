import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/models/food_data.dart';
import 'food_database.dart';

/// Reads and writes the user's own dishes in `user_custom_dishes`.
///
/// Kept separate from the standard catalog (`dishes`) so a catalog refresh
/// (replaceAll) never deletes user-created dishes.
class CustomDishRepository {
  CustomDishRepository({required Database Function() database})
    : _databaseGetter = database;

  final Database Function() _databaseGetter;

  Database get _database => _databaseGetter();

  Future<List<StandardDish>> getAllDishes() async {
    final rows = await _database.query(
      'user_custom_dishes',
      orderBy: 'dish_name COLLATE NOCASE',
    );
    return rows.map(_dishFromRow).toList(growable: false);
  }

  Future<StandardDish?> getDishById(String id) async {
    final rows = await _database.query(
      'user_custom_dishes',
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

  Future<void> upsertDish(StandardDish dish) async {
    final database = _database;
    final now = DateTime.now();
    final categoryRows = await database.query(
      'categories',
      columns: ['category_id'],
      where: 'category_id = ?',
      whereArgs: [dish.category],
      limit: 1,
    );
    if (categoryRows.isEmpty) {
      throw StateError(
        'Cannot save custom dish ${dish.id}: '
        'category ${dish.category} is missing',
      );
    }
    await database.insert(
      'user_custom_dishes',
      {
        'dish_id': dish.id,
        'dish_name': dish.name,
        'category': dish.category,
        'json_data': jsonEncode(dish.toJson()),
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> deleteDish(String id) async =>
      await _database.delete(
            'user_custom_dishes',
            where: 'dish_id = ?',
            whereArgs: [id],
          ) >
          0;

  static StandardDish _dishFromRow(Map<String, Object?> row) =>
      StandardDish.fromJson(
        (jsonDecode(row['json_data']! as String) as Map)
            .cast<String, dynamic>(),
      );
}
