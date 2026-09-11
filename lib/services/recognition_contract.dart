import 'dart:convert';

/// N0 wire contract only. No MealDish mapping, database or health-rule changes.
/// Loads the frozen local schema explicitly; never fetches remote $refs.
class RecognitionContract {
  RecognitionContract(this.schema);
  final Map<String, dynamic> schema;

  Never _fail(String code) =>
      throw FormatException(code); // No input values in errors.
  void _require(bool condition, String code) {
    if (!condition) _fail(code);
  }

  Map<String, dynamic> validate(String definition, dynamic value) =>
      _check(schema[r'$defs'][definition] as Map, value)
          as Map<String, dynamic>;

  // ponytail: implements only keywords in the bundled N0 schema, not a general
  // JSON Schema engine. New schema keywords require extending this validator.
  dynamic _check(Map rule, dynamic value) {
    if (rule.containsKey(r'$ref')) {
      final name = (rule[r'$ref'] as String).split('/').last;
      return _check(schema[r'$defs'][name] as Map, value);
    }
    if (rule['anyOf'] case final List options) {
      for (final Map option in options) {
        try {
          return _check(option, value);
        } on FormatException {
          /* Try next type. */
        }
      }
      _fail('RESULT_INVALID_TYPE');
    }
    if (rule.containsKey('const')) {
      _require(value == rule['const'], 'RESULT_INVALID_CONST');
    }
    if (rule['enum'] case final List values) {
      _require(values.contains(value), 'RESULT_INVALID_ENUM');
    }
    switch (rule['type']) {
      case 'null':
        _require(value == null, 'RESULT_INVALID_NULL');
      case 'boolean':
        _require(value is bool, 'RESULT_INVALID_BOOL');
      case 'integer':
      case 'number':
        _require(
          value is num &&
              value.isFinite &&
              (rule['type'] != 'integer' || value is int),
          'RESULT_INVALID_NUMBER',
        );
        if (rule['minimum'] case final num min) {
          _require(value >= min, 'RESULT_INVALID_MIN');
        }
        if (rule['maximum'] case final num max) {
          _require(value <= max, 'RESULT_INVALID_MAX');
        }
        if (rule['exclusiveMinimum'] case final num min) {
          _require(value > min, 'RESULT_INVALID_MIN');
        }
      case 'string':
        _require(value is String, 'RESULT_INVALID_STRING');
        final length = (value as String).runes.length;
        if (rule['minLength'] case final int min) {
          _require(length >= min, 'RESULT_INVALID_LENGTH');
        }
        if (rule['maxLength'] case final int max) {
          _require(length <= max, 'RESULT_INVALID_LENGTH');
        }
        if (rule['pattern'] case final String pattern) {
          _require(RegExp(pattern).hasMatch(value), 'RESULT_INVALID_PATTERN');
        }
      case 'array':
        _require(value is List, 'RESULT_INVALID_ARRAY');
        final list = value as List;
        if (rule['minItems'] case final int min) {
          _require(list.length >= min, 'RESULT_INVALID_LENGTH');
        }
        if (rule['maxItems'] case final int max) {
          _require(list.length <= max, 'RESULT_INVALID_LENGTH');
        }
        return [for (final item in list) _check(rule['items'] as Map, item)];
      case 'object':
        _require(value is Map, 'RESULT_INVALID_OBJECT');
        final map = value as Map;
        final properties = rule['properties'] as Map;
        for (final key in rule['required'] as List) {
          _require(map.containsKey(key), 'RESULT_MISSING_FIELD');
        }
        // Never silently flatten an invalid third level or independent child quantity.
        for (final key in [
          'components',
          'purchaseQuantity',
          'parentId',
          'parentProductId',
        ]) {
          _require(
            !map.containsKey(key) || properties.containsKey(key),
            'RESULT_INVALID_TREE',
          );
        }
        return <String, dynamic>{
          for (final String key in properties.keys)
            if (map.containsKey(key))
              key: _check(properties[key] as Map, map[key]),
        };
    }
    return value;
  }

