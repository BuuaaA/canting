import 'food_knowledge.dart';

import 'dart:convert';

/// Personal facts, never a reviewed recipe or recommendation candidate.
class FoodFacts {
  const FoodFacts({
    this.brand = '',
    required this.name,
    this.category = 'unknown',
    this.preparation = 'unknown',
    this.sauce = 'unknown',
  });
  final String brand, name, category, preparation, sauce;
  static String normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s，,。·（）()\[\]]'), '');
  String get key => jsonEncode([normalize(brand), normalize(name)]);
  Map<String, dynamic> toJson() => {
    'brand': brand,
    'name': name,
    'category': category,
    'preparation': preparation,
    'sauce': sauce,
  };
  factory FoodFacts.fromJson(Map<String, dynamic> j) => FoodFacts(
    brand: j['brand'] as String? ?? '',
    name: j['name'] as String,
    category: j['category'] as String? ?? 'unknown',
    preparation: j['preparation'] as String? ?? 'unknown',
    sauce: j['sauce'] as String? ?? 'unknown',
  );
}

class OrderSpec {
  const OrderSpec({
    this.sugar = 'unknown',
    this.cup = 'unknown',
    this.size = 'unknown',
  });
  final String sugar, cup, size;
  Map<String, dynamic> toJson() => {'sugar': sugar, 'cup': cup, 'size': size};
  factory OrderSpec.fromJson(Map<String, dynamic> j) => OrderSpec(
    sugar: j['sugar'] as String? ?? 'unknown',
    cup: j['cup'] as String? ?? 'unknown',
    size: j['size'] as String? ?? 'unknown',
  );
  static const sugarTerms = {
    '无糖': 'none',
    '低糖': 'low',
    '常规糖': 'regular',
    '高糖': 'high',
  };
  static const cupTerms = {'小杯': 'small', '中杯': 'medium', '大杯': 'large'};
  static const sizeTerms = {'小份': 'small', '正常份': 'normal', '大份': 'large'};
  static String _read(String raw, Map<String, String> terms) {
    final found = terms.entries.where((e) => raw.contains(e.key)).toList();
    return found.length == 1 ? found.single.value : 'unknown';
  }

  static bool ambiguous(String raw) => [
    sugarTerms,
    cupTerms,
    sizeTerms,
  ].any((terms) => terms.keys.where(raw.contains).length > 1);
  static OrderSpec parse(String raw) => OrderSpec(
    sugar: _read(raw, sugarTerms),
    cup: _read(raw, cupTerms),
    size: _read(raw, sizeTerms),
  );
  static String productName(String raw) =>
      raw.replaceAll(RegExp(r'无糖|低糖|常规糖|高糖|小杯|中杯|大杯|小份|正常份|大份'), '').trim();
  bool conflicts(OrderSpec other) =>
      (sugar != 'unknown' &&
          other.sugar != 'unknown' &&
          sugar != other.sugar) ||
      (cup != 'unknown' && other.cup != 'unknown' && cup != other.cup) ||
      (size != 'unknown' && other.size != 'unknown' && size != other.size);
}

class LocalFoodProfile {
  const LocalFoodProfile({
    required this.facts,
    required this.createdAt,
    required this.updatedAt,
    this.useCount = 0,
    this.lastSpec = const OrderSpec(),
    this.rawNames = const [],
  });
  final FoodFacts facts;
  final DateTime createdAt, updatedAt;
  final int useCount;
  final OrderSpec lastSpec;
  final List<String> rawNames;
  Map<String, dynamic> toJson() => {
    'facts': facts.toJson(),
    'last_spec_suggestion': lastSpec.toJson(),
    'raw_names': rawNames,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'use_count': useCount,
    'source': 'user_confirmed',
    'confirmation_scope': [
      for (final field in ['category', 'preparation', 'sauce'])
        if (facts.toJson()[field] != 'unknown') field,
    ],
    'confidence': null,
    'matched_by': 'brand_name_exact',
    'schema_version': 1,
    'policy_version': 'local-food-v1',
  };
  factory LocalFoodProfile.fromJson(Map<String, dynamic> j) => LocalFoodProfile(
    facts: FoodFacts.fromJson(Map<String, dynamic>.from(j['facts'] as Map)),
    lastSpec: OrderSpec.fromJson(
      Map<String, dynamic>.from(j['last_spec_suggestion'] as Map),
    ),
    createdAt: DateTime.parse(j['created_at'] as String),
    updatedAt: DateTime.parse(j['updated_at'] as String),
    useCount: j['use_count'] as int,
    rawNames: (j['raw_names'] as List? ?? const []).cast<String>(),
  );
}

