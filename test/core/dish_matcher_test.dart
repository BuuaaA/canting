import 'dart:io';

import 'package:canting/core/dish_matcher.dart';
import 'package:canting/core/models/match_result.dart';
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

    test('uses Levenshtein similarity for OCR suffixes and minor errors', () {
      final result = matcher.match(['黄焖鸡米饭大份']).single;

      expect(result.matchedDishId, 'hsm_rice');
      expect(result.matchType, MatchType.fuzzy);
      expect(result.confidence, closeTo(5 / 7, 0.000001));
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
}
