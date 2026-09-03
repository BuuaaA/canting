import 'package:canting/core_engine.dart';
import 'package:flutter/material.dart';

class OnboardingDraft {
  String gender = 'female';
  int heightCm = 165;
  double weightKg = 55;
  int age = 28;
  String activityLevel = 'light';
  String dietGoal = 'balanced';
  TimeOfDay breakfast = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay lunch = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay dinner = const TimeOfDay(hour: 18, minute: 30);
  int dayBoundaryHour = 1;
  String petType = 'cat';
  String petName = '小挑食';

  /// Builds the persisted profile, including the recommended daily intake
  /// snapshot computed from the draft values.
  ///
  /// [guidelines] 为膳食指南数据（main() 启动时从 JSON 加载），
  /// 目标份数按其中的能量档推荐表计算，不再硬编码。
  UserProfile toProfile({required DietaryGuidelines guidelines}) {
    final intake = IntakeCalculator().calculate(
      guidelines: guidelines,
      gender: gender,
      heightCm: heightCm,
      weightKg: weightKg,
      age: age,
      activityLevel: activityLevel,
      dietGoal: dietGoal,
    );
    return UserProfile(
      gender: gender,
      age: age,
      heightCm: heightCm.toDouble(),
      weightKg: weightKg,
      dietGoal: dietGoal,
      activityLevel: activityLevel,
      breakfastTime: _formatTime(breakfast),
      lunchTime: _formatTime(lunch),
      dinnerTime: _formatTime(dinner),
      dayStartTime: '${dayBoundaryHour.toString().padLeft(2, '0')}:00',
      onboardingCompleted: true,
      dailyIntake: intake,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  static String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}
