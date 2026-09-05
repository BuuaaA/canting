import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'portions.dart';

/// An interval is never silently reduced to a point estimate.
class KnowledgeRange {
  const KnowledgeRange._(this.min, this.max);
  final double min;
  final double max;

  static KnowledgeRange? parse(Object? value) {
    if (value == null) return null;
    if (value is! List ||
        value.length != 2 ||
        value.any((v) => v is! num || !v.isFinite) ||
        (value[0] as num) < 0 ||
        (value[1] as num) < (value[0] as num)) {
      throw const FormatException('Invalid nonnegative finite interval');
    }
    return KnowledgeRange._(
      (value[0] as num).toDouble(),
      (value[1] as num).toDouble(),
    );
  }
}

enum PortionUnit { g, ml }

class ConsumedPortion {
  const ConsumedPortion._(this.range, this.unit);
  final KnowledgeRange range;
  final PortionUnit unit;

  static ConsumedPortion? parse(Object? value) {
    if (value == null) return null;
    final map = _object(value);
    _keys(map, {'min', 'max', 'unit', 'scope'});
    if (!{'g', 'ml'}.contains(map['unit']) || map['scope'] != 'consumed') {
      throw const FormatException('Portion requires consumed scope and g/ml');
    }
    return ConsumedPortion._(
      KnowledgeRange.parse([map['min'], map['max']])!,
      map['unit'] == 'g' ? PortionUnit.g : PortionUnit.ml,
    );
  }
}

/// Product identity and dietary contributions are independent dimensions.
/// Legacy dishes have no verified knowledge record; absence stays unknown.
class FoodKnowledge {
  FoodKnowledge._(this._encoded, this.portion, this.contributions);
  final String _encoded;
  final ConsumedPortion? portion;
  final Map<String, KnowledgeRange?>? contributions;

  static const contributionKeys = {
    'grains',
    'vegetables',
    'fruits',
    'protein',
    'protein_soy',
    'oil',
  };
  static const originFields = {
    'semantic_category',
    'beverage_type',
    'recipe_known',
    'preparation',
    'sugar_level',
    'cup_size',
    'size_bucket',
    'portion_range',
    'category_contributions',
  };
  // Public serialization returns a copy; callers cannot mutate validated facts.
  Map<String, dynamic> toJson() =>
      (jsonDecode(_encoded) as Map).cast<String, dynamic>();
  String get id => toJson()['canonical_id'] as String;
  String get name => toJson()['canonical_name'] as String;
  String get productCategory => toJson()['semantic_category'] as String;
  String get beverageType => toJson()['beverage_type'] as String;

  /// Selected sweetness/add-sugar option, NOT measured total sugar.
  String get sugarLevel => toJson()['sugar_level'] as String;
  bool? get recipeKnown => toJson()['recipe_known'] as bool?;
  String get reviewStatus => toJson()['review_status'] as String;
  String get sourceType => toJson()['source_type'] as String;
  String get preparation => toJson()['preparation'] as String;
  String get cupSize => toJson()['cup_size'] as String;
  String get sizeBucket => toJson()['size_bucket'] as String;
  bool get estimated => toJson()['estimated'] as bool;
  double? get confidence => (toJson()['confidence'] as num?)?.toDouble();
  String get eligibility => toJson()['eligibility'] as String;

  /// Only exact, completely known contributions can enter the legacy scalar API.
  /// A range needs a separately authorized estimation step in a future consumer.
  Portions? get exactPortions {
    final values = contributions;
    if (values == null ||
        values.values.any((v) => v == null || v.min != v.max)) {
      return null;
    }
    return Portions.fromKnownJson({
      for (final key in contributionKeys) key: values[key]!.min,
    });
  }

