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

  /// 自定义菜的使用数据：使用次数 + 分量偏好。
  ///
  /// 存在 json_data 的扩展键里（StandardDish.fromJson 会忽略未知键，
  /// 不影响匹配引擎读取菜品本体）。
  static const _usageCountKey = 'usage_count';
  static const _preferredPortionKey = 'preferred_portion';

  /// 按菜名（归一化后精确匹配）查使用数据；没有记录返回 null。
  Future<CustomDishUsage?> getUsageByName(String dishName) async {
    final normalized = FoodDatabase.normalizeDishName(dishName);
    if (normalized.isEmpty) {
      return null;
    }
    final rows = await _database.query('user_custom_dishes');
    for (final row in rows) {
      if (FoodDatabase.normalizeDishName(row['dish_name']! as String) !=
          normalized) {
        continue;
      }
      final json =
          (jsonDecode(row['json_data']! as String) as Map)
              .cast<String, dynamic>();
      return CustomDishUsage(
        dish: StandardDish.fromJson(json),
        usageCount: (json[_usageCountKey] as num?)?.toInt() ?? 0,
        preferredPortion: json[_preferredPortionKey] as String?,
      );
    }
    return null;
  }

  /// 归一化菜名 → 使用次数，供搜索排序用。
  Future<Map<String, int>> usageCountsByName() async {
    final rows = await _database.query(
      'user_custom_dishes',
      columns: ['dish_name', 'json_data'],
    );
    return {
      for (final row in rows)
        FoodDatabase.normalizeDishName(row['dish_name']! as String):
            ((jsonDecode(row['json_data']! as String)
                        as Map)[_usageCountKey] as num?)
                ?.toInt() ??
            0,
    };
  }

  /// 写入/更新自定义菜本体，同时把使用次数与分量偏好写进 json_data
  /// 扩展键。category 必须存在于 categories 表（与 [upsertDish] 同约束）。
  Future<void> upsertDishWithMeta(
    StandardDish dish, {
    required int usageCount,
    String? preferredPortion,
  }) async {
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
        'json_data': jsonEncode({
          ...dish.toJson(),
          _usageCountKey: usageCount,
          _preferredPortionKey: ?preferredPortion,
        }),
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static StandardDish _dishFromRow(Map<String, Object?> row) =>
      StandardDish.fromJson(
        (jsonDecode(row['json_data']! as String) as Map)
            .cast<String, dynamic>(),
      );
}

/// 一道自定义菜的使用数据（模块 15 数据飞轮的本地部分，纯本地不上传）。
class CustomDishUsage {
  const CustomDishUsage({
    required this.dish,
    required this.usageCount,
    this.preferredPortion,
  });

  final StandardDish dish;

  /// 被手动添加过的次数。
  final int usageCount;

  /// 用户最近一次使用的分量（small/normal/large），下次默认带出。
  final String? preferredPortion;
}
