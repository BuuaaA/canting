import 'package:canting/core/models/daily_intake.dart';
import 'package:canting/core/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _sampleProfile() => UserProfile(
  gender: 'female',
  age: 28,
  heightCm: 165,
  weightKg: 55,
  dietGoal: 'balanced',
  activityLevel: 'light',
  breakfastTime: '07:30',
  lunchTime: '12:30',
  dinnerTime: '18:30',
  dayStartTime: '01:00',
  onboardingCompleted: true,
  dailyIntake: const DailyIntake(
    grains: 5,
    vegetables: 4,
    fruits: 2.5,
    protein: 4,
    proteinSoy: 1,
    oil: 2.5,
    bmr: 1450,
    tdee: 1740,
  ),
  createdAt: DateTime(2026, 9, 3, 8, 30),
  updatedAt: DateTime(2026, 9, 3, 9, 0),
);

void main() {
  group('UserProfile JSON round trip', () {
    test('preserves every field', () {
      final original = _sampleProfile();
      final restored = UserProfile.fromJson(original.toJson());

      expect(restored.gender, original.gender);
      expect(restored.age, original.age);
      expect(restored.heightCm, original.heightCm);
      expect(restored.weightKg, original.weightKg);
      expect(restored.dietGoal, original.dietGoal);
      expect(restored.activityLevel, original.activityLevel);
      expect(restored.breakfastTime, original.breakfastTime);
      expect(restored.lunchTime, original.lunchTime);
      expect(restored.dinnerTime, original.dinnerTime);
      expect(restored.dayStartTime, original.dayStartTime);
      expect(restored.onboardingCompleted, original.onboardingCompleted);
      expect(restored.dailyIntake!.grains, original.dailyIntake!.grains);
      expect(restored.dailyIntake!.vegetables, original.dailyIntake!.vegetables);
      expect(restored.dailyIntake!.fruits, original.dailyIntake!.fruits);
      expect(restored.dailyIntake!.protein, original.dailyIntake!.protein);
      expect(restored.dailyIntake!.proteinSoy, original.dailyIntake!.proteinSoy);
      expect(restored.dailyIntake!.oil, original.dailyIntake!.oil);
      expect(restored.dailyIntake!.bmr, original.dailyIntake!.bmr);
      expect(restored.dailyIntake!.tdee, original.dailyIntake!.tdee);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('round trips without the optional daily intake', () {
      final original = UserProfile(
        gender: 'female',
        age: 28,
        heightCm: 165,
        weightKg: 55,
        dietGoal: 'balanced',
        activityLevel: 'light',
        breakfastTime: '07:30',
        lunchTime: '12:30',
        dinnerTime: '18:30',
        dayStartTime: '01:00',
        onboardingCompleted: true,
        createdAt: DateTime(2026, 9, 3, 8, 30),
        updatedAt: DateTime(2026, 9, 3, 9, 0),
      );
      final restored = UserProfile.fromJson(original.toJson());

      expect(restored.dailyIntake, isNull);
      expect(restored.gender, original.gender);
    });

    test('onboardingCompleted survives as an int flag', () {
      final unfinished = _sampleProfile().copyWith(onboardingCompleted: false);
      final restored = UserProfile.fromJson(unfinished.toJson());
      expect(restored.onboardingCompleted, isFalse);
    });
  });
}
