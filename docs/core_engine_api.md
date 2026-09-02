# 餐盘核心引擎公开接口

统一导入：

```dart
import 'package:canting/core_engine.dart';
```

## 固定字符串

- 性别：`male`、`female`
- 活动水平：`sedentary`、`light`、`moderate`、`heavy`
- 饮食目标：`balanced`、`more_veg`、`more_protein`、`less_carb`
- 餐次：`breakfast`、`lunch`、`dinner`、`snack`
- 分量：`small`、`normal`、`large`
- 营养类别：`grains`、`vegetables`、`fruits`、`protein`、`protein_soy`、`oil`
- 钠等级：`low`、`mid`、`high`
- 油脂等级：`low`（🟢低）、`mid_high`（🟡中高）、`high`（🔴高）、`extreme`（⚫极高）

## 计算与匹配

```dart
class IntakeCalculator {
  DailyIntake calculate({
    required String gender,
    required int heightCm,
    required double weightKg,
    required int age,
    required String activityLevel,
    required String dietGoal,
  });
}

class DishMatcher {
  const DishMatcher(FoodDatabase foodDatabase);

  final FoodDatabase foodDatabase;

  List<MatchResult> match(List<String> dishNames);
  Portions calculatePortions(MatchResult match, String portionSize);
}

class RecommendationEngine {
  const RecommendationEngine(FoodDatabase foodDatabase);

  final FoodDatabase foodDatabase;

  Recommendation recommend({
    required List<MealRecord> todayMeals,
    required DailyIntake dailyIntake,
    required DateTime now,
    required String lastMealType,
  });
}

class CompletionCalculator {
  CompletionResult calculate({
    required Portions eatenPortions,
    required DailyIntake dailyIntake,
    String sodiumLevel = 'mid',
  });
}
```

## 食物数据库

```dart
class FoodDatabase {
  FoodDatabase({
    required Iterable<StandardDish> dishes,
    required Iterable<FoodCategory> categories,
  });

  factory FoodDatabase.fromJson({
    required String dishesJson,
    required String categoriesJson,
  });

  List<StandardDish> get dishes;
  List<FoodCategory> get categories;

  StandardDish? findDishById(String id);
  FoodCategory? findCategoryById(String id);
  StandardDish? findExactDish(String name);
  FoodCategory? categoryForDish(StandardDish dish);
  List<StandardDish> search(String query);
  List<StandardDish> dishesForNutrient(String nutrient);

  static String normalizeDishName(String value);
}

class DatabaseHelper {
  DatabaseHelper({
    DatabaseFactory? factory,
    String? databasePath,
  });

  static const int databaseVersion;
  static const String defaultDatabaseName;

  final String? databasePath;
  bool get isOpen;

  Future<void> initialize({FoodDatabase? seedData});
  Future<FoodDatabase> loadFoodDatabase();
  Future<List<StandardDish>> getAllDishes();
  Future<List<FoodCategory>> getAllCategories();
  Future<StandardDish?> getDishById(String id);
  Future<List<StandardDish>> searchDishes(String query);
  Future<void> replaceAll(FoodDatabase data);
  Future<void> upsertCategory(FoodCategory category);
  Future<void> upsertDish(StandardDish dish);
  Future<bool> deleteDish(String id);
  Future<void> close();
}
```

`DatabaseFactory` 来自 `package:sqflite/sqflite.dart`。生产环境可省略；它主要用于测试时注入内存数据库。

## 数据模型

