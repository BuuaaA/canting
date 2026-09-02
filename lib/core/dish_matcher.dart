import '../data/food_database.dart';
import 'models/food_data.dart';
import 'models/match_result.dart';
import 'models/portions.dart';

/// Maps OCR dish names to standard dishes or level-1 category averages.
class DishMatcher {
  const DishMatcher(this.foodDatabase);

  final FoodDatabase foodDatabase;

  List<MatchResult> match(List<String> dishNames) =>
      dishNames.map(_matchOne).toList(growable: false);

  Portions calculatePortions(MatchResult match, String portionSize) {
    final factor = switch (portionSize) {
      'small' => 0.8,
      'normal' => 1.0,
      'large' => 1.3,
      _ => throw ArgumentError.value(
        portionSize,
        'portionSize',
        'must be small, normal, or large',
      ),
    };
    return match.portionsNormal.scale(factor);
  }

  MatchResult _matchOne(String inputName) {
    final normalizedInput = FoodDatabase.normalizeDishName(inputName);
    if (normalizedInput.isEmpty) {
      return _unmatched(inputName);
    }

    final exactDish = foodDatabase.findExactDish(inputName);
    if (exactDish != null) {
      return _dishResult(
        inputName: inputName,
        dish: exactDish,
        confidence: 1,
        matchType: MatchType.exact,
      );
    }

    StandardDish? fuzzyDish;
    var highestSimilarity = 0.0;
    for (final dish in foodDatabase.dishes) {
      for (final candidate in [dish.name, ...dish.aliases]) {
        final similarity = _similarity(
          normalizedInput,
          FoodDatabase.normalizeDishName(candidate),
        );
        if (similarity > highestSimilarity) {
          highestSimilarity = similarity;
          fuzzyDish = dish;
        }
      }
    }
    if (fuzzyDish != null && highestSimilarity >= 0.7) {
      return _dishResult(
        inputName: inputName,
        dish: fuzzyDish,
        confidence: highestSimilarity,
        matchType: MatchType.fuzzy,
      );
    }

    FoodCategory? keywordCategory;
    var longestKeywordLength = 0;
    for (final category in foodDatabase.categories) {
      for (final keyword in category.keywords) {
        final normalizedKeyword = FoodDatabase.normalizeDishName(keyword);
        if (normalizedInput.contains(normalizedKeyword) &&
            normalizedKeyword.runes.length > longestKeywordLength) {
          keywordCategory = category;
          longestKeywordLength = normalizedKeyword.runes.length;
        }
      }
    }
    if (keywordCategory != null) {
      return MatchResult(
        inputName: inputName,
        matchedDishId: null,
        matchedDishName: keywordCategory.name,
        confidence: 0.5,
        matchType: MatchType.keyword,
        category: keywordCategory.id,
        portionsNormal: keywordCategory.averagePortions,
      );
    }

    return _unmatched(inputName);
  }

  static MatchResult _dishResult({
    required String inputName,
    required StandardDish dish,
    required double confidence,
    required MatchType matchType,
  }) => MatchResult(
    inputName: inputName,
    matchedDishId: dish.id,
    matchedDishName: dish.name,
    confidence: confidence,
    matchType: matchType,
    category: dish.category,
    portionsNormal: dish.correctedPortions,
  );

  static MatchResult _unmatched(String inputName) => MatchResult(
    inputName: inputName,
    matchedDishId: null,
    matchedDishName: '未识别',
    confidence: 0,
    matchType: MatchType.unmatched,
    category: 'unknown',
    portionsNormal: Portions.zero,
  );

  static double _similarity(String left, String right) {
    if (left == right) {
      return 1;
    }
    if (left.isEmpty || right.isEmpty) {
      return 0;
    }

    final leftRunes = left.runes.toList(growable: false);
    final rightRunes = right.runes.toList(growable: false);
    final previous = List<int>.generate(
      rightRunes.length + 1,
      (index) => index,
    );

    for (var leftIndex = 1; leftIndex <= leftRunes.length; leftIndex++) {
      var diagonal = previous[0];
      previous[0] = leftIndex;
      for (var rightIndex = 1; rightIndex <= rightRunes.length; rightIndex++) {
        final oldAbove = previous[rightIndex];
        final substitutionCost =
            leftRunes[leftIndex - 1] == rightRunes[rightIndex - 1] ? 0 : 1;
        previous[rightIndex] = _minimum(
          previous[rightIndex] + 1,
          previous[rightIndex - 1] + 1,
          diagonal + substitutionCost,
        );
        diagonal = oldAbove;
      }
    }

    final maxLength = leftRunes.length > rightRunes.length
        ? leftRunes.length
        : rightRunes.length;
    return 1 - previous.last / maxLength;
  }

  static int _minimum(int deletion, int insertion, int substitution) {
    var result = deletion < insertion ? deletion : insertion;
    if (substitution < result) {
      result = substitution;
    }
    return result;
  }
}
