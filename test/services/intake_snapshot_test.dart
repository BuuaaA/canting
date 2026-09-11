import 'dart:convert';
import 'dart:io';

import 'package:canting/core/models/meal_record.dart';
import 'package:canting/core/models/meal_draft_v2.dart';
import 'package:canting/services/recognition_contract.dart';
import 'package:canting/services/intake_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a fixed seven-day, image-free snapshot', () {
    final today = DateTime(2026, 9, 11);
    final snapshot = IntakeSnapshot.fromMeals(
      installationId: 'device-123',
      revision: 4,
      today: today,
      timezone: 'Asia/Shanghai',
      meals: [
        MealRecord(
          mealId: 'meal-1',
          mealType: 'lunch',
          timestamp: today,
          dishes: const [MealDish(name: '鸡腿', matchConfidence: .9)],
        ),
      ],
    );

    expect(snapshot.toJson()['snapshotRevision'], 4);
    expect(snapshot.days, hasLength(7));
    expect(snapshot.days.last['mealIds'], ['meal-1']);
    expect(snapshot.days.last['intakeItems'], hasLength(1));
    expect(snapshot.days.last['intakeItems'].single['grams'], isNull);
    final encoded = snapshot.toJson();
    expect(encoded['days'].toString(), contains('mealId'));
    expect(encoded['days'].toString(), isNot(contains('merchant')));
    expect(encoded['days'].toString(), isNot(contains('recognition_v2')));
    expect(encoded['days'].toString(), isNot(contains('imageUri')));
    expect(encoded['days'].toString(), isNot(contains('ocr')));
  });

  test('exports effective V2 ml amount and keeps unknown facts incomplete', () {
    final schema = jsonDecode(
      File('dev-docs/recognition-v2/recognition.schema.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final examples = jsonDecode(
      File('dev-docs/recognition-v2/examples.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final contract = RecognitionContract(schema);
    final draft =
        MealDraftV2(
          contract,
          examples['personal_half_bowl'] as Map<String, dynamic>,
          simulated: true,
        )..setIntake(
          'c-rice',
          basis: 'personal_consumed',
          portion: {'value': 300, 'unit': 'ml', 'band': 'unknown'},
        );
    final meal = draft.toMeal(
      mealType: 'lunch',
      timestamp: DateTime(2026, 9, 11),
    );
    final json = IntakeSnapshot.fromMeals(
      installationId: 'device-123',
      revision: 1,
      today: DateTime(2026, 9, 11),
      timezone: 'Asia/Shanghai',
      meals: [meal],
    ).toJson();
    final items = (json['days'] as List).last['intakeItems'] as List;
    expect(
      items.any((item) => item['amount'] == 300 && item['unit'] == 'ml'),
      isTrue,
    );
    expect(items.every((item) => item['grams'] == null), isTrue);
    expect(items.every((item) => item['amountBasis'] == 'unknown'), isTrue);
  });
}
