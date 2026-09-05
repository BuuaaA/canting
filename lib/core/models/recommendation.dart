class DishSuggestion {
  const DishSuggestion({
    required this.dishName,
    required this.searchKeyword,
    required this.primaryCategory,
    required this.oilLevel,
    this.slotCategory,
    this.servings,
    this.note,
  });

  final String dishName;
  final String searchKeyword;
  final String primaryCategory;

  /// Stable code: low, mid_high, high, or extreme.
  final String oilLevel;

  /// 本推荐要补的槽位分类（缺口来源）。展示层应使用 [primaryCategory]
  /// （菜品自身主导分类）；slotCategory 供仿真/测试按槽位换算食用量。
  final String? slotCategory;

  /// 推荐份数（贴合该类剩余缺口；null = 引擎未标注，展示层按常规份）。
  final double? servings;

  /// 份量/模式提示语（如「建议小份」「清淡模式：主食减量三成」）。
  final String? note;
}

class Recommendation {
  const Recommendation({
    required this.suggestedTime,
    required this.suggestedMealType,
    required this.primary,
    required this.alternatives,
    required this.reason,
    this.balanceMode = BalanceMode.routine,
    this.reasonCodes = const [],
    this.policyVersion = 'p3-v1',
  });

  final DateTime suggestedTime;
  final String suggestedMealType;
  final List<DishSuggestion> primary;
  final List<DishSuggestion> alternatives;
  final String reason;
  final List<String> reasonCodes;
  final String policyVersion;

  /// 本次推荐的平衡模式：routine（常规）/ light（清淡）。
  /// light 由 7 天滚动台账盈余激活，用于文案与测试断言。
  final String balanceMode;
}

/// 推荐平衡模式编码。
class BalanceMode {
  BalanceMode._();

  static const String routine = 'routine';
  static const String light = 'light';
}
