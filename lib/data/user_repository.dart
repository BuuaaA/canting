import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/models/daily_intake.dart';
import '../core/models/user_profile.dart';

/// Reads and writes the single-row [UserProfile] table.
class UserRepository {
  UserRepository({required Database Function() database})
    : _databaseGetter = database;

  final Database Function() _databaseGetter;

  Database get _database => _databaseGetter();

  Future<UserProfile?> getProfile() async {
    final rows = await _database.query(
      'user_profiles',
      limit: 1,
    );
    return rows.isEmpty ? null : _profileFromRow(rows.first);
  }

  Future<void> saveProfile(UserProfile profile) async {
    await _database.insert(
      'user_profiles',
      _profileRow(profile),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> hasCompletedOnboarding() async =>
      (await getProfile())?.onboardingCompleted ?? false;

  UserProfile _profileFromRow(Map<String, Object?> row) => UserProfile(
    gender: row['gender']! as String,
    age: (row['age']! as num).toInt(),
    heightCm: (row['height_cm']! as num).toDouble(),
    weightKg: (row['weight_kg']! as num).toDouble(),
    dietGoal: row['diet_goal']! as String,
    activityLevel: row['activity_level']! as String,
    breakfastTime: row['breakfast_time']! as String,
    lunchTime: row['lunch_time']! as String,
    dinnerTime: row['dinner_time']! as String,
    dayStartTime: row['day_start_time']! as String,
    onboardingCompleted: (row['onboarding_completed']! as num).toInt() != 0,
    dailyIntake: row['daily_intake_json'] == null
        ? null
        : DailyIntake.fromJson(
            (jsonDecode(row['daily_intake_json']! as String) as Map)
                .cast<String, dynamic>(),
          ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (row['created_at']! as num).toInt(),
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (row['updated_at']! as num).toInt(),
    ),
  );

  Map<String, Object?> _profileRow(UserProfile profile) {
    final json = profile.toJson();
    return {
      'id': 1,
      'gender': profile.gender,
      'age': profile.age,
      'height_cm': profile.heightCm,
      'weight_kg': profile.weightKg,
      'diet_goal': profile.dietGoal,
      'activity_level': profile.activityLevel,
      'breakfast_time': profile.breakfastTime,
      'lunch_time': profile.lunchTime,
      'dinner_time': profile.dinnerTime,
      'day_start_time': profile.dayStartTime,
      'onboarding_completed': profile.onboardingCompleted ? 1 : 0,
      'daily_intake_json': profile.dailyIntake == null
          ? null
          : jsonEncode(json['daily_intake']),
      'created_at': profile.createdAt.millisecondsSinceEpoch,
      'updated_at': profile.updatedAt.millisecondsSinceEpoch,
    };
  }
}
