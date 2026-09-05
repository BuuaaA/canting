import 'dart:convert';
import 'dart:io';

import 'package:canting/core/models/food_data.dart';
import 'package:canting/core/models/food_knowledge.dart';
import 'package:canting/core/models/portions.dart';
import 'package:canting/data/food_database.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> contractCases() => (jsonDecode(
  File('test/fixtures/food_knowledge_contract_cases.json').readAsStringSync(),
) as List).map((v) => (v as Map).cast<String, dynamic>()).toList();

FoodKnowledgePackage syntheticPackage(String version, {String name = '合成汉堡'}) {
  final record = (contractCases()[1]['record'] as Map).cast<String, dynamic>();
  record['data_version'] = version;
  record['canonical_name'] = name;
  final content = jsonEncode({
    'records': [record],
  });
  return FoodKnowledgePackage.fromJson({
    'schema_version': 2,
    'content_version': version,
    'content_sha256': sha256.convert(utf8.encode(content)).toString(),
    'content_json': content,
  });
}

void main() {
  test(
    'embedded knowledge cannot smuggle unknown contributions into old parser',
    () {
      final old =
          (jsonDecode(
                File('test/fixtures/legacy_dishes_29.json').readAsStringSync(),
              ) as List).first
              as Map;
      final unknown = (contractCases().first['record'] as Map)
          .cast<String, dynamic>();
      unknown['canonical_id'] = old['dish_id'];
      expect(
        () => StandardDish.fromJson({
          ...old.cast<String, dynamic>(),
          'knowledge': unknown,
        }),
        throwsFormatException,
      );
    },
  );

  test('nonfinite values, malformed types, and mutation cannot change validated facts', () {
    final r = (contractCases()[1]['record'] as Map).cast<String, dynamic>();
    for (final value in [double.nan, double.infinity, -1]) {
      expect(
        () => FoodKnowledge.fromJson({...r, 'confidence': value}),
        throwsFormatException,
      );
    }
    expect(
      () => FoodKnowledge.fromJson({...r, 'field_provenance': []}),
      throwsFormatException,
    );
    final parsed = FoodKnowledge.fromJson(r);
    r['semantic_category'] = 'unknown';
    parsed.toJson()['semantic_category'] = 'unknown';
    expect(parsed.productCategory, 'burger');
    expect(() => parsed.contributions!.clear(), throwsUnsupportedError);
  });

  for (final c in contractCases()) {
    test('shared contract: ${c['name']}', () {
      final record = (c['record'] as Map).cast<String, dynamic>();
      if (c['valid'] == true) {
        final parsed = FoodKnowledge.fromJson(record);
        expect(parsed.toJson(), record);
      } else {
        expect(() => FoodKnowledge.fromJson(record), throwsFormatException);
      }
    });
  }

  test('unknown/range cannot become legacy zero; real zero survives', () {
    FoodKnowledge named(String name) => FoodKnowledge.fromJson(
      (contractCases().singleWhere((c) => c['name'] == name)['record'] as Map)
          .cast<String, dynamic>(),
    );
    expect(named('unknown remains null').exactPortions, isNull);
    expect(
      named('burger separate mixed contributions').productCategory,
      'burger',
    );
    expect(named('burger separate mixed contributions').exactPortions, isNull);
    expect(named('real zero contributions').exactPortions!.grains, 0);
    expect(named('portion g').portion!.unit, PortionUnit.g);
    expect(named('portion ml').portion!.unit, PortionUnit.ml);
    expect(
      () => Portions.fromKnownJson({'grains': null}),
      throwsFormatException,
    );
    expect(
      () => StandardDish.fromJson(named('unknown remains null').toJson()),
      throwsFormatException,
    );
  });

  test(
    'legacy 1004 retain unknown provenance without changing legacy values',
    () {
      final db = FoodDatabase.fromJson(
        dishesJson: File('assets/data/dishes.json').readAsStringSync(),
        categoriesJson: File('assets/data/categories.json').readAsStringSync(),
      );
      expect(db.dishes.length, 1004);
      for (final dish in db.dishes) {
        expect(dish.knowledgeSource, 'unknown');
        expect(dish.knowledgeReviewStatus, 'unknown');
        expect(dish.sugarLevel, 'unknown');
        expect(dish.consumedPortion, isNull);
        expect(dish.toJson().containsKey('knowledge'), isFalse);
      }
      final combined = db.withKnowledgePackage(syntheticPackage('s1'));
      expect(
        combined.findKnowledgeById('synthetic:1')!.productCategory,
        'burger',
      );
      expect(combined.dishes.length, 1004);
    },
  );

  test('package digest and content version are independently verified', () {
    final p = syntheticPackage('s1');
    expect(FoodKnowledgePackage.fromJson(p.toJson()).digest, p.digest);
    expect(
      () =>
          FoodKnowledgePackage.fromJson({...p.toJson(), 'content_json': '{}'}),
      throwsFormatException,
    );
    expect(
      () => FoodKnowledgePackage.fromJson({
        ...p.toJson(),
        'content_version': 's2',
      }),
      throwsFormatException,
    );
    expect(
      () => FoodKnowledgePackage.fromJson({...p.toJson(), 'schema_version': 3}),
      throwsFormatException,
    );
    final body = jsonDecode(p.contentJson) as Map;
    final content = jsonEncode({
      'records': [body['records'][0], body['records'][0]],
    });
    expect(
      () => FoodKnowledgePackage.fromJson({
        ...p.toJson(),
        'content_json': content,
        'content_sha256': sha256.convert(utf8.encode(content)).toString(),
      }),
      throwsFormatException,
    );
  });
}
