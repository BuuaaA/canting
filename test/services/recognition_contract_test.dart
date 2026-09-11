import 'dart:convert';
import 'dart:io';

import 'package:canting/services/recognition_contract.dart';
import 'package:canting/services/recognition_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> read(String name) =>
    jsonDecode(File('dev-docs/recognition-v2/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final contract = RecognitionContract(read('recognition.schema'));
  Map<String, dynamic> example(String name) =>
      read('examples')[name] as Map<String, dynamic>;
  Map<String, dynamic> half() => example('personal_half_bowl');
  dynamic product(Map<String, dynamic> draft) => draft['products'][0];
  dynamic leaf(Map<String, dynamic> draft) =>
      product(draft)['components'][0]['calculation'];
  void rejected(Map<String, dynamic> draft) =>
      expect(() => contract.draft(draft), throwsFormatException);

  test('both entry fixtures and empty result satisfy model ownership', () {
    for (final name in ['screenshot', 'food_photo', 'empty_food']) {
      contract.draft(example(name), fromModel: true);
    }
  });
  test('personal half bowl bought twice is still half bowl', () {
    final d = contract.draft(half());
    expect(contract.effectiveAmounts(d), {'c-rice': 0.5});
    expect(product(d)['components'][0]['name']['provenance'], 'name_inference');
  });
  test('unreviewed and rejected portions or factors stay unknown', () {
    for (final status in ['unreviewed', 'rejected']) {
      final d = half();
      leaf(d)['portion']['reviewStatus'] = status;
      expect(contract.effectiveAmounts(d)['c-rice'], isNull);
      leaf(d)['portion']['reviewStatus'] = 'accepted';
      leaf(d)['portionBasis'] = 'per_product_unit';
      leaf(d)['allocationRatio'] = fact(1);
      leaf(d)['consumedRatio'] = fact(0)..['reviewStatus'] = status;
      expect(contract.effectiveAmounts(d)['c-rice'], isNull);
    }
  });

  test('stale ratios on personal input are rejected, not multiplied', () {
    final d = half();
    leaf(d)['consumedRatio'] = fact(0.5);
    rejected(d);
  });
  test('served total and per product have distinct formulas', () {
    for (final basis in ['served_total', 'per_product_unit']) {
      final d = half();
      leaf(d)['portionBasis'] = basis;
      leaf(d)['allocationRatio'] = fact(0.5);
      leaf(d)['consumedRatio'] = fact(0.5);
      expect(
        contract.effectiveAmounts(contract.draft(d))['c-rice'],
        basis == 'served_total' ? 0.125 : 0.25,
      );
    }
  });
  test('unknown is null; explicit zero consumed is zero', () {
    final d = half();
    leaf(d)['portionBasis'] = 'per_product_unit';
    expect(contract.effectiveAmounts(contract.draft(d))['c-rice'], isNull);
    leaf(d)['consumedRatio'] = fact(0);
    expect(contract.effectiveAmounts(contract.draft(d))['c-rice'], 0);
  });
  test('personal not eaten excludes leaf without inventing zero portion', () {
    final d = half();
    leaf(d)['notEaten'] = fact(true);
    expect(contract.effectiveAmounts(contract.draft(d)), isEmpty);
  });
  test('ordinal is not numerically multiplied', () {
    final d = half();
    leaf(d)['portion']['value'] = {
      'value': null,
      'unit': 'ordinal',
      'band': 'small',
    };
    expect(contract.effectiveAmounts(contract.draft(d))['c-rice'], isNull);
  });
  test('aggregate and children are exclusive, including switching back', () {
    final d = half();
    product(d)['calculation'] = jsonDecode(jsonEncode(leaf(d)));
    rejected(d);
    product(d)['nutritionMode'] = 'aggregate';
    rejected(d);
    leaf(d)['active'] = false;
    expect(contract.effectiveAmounts(contract.draft(d)), {'p-meal': 0.5});
    product(d)['nutritionMode'] = 'unknown';
    rejected(d);
  });
  test('unselected active node is rejected', () {
    final d = half();
    product(d)['selected'] = false;
    rejected(d);
  });
  test('invalid references, duplicate IDs and third tree level rejected', () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (d) =>
          d['evidence'][0]['assetId'] = '00000000-0000-4000-8000-000000000099',
      (d) => product(d)['displayName']['evidenceRefs'] = ['absent'],
      (d) => product(d)['components'][0]['componentId'] = 'p-meal',
      (d) => product(d)['components'][0]['components'] = [],
      (d) => d['assets'].add(jsonDecode(jsonEncode(d['assets'][0]))),
      (d) => d['evidence'][0]['bbox'] = [0, 0, 2, 1],
      (d) => d['evidence'][0]['bbox'] = [0.9, 0.1, 0.2, 0.3],
    ];
    for (final mutate in mutations) {
      final d = half();
      mutate(d);
      rejected(d);
    }
  });
  test('invalid numbers rejected at boundary including NaN and infinity', () {
    for (final value in [-1, 0, 100, 1.5, double.nan, double.infinity]) {
      final d = half();
      product(d)['purchaseQuantity'] = fact(value);
      rejected(d);
    }
    for (final value in [-1, 0, 100, double.nan, double.infinity]) {
      final d = half();
      leaf(d)['portion']['value']['value'] = value;
      rejected(d);
    }
  });
  test('unknown null and evidence provenance cannot be laundered', () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (d) => product(d)['rawName']['value'] = null,
      (d) => product(d)['purchaseQuantity']['provenance'] = 'unknown',
      (d) => product(d)['displayName']['evidenceRefs'] = [],
      (d) => product(d)['displayName']['provenance'] = 'photo_observed',
      (d) => d['evidence'][0]['textSpan'] = null,
    ];
    for (final mutate in mutations) {
      final d = half();
      mutate(d);
      rejected(d);
    }
  });
  test(
    'model cannot supply accepted, personal, database or selected facts',
    () {
      expect(
        () => contract.draft(half(), fromModel: true),
        throwsFormatException,
      );
      final d = example('screenshot');
      product(d)['selected'] = true;
      expect(() => contract.draft(d, fromModel: true), throwsFormatException);
    },
  );
  test(
    'g/ml require explicit user source; range requires reviewed mapping',
    () {
      final d = half();
      leaf(d)['portion']['value']['unit'] = 'g';
      contract.draft(d);
      leaf(d)['portion']['provenance'] = 'name_inference';
      rejected(d);
      leaf(d)['portion']['provenance'] = 'user_input';
      leaf(d)['estimateRange'] = fact({
        'min': 20,
        'max': 10,
        'unit': 'g',
        'knowledgeVersion': 'test-reviewed',
        'estimated': true,
      }, source: 'database_estimate');
      rejected(d);
      leaf(d)['estimateRange']['value']['max'] = 30;
      rejected(d); // Version text alone is not proof of a reviewed mapping.
      contract.draft(
        d,
        reviewedRanges: {'c-rice': leaf(d)['estimateRange']['value']},
      );
    },
  );
  test('limits 3 assets / 20 products / 8 components are enforced', () {
    for (final key in ['assets', 'products', 'components']) {
      final d = half();
      final List list = key == 'components' ? product(d)[key] : d[key];
      final count = key == 'assets'
          ? 4
          : key == 'products'
          ? 21
          : 9;
      list.addAll(
        List.generate(count, (_) => jsonDecode(jsonEncode(list.first))),
      );
      rejected(d);
    }
  });
  test('unknown payload fields are stripped; broken JSON/version rejected', () {
    final d = half();
    d['healthPolicy'] = 'change policy';
    expect(contract.draft(d).containsKey('healthPolicy'), false);
    d['schemaVersion'] = 'future';
    rejected(d);
    expect(() => contract.decodeDraft('{"products":'), throwsFormatException);
  });
  test(
    'mock explicitly reports simulation and binds request identity',
    () async {
      final adapter = RecognitionAdapter(contract);
      final config = example('provider')..['mode'] = 'mock';
      final response = await adapter.recognize(
        example('request'),
        config,
        mockResult: example('screenshot'),
      );
      expect(response['simulated'], true);
      expect(response['state'], 'review');
      expect(response['usage'], isNull);
      final emptyRequest = example('request')..['sourceKind'] = 'food_photo';
      final empty = await adapter.recognize(
        emptyRequest,
        config,
        mockResult: example('empty_food'),
      );
      expect(empty['state'], 'empty_food');
      expect(empty['result']['products'], isEmpty);
    },
  );
  test(
    'unconfigured/external are unavailable and never resolve secrets',
    () async {
      var calls = 0;
      final adapter = RecognitionAdapter(
        contract,
        credentials: (reference, use) async {
          calls++;
          return use('test-only-credential');
        },
      );
      for (final mode in ['unconfigured', 'external']) {
        final config = example('provider')..['mode'] = mode;
        if (mode == 'external') {
          config.addAll({
            'endpoint': 'https://example.invalid/recognize',
            'model': 'not-selected',
            'credentialRef': 'credential:test',
            'region': 'not-selected',
          });
        }
        final r = await adapter.recognize(example('request'), config);
        expect(r['state'], 'unavailable');
        expect(r['simulated'], false);
      }
      expect(calls, 0);
    },
  );
  test(
    'secrets cannot enter provider schema via headers/key/query/userinfo',
    () {
      for (final field in ['apiKey', 'headers', 'token', 'secret']) {
        final config = example('provider')..[field] = 'test-only';
        expect(() => contract.provider(config), throwsFormatException);
      }
      for (final url in [
        'http://example.invalid',
        'https://user:pass@example.invalid',
        'https://example.invalid/?key=test',
        'https://example.invalid/#token',
      ]) {
        final config = example('provider')..['endpoint'] = url;
        expect(() => contract.provider(config), throwsFormatException);
      }
    },
  );
  test(
    'empty result, error state and mock usage cannot contradict payload',
    () async {
      final req = example('request');
      final config = example('provider')..['mode'] = 'mock';
      final r = await RecognitionAdapter(contract)
          .recognize(req, config, mockResult: example('screenshot'));
      r['state'] = 'empty_food';
      r['errorCode'] = 'NO_FOOD';
      expect(() => contract.response(r, req), throwsFormatException);
      r['state'] = 'review';
      r['errorCode'] = null;
      r['usage'] = {'inputTokens': 0, 'outputTokens': 0, 'billableAttempts': 0};
      expect(() => contract.response(r, req), throwsFormatException);
      r['result'] = null;
      r['usage'] = null;
      r['state'] = 'error';
      expect(() => contract.response(r, req), throwsFormatException);
    },
  );

  test('late/cancelled/mismatched assets cannot be applied', () async {
    final req = example('request');
    final config = example('provider')..['mode'] = 'mock';
    final r = await RecognitionAdapter(contract)
        .recognize(req, config, mockResult: example('screenshot'));
    expect(contract.canApply(req, r, cancelled: true), false);
    req['draftRevision'] = 1;
    expect(contract.canApply(req, r), false);
    req['draftRevision'] = 0;
    r['assetIds'] = ['00000000-0000-4000-8000-000000000099'];
    expect(contract.canApply(req, r), false);
  });
}

Map<String, dynamic> fact(dynamic value, {String source = 'user_input'}) => {
  'value': value,
  'provenance': source,
  'reviewStatus': 'accepted',
  'evidenceRefs': <String>[],
};
