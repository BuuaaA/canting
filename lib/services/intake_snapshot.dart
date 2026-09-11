import 'dart:convert';
import 'dart:io';

import '../core/models/meal_record.dart';

/// The device-owned, image-free fact sent to the optional backend snapshot API.
/// The caller persists and increments [revision] locally before uploading.
class IntakeSnapshot {
  const IntakeSnapshot({
    required this.installationId,
    required this.revision,
    required this.timezone,
    required this.startDate,
    required this.endDate,
    required this.days,
    this.energy,
  });

  final String installationId;
  final int revision;
  final String timezone;
  final String startDate;
  final String endDate;
  final List<Map<String, dynamic>> days;
  final Map<String, dynamic>? energy;

  Map<String, dynamic> toJson() => {
    'installationId': installationId,
    'snapshotRevision': revision,
    'timezone': timezone,
    'windowStartDate': startDate,
    'windowEndDate': endDate,
    if (energy != null) 'energy': energy,
    'days': days,
  };

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  factory IntakeSnapshot.fromMeals({
    required String installationId,
    required int revision,
    required DateTime today,
    required Iterable<MealRecord> meals,
    required String timezone,
    Map<String, dynamic>? energy,
  }) {
    final anchor = DateTime(today.year, today.month, today.day);
    final byDay = <String, List<MealRecord>>{};
    for (final meal in meals) {
      final key = dateKey(meal.timestamp.toLocal());
      byDay.putIfAbsent(key, () => []).add(meal);
    }
    final days = <Map<String, dynamic>>[];
    for (var offset = -6; offset <= 0; offset++) {
      final day = DateTime(anchor.year, anchor.month, anchor.day + offset);
      final key = dateKey(day);
      final records = byDay[key] ?? const <MealRecord>[];
      final recordItems = {
        for (final meal in records) meal.mealId: _items(meal).toList(),
      };
      final complete =
          records.isNotEmpty &&
          records.every(
            (meal) =>
                meal.structureComplete &&
                recordItems[meal.mealId]!.isNotEmpty &&
                recordItems[meal.mealId]!.every(_isComplete),
          );
      days.add({
        'date': key,
        'status': records.isEmpty
            ? 'missing'
            : complete
            ? 'known'
            : 'partial',
        'mealIds': records.map((meal) => meal.mealId).toList(growable: false),
        'meals': records
            .map((meal) => _mealRef(meal, recordItems[meal.mealId]!))
            .toList(growable: false),
        'intakeItems': recordItems.values
            .expand((items) => items)
            .toList(growable: false),
      });
    }
    return IntakeSnapshot(
      installationId: installationId,
      revision: revision,
      timezone: timezone,
      startDate: days.first['date'] as String,
      endDate: days.last['date'] as String,
      days: days,
      energy: energy,
    );
  }

  /// Returns the same image-free, persisted intake facts used by the optional
  /// snapshot adapter. Statistics must consume these facts rather than the
  /// legacy six-group serving totals.
  static List<Map<String, dynamic>> itemsForMeal(MealRecord meal) =>
      _items(meal).toList(growable: false);

  static Iterable<Map<String, dynamic>> _items(MealRecord meal) sync* {
    final snapshot = meal.recognitionSnapshot;
    final draft = snapshot?['draft'];
    if (draft is Map) {
      for (final product in (draft['products'] as List? ?? const [])) {
        if (product is! Map || product['selected'] != true) continue;
        final mode = product['nutritionMode'];
        final nodes = mode == 'children'
            ? (product['components'] as List? ?? const [])
            : mode == 'aggregate'
            ? [product]
            : const [];
        for (final node in nodes) {
          if (node is Map && node['selected'] == true) {
            final item = _v2Item(meal.mealId, node, parent: product);
            if (item != null) yield item;
          }
        }
      }
      return;
    }
    for (final dish in meal.dishes) {
      final food = dish.food;
      final category = food?.facts.category;
      // Legacy MealDish stores food-group servings, not a trustworthy food
      // gram value. Keep grams unknown instead of inventing a conversion.
      const double? grams = null;
      yield {
        'foodKey': food?.facts.key,
        'mealId': meal.mealId,
        'name': dish.name,
        if (category != null) 'category': _category(category),
        'grams': grams,
        'animalSubtype': food?.facts.category == 'fish' ? 'fish' : null,
        'amount': null,
        'unit': grams == null ? 'unknown' : 'g',
        'amountBasis': 'unknown',
        'confidence': dish.matchConfidence == 0 ? null : dish.matchConfidence,
        'source': dish.matchConfidence > 0 ? 'local_rule' : 'manual',
        'estimateSource': dish.matchedDishId,
        'conversionVersion': null,
        'complete': false,
      };
    }
  }

