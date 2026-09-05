import 'models/food_knowledge.dart';
import 'models/food_data.dart';

enum Eligibility { eligible, conditional, ineligible }

/// Optional evidence for one exact built-in candidate. Never personal memory.
class CandidateFacts {
  const CandidateFacts({
    required this.identity,
    required this.source,
    this.nonFriedProtein,
    this.grains,
    this.vegetables,
    this.sauce = 'unknown',
  });
  final String identity, source, sauce;
  final bool? nonFriedProtein, grains, vegetables;
  Map<String, dynamic> toJson() => {
    'identity': identity,
    'source': source,
    'non_fried_protein': nonFriedProtein,
    'grains': grains,
    'vegetables': vegetables,
    'sauce': sauce,
  };
  factory CandidateFacts.fromJson(Map<String, dynamic> j) => CandidateFacts(
    identity: j['identity'] as String? ?? '',
    source: j['source'] as String? ?? '',
    nonFriedProtein: j['non_fried_protein'] as bool?,
    grains: j['grains'] as bool?,
    vegetables: j['vegetables'] as bool?,
    sauce: j['sauce'] as String? ?? 'unknown',
  );
  bool completeFor(String id) =>
      identity == id &&
      source.trim().isNotEmpty &&
      nonFriedProtein == true &&
      grains == true &&
      vegetables == true &&
      {'none', 'light'}.contains(sauce);
}

class EligibilityDecision {
  EligibilityDecision(
    this.eligibility,
    Iterable<String> reasons,
    Iterable<Map<String, String>> evidence,
  ) : reasonCodes = List.unmodifiable(reasons),
      evidenceRefs = List.unmodifiable(evidence);
  final Eligibility eligibility;
  final List<String> reasonCodes;
  final List<Map<String, String>> evidenceRefs;
  String get policyVersion => RecommendationSafety.version;
  Map<String, dynamic> toJson() => {
    'eligibility': eligibility.name,
    'reasonCodes': reasonCodes,
    'policyVersion': policyVersion,
    'evidenceRefs': evidenceRefs,
  };
}