  factory FoodKnowledge.fromJson(Map<String, dynamic> r) {
    _keys(r, _required);
    for (final entry in _enums.entries) {
      if (!entry.value.contains(r[entry.key])) {
        throw FormatException('Invalid ${entry.key}');
      }
    }
    for (final key in [
      'canonical_id',
      'canonical_name',
      'source_id',
      'data_version',
      'transform_version',
      'policy_version',
    ]) {
      if (!_text(r[key])) throw FormatException('Missing $key');
    }
    if (r['source_sha256'] is! String ||
        !_digest.hasMatch(r['source_sha256'] as String) ||
        r['schema_version'] is! int ||
        r['schema_version'] != 2) {
      throw const FormatException('Invalid source digest or knowledge schema');
    }
    for (final key in ['estimated', 'facts_complete']) {
      if (r[key] is! bool) throw FormatException('Invalid $key');
    }
    if (r['recipe_known'] != null && r['recipe_known'] is! bool) {
      throw const FormatException('Invalid recipe_known');
    }
    final confidence = r['confidence'];
    if (confidence != null &&
        (confidence is! num ||
            !confidence.isFinite ||
            confidence < 0 ||
            confidence > 1 ||
            !_text(r['confidence_evidence']))) {
      throw const FormatException('Uncalibrated confidence');
    }
    for (final key in [
      'confidence_evidence',
      'license_evidence',
      'review_evidence',
    ]) {
      if (r[key] != null && !_text(r[key])) {
        throw FormatException('Invalid evidence: $key');
      }
    }
    for (final key in ['risk_tags', 'eligibility_reasons', 'aliases']) {
      final v = r[key];
      if (v is! List ||
          v.any((x) => x is! String) ||
          v.toSet().length != v.length) {
        throw FormatException('Invalid string list: $key');
      }
    }
    if ((r['risk_tags'] as List).any((x) => !_risks.contains(x))) {
      throw const FormatException('Invalid risk');
    }
    final beverage = r['semantic_category'] == 'beverage';
    if (beverage
        ? (r['beverage_type'] == 'notApplicable' ||
              r['sugar_level'] == 'notApplicable')
        : !{'unknown', 'notApplicable'}.contains(r['beverage_type'])) {
      throw const FormatException('Inconsistent beverage facts');
    }
    final portion = ConsumedPortion.parse(r['portion_range']);
    Map<String, KnowledgeRange?>? contributions;
    if (r['category_contributions'] != null) {
      final map = _object(r['category_contributions']);
      _keys(map, contributionKeys);
      contributions = Map.unmodifiable({
        for (final key in contributionKeys) key: KnowledgeRange.parse(map[key]),
      });
    }
    final provenance = _object(r['field_provenance']);
    for (final field in originFields) {
      final p = _object(provenance[field]);
      if (!{
            'source',
            'calculated',
            'inferred',
            'estimated',
            'user_confirmed',
            'unknown',
          }.contains(p['kind']) ||
          (p['kind'] != 'unknown' && !_text(p['evidence'])) ||
          ({'estimated', 'inferred'}.contains(p['kind']) &&
              r['estimated'] != true)) {
        throw FormatException('Invalid origin: $field');
      }
    }
    bool unknown(String key) => (provenance[key] as Map)['kind'] == 'unknown';
    if ((portion != null && unknown('portion_range')) ||
        (contributions != null && unknown('category_contributions')) ||
        (r['recipe_known'] == true && unknown('recipe_known'))) {
      throw const FormatException('Known fact requires evidence');
    }
    if ((r['review_status'] == 'reviewed' && !_text(r['review_evidence'])) ||
        (r['license_status'] == 'approved' && !_text(r['license_evidence']))) {
      throw const FormatException('Review/license requires evidence');
    }
    if (r['eligibility'] == 'eligible' &&
        ({'fried', 'unknown'}.contains(r['preparation']) ||
            (r['risk_tags'] as List).isNotEmpty ||
            r['facts_complete'] != true ||
            r['review_status'] != 'reviewed' ||
            r['license_status'] != 'approved' ||
            (r['eligibility_reasons'] as List).isEmpty ||
            r['semantic_category'] == 'unknown' ||
            contributions == null ||
            contributions.values.any((v) => v == null) ||
            {'low', 'regular', 'high'}.contains(r['sugar_level']) ||
            r['recipe_known'] != true ||
            (beverage &&
                (r['sugar_level'] != 'none' ||
                    r['beverage_type'] == 'unknown' ||
                    unknown('sugar_level') ||
                    unknown('beverage_type'))) ||
            [
              'semantic_category',
              'preparation',
              'category_contributions',
            ].any(unknown))) {
      throw const FormatException('Facts do not permit eligible');
    }
    return FoodKnowledge._(jsonEncode(r), portion, contributions);
  }
}