  static Map<String, dynamic>? _v2Item(String mealId, Map node, {Map? parent}) {
    final calculation = node['calculation'];
    if (calculation is! Map || calculation['active'] != true) return null;
    final notEaten = (calculation['notEaten'] as Map?)?['value'] == true;
    if (notEaten) return null;
    final portion = calculation['portion'];
    final value = (portion is Map ? portion['value'] : null) as Map?;
    var amount = (value?['value'] as num?)?.toDouble();
    final unit = value?['unit'] as String? ?? 'unknown';
    final basis = calculation['portionBasis'] as String? ?? 'unknown';
    if (basis != 'personal_consumed') {
      final factors = <num?>[
        _acceptedNumber(calculation['allocationRatio']),
        _acceptedNumber(calculation['consumedRatio']),
      ];
      if (basis == 'per_product_unit') {
        factors.add(_acceptedNumber(parent?['purchaseQuantity']));
      }
      for (final factor in factors) {
        amount = amount == null || factor == null ? null : amount * factor;
      }
    }
    if (amount != null && amount <= 0) return null;
    final nameFact = (node['displayName'] ?? node['name']) as Map?;
    final categoryFact = node['categoryId'] as Map?;
    final category = _category(categoryFact?['value'] as String? ?? '');
    final source = _source(node, calculation);
    return {
      'mealId': mealId,
      'name': nameFact?['value'],
      'foodKey': null,
      'animalSubtype': _acceptedString(node['animalSubtype']),
      'category': category,
      'grams': unit == 'g' ? amount : null,
      'amount': unit == 'ml'
          ? amount
          : unit == 'g'
          ? amount
          : null,
      'unit': unit == 'g' || unit == 'ml' ? unit : 'unknown',
      'amountBasis': 'unknown',
      'equivalentAmount': null,
      'equivalentUnit': null,
      'cookingMethod': null,
      'confidence': ((node['confidence'] as Map?)?['raw'] as num?)?.toDouble(),
      'source': source,
      'estimateSource': null,
      'conversionVersion': null,
      'complete': amount != null && category != null,
    };
  }

  static String _source(Map node, Map calculation) {
    final fields = [node['name'], node['categoryId'], calculation['portion']];
    return fields.any(
          (value) => value is Map && value['provenance'] == 'user_input',
        )
        ? 'user_edit'
        : 'ai';
  }

  static num? _acceptedNumber(dynamic fact) {
    if (fact is! Map || fact['reviewStatus'] != 'accepted') return null;
    final value = fact['value'];
    return value is num ? value : null;
  }

  static String? _acceptedString(dynamic fact) {
    if (fact is! Map || fact['reviewStatus'] != 'accepted') return null;
    return fact['value'] is String ? fact['value'] as String : null;
  }

  static bool _isComplete(Map<String, dynamic> item) =>
      item['complete'] == true;

  static Map<String, dynamic> _mealRef(
    MealRecord meal,
    List<Map<String, dynamic>> items,
  ) => {
    'mealId': meal.mealId,
    'occurredAt': meal.timestamp.toIso8601String(),
    'intakeItems': items,
    'completeness':
        meal.structureComplete && items.isNotEmpty && items.every(_isComplete)
        ? 'known'
        : 'partial',
  };

  static String? _category(String value) => switch (value) {
    // The legacy combined category cannot reliably distinguish grains/roots.
    'grain_tuber' => null,
    'vegetable' => 'vegetable',
    'fruit' => 'fruit',
    'protein_meat_egg' => 'animal_food',
    'dairy' || 'dairy_products' => 'dairy',
    'soy' || 'soy_products' => 'soy',
    'nut' => 'nut',
    'oil' || 'cooking_oil' => 'cooking_oil',
    'salt' => 'salt',
    _ => null,
  };
}

class IntakeSnapshotClient {
  const IntakeSnapshotClient();

  Future<int> upload({
    required Uri endpoint,
    required String deviceId,
    required IntakeSnapshot snapshot,
    String? bearerToken,
    HttpClient? client,
  }) async {
    final http = client ?? HttpClient();
    try {
      final request = await http.putUrl(
        endpoint.resolve('/v1/intake/snapshot'),
      );
      request.headers
        ..contentType = ContentType.json
        ..set('X-Device-Id', deviceId);
      if (bearerToken?.isNotEmpty == true) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      request.add(utf8.encode(jsonEncode(snapshot.toJson())));
      final response = await request.close();
      final body = jsonDecode(await utf8.decoder.bind(response).join());
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw IntakeSnapshotException(response.statusCode, body);
      }
      final revision = (body as Map)['sourceRevision'];
      if (revision is! int) {
        throw const FormatException('Missing sourceRevision');
      }
      return revision;
    } finally {
      if (client == null) {
        http.close(force: true);
      }
    }
  }
}

class IntakeSnapshotException implements Exception {
  const IntakeSnapshotException(this.statusCode, this.body);
  final int statusCode;
  final Object? body;
}
