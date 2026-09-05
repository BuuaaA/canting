import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:canting/core_engine.dart';
import 'package:canting/core/local_food_matcher.dart';
import 'package:canting/core/models/local_food.dart';
import 'package:canting/data/local_food_repository.dart';
import 'package:canting/data/meal_repository.dart';
import 'package:canting/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory dir;
  late DatabaseHelper db;
  late AppState state;
  late FoodDatabase catalog;
  Future<void> open() async {
    db = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: '${dir.path}/test.db',
    );
    await db.initialize(seedData: catalog);
    state = AppState(databaseHelper: db);
    await state.loadFromDatabase();
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('p2-food-');
    catalog = FoodDatabase.fromJson(
      dishesJson: File('assets/data/dishes.json').readAsStringSync(),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
    await open();
  });
  tearDown(() async {
    state.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });
  MealDish confirmed({
    String brand = '品牌甲',
    String name = '青青糯山',
    String category = 'milk_tea',
    String preparation = 'unknown',
    OrderSpec spec = const OrderSpec(sugar: 'regular', cup: 'large'),
  }) => MealDish(
    name: name,
    contributionsKnown: false,
    food: FoodObservation(
      facts: FoodFacts(
        brand: brand,
        name: name,
        category: category,
        preparation: preparation,
      ),
      spec: spec,
      confirmed: true,
      confirmedAt: DateTime.now(),
    ),
  );
  Future<MealRecord> save(MealDish dish, String id) async {
    final meal = state.buildMealRecord(
      mealType: 'lunch',
      timestamp: DateTime.now(),
      dishes: [dish],
      mealId: id,
    );
    await state.saveMeal(meal);
    return meal;
  }

  test('unknown classification survives restart; explicit specs win; history immutable', () async {
    expect(
      state
          .resolveFood(const MealDish(name: '青青糯山'), brand: '品牌甲')
          .food!
          .decision,
      FoodDecision.manual,
    );
    await save(confirmed(), 'first');
    final before = (await db.database.query('meal_records'))
        .single['record_json'];
    state.dispose();
    await db.close();
    await open();
    final next = state.resolveFood(
      const MealDish(name: '青青糯山 无糖 小杯'),
      brand: '品牌甲',
    );
    expect(next.food!.facts.category, 'milk_tea');
    expect(next.food!.spec.sugar, 'none');
    expect(next.food!.spec.cup, 'small');
    expect(next.food!.suggestion!.sugar, 'regular');
    await save(
      confirmed(
        spec: const OrderSpec(sugar: 'none', cup: 'small'),
      ),
      'second',
    );
    expect(
      (await db.database.query(
        'meal_records',
        where: 'id = ?',
        whereArgs: ['first'],
      )).single['record_json'],
      before,
    );
    expect(state.localFoods.single.useCount, 2);
  });
  test('missing specs remain unknown; last order is suggestion only', () async {
    await save(confirmed(), 'first');
    final next = state.resolveFood(const MealDish(name: '青青糯山'), brand: '品牌甲');
    expect(next.food!.spec.sugar, 'unknown');
    expect(next.food!.spec.cup, 'unknown');
    expect(next.food!.confirmed, false);
  });
  test('brands and missing brand do not overwrite each other', () async {
    await save(confirmed(), 'a');
    for (final brand in ['', '品牌乙']) {
      final next = state.resolveFood(
        const MealDish(name: '青青糯山'),
        brand: brand,
      );
      expect(next.food!.decision, FoodDecision.candidate);
      expect(next.food!.facts.category, 'unknown');
    }
    await save(confirmed(brand: '品牌乙', category: 'coffee'), 'b');
    expect(state.localFoods.length, 2);
    expect(
      state
          .resolveFood(const MealDish(name: '青青糯山'), brand: '品牌甲')
          .food!
          .facts
          .category,
      'milk_tea',
    );
  });
  test('burger and dessert save with null contribution and no recommendation mutation', () async {
    final initial = await db.database.query('dishes');
    for (final pair in [('香辣鸡腿堡', 'burger'), ('巴斯克', 'dessert')]) {
      final meal = await save(
        confirmed(
          name: pair.$1,
          category: pair.$2,
          preparation: 'fried',
          spec: const OrderSpec(size: 'small'),
        ),
        pair.$1,
      );
      expect(meal.structureComplete, false);
      expect(meal.dishes.single.toJson()['portions'], isNull);
      expect(() => meal.dishes.single.portions, throwsStateError);
      expect(meal.toJson()['total_scope'], 'known_subtotal');
    }
    expect(await db.database.query('dishes'), initial);
    expect(await db.database.query('user_custom_dishes'), isEmpty);
  });
  test('cake dimensions never become eaten portion', () {
    final row = state.resolveFood(const MealDish(name: '奶油蛋糕30寸'));
    expect(row.food!.spec.size, 'unknown');
    expect(row.toJson()['portions'], isNull);
  });
  test(
    'mixed known and unknown preserves every row and known subtotal',
    () async {
      final meal = MealRecord(
        mealId: 'mixed',
        mealType: 'lunch',
        timestamp: DateTime.now(),
        dishes: [
          const MealDish(name: '米饭', portions: Portions(grains: 2)),
          state.resolveFood(const MealDish(name: '神秘商品')),
        ],
      );
      await state.saveMeal(meal);
      final restored = await MealRepository(database: () => db.database)
          .getMealById('mixed');
      expect(restored!.dishes.length, 2);
      expect(restored.structureComplete, false);
      expect(restored.portionsTotal.grains, 2);
      expect(restored.dishes.last.toJson()['portions'], isNull);
    },
  );
  test('memory edits and delete affect future only', () async {
    await save(confirmed(), 'meal');
    final before = await db.database.query('meal_records');
    final old = state.localFoods.single;
    await state.editLocalFood(
      old.facts.key,
      LocalFoodProfile(
        facts: FoodFacts(
          brand: old.facts.brand,
          name: old.facts.name,
          category: 'coffee',
        ),
        createdAt: old.createdAt,
        updatedAt: DateTime.now(),
        useCount: old.useCount,
        lastSpec: old.lastSpec,
      ),
    );
    expect(
      state
          .resolveFood(const MealDish(name: '青青糯山'), brand: '品牌甲')
          .food!
          .facts
          .category,
      'coffee',
    );
    await state.deleteLocalFood(old.facts.key);
    expect(state.localFoods, isEmpty);
    expect(await db.database.query('meal_records'), before);
    expect(
      state
          .resolveFood(const MealDish(name: '青青糯山'), brand: '品牌甲')
          .food!
          .decision,
      FoodDecision.manual,
    );
  });
  test('failed memory write rolls back meal and in-memory state', () async {
    await db.database.execute(
      "CREATE TRIGGER fail_profile BEFORE INSERT ON user_food_profiles BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    final pet = state.pet.toJson();
    await expectLater(
      save(confirmed(), 'failed'),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.database.query('meal_records'), isEmpty);
    expect(state.localFoods, isEmpty);
    expect(state.pet.toJson(), pet);
    expect(state.mealById('failed'), isNull);
  });
  test(
    'export includes all persisted meals after restart; clear is atomic',
    () async {
      await save(confirmed(), 'old');
      state.dispose();
      await db.close();
      await open();
      final exported = jsonDecode(await state.exportAllJson()) as Map;
      expect((exported['meal_records'] as List).length, 1);
      expect((exported['user_food_profiles'] as List).length, 1);
      await db.database.execute(
        "CREATE TRIGGER fail_clear BEFORE DELETE ON user_food_profiles BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(
        state.clearAllData(),
        throwsA(isA<DatabaseException>()),
      );
      expect((await db.database.query('meal_records')).length, 1);
      await db.database.execute('DROP TRIGGER fail_clear');
      await state.clearAllData();
      expect(state.localFoods, isEmpty);
      expect(await db.database.query('meal_records'), isEmpty);
      expect(await db.database.query('dishes'), isNotEmpty);
    },
  );
  test('v3 migration preserves historical JSON exactly', () async {
    await save(confirmed(), 'old');
    final before = await db.database.query('meal_records');
    await db.database.execute('DROP TABLE user_food_profiles');
    await db.database.setVersion(3);
    state.dispose();
    await db.close();
    await open();
    expect(await db.database.getVersion(), 4);
    expect(await db.database.query('meal_records'), before);
    expect(await LocalFoodRepository(() => db.database).all(), isEmpty);
  });
  test(
    'decision policy exact positive, fuzzy/keyword negative and empty boundary',
    () {
      final matcher = LocalFoodMatcher(DishMatcher(catalog), []);
      expect(
        matcher.resolve(const MealDish(name: '白斩鸡')).contributionsKnown,
        true,
      );
      expect(
        matcher.resolve(const MealDish(name: '黄闷鸡米饭')).food!.decision,
        FoodDecision.candidate,
      );
      expect(
        matcher.resolve(const MealDish(name: '招牌咖喱盖饭超值装')).food!.decision,
        FoodDecision.candidate,
      );
      expect(
        matcher.resolve(const MealDish(name: '')).food!.decision,
        FoodDecision.manual,
      );
      expect(
        matcher
            .resolve(const MealDish(name: '白斩鸡'), brand: '专属品牌')
            .food!
            .decision,
        FoodDecision.candidate,
      );
    },
  );
  test('known row portion edit rescales once while original snapshot remains unchanged', () {
    const original = MealDish(
      name: '白斩鸡',
      matchedDishId: 'white_cut_chicken',
      portions: Portions(protein: 2),
    );
    final small = original.copyWith(portionSize: 'small');
    expect(small.portions.protein, 1.6);
    expect(small.copyWith().portions.protein, 1.6);
    expect(
      small.copyWith(portionSize: 'large').portions.protein,
      closeTo(2.6, 1e-9),
    );
    expect(original.portions.protein, 2);
  });
}