/// SHA-256 covers the exact UTF-8 content_json string, before JSON parsing.
/// This avoids platform-dependent number/canonical-JSON representations.
class FoodKnowledgePackage {
  FoodKnowledgePackage._(
    this.contentVersion,
    this.digest,
    this.contentJson,
    this.records,
  );
  static const schemaVersion = 2;
  final String contentVersion;
  final String digest;
  final String contentJson;
  final List<FoodKnowledge> records;

  FoodKnowledge? findById(String id) {
    for (final record in records) {
      if (record.id == id) return record;
    }
    return null;
  }

  factory FoodKnowledgePackage.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'schema_version',
      'content_version',
      'content_sha256',
      'content_json',
    });
    if (json['schema_version'] is! int ||
        json['schema_version'] != schemaVersion ||
        !_text(json['content_version']) ||
        json['content_json'] is! String ||
        json['content_sha256'] is! String ||
        !_digest.hasMatch(json['content_sha256'] as String)) {
      throw const FormatException('Invalid knowledge package envelope');
    }
    final content = json['content_json'] as String;
    if (sha256.convert(utf8.encode(content)).toString() !=
        json['content_sha256']) {
      throw const FormatException('Content digest mismatch');
    }
    final body = _object(jsonDecode(content));
    _keys(body, {'records'});
    if (body['records'] is! List) {
      throw const FormatException('records must be a list');
    }
    final records = <FoodKnowledge>[];
    final ids = <String>{};
    for (final value in body['records'] as List) {
      final r = FoodKnowledge.fromJson(_object(value));
      if (!ids.add(r.id) ||
          r.toJson()['data_version'] != json['content_version']) {
        throw const FormatException('Duplicate ID or content version mismatch');
      }
      records.add(r);
    }
    return FoodKnowledgePackage._(
      json['content_version'] as String,
      json['content_sha256'] as String,
      content,
      List.unmodifiable(records),
    );
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'content_version': contentVersion,
    'content_sha256': digest,
    'content_json': contentJson,
  };
}

final _digest = RegExp(r'^[0-9a-f]{64}$');
bool _text(Object? value) => value is String && value.trim().isNotEmpty;
Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected object');
  }
  return value;
}

void _keys(Map<String, dynamic> value, Set<String> expected) {
  if (value.length != expected.length || !expected.containsAll(value.keys)) {
    throw const FormatException('Missing/unexpected fields');
  }
}

const _required = {
  "aliases",
  "beverage_type",
  "canonical_id",
  "canonical_name",
  "category_contributions",
  "confidence",
  "confidence_evidence",
  "cup_size",
  "data_version",
  "eligibility",
  "eligibility_reasons",
  "estimated",
  "facts_complete",
  "field_provenance",
  "license_evidence",
  "license_status",
  "policy_version",
  "portion_range",
  "preparation",
  "recipe_known",
  "review_evidence",
  "review_status",
  "risk_tags",
  "schema_version",
  "semantic_category",
  "size_bucket",
  "source_id",
  "source_sha256",
  "source_type",
  "sugar_level",
  "transform_version",
};
const _risks = {
  "alcohol",
  "fried",
  "high_oil",
  "high_sodium",
  "high_sugar",
  "source_conflict",
  "sugary_drink",
  "unknown_ingredients",
  "unknown_preparation",
};
const _enums = <String, Set<String>>{
  "source_type": {"editorial", "nutridata", "user_confirmed"},
  "review_status": {"needs_review", "rejected", "reviewed", "unreviewed"},
  "license_status": {"approved", "restricted", "unknown"},
  "semantic_category": {
    "beverage",
    "burger",
    "condiment",
    "dairy",
    "dessert",
    "fruits",
    "grains",
    "mixed",
    "nuts",
    "protein",
    "protein_soy",
    "unknown",
    "vegetables",
    "water",
  },
  "beverage_type": {
    "coffee",
    "milk",
    "milk_tea",
    "notApplicable",
    "other",
    "tea",
    "unknown",
    "water",
  },
  "preparation": {
    "boiled",
    "fried",
    "grilled",
    "mixed",
    "pan_fried",
    "raw",
    "steamed",
    "stewed",
    "stir_fried",
    "unknown",
  },
  "sugar_level": {"high", "low", "none", "notApplicable", "regular", "unknown"},
  "cup_size": {"large", "notApplicable", "regular", "small", "unknown"},
  "size_bucket": {"large", "regular", "small", "unknown"},
  "eligibility": {"conditional", "eligible", "ineligible"},
};
