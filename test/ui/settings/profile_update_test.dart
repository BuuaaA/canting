import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/ui/settings/profile_update.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _profile() {
  final now = DateTime(2026, 9, 1);
  return UserProfile(
    gender: 'female',
    age: 28,
    heightCm: 165,
    weightKg: 55,
    dietGoal: 'balanced',
    activityLevel: 'light',
    breakfastTime: '08:00',
    lunchTime: '12:00',
    dinnerTime: '18:30',
    dayStartTime: '01:00',
    onboardingCompleted: true,
    createdAt: now,
    updatedAt: now,
  );
}

DietaryGuidelines _guidelines() => DietaryGuidelines.fromJson(
  (jsonDecode(
        File('assets/data/dietary_guidelines.json').readAsStringSync(),
      )
      as Map)
      .cast<String, dynamic>(),
);

void main() {
  late DietaryGuidelines guidelines;

  setUpAll(() {
    guidelines = _guidelines();
  });

  group('ProfileUpdate.validate', () {
    test('接受正常范围的数值', () {
      expect(
        ProfileUpdate.validate(age: 28, heightCm: 165, weightKg: 55),
        isNull,
      );
    });

    test('拒绝超出范围的年龄、身高、体重', () {
      expect(
        ProfileUpdate.validate(age: 0, heightCm: 165, weightKg: 55),
        isNotNull,
      );
      expect(
        ProfileUpdate.validate(age: 28, heightCm: 10, weightKg: 55),
        isNotNull,
      );
      expect(
        ProfileUpdate.validate(age: 28, heightCm: 165, weightKg: 999),
        isNotNull,
      );
    });
  });

  group('ProfileUpdate.apply', () {
    test('保持未修改字段不变', () {
      final updated = ProfileUpdate.apply(
        current: _profile(),
        guidelines: guidelines,
        weightKg: 60,
      );

      expect(updated.gender, 'female');
      expect(updated.age, 28);
      expect(updated.heightCm, 165);
      expect(updated.weightKg, 60);
      expect(updated.activityLevel, 'light');
      expect(updated.dietGoal, 'balanced');
      expect(updated.breakfastTime, '08:00');
      expect(updated.onboardingCompleted, isTrue);
    });

    test('修改体重后用 IntakeCalculator 重算每日目标', () {
      final before = ProfileUpdate.apply(
        current: _profile(),
        guidelines: guidelines,
      );
      final after = ProfileUpdate.apply(
        current: _profile(),
        guidelines: guidelines,
        weightKg: 80,
      );

      // 体重增加 → BMR/TDEE 上升 → 主食目标上升。
      expect(after.dailyIntake!.bmr, greaterThan(before.dailyIntake!.bmr));
      expect(after.dailyIntake!.grains, greaterThan(before.dailyIntake!.grains));
    });

    test('切换饮食目标后目标份数按规则调整', () {
      final balanced = ProfileUpdate.apply(
        current: _profile(),
        guidelines: guidelines,
      );
      final moreVeg = ProfileUpdate.apply(
        current: _profile(),
        guidelines: guidelines,
        dietGoal: 'more_veg',
      );

      expect(moreVeg.dietGoal, 'more_veg');
      expect(
        moreVeg.dailyIntake!.vegetables,
        greaterThan(balanced.dailyIntake!.vegetables),
      );
    });

    test('更新 updatedAt 并保留 createdAt', () {
      final updated = ProfileUpdate.apply(
        current: _profile(),
        guidelines: guidelines,
      );

      expect(updated.createdAt, _profile().createdAt);
      expect(
        updated.updatedAt.isAfter(_profile().updatedAt),
        isTrue,
      );
    });
  });
}
