import '../data/food_database.dart';
import 'models/food_data.dart';
import 'models/match_result.dart';
import 'models/portions.dart';

/// Maps OCR dish names to standard dishes or level-1 category averages.
///
/// 用户自定义菜品（user_custom_dishes 表）在每个匹配阶段都优先于标准菜库：
/// 同名时直接命中自定义，同分时模糊匹配也偏向自定义。
class DishMatcher {
  DishMatcher(this.foodDatabase, {List<StandardDish> customDishes = const []})
    : _customDishes = List.unmodifiable(customDishes) {
    _customNameIndex = {};
    for (final dish in _customDishes) {
      for (final name in [dish.name, ...dish.aliases]) {
        _customNameIndex.putIfAbsent(
          FoodDatabase.normalizeDishName(name),
          () => dish,
        );
      }
    }
  }

  final FoodDatabase foodDatabase;
  final List<StandardDish> _customDishes;
  late final Map<String, StandardDish> _customNameIndex;

  /// 包含匹配的固定置信度（模块文档定义）。
  static const _containsConfidence = 0.8;

  /// 浮点相似度比较用的容差。
  static const _epsilon = 0.000000001;

  List<StandardDish> get customDishes => _customDishes;

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

    // 1. 精确匹配：自定义菜优先，再查标准菜（含别名）。
    final customExact = _customNameIndex[normalizedInput];
    if (customExact != null) {
      return _dishResult(
        inputName: inputName,
        dish: customExact,
        confidence: 1,
        matchType: MatchType.exact,
      );
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

    // 2. 包含匹配 + 3. 模糊匹配：两条都算完，取证据更强的一方。
    //    置信度打平时（模糊相似度 = 0.8），菜名更长（更具体）的赢，
    //    例如「黄闷鸡米饭」（错字全名）优先于白米饭的别名「米饭」。
    final containsMatch = _findBestContains(normalizedInput);

    StandardDish? fuzzyDish;
    var fuzzySimilarity = 0.0;
    for (final dish in [..._customDishes, ...foodDatabase.dishes]) {
      for (final candidate in [dish.name, ...dish.aliases]) {
        final similarity = nameSimilarity(
          normalizedInput,
          FoodDatabase.normalizeDishName(candidate),
        );
        if (similarity > fuzzySimilarity) {
          fuzzySimilarity = similarity;
          fuzzyDish = dish;
        }
      }
    }
    final hasFuzzyMatch = fuzzyDish != null && fuzzySimilarity >= 0.7;

    if (hasFuzzyMatch) {
      final preferFuzzy =
          containsMatch == null ||
          fuzzySimilarity > _containsConfidence + _epsilon ||
          ((fuzzySimilarity - _containsConfidence).abs() < _epsilon &&
              fuzzyDish.name.runes.length > containsMatch.$2);
      if (preferFuzzy) {
        return _dishResult(
          inputName: inputName,
          dish: fuzzyDish,
          confidence: fuzzySimilarity,
          matchType: MatchType.fuzzy,
        );
      }
    }
    if (containsMatch != null) {
      return _dishResult(
        inputName: inputName,
        dish: containsMatch.$1,
        confidence: _containsConfidence,
        matchType: MatchType.contains,
      );
    }
    if (hasFuzzyMatch) {
      return _dishResult(
        inputName: inputName,
        dish: fuzzyDish,
        confidence: fuzzySimilarity,
        matchType: MatchType.fuzzy,
      );
    }

    // 4. 关键词归类兜底。
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

  /// 包含匹配：取被包含的**最长**候选（菜名/别名），自定义菜在等长时优先。
  /// 参与匹配的一词至少 2 个字，避免单字（如「鸡」）误命中大量菜品。
  /// 返回 (命中的菜品, 被包含候选的长度)。
  (StandardDish, int)? _findBestContains(String normalizedInput) {
    final inputLength = normalizedInput.runes.length;
    StandardDish? bestDish;
    var bestTermLength = 0;
    for (final dish in [..._customDishes, ...foodDatabase.dishes]) {
      for (final candidate in [dish.name, ...dish.aliases]) {
        final normalizedCandidate = FoodDatabase.normalizeDishName(candidate);
        final candidateLength = normalizedCandidate.runes.length;
        if (candidateLength < 2 || candidateLength <= bestTermLength) {
          continue;
        }
        if (normalizedInput.contains(normalizedCandidate) ||
            (inputLength >= 2 &&
                normalizedCandidate.contains(normalizedInput))) {
          bestDish = dish;
          bestTermLength = candidateLength;
        }
      }
    }
    if (bestDish == null) {
      return null;
    }
    return (bestDish, bestTermLength);
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

  static double nameSimilarity(String left, String right) {
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
