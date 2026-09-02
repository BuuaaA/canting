class DishSuggestion {
  const DishSuggestion({
    required this.dishName,
    required this.searchKeyword,
    required this.primaryCategory,
    required this.oilLevel,
  });

  final String dishName;
  final String searchKeyword;
  final String primaryCategory;

  /// Stable code: low, mid_high, high, or extreme.
  final String oilLevel;
}

class Recommendation {
  const Recommendation({
    required this.suggestedTime,
    required this.suggestedMealType,
    required this.primary,
    required this.alternatives,
    required this.reason,
  });

  final DateTime suggestedTime;
  final String suggestedMealType;
  final List<DishSuggestion> primary;
  final List<DishSuggestion> alternatives;
  final String reason;
}