  Map<String, dynamic> decodeDraft(String text, {bool fromModel = false}) {
    _require(text.length <= 256 * 1024, 'RESULT_TOO_LARGE');
    dynamic parsed;
    try {
      parsed = jsonDecode(text);
    } on FormatException {
      _fail('RESULT_INVALID_JSON');
    }
    return draft(parsed, fromModel: fromModel);
  }

  void _box(List box) =>
      _require(box[0] < box[2] && box[1] < box[3], 'RESULT_INVALID_BOX');

  void _assets(Map d) {
    final ids = <String>{};
    for (final Map asset in d['assets']) {
      _require(ids.add(asset['assetId'] as String), 'RESULT_DUPLICATE_ID');
      _box(asset['crop'] as List);
    }
    _require(d['draftId'] != d['requestId'], 'RESULT_DUPLICATE_ID');
    _require(
      !ids.contains(d['draftId']) && !ids.contains(d['requestId']),
      'RESULT_DUPLICATE_ID',
    );
  }

  Map<String, dynamic> request(dynamic input) {
    final d = validate('Request', input);
    _assets(d);
    return d;
  }

  Map<String, dynamic> provider(dynamic input) {
    _require(input is Map, 'CONFIG_INVALID');
    final allowed = (schema[r'$defs']['Provider']['properties'] as Map).keys
        .toSet();
    _require(
      allowed.containsAll((input as Map).keys),
      'CONFIG_SECRET_OR_UNKNOWN_FIELD',
    );
    final p = validate('Provider', input);
    if (p['endpoint'] != null) {
      final uri = Uri.tryParse(p['endpoint'] as String);
      _require(
        uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            !uri.hasQuery &&
            !uri.hasFragment,
        'CONFIG_INVALID_ENDPOINT',
      );
    }
    if (p['mode'] == 'external') {
      _require(
        p['endpoint'] != null && p['model'] != null,
        'CONFIG_INCOMPLETE',
      );
    }
    return p;
  }

