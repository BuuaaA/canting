import 'dart:io';

import 'package:canting/core/models/food_data.dart';
import 'package:canting/core/models/portions.dart';
import 'package:canting/data/database_helper.dart';
import 'package:canting/data/food_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  late FoodDatabase seedData;
  late DatabaseHelper helper;

  setUpAll(() {
    sqfliteFfiInit();
    seedData = FoodDatabase.fromJson(
      dishesJson: File('assets/data/dishes.json').readAsStringSync(),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
  });

  setUp(() async {
    helper = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await helper.initialize(seedData: seedData);
  });

  tearDown(() => helper.close());

  group('DatabaseHelper', () {
    test('creates tables and imports seed data on first open', () async {
      expect(helper.isOpen, isTrue);
      expect(await helper.getAllCategories(), hasLength(15));
      expect((await helper.getAllDishes()).length, greaterThanOrEqualTo(20));

      final loaded = await helper.loadFoodDatabase();
      expect(loaded.findDishById('hsm_rice')?.name, '黄焖鸡米饭');
      expect(
        loaded.findDishById('hsm_rice')!.correctedPortions.oil,
        closeTo(2.304, 0.000001),
      );
    });

    test('does not overwrite existing rows when initialized again', () async {
      final original = (await helper.getDishById('hsm_rice'))!;
      final customized = StandardDish(
        id: original.id,
        name: '自定义黄焖鸡',
        aliases: original.aliases,
        category: original.category,
        portionsNormal: original.portionsNormal,
        cookingOilRatio: original.cookingOilRatio,
        oilFactor: original.oilFactor,
        sodiumLevel: original.sodiumLevel,
        searchKeywords: original.searchKeywords,
        tags: original.tags,
      );
      await helper.upsertDish(customized);

      await helper.initialize(seedData: seedData);

      expect((await helper.getDishById('hsm_rice'))?.name, '自定义黄焖鸡');
    });

    test('searches persisted aliases and keywords', () async {
      final aliasResults = await helper.searchDishes('白斩鸡');
      final keywordResults = await helper.searchDishes('鸡肉轻食');

      expect(aliasResults.single.id, 'white_cut_chicken');
      expect(
        keywordResults.map((dish) => dish.id),
        contains('chicken_breast_salad'),
      );
    });

    test('upserts and deletes a custom dish', () async {
      const customDish = StandardDish(
        id: 'apple_cup',
        name: '苹果果切',
        aliases: ['苹果切盘'],
        category: 'fruit',
        portionsNormal: Portions(fruits: 2),
        cookingOilRatio: 0,
        oilFactor: 1,
        sodiumLevel: 'low',
        searchKeywords: ['苹果', '果切'],
        tags: ['snack', 'fruits'],
      );

      await helper.upsertDish(customDish);
      expect((await helper.getDishById('apple_cup'))?.name, '苹果果切');
      expect(await helper.deleteDish('apple_cup'), isTrue);
      expect(await helper.getDishById('apple_cup'), isNull);
      expect(await helper.deleteDish('apple_cup'), isFalse);
    });

    test('rejects a dish whose category has not been saved', () async {
      const invalidDish = StandardDish(
        id: 'invalid',
        name: '无分类菜品',
        aliases: [],
        category: 'missing',
        portionsNormal: Portions.zero,
        cookingOilRatio: 0,
        oilFactor: 1,
        sodiumLevel: 'low',
        searchKeywords: [],
      );

      await expectLater(helper.upsertDish(invalidDish), throwsStateError);
    });

    test('requires initialization before any query', () async {
      final unopened = DatabaseHelper(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );

      await expectLater(unopened.getAllDishes(), throwsStateError);
    });
  });
}
