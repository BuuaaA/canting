import 'portions.dart';

/// A level-1 takeaway-food category.
class FoodCategory {
  const FoodCategory({
    required this.id,
    required this.name,
    required this.oilLevel,
    required this.oilFactor,
    required this.averagePortions,
    required this.keywords,
  });

  final String id;
  final String name;

  /// Stable code: low, mid_high, high, or extreme.
  final String oilLevel;
  final double oilFactor;
  final Portions averagePortions;
  final List<String> keywords;

  factory FoodCategory.fromJson(Map<String, dynamic> json) => FoodCategory(
    id: json['category_id'] as String,
    name: json['category_name'] as String,
    oilLevel: json['oil_level'] as String,
    oilFactor: (json['oil_factor'] as num).toDouble(),
    averagePortions: Portions.fromJson(
      (json['average_portions'] as Map).cast<String, dynamic>(),
    ),
    keywords: List<String>.from(json['keywords'] as List),
  );

  Map<String, dynamic> toJson() => {
    'category_id': id,
    'category_name': name,
    'oil_level': oilLevel,
    'oil_factor': oilFactor,
    'average_portions': averagePortions.toJson(),
    'keywords': keywords,
  };
}

/// A level-2 standard dish loaded from the local seed database.
class StandardDish {
  const StandardDish({
    required this.id,
    required this.name,
    required this.aliases,
    required this.category,
    required this.portionsNormal,
    required this.cookingOilRatio,
    required this.oilFactor,
    required this.sodiumLevel,
    required this.searchKeywords,
    this.tags = const [],
  });

  final String id;
  final String name;
  final List<String> aliases;
  final String category;

  /// Raw portions before the takeaway cooking-oil correction.
  final Portions portionsNormal;
  final double cookingOilRatio;
  final double oilFactor;
  final String sodiumLevel;
  final List<String> searchKeywords;
  final List<String> tags;

  /// Corrects only cooking oil; intrinsic fat remains unchanged.
  Portions get correctedPortions {
    final correctedOil =
        portionsNormal.oil * (1 + cookingOilRatio * (oilFactor - 1));
    return Portions(
      grains: portionsNormal.grains,
      vegetables: portionsNormal.vegetables,
      fruits: portionsNormal.fruits,
      protein: portionsNormal.protein,
      proteinSoy: portionsNormal.proteinSoy,
      oil: correctedOil,
    );
  }

  factory StandardDish.fromJson(Map<String, dynamic> json) {
    final cookingOilRatio = (json['cooking_oil_ratio'] as num).toDouble();
    if (cookingOilRatio < 0 || cookingOilRatio > 1) {
      throw FormatException(
        'cooking_oil_ratio must be between 0 and 1: ${json['dish_id']}',
      );
    }

    return StandardDish(
      id: json['dish_id'] as String,
      name: json['dish_name'] as String,
      aliases: List<String>.from(json['aliases'] as List),
      category: json['category'] as String,
      portionsNormal: Portions.fromJson(
        (json['portions_normal'] as Map).cast<String, dynamic>(),
      ),
      cookingOilRatio: cookingOilRatio,
      oilFactor: (json['oil_factor'] as num).toDouble(),
      sodiumLevel: json['sodium_level'] as String,
      searchKeywords: List<String>.from(json['search_keywords'] as List),
      tags: List<String>.from(json['tags'] as List? ?? const []),
    );
  }

  Map<String, dynamic> toJson() => {
    'dish_id': id,
    'dish_name': name,
    'aliases': aliases,
    'category': category,
    'portions_normal': portionsNormal.toDishJson(),
    'cooking_oil_ratio': cookingOilRatio,
    'oil_factor': oilFactor,
    'sodium_level': sodiumLevel,
    'search_keywords': searchKeywords,
    'tags': tags,
  };
}