  Map<String, dynamic> draft(
    dynamic input, {
    bool fromModel = false,
    Map<String, dynamic> reviewedRanges = const {},
  }) {
    final d = validate('Draft', input);
    _assets(d);
    final ids = <String>{
      d['draftId'],
      d['requestId'],
      for (final Map a in d['assets']) a['assetId'],
    };
    final assets = {for (final Map a in d['assets']) a['assetId']};
    final evidence = <String, Map>{};
    for (final Map e in d['evidence']) {
      final id = e['evidenceId'] as String;
      _require(ids.add(id), 'RESULT_DUPLICATE_ID');
      evidence[id] = e;
      _require(
        e['assetId'] == null || assets.contains(e['assetId']),
        'RESULT_INVALID_ASSET_REF',
      );
      if (e['bbox'] != null) {
        _box(e['bbox'] as List);
        _require(e['assetId'] != null, 'RESULT_INVALID_ASSET_REF');
      }
      if (e['type'] == 'text_observed') {
        _require(
          e['assetId'] != null &&
              e['textSpan'] != null &&
              (e['textSpan'] as String).trim().isNotEmpty,
          'RESULT_NO_TEXT_EVIDENCE',
        );
      }
      if (e['type'] == 'photo_observed') {
        _require(
          d['sourceKind'] == 'food_photo' &&
              e['assetId'] != null &&
              e['bbox'] != null,
          'RESULT_NO_PHOTO_EVIDENCE',
        );
      }
      if (fromModel) {
        _require(
          !['user_input', 'database_estimate'].contains(e['type']),
          'RESULT_OWNER_VIOLATION',
        );
      }
    }
    void checkFact(Map f) {
      _require(
        (f['value'] == null) == (f['provenance'] == 'unknown'),
        'RESULT_UNKNOWN_MISMATCH',
      );
      final refs = f['evidenceRefs'] as List;
      _require(
        refs.toSet().length == refs.length && refs.every(evidence.containsKey),
        'RESULT_INVALID_EVIDENCE_REF',
      );
      final source = f['provenance'];
      if (source == 'text_observed' || source == 'photo_observed') {
        _require(
          refs.any((id) => evidence[id]!['type'] == source),
          'RESULT_SOURCE_MISMATCH',
        );
      }
      if (fromModel) {
        _require(
          f['reviewStatus'] == 'unreviewed' &&
              source != 'user_input' &&
              source != 'database_estimate',
          'RESULT_OWNER_VIOLATION',
        );
      }
    }

    void calculation(Map c, String id, bool allowed) {
      for (final key in [
        'portion',
        'allocationRatio',
        'consumedRatio',
        'estimateRange',
        'notEaten',
      ]) {
        checkFact(c[key] as Map);
      }
      _require(c['active'] == false || allowed, 'RESULT_INACTIVE_PATH');
      if (c['portionBasis'] == 'personal_consumed') {
        _require(
          c['allocationRatio']['value'] == null &&
              c['consumedRatio']['value'] == null,
          'RESULT_PERSONAL_HAS_RATIOS',
        );
        if (c['portion']['value'] != null) {
          _require(
            c['portion']['provenance'] == 'user_input',
            'RESULT_PERSONAL_NOT_USER',
          );
        }
      }
      if (fromModel) {
        _require(
          c['active'] == false &&
              c['allocationRatio']['value'] == null &&
              c['consumedRatio']['value'] == null &&
              c['portionBasis'] != 'personal_consumed',
          'RESULT_OWNER_VIOLATION',
        );
      }
      if (c['notEaten']['value'] != null) {
        _require(
          c['notEaten']['provenance'] == 'user_input' &&
              c['notEaten']['reviewStatus'] == 'accepted' &&
              c['portionBasis'] == 'personal_consumed',
          'RESULT_INVALID_NOT_EATEN',
        );
      }
      final Map? portion = c['portion']['value'];
      if (portion != null) {
        final value = portion['value'];
        final limit = ['g', 'ml'].contains(portion['unit']) ? 10000 : 99;
        _require(
          value == null ||
              (value is num && value.isFinite && value > 0 && value <= limit),
          'RESULT_INVALID_PORTION',
        );
        if (['ml', 'g'].contains(portion['unit'])) {
          _require(
            c['portion']['provenance'] == 'user_input',
            'RESULT_MASS_NOT_USER',
          );
        }
        if (portion['unit'] == 'ordinal' || portion['unit'] == 'unknown') {
          _require(portion['value'] == null, 'RESULT_ORDINAL_NUMBER');
        }
        if (portion['unit'] == 'ordinal') {
          _require(portion['band'] != 'unknown', 'RESULT_ORDINAL_UNKNOWN');
        }
      }
      final Map? range = c['estimateRange']['value'];
      if (range != null) {
        _require(
          range['min'] <= range['max'] &&
              c['estimateRange']['provenance'] == 'database_estimate' &&
              reviewedRanges.containsKey(id) &&
              _same(range, reviewedRanges[id]),
          'RESULT_UNREVIEWED_RANGE',
        );
      }
    }

    for (final Map p in d['products']) {
      final id = p['productId'] as String;
      _require(ids.add(id), 'RESULT_DUPLICATE_ID');
      for (final key in ['displayName', 'rawName', 'purchaseQuantity']) {
        checkFact(p[key] as Map);
      }
      for (final Map spec in p['specifications']) {
        checkFact(spec);
      }
      if (fromModel) {
        _require(p['selected'] == false, 'RESULT_UNCALIBRATED_SELECTION');
      }
      calculation(
        p['calculation'] as Map,
        id,
        p['selected'] == true && p['nutritionMode'] == 'aggregate',
      );
      for (final Map c in p['components']) {
        final id = c['componentId'] as String;
        _require(ids.add(id), 'RESULT_DUPLICATE_ID');
        checkFact(c['name'] as Map);
        checkFact(c['categoryId'] as Map);
        if (fromModel) {
          _require(c['selected'] == false, 'RESULT_UNCALIBRATED_SELECTION');
        }
        calculation(
          c['calculation'] as Map,
          id,
          p['selected'] == true &&
              c['selected'] == true &&
              p['nutritionMode'] == 'children',
        );
      }
    }
    return d;
  }

