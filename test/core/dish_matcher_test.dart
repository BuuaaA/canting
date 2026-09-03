import 'dart:io';

import 'package:canting/core/dish_matcher.dart';
import 'package:canting/core/models/food_data.dart';
import 'package:canting/core/models/match_result.dart';
import 'package:canting/core/models/portions.dart';
import 'package:canting/data/food_database.dart';
import 'package:test/test.dart';

void main() {
  late DishMatcher matcher;

  setUpAll(() {
    final database = FoodDatabase.fromJson(
      dishesJson: File('assets/data/dishes.json').readAsStringSync(),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
    matcher = DishMatcher(database);
  });

  group('DishMatcher', () {
    test('matches standard names and aliases exactly after normalization', () {
      final results = matcher.match([' 黄焖鸡-米饭！ ', '白斩鸡']);

      expect(results[0].matchedDishId, 'hsm_rice');
      expect(results[0].confidence, 1);
      expect(results[0].matchType, MatchType.exact);
      expect(results[1].matchedDishId, 'white_cut_chicken');
      expect(results[1].matchType, MatchType.exact);
    });

    test('uses contains matching for OCR suffix noise', () {
      final result = matcher.match(['黄焖鸡米饭大份']).single;

      expect(result.matchedDishId, 'hsm_rice');
      expect(result.matchType, MatchType.contains);
      expect(result.confidence, 0.8);
    });

    test('uses Levenshtein similarity for OCR typos', () {
      // 「焖」错写为「闷」，包含匹配不命中，落到模糊匹配。
      final result = matcher.match(['黄闷鸡米饭']).single;

      expect(result.matchedDishId, 'hsm_rice');
      expect(result.matchType, MatchType.fuzzy);
      expect(result.confidence, closeTo(0.8, 0.000001));
    });

    test('falls back to an L1 category average on a keyword match', () {
      final result = matcher.match(['招牌咖喱盖饭超值装']).single;

      expect(result.matchedDishId, isNull);
      expect(result.matchedDishName, '酱汁拌饭类');
      expect(result.category, 'rice_sauce');
      expect(result.matchType, MatchType.keyword);
      expect(result.confidence, 0.5);
      expect(result.shouldAutoAdd, isTrue);
    });

    test('marks unknown and blank inputs as unmatched', () {
      final results = matcher.match(['神秘料理', '...']);

      for (final result in results) {
        expect(result.matchedDishId, isNull);
        expect(result.matchType, MatchType.unmatched);
        expect(result.confidence, 0);
        expect(result.shouldAutoAdd, isFalse);
      }
    });

    test('applies portion-size factors to all corrected portions', () {
      final match = matcher.match(['黄焖鸡米饭']).single;
      final small = matcher.calculatePortions(match, 'small');
      final large = matcher.calculatePortions(match, 'large');

      expect(small.grains, closeTo(match.portionsNormal.grains * 0.8, 0.0001));
      expect(small.oil, closeTo(2.304 * 0.8, 0.0001));
      expect(
        large.protein,
        closeTo(match.portionsNormal.protein * 1.3, 0.0001),
      );
    });

    test('rejects an unsupported portion size', () {
      final match = matcher.match(['米饭']).single;

      expect(
        () => matcher.calculatePortions(match, 'extra_large'),
        throwsArgumentError,
      );
    });
  });

  group('DishMatcher with user custom dishes', () {
    late FoodDatabase database;

    setUpAll(() {
      database = FoodDatabase.fromJson(
        dishesJson: File('assets/data/dishes.json').readAsStringSync(),
        categoriesJson: File('assets/data/categories.json')
            .readAsStringSync(),
      );
    });

    StandardDish customDish({
      String id = 'custom_mama_pork',
      String name = '妈妈牌红烧肉',
      List<String> aliases = const ['妈妈的红烧肉'],
    }) => StandardDish(
      id: id,
      name: name,
      aliases: aliases,
      category: 'braised',
      portionsNormal: const Portions(grains: 0, vegetables: 0.1, protein: 2),
      cookingOilRatio: 0.3,
      oilFactor: 1.6,
      sodiumLevel: 'high',
      searchKeywords: const [],
    );

    test('a custom dish with the same name wins over the catalog', () {
      final matcher = DishMatcher(
        database,
        customDishes: [customDish(name: '红烧肉')],
      );
      final result = matcher.match(['红烧肉']).single;

      expect(result.matchedDishId, 'custom_mama_pork');
      expect(result.matchType, MatchType.exact);
      expect(result.confidence, 1);
      expect(result.matchedDishName, '红烧肉');
    });

    test('a custom dish is matched by its alias', () {
      final matcher = DishMatcher(database, customDishes: [customDish()]);
      final result = matcher.match(['妈妈的红烧肉']).single;

      expect(result.matchedDishId, 'custom_mama_pork');
      expect(result.matchType, MatchType.exact);
    });

    test('a custom dish wins contains matching with OCR suffix noise', () {
      final matcher = DishMatcher(database, customDishes: [customDish()]);
      final result = matcher.match(['妈妈牌红烧肉盖饭']).single;

      expect(result.matchedDishId, 'custom_mama_pork');
      expect(result.matchType, MatchType.contains);
      expect(result.confidence, 0.8);
    });

    test('a custom dish wins fuzzy matching on equal similarity', () {
      final matcher = DishMatcher(
        database,
        customDishes: [customDish(name: '黄焖鸡米饭')],
      );
      // 「黄闷鸡米饭」与自定义菜和标准菜距离相同，自定义优先。
      final result = matcher.match(['黄闷鸡米饭']).single;

      expect(result.matchedDishId, 'custom_mama_pork');
      expect(result.matchType, MatchType.fuzzy);
    });

    test('custom dishes do not interfere with keyword fallback', () {
      final matcher = DishMatcher(database, customDishes: [customDish()]);
      final result = matcher.match(['神秘料理']).single;

      expect(result.matchedDishId, isNull);
      expect(result.matchType, MatchType.unmatched);
    });

    test('a matcher without custom dishes still finds catalog dishes', () {
      final result = DishMatcher(database).match(['红烧肉']).single;

      expect(result.matchedDishId, isNot('custom_mama_pork'));
      expect(result.matchType, MatchType.exact);
    });
  });
}
