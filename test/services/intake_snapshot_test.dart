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

    final fixturePath = File(
      '${Directory.current.parent.parent.path}/handoffs/01/fixtures/flutter_intake_snapshot.json',
    );
    fixturePath.parent.createSync(recursive: true);
    fixturePath.writeAsStringSync(jsonEncode(json));
  });

  test(
    'V2 modes preserve effective amounts, unknown ml, exclusions, and paths',
    () {
      final schema = jsonDecode(
        File('dev-docs/recognition-v2/recognition.schema.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final examples = jsonDecode(
        File('dev-docs/recognition-v2/examples.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      MealRecord exportFor({
        required String basis,
        Map<String, dynamic>? portion,
        double? allocation,
        double? consumed,
        bool notEaten = false,
      }) {
        final draft = MealDraftV2(
          RecognitionContract(schema),
          examples['personal_half_bowl'] as Map<String, dynamic>,
          simulated: true,
        );
        if (basis == 'per_product_unit') {
          draft.editFact('p-meal', 'purchaseQuantity', 2);
        }
        draft.setIntake(
          'c-rice',
          basis: basis,
          portion: portion ?? {'value': 1, 'unit': 'g', 'band': 'unknown'},
          allocation: allocation,
          consumed: consumed,
          notEaten: notEaten,
        );
        return draft.toMeal(
          mealType: 'lunch',
          timestamp: DateTime(2026, 9, 11),
        );
      }

      Map<String, dynamic> onlyItem(MealRecord meal) {
        final json = IntakeSnapshot.fromMeals(
          installationId: 'device-123',
          revision: 1,
          today: DateTime(2026, 9, 11),
          timezone: 'Asia/Shanghai',
          meals: [meal],
        ).toJson();
        return ((json['days'] as List).last['intakeItems'] as List).single
            as Map<String, dynamic>;
      }

      final personal = onlyItem(
        exportFor(
          basis: 'personal_consumed',
          portion: {'value': 1, 'unit': 'g', 'band': 'unknown'},
        ),
      );
      expect(personal['amount'], 1);
      expect(personal['complete'], isFalse);

      final served = onlyItem(
        exportFor(basis: 'served_total', allocation: .5, consumed: .5),
      );
      expect(served['amount'], .25);

      final perUnit = onlyItem(
        exportFor(basis: 'per_product_unit', allocation: 1, consumed: .5),
      );
      expect(perUnit['amount'], 1);

      final unknownMl = onlyItem(
        exportFor(
          basis: 'served_total',
          portion: {'value': 300, 'unit': 'ml', 'band': 'unknown'},
        ),
      );
      expect(unknownMl['unit'], 'ml');
      expect(unknownMl['amount'], isNull);
      expect(unknownMl['complete'], isFalse);

      final excluded = IntakeSnapshot.fromMeals(
        installationId: 'device-123',
        revision: 1,
        today: DateTime(2026, 9, 11),
        timezone: 'Asia/Shanghai',
        meals: [exportFor(basis: 'personal_consumed', notEaten: true)],
      ).toJson();
      expect((excluded['days'] as List).last['intakeItems'], isEmpty);
    },
  );
}