  bool _same(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]));
    }
    return a == b;
  }

  Map<String, dynamic> response(dynamic input, Map<String, dynamic> req) {
    final r = validate('Response', input);
    _require(
      r['draftId'] == req['draftId'] &&
          r['requestId'] == req['requestId'] &&
          r['draftRevision'] == req['draftRevision'] &&
          _same(r['assetIds'], [
            for (final Map a in req['assets']) a['assetId'],
          ]),
      'STALE_DRAFT',
    );
    final hasResult = r['state'] == 'review' || r['state'] == 'empty_food';
    _require(hasResult == (r['result'] != null), 'RESULT_INVALID_STATE');
    if (r['state'] == 'unavailable') {
      _require(
        r['errorCode'] == 'PROVIDER_UNAVAILABLE',
        'RESULT_INVALID_STATE',
      );
    } else if (r['state'] == 'expired') {
      _require(r['errorCode'] == 'RESULT_EXPIRED', 'RESULT_INVALID_STATE');
    } else if (r['state'] == 'error') {
      _require(
        r['errorCode'] != null && r['errorCode'] != 'NO_FOOD',
        'RESULT_INVALID_STATE',
      );
    } else if (['processing', 'cancelled', 'deleted'].contains(r['state'])) {
      _require(r['errorCode'] == null, 'RESULT_INVALID_STATE');
    }
    if (r['simulated'] == true) {
      _require(r['usage'] == null, 'RESULT_MOCK_USAGE');
    }
    if (hasResult) {
      final d = draft(r['result'], fromModel: true);
      for (final key in [
        'draftId',
        'requestId',
        'draftRevision',
        'sourceKind',
        'assets',
      ]) {
        _require(_same(d[key], req[key]), 'STALE_DRAFT');
      }
      _require(
        (r['state'] == 'empty_food') == (d['products'] as List).isEmpty,
        'RESULT_INVALID_EMPTY',
      );
      _require(
        r['errorCode'] == (r['state'] == 'empty_food' ? 'NO_FOOD' : null),
        'RESULT_INVALID_STATE',
      );
      r['result'] = d;
    }
    return r;
  }

  bool canApply(
    Map<String, dynamic> req,
    dynamic input, {
    bool cancelled = false,
  }) {
    if (cancelled) return false;
    try {
      final r = response(input, request(req));
      return ['review', 'empty_food'].contains(r['state']);
    } on FormatException {
      return false;
    }
  }

  /// Executable §6.1 reference, not food-group contributions or persistence.
  /// Returns amounts in EACH leaf's original unit; callers must not sum units.
  Map<String, num?> effectiveAmounts(
    Map<String, dynamic> input, {
    Map<String, dynamic> reviewedRanges = const {},
  }) {
    final d = draft(input, reviewedRanges: reviewedRanges);
    dynamic confirmed(Map fact) =>
        fact['reviewStatus'] == 'accepted' ? fact['value'] : null;
    final result = <String, num?>{};
    for (final Map p in d['products']) {
      final nodes = p['nutritionMode'] == 'aggregate'
          ? [p]
          : p['nutritionMode'] == 'children'
          ? p['components'] as List
          : <dynamic>[];
      for (final Map node in nodes) {
        final Map c = node['calculation'];
        if (c['active'] != true || c['notEaten']['value'] == true) continue;
        final id = (node['componentId'] ?? node['productId']) as String;
        final Map? portion = confirmed(c['portion'] as Map);
        final basis = c['portionBasis'];
        num? amount;
        if (basis != 'unknown') {
          if (basis != 'personal_consumed' &&
              confirmed(c['consumedRatio'] as Map) == 0) {
            amount = 0;
          } else if (portion != null &&
              !['ordinal', 'unknown'].contains(portion['unit'])) {
            amount = portion['value'] as num?;
            if (basis != 'personal_consumed') {
              final factors = [
                confirmed(c['allocationRatio'] as Map),
                confirmed(c['consumedRatio'] as Map),
                if (basis == 'per_product_unit')
                  confirmed(p['purchaseQuantity'] as Map),
              ];
              for (final factor in factors) {
                amount = amount == null || factor == null
                    ? null
                    : amount * (factor as num);
              }
            }
          }
        }
        result[id] = amount;
      }
    }
    return result;
  }
}
