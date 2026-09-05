import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/data/custom_dish_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseHelper helper;
  late FoodDatabase seed;
  late CustomDishRepository custom;
  setUp(() async {
    sqfliteFfiInit();
    seed = FoodDatabase.fromJson(
      dishesJson: File('assets/data/dishes.json').readAsStringSync(),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
    helper = DatabaseHelper(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
    await helper.initialize(seedData: seed);
    custom = CustomDishRepository(database: () => helper.database);
  });
  tearDown(() => helper.close());

  test('three search entry points preserve results and order across normalized input', () async {
    for (final dish in seed.dishes.take(12)) {
      await custom.upsertDish(dish);
    }
    // Frozen pre-refactor behavior, compared against all three public APIs.
    List<String> legacy(Iterable<StandardDish> dishes, String query) {
      final normalized = FoodDatabase.normalizeDishName(query);
      if (normalized.isEmpty) return [];
      return dishes
          .where(
            (dish) => [dish.name, ...dish.aliases, ...dish.searchKeywords]
                .map(FoodDatabase.normalizeDishName)
                .any(
                  (term) =>
                      term.contains(normalized) || normalized.contains(term),
                ),
          )
          .map((dish) => dish.id)
          .toList();
    }

    final standard = await helper.getAllDishes();
    final own = await custom.getAllDishes();
    for (final query in [
      '',
      ' ！？ ',
      '白斩鸡',
      '鸡肉轻食',
      ' MILK Tea ',
      '超长黄焖鸡米饭套餐',
      '米饭',
      '不存在的合成商品',
    ]) {
      expect(
        seed.search(query).map((dish) => dish.id),
        legacy(seed.dishes, query),
      );
      expect(
        (await helper.searchDishes(query)).map((dish) => dish.id),
        legacy(standard, query),
      );
      expect(
        (await custom.searchDishes(query)).map((dish) => dish.id),
        legacy(own, query),
      );
    }
    await helper.close();
    expect(await helper.searchDishes(' !!! '), isEmpty);
    expect(await custom.searchDishes(''), isEmpty);
  });

  test('shared custom writer preserves metadata omission replacement and validation', () async {
    final dish = seed.dishes.first;
    await custom.upsertDishWithMeta(
      dish,
      usageCount: 7,
      preferredPortion: 'large',
    );
    expect((await custom.getUsageByName(dish.name))!.usageCount, 7);
    expect((await custom.getUsageByName(dish.name))!.preferredPortion, 'large');
    await custom.upsertDishWithMeta(dish, usageCount: 8);
    expect((await custom.getUsageByName(dish.name))!.preferredPortion, isNull);
    await custom.upsertDish(dish);
    final rows = await helper.database.query('user_custom_dishes');
    expect(rows, hasLength(1));
    final json = jsonDecode(rows.single['json_data']! as String) as Map;
    expect(json.containsKey('usage_count'), false);
    expect(json.containsKey('preferred_portion'), false);
    expect((await custom.getUsageByName(dish.name))!.usageCount, 0);
    final invalid = StandardDish(
      id: 'invalid',
      name: '合成无分类',
      aliases: [],
      category: 'missing',
      portionsNormal: Portions.zero,
      cookingOilRatio: 0,
      oilFactor: 1,
      sodiumLevel: 'low',
      searchKeywords: [],
    );
    await expectLater(custom.upsertDish(invalid), throwsStateError);
    await expectLater(
      custom.upsertDishWithMeta(invalid, usageCount: 1),
      throwsStateError,
    );
    expect(await custom.getAllDishes(), hasLength(1));
  });

  test('portion category maps stay independent and retain all six values', () {
    const portions = Portions(
      grains: 1,
      vegetables: 2,
      fruits: 3,
      protein: 4,
      proteinSoy: 5,
      oil: 6,
    );
    final first = portions.byCategory;
    expect(first, portions.toJson());
    first['oil'] = 99;
    expect(portions.byCategory['oil'], 6);
    expect(portions.toDishJson()['oil_base'], 6);
  });
}