class RecommendationSafety {
  static const version = 'p3-v1';
  static EligibilityDecision evaluate(
    StandardDish dish,
    FoodCategory? category, {
    FoodKnowledge? knowledgeOverride,
  }) {
    final excluded = <String>{};
    final pending = <String>{};
    final refs = <Map<String, String>>[];
    void evidence(String code, String field, String source) {
      refs.add({
        'reason': code,
        'field': field,
        'source': source,
        'identity': dish.id,
      });
    }

    void block(String code, String field, [String source = 'legacy_catalog']) {
      excluded.add(code);
      evidence(code, field, source);
    }

    void unknown(String code, String field) {
      pending.add(code);
      evidence(code, field, 'missing_or_proxy');
    }

    if (!dish.recommendable) block('not_recommendable', 'recommendable');
    final k = knowledgeOverride ?? dish.knowledge;
    if (k != null && k.id != dish.id) {
      unknown('identity_conflict', 'knowledge.canonical_id');
    }
    if (dish.knowledge != null &&
        knowledgeOverride != null &&
        dish.knowledge!.toJson().toString() !=
            knowledgeOverride.toJson().toString()) {
      unknown('source_conflict', 'attached_knowledge/knowledge_package');
    }
    final attached = dish.knowledge;
    if (attached?.preparation == 'fried') {
      block('fried', 'attached_knowledge.preparation', attached!.sourceType);
    }
    if (attached?.eligibility == 'ineligible') {
      block(
        'knowledge_ineligible',
        'attached_knowledge.eligibility',
        attached!.sourceType,
      );
    }
    if (attached?.productCategory == 'beverage' &&
        {'low', 'regular', 'high'}.contains(attached?.sugarLevel)) {
      block(
        'sugary_drink',
        'attached_knowledge.sugar_level',
        attached!.sourceType,
      );
    }
    final knowledge = k?.toJson();
    for (final source in <String, Iterable<dynamic>>{
      'quality_tags': dish.qualityTags,
      'tags': dish.tags,
      'knowledge.risk_tags': knowledge?['risk_tags'] as List? ?? [],
      'attached_knowledge.risk_tags':
          attached?.toJson()['risk_tags'] as List? ?? [],
    }.entries) {
      for (final tag in source.value) {
        if ({
          'fried',
          'high_oil',
          'high_sodium',
          'high_sugar',
          'alcohol',
          'sugary_drink',
          'sugary',
        }.contains(tag)) {
          block(
            tag == 'sugary' ? 'sugary_drink' : tag as String,
            source.key,
            source.key.startsWith('attached_knowledge')
                ? attached!.sourceType
                : source.key.startsWith('knowledge')
                ? k!.sourceType
                : 'legacy_catalog',
          );
        }
        if ({
          'unknown_preparation',
          'unknown_ingredients',
          'source_conflict',
        }.contains(tag)) {
          unknown(tag as String, source.key);
        }
      }
    }
    if (dish.category == 'fried' || k?.preparation == 'fried') {
      block('fried', 'category/preparation');
    }
    if (dish.sodiumLevel == 'high') block('high_sodium', 'sodium_level');
    if ({'high', 'extreme'}.contains(category?.oilLevel)) {
      block('high_oil', 'category.oil_level');
    }
    if (k?.productCategory == 'beverage' &&
        {'low', 'regular', 'high'}.contains(k?.sugarLevel)) {
      block('sugary_drink', 'knowledge.sugar_level');
    }
    if (k?.eligibility == 'ineligible') {
      block('knowledge_ineligible', 'knowledge.eligibility', k!.sourceType);
    }
    if (k != null && k.eligibility != 'eligible') {
      unknown('knowledge_not_eligible', 'knowledge.eligibility');
    }
    if (category == null ||
        !{'low', 'mid_high', 'high', 'extreme'}.contains(category.oilLevel) ||
        !{'low', 'mid', 'high'}.contains(dish.sodiumLevel) ||
        dish.correctedPortions.byCategory.values.any(
          (v) => !v.isFinite || v < 0,
        )) {
      unknown('invalid_candidate', 'category/portions/sodium');
    }
    // Bounded name proxies: do not interpret 非油炸 as affirmative fried.
    final name = dish.name.replaceAll(RegExp(r'非油炸|不油炸|无油炸'), '');
    if (RegExp(r'^(油炸|炸鸡|炸鱼|炸虾|炸猪|炸肉|炸薯|薯条|油条)|油炸$').hasMatch(name)) {
      block('fried', 'dish_name', 'legacy_name_proxy');
    }
    if (RegExp(
      r'^(啤酒|白酒|红酒|葡萄酒|威士忌|伏特加|鸡尾酒)(\s|$)|^(beer|wine)$',
      caseSensitive: false,
    ).hasMatch(name)) {
      block('alcohol', 'dish_name', 'legacy_name_proxy');
    }
    final combination =
        RegExp(
          r'汉堡|三明治|burger|sandwich',
          caseSensitive: false,
        ).hasMatch(dish.name) ||
        k?.productCategory == 'burger';
    if (combination) {
      if (dish.candidateFacts?.completeFor(dish.id) != true) {
        unknown('unknown_preparation', 'candidate_facts');
      } else {
        evidence(
          'confirmed_light_composition',
          'candidate_facts',
          dish.candidateFacts!.source,
        );
      }
    }
    if (RegExp(r'奶茶|咖啡|可乐|汽水|果汁|饮料').hasMatch(dish.name) &&
        k?.eligibility != 'eligible') {
      unknown('unknown_ingredients', 'beverage_recipe');
    }
    if (excluded.isNotEmpty) {
      return EligibilityDecision(Eligibility.ineligible, [
        ...excluded,
        ...pending,
      ], refs);
    }
    if (pending.isNotEmpty) {
      return EligibilityDecision(Eligibility.conditional, pending, refs);
    }
    final reason = combination
        ? 'confirmed_light_composition'
        : k != null
        ? 'reviewed_knowledge'
        : 'legacy_low_risk';
    evidence(
      reason,
      k == null ? 'legacy_fields' : 'knowledge',
      k?.sourceType ?? 'legacy_compatibility_not_review',
    );
    return EligibilityDecision(Eligibility.eligible, [reason], refs);
  }
}
