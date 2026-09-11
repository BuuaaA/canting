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
    Map<String, dynamic>? energy,
  }) {
    final anchor = DateTime(today.year, today.month, today.day);
    final byDay = <String, List<MealRecord>>{};
    for (final meal in meals) {
      final key = dateKey(meal.timestamp);
      byDay.putIfAbsent(key, () => []).add(meal);
    }
    final days = <Map<String, dynamic>>[];
    for (var offset = -6; offset <= 0; offset++) {
      final day = anchor.add(Duration(days: offset));
      final key = dateKey(day);
      final records = byDay[key] ?? const <MealRecord>[];
      days.add({
        'date': key,
        'status': records.isEmpty ? 'missing' : 'known',
        'mealIds': records.map((meal) => meal.mealId).toList(growable: false),
        'meals': records.map((meal) => meal.toJson()).toList(growable: false),
        'intakeItems': records.expand(_items).toList(growable: false),
      });
    }
    return IntakeSnapshot(
      installationId: installationId,
      revision: revision,
      timezone: today.timeZoneName,
      startDate: days.first['date'] as String,
      endDate: days.last['date'] as String,
      days: days,
      energy: energy,
    );
  }

  static Iterable<Map<String, dynamic>> _items(MealRecord meal) sync* {
    for (final dish in meal.dishes) {
      final food = dish.food;
      final category = food?.facts.category;
      // Legacy MealDish stores food-group servings, not a trustworthy food
      // gram value. Keep grams unknown instead of inventing a conversion.
      const double? grams = null;
      yield {
        'foodKey': food?.facts.key,
        'name': dish.name,
        if (category != null) 'category': _category(category),
        'grams': grams,
        'unit': grams == null ? 'unknown' : 'g',
        'amountBasis': 'unknown',
        'confidence': dish.matchConfidence == 0 ? null : dish.matchConfidence,
        'source': dish.matchConfidence > 0 ? 'local_rule' : 'manual',
        'estimateSource': dish.matchedDishId,
      };
    }
  }

  static String? _category(String value) => switch (value) {
    'grain_tuber' => 'grain',
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
      final request = await http.putUrl(endpoint.resolve('/v1/intake/snapshot'));
      request.headers
        ..contentType = ContentType.json
        ..set('X-Device-Id', deviceId);
      if (bearerToken?.isNotEmpty == true) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
      }
      request.add(utf8.encode(jsonEncode(snapshot.toJson())));
      final response = await request.close();
      final body = jsonDecode(await utf8.decoder.bind(response).join());
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw IntakeSnapshotException(response.statusCode, body);
      }
      final revision = (body as Map)['sourceRevision'];
      if (revision is! int) throw const FormatException('Missing sourceRevision');
      return revision;
    } finally {
      if (client == null) http.close(force: true);
    }
  }
}

class IntakeSnapshotException implements Exception {
  const IntakeSnapshotException(this.statusCode, this.body);
  final int statusCode;
  final Object? body;
}
