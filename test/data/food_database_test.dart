import 'dart:io';

import 'package:canting/data/food_database.dart';
import 'package:test/test.dart';

void main() {
  late FoodDatabase database;

  setUpAll(() {
    database = FoodDatabase.fromJson(
      dishesJson: File('assets/data/dishes.json').readAsStringSync(),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
  });

  group('FoodDatabase', () {
    test('loads the complete category taxonomy and at least 20 dishes', () {
      expect(database.categories, hasLength(15));
      expect(database.dishes.length, greaterThanOrEqualTo(20));
      expect(database.findDishById('hsm_rice')?.name, '黄焖鸡米饭');
    });

    test(
      'normalizes spaces, punctuation, and letter case for exact lookup',
      () {
        expect(database.findExactDish(' 黄焖鸡-米饭！ ')?.id, 'hsm_rice');
        expect(database.findExactDish('MILK TEA'), isNull);
      },
    );

    test('searches names, aliases, and takeaway keywords', () {
      expect(database.search('白斩鸡').single.id, 'white_cut_chicken');
      expect(
        database.search('鸡肉轻食').map((dish) => dish.id),
        contains('chicken_breast_salad'),
      );
    });

    test('corrects only the cooking-oil share', () {
      final dish = database.findDishById('hsm_rice')!;

      // 1.6 * [1 + 0.55 * (1.8 - 1)] = 2.304.
      expect(dish.correctedPortions.oil, closeTo(2.304, 0.000001));
      expect(dish.correctedPortions.protein, dish.portionsNormal.protein);
    });

    test('sorts nutrient queries from largest contribution to smallest', () {
      final vegetableDishes = database.dishesForNutrient('vegetables');

      expect(vegetableDishes, isNotEmpty);
      expect(
        vegetableDishes.first.correctedPortions.vegetables,
        greaterThanOrEqualTo(vegetableDishes.last.correctedPortions.vegetables),
      );
    });

    test('rejects a dish that references an unknown category', () {
      const dishesJson = '''
      [{
        "dish_id": "bad",
        "dish_name": "测试菜",
        "aliases": [],
        "category": "missing",
        "portions_normal": {
          "grains": 0,
          "vegetables": 1,
          "fruits": 0,
          "protein": 0,
          "protein_soy": 0,
          "oil_base": 0
        },
        "cooking_oil_ratio": 0,
        "oil_factor": 1,
        "sodium_level": "low",
        "search_keywords": [],
        "tags": []
      }]
      ''';

      expect(
        () => FoodDatabase.fromJson(
          dishesJson: dishesJson,
          categoriesJson: File('assets/data/categories.json')
              .readAsStringSync(),
        ),
        throwsFormatException,
      );
    });
  });
}
