import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DietaryGuidelines _guidelines() => DietaryGuidelines.fromJson(
  (jsonDecode(
        File('assets/data/dietary_guidelines.json').readAsStringSync(),
      )
      as Map)
      .cast<String, dynamic>(),
);

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
    createdAt: now,
    updatedAt: now,
  );
}

MealRecord _meal(String id, DateTime time, Portions portions) => MealRecord(
  mealId: id,
  mealType: 'lunch',
  timestamp: time,
  dishes: [MealDish(name: '测试菜', quantity: 1, portions: portions)],
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

  group('AppState.refreshPetVitality（模块 7 活力值）', () {
    test('最近 3 天吃得均衡 → 活力值按饮食质量重算', () async {
      final (state, helper) = await _buildState();
      addTearDown(helper.close);

      // 今天两餐各吃半份目标（单日按当天总量对目标评分），
      // 昨天一餐吃满目标 → 两天都全分类达标。
      const halfPortions = Portions(
        grains: 2.5,
        vegetables: 2,
        fruits: 1.25,
        protein: 2,
        proteinSoy: 0.5,
        oil: 1.25,
      );
      const fullPortions = Portions(
        grains: 5,
        vegetables: 4,
        fruits: 2.5,
        protein: 4,
        proteinSoy: 1,
        oil: 2.5,
      );
      await state.saveMeal(
        _meal('d1-1', DateTime(2026, 9, 4, 12), halfPortions),
      );
      await state.saveMeal(
        _meal('d1-2', DateTime(2026, 9, 4, 18, 30), halfPortions),
      );
      await state.saveMeal(
        _meal('d2-1', DateTime(2026, 9, 3, 12), fullPortions),
      );
      final growthBeforeRefresh = state.pet.growth;

      await state.refreshPetVitality(now: DateTime(2026, 9, 4, 20));

      // 两天有记录：100 与 100 的平均 → 100（钳制上限）。
      expect(state.pet.vitality, 100);
      // 成长值不受活力值刷新影响。
      expect(state.pet.growth, growthBeforeRefresh);
    });

    test('最近 3 天没有记录 → 活力值保持不变（交给离线衰减）', () async {
      final (state, helper) = await _buildState();
      addTearDown(helper.close);

      final before = state.pet.vitality;
      await state.refreshPetVitality(now: DateTime(2026, 9, 4, 20));

      expect(state.pet.vitality, before);
    });

    test('吃得很差的日子会拉低活力值', () async {
      final (state, helper) = await _buildState();
      addTearDown(helper.close);

      // 一天两餐但几乎没有份数 → 基础 60 分 + 5（满 2 餐）= 65。
      await state.saveMeal(
        _meal('bad-1', DateTime(2026, 9, 4, 12), Portions.zero),
      );
      await state.saveMeal(
        _meal('bad-2', DateTime(2026, 9, 4, 18, 30), Portions.zero),
      );
      final growthBeforeRefresh = state.pet.growth;

      await state.refreshPetVitality(now: DateTime(2026, 9, 4, 20));

      expect(state.pet.vitality, 65);
      // 成长值不受影响。
      expect(state.pet.growth, growthBeforeRefresh);
    });
  });
}
