import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/data/user_repository.dart';
import 'package:canting/pet.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

Future<(AppState, DatabaseHelper)> _buildState() async {
  sqfliteFfiInit();
  final helper = DatabaseHelper(
    factory: databaseFactoryFfiNoIsolate,
    databasePath: inMemoryDatabasePath,
  );
  await helper.initialize();
  final state = AppState(
    databaseHelper: helper,
    guidelines: _guidelines(),
  );
  await state.loadFromDatabase();
  await state.completeOnboarding(
    profile: _profile(),
    petType: 'cat',
    petName: '小挑食',
  );
  return (state, helper);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppState 个人设置（模块 10）', () {
    test('updateProfile 落库并可重新加载', () async {
      final (state, helper) = await _buildState();
      addTearDown(helper.close);

      final updated = state.profile!.copyWith(
        weightKg: 70,
        age: 30,
        updatedAt: DateTime(2026, 9, 2),
      );
      await state.updateProfile(updated);

      expect(state.profile!.weightKg, 70);
      expect(state.profile!.age, 30);
      expect(state.onboardingComplete, isTrue);

      final reloaded = await UserRepository(
        database: () => helper.database,
      ).getProfile();
      expect(reloaded!.weightKg, 70);
      expect(reloaded.age, 30);
    });

    test('clearAllData 清空记录、宠物、档案与自定义菜品', () async {
      final (state, helper) = await _buildState();
      addTearDown(helper.close);

      // 先制造一点数据。
      final db = helper.database;
      await db.insert('user_custom_dishes', {
        'dish_id': 'custom-1',
        'dish_name': '自制菜',
        'category': 'grain_tuber',
        'json_data': '{}',
        'created_at': 0,
        'updated_at': 0,
      });
      await state.saveMeal(
        MealRecord(
          mealId: 'meal-1',
          mealType: 'lunch',
          timestamp: DateTime(2026, 9, 2, 12),
        ),
      );

      await state.clearAllData();

      expect(state.profile, isNull);
      expect(state.onboardingComplete, isFalse);
      expect(state.pet.growth, 0);
      expect(state.pet.vitality, PetStateMachine.initialVitality);

      // 数据库层面确认清空。
      expect(
        (await db.query('meal_records')).length,
        0,
        reason: '餐食记录应被清空',
      );
      expect(
        (await db.query('pet_states')).length,
        0,
        reason: '宠物状态应被清空',
      );
      expect(
        (await db.query('user_profiles')).length,
        0,
        reason: '个人档案应被清空',
      );
      expect(
        (await db.query('user_custom_dishes')).length,
        0,
        reason: '自定义菜品应被清空',
      );
    });
  });

  group('AppState 通知开关落盘（shared_preferences 回调）', () {
    test('setMealReminder / setGapReminder 触发对应开关的持久化回调', () async {
      final (state, helper) = await _buildState();
      addTearDown(helper.close);

      final persisted = <({bool? mealReminder, bool? gapReminder})>[];
      state.persistNotificationSwitches = ({
        bool? mealReminder,
        bool? gapReminder,
      }) {
        persisted.add((mealReminder: mealReminder, gapReminder: gapReminder));
      };

      state.setMealReminder(true);
      state.setGapReminder(true);
      state.setMealReminder(false);

      expect(state.mealReminder, isFalse);
      expect(state.gapReminder, isTrue);
      expect(persisted, [
        (mealReminder: true, gapReminder: null),
        (mealReminder: null, gapReminder: true),
        (mealReminder: false, gapReminder: null),
      ]);
    });

    test('clearAllData 把两个提醒开关的关闭状态落盘', () async {
      final (state, helper) = await _buildState();
      addTearDown(helper.close);

      final persisted = <({bool? mealReminder, bool? gapReminder})>[];
      state.persistNotificationSwitches = ({
        bool? mealReminder,
        bool? gapReminder,
      }) {
        persisted.add((mealReminder: mealReminder, gapReminder: gapReminder));
      };

      state.setMealReminder(true);
      state.setGapReminder(true);
      persisted.clear();

      await state.clearAllData();

      expect(state.mealReminder, isFalse);
      expect(state.gapReminder, isFalse);
      expect(persisted, [(mealReminder: false, gapReminder: false)]);
    });
  });
}