enum FoodDecision { autoFill, candidate, manual }

/// Immutable meal snapshot. No license or built-in review assertion is implied.
class FoodObservation {
  const FoodObservation({
    required this.facts,
    this.spec = const OrderSpec(),
    this.suggestion,
    this.confirmed = false,
    this.matchedBy = 'manual',
    this.decision = FoodDecision.manual,
    this.candidateName,
    this.confirmedAt,
    this.rawName = '',
    this.knowledge,
    this.brandOrigin = 'legacy_unknown',
    this.merchantContext = '',
  });
  final FoodFacts facts;
  final OrderSpec spec;
  final OrderSpec? suggestion;
  final bool confirmed;
  final String matchedBy;
  final FoodDecision decision;
  final String? candidateName;
  final DateTime? confirmedAt;
  final String rawName;
  final FoodKnowledge? knowledge;

  /// merchant: inferred context; explicit: item-level user input (including empty).
  /// Old snapshots have no provenance; keep them intact until explicitly edited.
  final String brandOrigin, merchantContext;
  FoodObservation withBrandContext(String origin, String merchant) =>
      FoodObservation(
        facts: facts,
        spec: spec,
        suggestion: suggestion,
        confirmed: confirmed,
        matchedBy: matchedBy,
        decision: decision,
        candidateName: candidateName,
        confirmedAt: confirmedAt,
        rawName: rawName,
        knowledge: knowledge,
        brandOrigin: origin,
        merchantContext: merchant,
      );
  Map<String, dynamic> toJson() => {
    'facts': facts.toJson(),
    'spec': spec.toJson(),
    'suggestion': suggestion?.toJson(),
    'confirmed': confirmed,
    'confirmed_at': confirmedAt?.toIso8601String(),
    'raw_name': rawName,
    'brand_origin': brandOrigin,
    'merchant_context': merchantContext,
    'matched_by': matchedBy,
    'decision': decision.name,
    'candidate_name': candidateName,
    'source': confirmed ? 'user_confirmed' : matchedBy,
    'confidence': null,
    'contributions': knowledge?.toJson()['category_contributions'],
    'portion_range': knowledge?.toJson()['portion_range'],
    'estimated': knowledge?.estimated ?? false,
    'knowledge_snapshot': knowledge?.toJson(),
    'schema_version': 1,
    'policy_version': 'local-food-v1',
  };
  factory FoodObservation.fromJson(Map<String, dynamic> j) => FoodObservation(
    facts: FoodFacts.fromJson(Map<String, dynamic>.from(j['facts'] as Map)),
    spec: OrderSpec.fromJson(Map<String, dynamic>.from(j['spec'] as Map)),
    suggestion: j['suggestion'] == null
        ? null
        : OrderSpec.fromJson(Map<String, dynamic>.from(j['suggestion'] as Map)),
    rawName: j['raw_name'] as String? ?? '',
    brandOrigin: j['brand_origin'] as String? ?? 'legacy_unknown',
    merchantContext: j['merchant_context'] as String? ?? '',
    knowledge: j['knowledge_snapshot'] == null
        ? null
        : FoodKnowledge.fromJson(
            Map<String, dynamic>.from(j['knowledge_snapshot'] as Map),
          ),
    confirmed: j['confirmed'] == true,
    matchedBy: j['matched_by'] as String,
    decision: FoodDecision.values.byName(j['decision'] as String),
    candidateName: j['candidate_name'] as String?,
    confirmedAt: j['confirmed_at'] == null
        ? null
        : DateTime.parse(j['confirmed_at'] as String),
  );
}

/// Central decision configuration; legacy similarities are never probabilities.
abstract final class FoodMatchPolicy {
  static const version = 'local-food-v1';
  static const candidateSimilarity = 0.7;
  static const autoMethods = {
    'exact',
    'local_exact',
    'knowledge_variant_exact',
  };
  static const candidateMethods = {
    'contains',
    'fuzzy',
    'keyword',
    'brand_conflict',
  };
  static FoodDecision decisionFor(String method) => autoMethods.contains(method)
      ? FoodDecision.autoFill
      : candidateMethods.contains(method)
      ? FoodDecision.candidate
      : FoodDecision.manual;
}
