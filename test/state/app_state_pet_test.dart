import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/data/meal_repository.dart';
import 'package:canting/data/pet_repository.dart';
import 'package:canting/pet.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DietaryGuidelines _guidelines() => DietaryGuidelines.fromJson(
  (jsonDecode(
    File('assets/data/dietary_guidelines.json').readAsStringSync(),
  ) as Map).cast<String, dynamic>(),
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
  final state = AppState(databaseHelper: helper, guidelines: _guidelines());
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

  group('活力值口径抽查：删除回退 vs 3 天重算（模块 7 边界）', () {
    const fullPortions = Portions(
      grains: 5,
      vegetables: 4,
      fruits: 2.5,
      protein: 4,
      proteinSoy: 1,
      oil: 2.5,
    );

    MealRecord fullMeal(String id, DateTime time) => MealRecord(
      mealId: id,
      mealType: 'lunch',
      timestamp: time,
      dishes: const [
        MealDish(name: '测试菜', quantity: 1, portions: fullPortions),
      ],
      completionRate: 1,
    );

    test('clampVitality 钳制到引擎合法区间 [15, 100]', () {
      expect(PetStateMachine.clampVitality(6), 15);
      expect(PetStateMachine.clampVitality(15), 15);
      expect(PetStateMachine.clampVitality(60), 60);
      expect(PetStateMachine.clampVitality(100), 100);
      expect(PetStateMachine.clampVitality(120), 100);
    });

    test('删除回退不会把活力值打到合法下限以下（此前 [0,100] 钳制会越界崩溃）', () async {
      final (state, helper) = await _buildState();
      addTearDown(helper.close);

      final petRepo = PetRepository(database: () => helper.database);

      // completion=1.0 的记录落在 3 天窗口之外，避免启动重算改写活力值。
      final now = DateTime.now();
      final longAgo = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 10));
      await state.saveMeal(
        fullMeal('old-good', longAgo.add(const Duration(hours: 12))),
      );

      // 直接把活力值压到 16（模拟其它路径如离线衰减已经消耗掉余量），
      // 重新 loadFromDatabase 载入该状态（窗口内无记录 → 重算保持不变）。
      await petRepo.savePet(state.pet.copyWith(vitality: 16));
      final reloaded = AppState(
        databaseHelper: helper,
        guidelines: _guidelines(),
      );
      await reloaded.loadFromDatabase();
      expect(reloaded.pet.vitality, 16);

      // 删除已有实际 +10 凭证的记录：回退 -10。旧实现按 [0,100] 钳制
      // 会得到 6，PetData 构造器（合法区间 [15,100]）直接抛 RangeError。
      await reloaded.deleteMeal('old-good');

      expect(reloaded.pet.vitality, 15);
    });

    test('当天删除全部记录后，删除路径与 3 天重算收敛到同一值', () async {
      final (state, helper) = await _buildState();
      addTearDown(helper.close);

      final mealRepo = MealRepository(database: () => helper.database);
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final yesterday = todayStart.subtract(const Duration(days: 1));

      // 昨天一餐（直接落库，不动活力值）；今天两餐经记录路径各 +10。
      await mealRepo.addMeal(
        fullMeal('y-1', yesterday.add(const Duration(hours: 12))),
      );
      await state.saveMeal(
        fullMeal('t-1', todayStart.add(const Duration(hours: 12))),
      );
      await state.saveMeal(
        fullMeal('t-2', todayStart.add(const Duration(hours: 18, minutes: 30))),
      );
      expect(state.pet.vitality, 80);
      final growthBeforeDelete = state.pet.growth;

      await state.deleteMeal('t-1');
      await state.deleteMeal('t-2');

      // 窗口内只剩昨天（得分 100）→ 收敛到 100，而不是停在回退值 60。
      expect(state.pet.vitality, 100);
      // 成长值只增不减。
      expect(state.pet.growth, growthBeforeDelete);

      // 与「下次启动」的重算结果一致。
      final reloaded = AppState(
        databaseHelper: helper,
        guidelines: _guidelines(),
      );
      await reloaded.loadFromDatabase();
      expect(reloaded.pet.vitality, 100);
    });

    test('跨日删除昨天的记录后，同样收敛到重算口径', () async {
      final (state, helper) = await _buildState();
      addTearDown(helper.close);

      const halfPortions = Portions(
        grains: 2.5,
        vegetables: 2,
        fruits: 1.25,
        protein: 2,
        proteinSoy: 0.5,
        oil: 1.25,
      );
      MealRecord halfMeal(String id, DateTime time) => MealRecord(
        mealId: id,
        mealType: 'lunch',
        timestamp: time,
        dishes: [MealDish(name: '测试菜', quantity: 1, portions: halfPortions)],
        completionRate: 1,
      );

      final mealRepo = MealRepository(database: () => helper.database);
      final now = DateTime.now();
      final yesterday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1));
      // 两餐各半份 → 当日合计恰达目标（全分类达标，得分 100）。
      await mealRepo.addMeal(
        halfMeal('y-1', yesterday.add(const Duration(hours: 12))),
      );
      await mealRepo.addMeal(
        halfMeal('y-2', yesterday.add(const Duration(hours: 18, minutes: 30))),
      );

      // 模拟当天启动：重算把活力值拉到昨天的饮食质量 100。
      await state.refreshPetVitality();
      expect(state.pet.vitality, 100);

      // 删除昨天第一条：回退到 90 后立即重算——昨天只剩一餐（半份，
      // 全分类未达标 → 60），删除路径收敛到重算口径 60，
      // 与下次启动的重算结果一致。
      await state.deleteMeal('y-1');
      expect(state.pet.vitality, 60);

      final reloaded = AppState(
        databaseHelper: helper,
        guidelines: _guidelines(),
      );
      await reloaded.loadFromDatabase();
      expect(reloaded.pet.vitality, 60);
    });

    test('窗口内已无任何记录时，删除回退值保留（重算不改动）', () async {
      final (state, helper) = await _buildState();
      addTearDown(helper.close);

      // 只记今天一餐（+10 → 70），删掉后窗口内没有任何记录：
      // 重算按口径保持不变，停留在回退后的 60。
      await state.saveMeal(
        fullMeal(
          't-1',
          DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
            12,
          ),
        ),
      );
      expect(state.pet.vitality, 70);

      await state.deleteMeal('t-1');

      expect(state.pet.vitality, 60);
    });
  });
}
