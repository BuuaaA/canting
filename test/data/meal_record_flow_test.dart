import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/data/meal_repository.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 模块 06 餐食记录的端到端数据流测试：
/// 分量系数 → 份数落库 → 完成度 → 删除回退。
///
/// 直接读 assets/data 下的真实数据文件（与核心测试同一套基准）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late DatabaseHelper helper;
  late AppState appState;
  late MealRepository mealRepo;
  late FoodDatabase foodDatabase;

  setUp(() async {
    final dishesJson = await File('assets/data/dishes.json').readAsString();
    final categoriesJson = await File(
      'assets/data/categories.json',
    ).readAsString();
    final guidelinesJson = await File(
      'assets/data/dietary_guidelines.json',
    ).readAsString();
    foodDatabase = FoodDatabase.fromJson(
      dishesJson: dishesJson,
      categoriesJson: categoriesJson,
    );

    helper = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await helper.initialize(
      seedData: FoodDatabase.fromJson(
        dishesJson: dishesJson,
        categoriesJson: categoriesJson,
      ),
    );
    mealRepo = MealRepository(database: () => helper.database);
    appState = AppState(
      databaseHelper: helper,
      guidelines: DietaryGuidelines.fromJson(
        (jsonDecode(guidelinesJson) as Map).cast<String, dynamic>(),
      ),
    );
    await appState.loadFromDatabase();
  });

  tearDown(() async {
    await helper.close();
  });

  group('buildMealRecord 分量系数', () {
    test('小份按 0.8 缩放标准份数', () {
      final expected = DishMatcher(
        foodDatabase,
      ).match(['黄焖鸡米饭']).single.portionsNormal;

      final meal = appState.buildMealRecord(
        mealType: 'lunch',
        timestamp: DateTime(2026, 9, 4, 12, 0),
        dishes: const [MealDish(name: '黄焖鸡米饭', portionSize: 'small')],
      );

      expect(meal.dishes.single.matchedDishId, 'hsm_rice');
      expect(meal.dishes.single.matchConfidence, 1);
      expect(meal.dishes.single.portions.grains, closeTo(expected.grains * 0.8, 1e-9));
      expect(meal.dishes.single.portions.protein, closeTo(expected.protein * 0.8, 1e-9));
      expect(meal.portionsTotal.grains, closeTo(expected.grains * 0.8, 1e-9));
    });

    test('大份按 1.3 缩放标准份数', () {
      final expected = DishMatcher(
        foodDatabase,
      ).match(['黄焖鸡米饭']).single.portionsNormal;

      final meal = appState.buildMealRecord(
        mealType: 'dinner',
        timestamp: DateTime(2026, 9, 4, 18, 30),
        dishes: const [MealDish(name: '黄焖鸡米饭', portionSize: 'large')],
      );

      expect(meal.portionsTotal.grains, closeTo(expected.grains * 1.3, 1e-9));
      expect(meal.portionsTotal.protein, closeTo(expected.protein * 1.3, 1e-9));
    });

    test('常规份保持标准份数，空菜名被过滤', () {
      final expected = DishMatcher(
        foodDatabase,
      ).match(['黄焖鸡米饭']).single.portionsNormal;

      final meal = appState.buildMealRecord(
        mealType: 'lunch',
        timestamp: DateTime(2026, 9, 4, 12, 0),
        dishes: const [
          MealDish(name: '黄焖鸡米饭'),
          MealDish(name: '  '),
        ],
      );

      expect(meal.dishes, hasLength(1));
      expect(meal.portionsTotal.grains, closeTo(expected.grains, 1e-9));
    });

    test('已带份数的菜（手填）不被匹配结果覆盖', () {
      const manualPortions = Portions(grains: 3, vegetables: 2);

      final meal = appState.buildMealRecord(
        mealType: 'lunch',
        timestamp: DateTime(2026, 9, 4, 12, 0),
        dishes: const [
          MealDish(name: '妈妈牌杂粮饭', portions: manualPortions),
        ],
      );

      expect(meal.portionsTotal.grains, 3);
      expect(meal.portionsTotal.vegetables, 2);
    });
  });

  group('buildMealRecord 完成度', () {
    test('完成度来自当日真实结构，介于 0 和 1 之间', () {
      final meal = appState.buildMealRecord(
        mealType: 'lunch',
        timestamp: DateTime(2026, 9, 4, 12, 0),
        dishes: const [MealDish(name: '黄焖鸡米饭')],
      );

      final expectedDayEaten = meal.portionsTotal;
      final expected = CompletionCalculator()
          .calculate(
            eatenPortions: expectedDayEaten,
            dailyIntake: appState.dailyIntake,
          )
          .overall;
      expect(meal.completionRate, closeTo(expected, 1e-9));
      expect(meal.completionRate, greaterThan(0));
      expect(meal.completionRate, lessThanOrEqualTo(1));
    });
  });

  group('保存与删除联动', () {
    MealRecord meal(
      String id, {
      required DateTime time,
      double completionRate = 0.85,
    }) => MealRecord(
      mealId: id,
      mealType: 'lunch',
      timestamp: time,
      dishes: const [MealDish(name: '黄焖鸡米饭', portionSize: 'normal')],
      completionRate: completionRate,
    );

    test('记录新餐后活力值上升，删除后按同一规则回退，成长值不回退', () async {
      final vitalityBefore = appState.pet.vitality;
      final growthBefore = appState.pet.growth;

      final record = meal('m1', time: DateTime(2026, 9, 4, 12, 0));
      await appState.saveMeal(record, source: 'manual');
      final vitalityAfterSave = appState.pet.vitality;
      final growthAfterSave = appState.pet.growth;

      // completionRate 0.85 ≥ 0.8 → 活力 +10，成长 +10。
      expect(vitalityAfterSave, vitalityBefore + 10);
      expect(growthAfterSave, growthBefore + 10);

      await appState.deleteMeal('m1');
      expect(appState.pet.vitality, vitalityBefore);
      expect(appState.pet.growth, growthAfterSave);
    });

    test('删除当日最后一条记录后当日结构归零', () async {
      await appState.saveMeal(
        meal('m1', time: DateTime(2026, 9, 4, 12, 0)),
      );
      expect(appState.mealsFor(DateTime(2026, 9, 4)), hasLength(1));

      await appState.deleteMeal('m1');

      expect(appState.mealsFor(DateTime(2026, 9, 4)), isEmpty);
      expect(await mealRepo.getMealsByDate(DateTime(2026, 9, 4)), isEmpty);
      expect(appState.completionFor(DateTime(2026, 9, 4)).overall, 0);
    });

    test('跨日期添加落在对应日期，不影响今天', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await appState.saveMeal(
        meal('m-old', time: DateTime(yesterday.year, yesterday.month, yesterday.day, 12, 0)),
      );

      final yesterdayMeals = appState.mealsFor(yesterday);
      expect(yesterdayMeals, hasLength(1));
      expect(yesterdayMeals.single.mealId, 'm-old');
      expect(await mealRepo.getMealsByDate(yesterday), hasLength(1));
      expect(appState.mealsFor(DateTime.now()), isEmpty);
    });

    test('同一餐重复添加两条记录互相独立', () async {
      final time = DateTime(2026, 9, 4, 12, 0);
      await appState.saveMeal(meal('m1', time: time));
      await appState.saveMeal(meal('m2', time: time));

      final dayMeals = await mealRepo.getMealsByDate(time);
      expect(dayMeals.map((m) => m.mealId), containsAll(['m1', 'm2']));
      expect(appState.mealsFor(time), hasLength(2));
    });

    test('备注和来源写入独立列，读回一致', () async {
      await appState.saveMeal(
        meal('m1', time: DateTime(2026, 9, 4, 12, 0)),
        note: '少油少盐',
        source: 'manual',
      );

      expect(await mealRepo.getNote('m1'), '少油少盐');
      final rows = await helper.database.query(
        'meal_records',
        where: 'id = ?',
        whereArgs: ['m1'],
        limit: 1,
      );
      final recordJson =
          (jsonDecode(rows.single['record_json']! as String) as Map)
              .cast<String, dynamic>();
      expect(recordJson['source'], 'manual');
      // 扩展键不影响模块间格式的读取。
      expect((await mealRepo.getMealById('m1'))!.mealId, 'm1');
    });
  });
}