```dart
class Portions {
  const Portions({
    double grains = 0,
    double vegetables = 0,
    double fruits = 0,
    double protein = 0,
    double proteinSoy = 0,
    double oil = 0,
  });

  static const Portions zero;

  final double grains;
  final double vegetables;
  final double fruits;
  final double protein;
  final double proteinSoy;
  final double oil;

  factory Portions.fromJson(Map<String, dynamic> json);
  Map<String, double> toJson();
  Map<String, double> toDishJson();
  Map<String, double> get byCategory;
  double valueFor(String category);
  Portions scale(double factor);
  Portions operator +(Portions other);
}

class DailyIntake {
  const DailyIntake({
    required double grains,
    required double vegetables,
    required double fruits,
    required double protein,
    required double proteinSoy,
    required double oil,
    required double bmr,
    required double tdee,
  });

  final double grains;
  final double vegetables;
  final double fruits;
  final double protein;
  final double proteinSoy;
  final double oil;
  final double bmr;
  final double tdee;

  Portions get portions;
  Map<String, double> toJson();
}

enum MatchType { exact, fuzzy, keyword, unmatched }

class MatchResult {
  const MatchResult({
    required String inputName,
    required String? matchedDishId,
    required String matchedDishName,
    required double confidence,
    required MatchType matchType,
    required String category,
    required Portions portionsNormal,
  });

  final String inputName;
  final String? matchedDishId;
  final String matchedDishName;
  final double confidence;
  final MatchType matchType;
  final String category;
  final Portions portionsNormal;

  bool get isMatched;
  bool get shouldAutoAdd;
}

class MealDish {
  const MealDish({
    required String name,
    required double quantity,
    required String portionSize,
    required String? matchedDishId,
    required double matchConfidence,
    required Portions portions,
  });

  final String name;
  final double quantity;
  final String portionSize;
  final String? matchedDishId;
  final double matchConfidence;
  final Portions portions;

  factory MealDish.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}

class MealRecord {
  MealRecord({
    required String mealId,
    required String mealType,
    required DateTime timestamp,
    List<MealDish> dishes = const [],
    Portions? portionsTotal,
    double completionRate = 0,
    String sodiumLevel = 'mid',
  });

  final String mealId;
  final String mealType;
  final DateTime timestamp;
  final List<MealDish> dishes;
  final Portions portionsTotal;
  final double completionRate;
  final String sodiumLevel;

  factory MealRecord.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}

class FoodCategory {
  const FoodCategory({
    required String id,
    required String name,
    required String oilLevel,
    required double oilFactor,
    required Portions averagePortions,
    required List<String> keywords,
  });

  final String id;
  final String name;
  final String oilLevel;
  final double oilFactor;
  final Portions averagePortions;
  final List<String> keywords;

  factory FoodCategory.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}

class StandardDish {
  const StandardDish({
    required String id,
    required String name,
    required List<String> aliases,
    required String category,
    required Portions portionsNormal,
    required double cookingOilRatio,
    required double oilFactor,
    required String sodiumLevel,
    required List<String> searchKeywords,
    List<String> tags = const [],
  });

  final String id;
  final String name;
  final List<String> aliases;
  final String category;
  final Portions portionsNormal;
  final double cookingOilRatio;
  final double oilFactor;
  final String sodiumLevel;
  final List<String> searchKeywords;
  final List<String> tags;

  Portions get correctedPortions;
  factory StandardDish.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}

class Recommendation {
  const Recommendation({
    required DateTime suggestedTime,
    required String suggestedMealType,
    required List<DishSuggestion> primary,
    required List<DishSuggestion> alternatives,
    required String reason,
  });

  final DateTime suggestedTime;
  final String suggestedMealType;
  final List<DishSuggestion> primary;
  final List<DishSuggestion> alternatives;
  final String reason;
}

class DishSuggestion {
  const DishSuggestion({
    required String dishName,
    required String searchKeyword,
    required String primaryCategory,
    required String oilLevel,
  });

  final String dishName;
  final String searchKeyword;
  final String primaryCategory;
  final String oilLevel;
}

class CompletionResult {
  const CompletionResult({
    required double overall,
    required Map<String, double> byCategory,
    required String? biggestGap,
    required String sodiumLevel,
  });

  final double overall;
  final Map<String, double> byCategory;
  final String? biggestGap;
  final String sodiumLevel;
}
```
