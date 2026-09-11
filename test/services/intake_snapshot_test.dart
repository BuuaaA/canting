import 'package:canting/core/models/meal_record.dart';
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
    expect(encoded.containsKey('meals'), isTrue);
    expect(encoded['days'].toString(), isNot(contains('merchant')));
    expect(encoded['days'].toString(), isNot(contains('recognition_v2')));
    expect(encoded['days'].toString(), isNot(contains('imageUri')));
    expect(encoded['days'].toString(), isNot(contains('ocr')));
  });
}
