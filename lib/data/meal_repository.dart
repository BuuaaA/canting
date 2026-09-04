import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core_engine.dart';

/// Reads and writes [MealRecord]s in the `meal_records` table.
///
/// Queryable columns (`meal_time`, `meal_type`) are stored alongside the full
/// record JSON so date filters never need to parse JSON.
class MealRepository {
  MealRepository({required Database Function() database})
    : _databaseGetter = database;

  final Database Function() _databaseGetter;

  Database get _database => _databaseGetter();

  /// All meals on the natural day containing [date], newest first.
  Future<List<MealRecord>> getMealsByDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    return getMealsByDateRange(start, start.add(const Duration(days: 1)));
  }

  /// Meals in `[start, end)`, newest first.
  Future<List<MealRecord>> getMealsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _database.query(
      'meal_records',
      where: 'meal_time >= ? AND meal_time < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'meal_time DESC',
    );
    return rows.map(_mealFromRow).toList(growable: false);
  }

  Future<MealRecord?> getMealById(String id) async {
    final rows = await _database.query(
      'meal_records',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _mealFromRow(rows.single);
  }

  Future<void> addMeal(MealRecord meal, {String? note, String? source}) async {
    final now = DateTime.now();
    await _database.insert(
      'meal_records',
      _mealRow(meal, createdAt: now, updatedAt: now, note: note, source: source),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateMeal(MealRecord meal, {String? note}) async {
    await _database.update(
      'meal_records',
      _mealRow(meal, createdAt: null, updatedAt: DateTime.now(), note: note),
      where: 'id = ?',
      whereArgs: [meal.mealId],
    );
  }

  /// Reads the user note stored in the `note` column (not part of the
  /// module-to-module record JSON).
  Future<String?> getNote(String mealId) async {
    final rows = await _database.query(
      'meal_records',
      columns: ['note'],
      where: 'id = ?',
      whereArgs: [mealId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['note'] as String?;
  }

  Future<void> deleteMeal(String mealId) async {
    await _database.delete(
      'meal_records',
      where: 'id = ?',
      whereArgs: [mealId],
    );
  }

  /// Removes every meal record (used by "清除数据").
  Future<void> deleteAllMeals() async {
    await _database.delete('meal_records');
  }

  MealRecord _mealFromRow(Map<String, Object?> row) =>
      MealRecord.fromJson(
        (jsonDecode(row['record_json']! as String) as Map)
            .cast<String, dynamic>(),
      );

  Map<String, Object?> _mealRow(
    MealRecord meal, {
    DateTime? createdAt,
    required DateTime updatedAt,
    String? note,
    String? source,
  }) {
    // source（ocr/manual/mixed）不属于模块间 JSON 格式，作为扩展键写进
    // record_json；MealRecord.fromJson 会忽略未知键，向后兼容。
    final recordJson = source == null || source.isEmpty
        ? jsonEncode(meal.toJson())
        : jsonEncode({...meal.toJson(), 'source': source});
    return {
      'id': meal.mealId,
      'meal_time': meal.timestamp.millisecondsSinceEpoch,
      'meal_type': meal.mealType,
      'record_json': recordJson,
      'note': note,
      if (createdAt != null) 'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }
}
