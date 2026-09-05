import 'dart:convert';

import '../core/models/food_data.dart';
import '../core/models/food_knowledge.dart';

/// Immutable in-memory catalog of level-1 categories and level-2 dishes.
class FoodDatabase {
  FoodDatabase({
    required Iterable<StandardDish> dishes,
    required Iterable<FoodCategory> categories,
    this.schemaVersion = 1,
    this.knowledgePackage,
  }) : _dishes = List.unmodifiable(dishes),
       _categories = List.unmodifiable(categories) {
    _validate();
    _dishesById = {for (final dish in _dishes) dish.id: dish};
    _categoriesById = {
      for (final category in _categories) category.id: category,
    };
    _exactNameIndex = {};
    for (final dish in _dishes) {
      for (final name in [dish.name, ...dish.aliases]) {
        _exactNameIndex.putIfAbsent(normalizeDishName(name), () => dish);
      }
    }
  }

  /// Seed catalog schema version from dishes.json ("schema_version", default
  /// 1 for the legacy bare-array format). Drives database re-seeding.
  final int schemaVersion;
  final FoodKnowledgePackage? knowledgePackage;

  FoodKnowledge? findKnowledgeById(String id) => knowledgePackage?.findById(id);

  /// Knowledge remains separate from legacy point estimates and engine inputs.
  FoodDatabase withKnowledgePackage(FoodKnowledgePackage package) =>
      FoodDatabase(
        dishes: dishes,
        categories: categories,
        schemaVersion: schemaVersion,
        knowledgePackage: package,
      );

  factory FoodDatabase.fromJson({
    required String dishesJson,
    required String categoriesJson,
  }) {
    final dishRoot = jsonDecode(dishesJson);
    final categoryRoot = jsonDecode(categoriesJson);

    // Accept both the legacy bare array and the v2 envelope
    // {"schema_version": 2, "dishes": [...]}.
    final List<dynamic> dishList;
    var schemaVersion = 1;
    if (dishRoot is List) {
      dishList = dishRoot;
    } else if (dishRoot is Map) {
      final map = dishRoot.cast<String, dynamic>();
      schemaVersion = (map['schema_version'] as num?)?.toInt() ?? 1;
      final dishes = map['dishes'];
      if (dishes is! List) {
        throw const FormatException(
          'dishes JSON object must contain a "dishes" array',
        );
      }
      dishList = dishes;
    } else {
      throw const FormatException(
        'dishes JSON root must be an array or an object',
      );
    }

    if (categoryRoot is! List) {
      throw const FormatException('categories JSON root must be an array');
    }

    return FoodDatabase(
      dishes: dishList.map(
        (item) => StandardDish.fromJson((item as Map).cast<String, dynamic>()),
      ),
      categories: categoryRoot.map(
        (item) => FoodCategory.fromJson((item as Map).cast<String, dynamic>()),
      ),
      schemaVersion: schemaVersion,
    );
  }

  final List<StandardDish> _dishes;
  final List<FoodCategory> _categories;
  late final Map<String, StandardDish> _dishesById;
  late final Map<String, FoodCategory> _categoriesById;
  late final Map<String, StandardDish> _exactNameIndex;

  List<StandardDish> get dishes => _dishes;
  List<FoodCategory> get categories => _categories;

  StandardDish? findDishById(String id) => _dishesById[id];

  FoodCategory? findCategoryById(String id) => _categoriesById[id];

  StandardDish? findExactDish(String name) =>
      _exactNameIndex[normalizeDishName(name)];

  FoodCategory? categoryForDish(StandardDish dish) =>
      findCategoryById(dish.category);

  List<StandardDish> search(String query) {
    final normalizedQuery = normalizeDishName(query);
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    return _dishes
        .where((dish) {
          final terms = [
            dish.name,
            ...dish.aliases,
            ...dish.searchKeywords,
          ].map(normalizeDishName);
          return terms.any(
            (term) =>
                term.contains(normalizedQuery) ||
                normalizedQuery.contains(term),
          );
        })
        .toList(growable: false);
  }

  List<StandardDish> dishesForNutrient(String nutrient) {
    final matches =
        _dishes
            .where((dish) => dish.correctedPortions.valueFor(nutrient) > 0)
            .toList()
          ..sort(
            (left, right) => right.correctedPortions
                .valueFor(nutrient)
                .compareTo(left.correctedPortions.valueFor(nutrient)),
          );
    return List.unmodifiable(matches);
  }

  static String normalizeDishName(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[^\u3400-\u4dbf\u4e00-\u9fffa-z0-9]'), '');

  void _validate() {
    final categoryIds = <String>{};
    for (final category in _categories) {
      if (!categoryIds.add(category.id)) {
        throw FormatException('duplicate category_id: ${category.id}');
      }
      if (!const {
        'low',
        'mid_high',
        'high',
        'extreme',
      }.contains(category.oilLevel)) {
        throw FormatException(
          'invalid oil_level for category ${category.id}: '
          '${category.oilLevel}',
        );
      }
    }

    final dishIds = <String>{};
    for (final dish in _dishes) {
      if (!dishIds.add(dish.id)) {
        throw FormatException('duplicate dish_id: ${dish.id}');
      }
      if (!categoryIds.contains(dish.category)) {
        throw FormatException(
          'dish ${dish.id} references unknown category ${dish.category}',
        );
      }
      if (!const {'low', 'mid', 'high'}.contains(dish.sodiumLevel)) {
        throw FormatException(
          'invalid sodium_level for dish ${dish.id}: ${dish.sodiumLevel}',
        );
      }
      if (dish.oilFactor <= 0) {
        throw FormatException('oil_factor must be positive: ${dish.id}');
      }
    }
  }
}
