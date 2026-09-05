import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/exposure.dart';
import '../core/record_window.dart';
import '../core/models/meal_record.dart';
import 'meal_repository.dart';

class ExposureRepository {
  ExposureRepository(this.database);
  final Database Function() database;
  static const prefix = 'p3.exposure.';
  Future<Map<String, dynamic>> preferences() async {
    final rows = await database().query(
      'app_meta',
      where: 'key = ?',
      whereArgs: ['${prefix}preferences'],
    );
    return rows.isEmpty
        ? {}
        : Map<String, dynamic>.from(
            jsonDecode(rows.single['value'] as String) as Map,
          );
  }

  Future<void> savePreferences(Map<String, dynamic> value) => database().insert(
    'app_meta',
    {'key': '${prefix}preferences', 'value': jsonEncode(value)},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  Future<void> clearPreferences() async {
    await database().delete(
      'app_meta',
      where: 'key = ?',
      whereArgs: ['${prefix}preferences'],
    );
  }

  Future<ExposurePrompt?> claim(MealRecord meal, DateTime now) async {
    if (localDay(meal.timestamp) != localDay(now)) return null;
    return database().transaction((txn) async {
      final key = '${prefix}shown.${meal.mealId}';
      if ((await txn.query(
        'app_meta',
        where: 'key = ?',
        whereArgs: [key],
      )).isNotEmpty) {
        return null;
      }
      // Claim before returning UI data. Restart may miss one prompt, never replay it.
      await txn.insert('app_meta', {
        'key': key,
        'value': now.toUtc().toIso8601String(),
      });
      final day = localDay(now);
      final meals = await MealRepository(database: () => txn)
          .getMealsByDateRange(
            DateTime(day.year, day.month, day.day - 6),
            DateTime(day.year, day.month, day.day + 1),
          );
      final rows = await txn.query(
        'app_meta',
        where: 'key = ?',
        whereArgs: ['${prefix}preferences'],
      );
      final prefs = rows.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(
              jsonDecode(rows.single['value'] as String) as Map,
            );
      final counts = Exposure.counts(meals);
      final previous = Exposure.counts(
        meals.where((m) => m.mealId != meal.mealId),
      );
      final active = <String, int>{};
      for (final family in Exposure.families(meal)) {
        final until = DateTime.tryParse(
          prefs['muted_$family'] as String? ?? '',
        );
        if (prefs['enabled'] != false &&
            (until == null || !now.isBefore(until)) &&
            (counts[family] ?? 0) >= 2 &&
            (previous[family] ?? 0) >= 1) {
          active[family] = counts[family]!;
        }
      }
      return active.isEmpty
          ? null
          : ExposurePrompt(
              meal.mealId,
              active,
              nextTimePreference: prefs['next_time_preference'] as String?,
            );
    });
  }
}
