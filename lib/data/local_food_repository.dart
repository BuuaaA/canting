import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/models/local_food.dart';

class LocalFoodRepository {
  LocalFoodRepository(this.database);
  final Database Function() database;
  Future<List<LocalFoodProfile>> all() async =>
      (await database().query('user_food_profiles', orderBy: 'match_key'))
          .map(
            (r) => LocalFoodProfile.fromJson(
              Map<String, dynamic>.from(
                jsonDecode(r['json_data'] as String) as Map,
              ),
            ),
          )
          .toList();
  static Future<void> remember(
    DatabaseExecutor txn,
    FoodObservation observation,
  ) async {
    if (!observation.confirmed || observation.facts.category == 'unknown') {
      return;
    }
    final rows = await txn.query(
      'user_food_profiles',
      where: 'match_key = ?',
      whereArgs: [observation.facts.key],
    );
    final prior = rows.isEmpty
        ? null
        : LocalFoodProfile.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(rows.single['json_data'] as String) as Map,
            ),
          );
    final now = DateTime.now();
    final profile = LocalFoodProfile(
      facts: observation.facts,
      createdAt: prior?.createdAt ?? now,
      updatedAt: now,
      useCount: (prior?.useCount ?? 0) + 1,
      lastSpec: observation.spec,
      rawNames: {
        ...?prior?.rawNames,
        if (observation.rawName.isNotEmpty) observation.rawName,
      }.toList(),
    );
    await txn.insert('user_food_profiles', {
      'match_key': profile.facts.key,
      'json_data': jsonEncode(profile.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> edit(String oldKey, LocalFoodProfile value) =>
      database().transaction((txn) async {
        if (oldKey != value.facts.key &&
            (await txn.query(
              'user_food_profiles',
              where: 'match_key = ?',
              whereArgs: [value.facts.key],
            )).isNotEmpty) {
          throw StateError('同品牌同名记忆已存在，请先编辑该记录');
        }
        await txn.delete(
          'user_food_profiles',
          where: 'match_key = ?',
          whereArgs: [oldKey],
        );
        await txn.insert('user_food_profiles', {
          'match_key': value.facts.key,
          'json_data': jsonEncode(value.toJson()),
        });
      });
  Future<void> delete(String key) async {
    await database().delete(
      'user_food_profiles',
      where: 'match_key = ?',
      whereArgs: [key],
    );
  }
}
