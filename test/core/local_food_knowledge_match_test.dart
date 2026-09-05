import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:canting/core_engine.dart';
import 'package:canting/core/models/local_food.dart';
import 'package:canting/core/models/food_knowledge.dart';
import 'package:canting/core/local_food_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/food_knowledge_test.dart' show contractCases;

void main() {
  LocalFoodMatcher matcher() {
    final records = [
      for (final pair in [('none', 'small'), ('regular', 'large')])
        {
          ...Map<String, dynamic>.from(contractCases()[1]['record'] as Map),
          'canonical_id': pair.$1,
          'canonical_name': '合成咖啡',
          'semantic_category': 'beverage',
          'beverage_type': 'coffee',
          'sugar_level': pair.$1,
          'cup_size': pair.$2,
          'size_bucket': 'unknown',
          'eligibility': 'ineligible',
          'facts_complete': false,
        },
    ];
    final content = jsonEncode({'records': records});
    final package = FoodKnowledgePackage.fromJson({
      'schema_version': 2,
      'content_version': 'test-only',
      'content_json': content,
      'content_sha256': sha256.convert(utf8.encode(content)).toString(),
    });
    return LocalFoodMatcher(
      DishMatcher(
        FoodDatabase(dishes: [], categories: [], knowledgePackage: package),
      ),
      [],
    );
  }

  test('explicit exact specification selects variant and preserves interval source', () {
    final row = matcher().resolve(const MealDish(name: '合成咖啡 无糖 小杯'));
    expect(row.food!.matchedBy, 'knowledge_variant_exact');
    expect(row.food!.spec.sugar, 'none');
    expect(row.food!.knowledge!.id, 'none');
    expect(row.food!.knowledge!.contributions!['vegetables']!.max, 1);
    expect(row.contributionsKnown, false);
    final restored = MealDish.fromJson(row.toJson());
    expect(restored.food!.knowledge!.toJson(), row.food!.knowledge!.toJson());
    expect(restored.toJson()['portions'], isNull);
  });
  test('missing or contradictory specification does not choose a variant', () {
    for (final raw in ['合成咖啡', '合成咖啡 无糖 大杯', '合成咖啡 无糖 常规糖 小杯']) {
      final result = matcher().resolve(MealDish(name: raw));
      expect(result.food!.decision, FoodDecision.candidate);
      expect(result.food!.knowledge, isNull);
    }
  });
  test('a brand cannot silently consume an unbranded knowledge recipe', () {
    final result = matcher().resolve(
      const MealDish(name: '合成咖啡 无糖 小杯'),
      brand: '不同品牌',
    );
    expect(result.food!.knowledge, isNull);
    expect(result.contributionsKnown, false);
  });
  test('raw alias survives canonical rename and same-name brand conflict stays a candidate', () {
    final local = LocalFoodProfile(
      facts: const FoodFacts(brand: '甲', name: '纠正后的商品', category: 'milk_tea'),
      rawNames: const ['青青糯山'],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final match = LocalFoodMatcher(null, [local]);
    expect(
      match
          .resolve(const MealDish(name: '青青糯山 无糖 小杯'), brand: '甲')
          .food!
          .facts
          .name,
      '纠正后的商品',
    );
    expect(
      match.resolve(const MealDish(name: '纠正后的商品'), brand: '乙').food!.decision,
      FoodDecision.candidate,
    );
    expect(OrderSpec.parse('青青糯山 无糖 常规糖').sugar, 'unknown');
    final fuzzy = LocalFoodMatcher(null, [
      LocalFoodProfile(
        facts: const FoodFacts(brand: '甲', name: '青青糯山', category: 'milk_tea'),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ]);
    expect(
      fuzzy.resolve(const MealDish(name: '青責糯山'), brand: '乙').food!.decision,
      FoodDecision.candidate,
    );
  });
}
