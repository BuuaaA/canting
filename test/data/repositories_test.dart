import 'package:canting/core/models/daily_intake.dart';
import 'package:canting/core/models/food_data.dart';
import 'package:canting/core/models/meal_record.dart';
import 'package:canting/core/models/portions.dart';
import 'package:canting/core/models/user_profile.dart';
import 'package:canting/data/custom_dish_repository.dart';
import 'package:canting/data/database_helper.dart';
import 'package:canting/data/meal_repository.dart';
import 'package:canting/data/pet_repository.dart';
import 'package:canting/data/user_repository.dart';
import 'package:canting/pet/pet_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DatabaseHelper helper;
  late UserRepository userRepo;
  late MealRepository mealRepo;
  late PetRepository petRepo;
  late CustomDishRepository customDishRepo;

  setUp(() async {
    helper = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await helper.initialize();
    userRepo = UserRepository(database: () => helper.database);
    mealRepo = MealRepository(database: () => helper.database);
    petRepo = PetRepository(database: () => helper.database);
    customDishRepo = CustomDishRepository(database: () => helper.database);
  });

  tearDown(() => helper.close());

  UserProfile sampleProfile() => UserProfile(
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
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 2),
  );

  group('UserRepository', () {
    test('returns null when no profile has been saved', () async {
      expect(await userRepo.getProfile(), isNull);
      expect(await userRepo.hasCompletedOnboarding(), isFalse);
    });

    test('saves and reloads the profile', () async {
      final profile = sampleProfile();
      await userRepo.saveProfile(profile);

      final loaded = await userRepo.getProfile();
      expect(loaded, isNotNull);
      expect(loaded!.gender, 'female');
      expect(loaded.heightCm, 165);
      expect(loaded.dailyIntake!.vegetables, 4);
      expect(loaded.onboardingCompleted, isTrue);
      expect(await userRepo.hasCompletedOnboarding(), isTrue);
    });

    test('overwrites instead of duplicating the single row', () async {
      await userRepo.saveProfile(sampleProfile());
      await userRepo.saveProfile(
        sampleProfile().copyWith(weightKg: 56, updatedAt: DateTime(2026, 9, 3)),
      );

      final loaded = await userRepo.getProfile();
      expect(loaded!.weightKg, 56);
      final rows = await helper.database.query('user_profiles');
      expect(rows, hasLength(1));
    });
  });

  group('MealRepository', () {
    MealRecord meal(
      String id, {
      required DateTime time,
      String type = 'lunch',
      String? merchant = '邻里小馆',
    }) => MealRecord(
      mealId: id,
      mealType: type,
      timestamp: time,
      merchant: merchant,
      dishes: [
        MealDish(name: '杂粮饭', quantity: 1, portionSize: 'normal'),
        MealDish(name: '清炒时蔬', quantity: 1, portionSize: 'small'),
      ],
      completionRate: 0.72,
    );

    test('returns nothing for an empty table', () async {
      expect(await mealRepo.getMealsByDate(DateTime(2026, 9, 3)), isEmpty);
    });

    test('adds and reads back a meal with dishes and merchant', () async {
      final record = meal('m1', time: DateTime(2026, 9, 3, 12, 18));
      await mealRepo.addMeal(record);

      final loaded = await mealRepo.getMealById('m1');
      expect(loaded, isNotNull);
      expect(loaded!.merchant, '邻里小馆');
      expect(loaded.mealType, 'lunch');
      expect(loaded.dishes.map((dish) => dish.name), ['杂粮饭', '清炒时蔬']);
      expect(loaded.dishes[1].portionSize, 'small');
      expect(loaded.completionRate, 0.72);
    });

    test('getMealsByDate filters to the natural day, newest first', () async {
      await mealRepo.addMeal(meal('a', time: DateTime(2026, 9, 3, 8, 0)));
      await mealRepo.addMeal(meal('b', time: DateTime(2026, 9, 3, 12, 0)));
      await mealRepo.addMeal(meal('c', time: DateTime(2026, 9, 2, 19, 0)));
      await mealRepo.addMeal(
        meal('d', time: DateTime(2026, 9, 3, 23, 59), type: 'snack'),
      );
      await mealRepo.addMeal(meal('e', time: DateTime(2026, 9, 4, 0, 30)));

      final sept3 = await mealRepo.getMealsByDate(DateTime(2026, 9, 3));
      expect(sept3.map((m) => m.mealId).toList(), ['d', 'b', 'a']);
    });

    test('getMealsByDateRange covers [start, end)', () async {
      await mealRepo.addMeal(meal('a', time: DateTime(2026, 9, 1, 8, 0)));
      await mealRepo.addMeal(meal('b', time: DateTime(2026, 9, 3, 8, 0)));
      await mealRepo.addMeal(meal('c', time: DateTime(2026, 9, 5, 8, 0)));

      final range = await mealRepo.getMealsByDateRange(
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 4),
      );
      expect(range.map((m) => m.mealId).toSet(), {'a', 'b'});
    });

    test('updateMeal rewrites the record in place', () async {
      await mealRepo.addMeal(meal('m1', time: DateTime(2026, 9, 3, 12, 0)));
      final original = (await mealRepo.getMealById('m1'))!;
      await mealRepo.updateMeal(
        MealRecord(
          mealId: original.mealId,
          mealType: original.mealType,
          timestamp: original.timestamp,
          merchant: original.merchant,
          dishes: const [MealDish(name: '低油版鸡胸肉沙拉')],
          completionRate: 0.9,
        ),
      );

      final loaded = await mealRepo.getMealById('m1');
      expect(loaded!.dishes.single.name, '低油版鸡胸肉沙拉');
      expect(loaded.completionRate, 0.9);
      expect(await mealRepo.getMealsByDate(DateTime(2026, 9, 3)), hasLength(1));
    });

    test('deleteMeal removes only the target row', () async {
      await mealRepo.addMeal(meal('a', time: DateTime(2026, 9, 3, 8, 0)));
      await mealRepo.addMeal(meal('b', time: DateTime(2026, 9, 3, 12, 0)));

      await mealRepo.deleteMeal('a');

      expect(await mealRepo.getMealById('a'), isNull);
      expect(await mealRepo.getMealsByDate(DateTime(2026, 9, 3)), hasLength(1));
    });

    test('deleteAllMeals clears the table', () async {
      await mealRepo.addMeal(meal('a', time: DateTime(2026, 9, 3, 8, 0)));
      await mealRepo.addMeal(meal('b', time: DateTime(2026, 9, 4, 8, 0)));

      await mealRepo.deleteAllMeals();

      expect(await mealRepo.getMealsByDateRange(DateTime(2026), DateTime(2027)), isEmpty);
    });
  });

  group('PetRepository', () {
    PetData pet() => PetData(
      petType: 'cat',
      petName: '小挑食',
      growthStage: GrowthStage.baby,
      vitality: 66,
      growth: 52,
      lastVitalityUpdate: DateTime(2026, 9, 3, 12, 0),
      createdAt: DateTime(2026, 9, 1),
      lastMealTime: DateTime(2026, 9, 3, 12, 0),
      petTapsToday: 2,
      todayMealCount: 1,
      todayCompletionRate: 0.72,
    );

    test('returns null before the pet exists', () async {
      expect(await petRepo.getPet(), isNull);
    });

    test('saves and restores every PetData field', () async {
      final original = pet();
      await petRepo.savePet(original);

      final loaded = await petRepo.getPet();
      expect(loaded, isNotNull);
      expect(loaded!.petType, 'cat');
      expect(loaded.petName, '小挑食');
      expect(loaded.growthStage, GrowthStage.baby);
      expect(loaded.vitality, 66);
      expect(loaded.growth, 52);
      expect(loaded.lastMealTime, original.lastMealTime);
      expect(loaded.petTapsToday, 2);
      expect(loaded.todayCompletionRate, 0.72);
    });

    test('savePet overwrites the single row', () async {
      await petRepo.savePet(pet());
      await petRepo.savePet(pet().copyWith(vitality: 70));

      final loaded = await petRepo.getPet();
      expect(loaded!.vitality, 70);
      final rows = await helper.database.query('pet_states');
      expect(rows, hasLength(1));
    });
  });

  group('CustomDishRepository', () {
    setUp(() async {
      // The custom-dish upsert validates that the category exists.
      await helper.database.insert('categories', {
        'category_id': 'fruit',
        'category_name': '水果',
        'json_data': '{}',
      });
    });

    StandardDish dish(String id, String name, {List<String> aliases = const []}) =>
        StandardDish(
          id: id,
          name: name,
          aliases: aliases,
          category: 'fruit',
          portionsNormal: const Portions(fruits: 2),
          cookingOilRatio: 0,
          oilFactor: 1,
          sodiumLevel: 'low',
          searchKeywords: [],
        );

    test('upserts, reads back, and deletes custom dishes', () async {
      await customDishRepo.upsertDish(dish('c1', '妈妈牌苹果果切', aliases: ['苹果切盘']));

      final loaded = await customDishRepo.getDishById('c1');
      expect(loaded, isNotNull);
      expect(loaded!.name, '妈妈牌苹果果切');
      expect(loaded.aliases, ['苹果切盘']);
      expect(loaded.category, 'fruit');
      expect(loaded.portionsNormal.fruits, 2);

      expect(await customDishRepo.deleteDish('c1'), isTrue);
      expect(await customDishRepo.getDishById('c1'), isNull);
      expect(await customDishRepo.deleteDish('c1'), isFalse);
    });

    test('upserting the same id replaces instead of duplicating', () async {
      await customDishRepo.upsertDish(dish('c1', '旧名字'));
      await customDishRepo.upsertDish(dish('c1', '新名字'));

      expect(await customDishRepo.getAllDishes(), hasLength(1));
      expect((await customDishRepo.getDishById('c1'))!.name, '新名字');
    });

    test('searches by name and alias', () async {
      await customDishRepo.upsertDish(dish('c1', '妈妈牌苹果果切', aliases: ['苹果切盘']));
      await customDishRepo.upsertDish(dish('c2', '无糖豆浆'));

      final byName = await customDishRepo.searchDishes('苹果果切');
      expect(byName.single.id, 'c1');
      final byAlias = await customDishRepo.searchDishes('苹果切盘');
      expect(byAlias.single.id, 'c1');
      expect(await customDishRepo.searchDishes('豆浆'), hasLength(1));
      expect(await customDishRepo.searchDishes('米饭'), isEmpty);
    });

    test('rejects a dish whose category does not exist', () async {
      final invalid = StandardDish(
        id: 'bad',
        name: '无分类菜品',
        aliases: [],
        category: 'missing',
        portionsNormal: Portions.zero,
        cookingOilRatio: 0,
        oilFactor: 1,
        sodiumLevel: 'low',
        searchKeywords: [],
      );

      await expectLater(customDishRepo.upsertDish(invalid), throwsStateError);
    });
  });
}
