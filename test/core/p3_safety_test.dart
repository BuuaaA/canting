import 'package:flutter_test/flutter_test.dart';
import 'package:canting/core/recommendation_safety.dart';
import 'package:canting/core/models/food_data.dart';
import 'package:canting/core/models/portions.dart';

StandardDish sample({
  String name = '米饭',
  List<String> tags = const [],
  bool recommendable = true,
  CandidateFacts? facts,
}) => StandardDish(
  id: 'sample',
  name: name,
  aliases: const [],
  category: 'grains',
  portionsNormal: const Portions(grains: 1),
  cookingOilRatio: 0,
  oilFactor: 1,
  sodiumLevel: 'low',
  searchKeywords: const [],
  qualityTags: tags,
  recommendable: recommendable,
  candidateFacts: facts,
);
const category = FoodCategory(
  id: 'grains',
  name: '主食',
  oilLevel: 'low',
  oilFactor: 1,
  averagePortions: Portions(grains: 1),
  keywords: [],
);
void main() {
  test('legacy low risk remains eligible without claiming review', () {
    final result = RecommendationSafety.evaluate(sample(), category);
    expect(result.eligibility, Eligibility.eligible);
    expect(result.reasonCodes, contains('legacy_low_risk'));
  });
  for (final tag in [
    'fried',
    'high_sodium',
    'high_oil',
    'high_sugar',
    'alcohol',
    'sugary_drink',
    'sugary',
  ]) {
    test('light cannot override $tag', () {
      expect(
        RecommendationSafety.evaluate(
          sample(tags: [tag, 'light']),
          category,
        ).eligibility,
        Eligibility.ineligible,
      );
    });
  }
  test('unknown recipe and negated fried are not invented facts', () {
    expect(
      RecommendationSafety.evaluate(
        sample(name: '非油炸汉堡'),
        category,
      ).eligibility,
      Eligibility.conditional,
    );
    expect(
      RecommendationSafety.evaluate(sample(name: '无糖奶茶'), category).eligibility,
      Eligibility.conditional,
    );
  });
  test(
    'exact sourced composition needs all facts and cannot override exclusion',
    () {
      const facts = CandidateFacts(
        identity: 'sample',
        source: 'test fixture only',
        nonFriedProtein: true,
        grains: true,
        vegetables: true,
        sauce: 'none',
      );
      expect(
        RecommendationSafety.evaluate(
          sample(name: '汉堡', facts: facts),
          category,
        ).eligibility,
        Eligibility.eligible,
      );
      expect(
        RecommendationSafety.evaluate(
          sample(name: '汉堡', facts: facts, tags: ['fried']),
          category,
        ).eligibility,
        Eligibility.ineligible,
      );
      expect(
        RecommendationSafety.evaluate(
          sample(
            name: '汉堡',
            facts: const CandidateFacts(
              identity: 'sample',
              source: 'test',
              nonFriedProtein: true,
              grains: true,
              sauce: 'none',
            ),
          ),
          category,
        ).eligibility,
        Eligibility.conditional,
      );
    },
  );
}
