import 'portions.dart';

enum MatchType { exact, contains, fuzzy, keyword, unmatched }

/// Result of mapping one OCR dish name to the local food taxonomy.
class MatchResult {
  const MatchResult({
    required this.inputName,
    required this.matchedDishId,
    required this.matchedDishName,
    required this.confidence,
    required this.matchType,
    required this.category,
    required this.portionsNormal,
  });

  final String inputName;
  final String? matchedDishId;
  final String matchedDishName;
  final double confidence;
  final MatchType matchType;
  final String category;

  /// Normal-size portions after cooking-oil correction.
  final Portions portionsNormal;

  bool get isMatched => matchedDishId != null || matchType == MatchType.keyword;
  bool get shouldAutoAdd => confidence >= 0.5;
}
