import 'daily_intake.dart';

/// Single-user profile persisted in the `user_profiles` table (row id = 1).
class UserProfile {
  const UserProfile({
    required this.gender,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.dietGoal,
    required this.activityLevel,
    required this.breakfastTime,
    required this.lunchTime,
    required this.dinnerTime,
    required this.dayStartTime,
    required this.onboardingCompleted,
    required this.createdAt,
    required this.updatedAt,
    this.dailyIntake,
  });

  final String gender; // male / female
  final int age;
  final double heightCm;
  final double weightKg;
  final String dietGoal; // balanced / more_veg / more_protein / less_carb
  final String activityLevel; // sedentary / light / moderate / heavy

  /// Meal times as "HH:mm" strings, e.g. "07:30".
  final String breakfastTime;
  final String lunchTime;
  final String dinnerTime;

  /// The hour that starts a new day, e.g. "01:00".
  final String dayStartTime;

  final bool onboardingCompleted;

  /// Snapshot of the recommended daily intake at the time the profile was
  /// saved; null until first computed.
  final DailyIntake? dailyIntake;

  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile copyWith({
    String? gender,
    int? age,
    double? heightCm,
    double? weightKg,
    String? dietGoal,
    String? activityLevel,
    String? breakfastTime,
    String? lunchTime,
    String? dinnerTime,
    String? dayStartTime,
    bool? onboardingCompleted,
    DailyIntake? dailyIntake,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => UserProfile(
    gender: gender ?? this.gender,
    age: age ?? this.age,
    heightCm: heightCm ?? this.heightCm,
    weightKg: weightKg ?? this.weightKg,
    dietGoal: dietGoal ?? this.dietGoal,
    activityLevel: activityLevel ?? this.activityLevel,
    breakfastTime: breakfastTime ?? this.breakfastTime,
    lunchTime: lunchTime ?? this.lunchTime,
    dinnerTime: dinnerTime ?? this.dinnerTime,
    dayStartTime: dayStartTime ?? this.dayStartTime,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    dailyIntake: dailyIntake ?? this.dailyIntake,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    gender: json['gender'] as String,
    age: (json['age'] as num).toInt(),
    heightCm: (json['height_cm'] as num).toDouble(),
    weightKg: (json['weight_kg'] as num).toDouble(),
    dietGoal: json['diet_goal'] as String,
    activityLevel: json['activity_level'] as String,
    breakfastTime: json['breakfast_time'] as String,
    lunchTime: json['lunch_time'] as String,
    dinnerTime: json['dinner_time'] as String,
    dayStartTime: json['day_start_time'] as String,
    onboardingCompleted: (json['onboarding_completed'] as num?)!.toInt() != 0,
    dailyIntake: json['daily_intake'] == null
        ? null
        : DailyIntake.fromJson(
            (json['daily_intake'] as Map).cast<String, dynamic>(),
          ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated_at'] as int),
  );

  Map<String, dynamic> toJson() => {
    'gender': gender,
    'age': age,
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'diet_goal': dietGoal,
    'activity_level': activityLevel,
    'breakfast_time': breakfastTime,
    'lunch_time': lunchTime,
    'dinner_time': dinnerTime,
    'day_start_time': dayStartTime,
    'onboarding_completed': onboardingCompleted ? 1 : 0,
    if (dailyIntake != null) 'daily_intake': dailyIntake!.toJson(),
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };
}
