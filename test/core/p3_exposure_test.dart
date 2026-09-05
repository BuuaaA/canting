import 'package:flutter_test/flutter_test.dart';
import 'package:canting/core/exposure.dart';
import 'package:canting/core/models/meal_record.dart';
import 'package:canting/core/models/local_food.dart';

MealRecord drink(String id, String sugar, DateTime date, {int lines = 1}) =>
    MealRecord(
      mealId: id,
      mealType: 'lunch',
      timestamp: date,
      dishes: List.generate(
        lines,
        (_) => MealDish(
          name: '饮品',
          quantity: 2,
          contributionsKnown: false,
          food: FoodObservation(
            facts: const FoodFacts(name: '饮品', category: 'milk_tea'),
            spec: OrderSpec(sugar: sugar),
            confirmed: true,
          ),
        ),
      ),
    );
void main() {
  for (final sugar in ['low', 'regular', 'high']) {
    test('$sugar counts first occurrence and repeats only across meal IDs', () {
      final d = DateTime(2026, 1, 1);
      final first = drink('a', sugar, d, lines: 2);
      expect(Exposure.counts([first])['sugary_drink'], 1);
      expect(Exposure.counts([first, drink('b', 'low', d)])['sugary_drink'], 2);
    });
  }
  test('none/unknown do not assert added sugar', () {
    expect(
      Exposure.counts([
        drink('a', 'none', DateTime(2026)),
        drink('b', 'unknown', DateTime(2026)),
      ]),
      isEmpty,
    );
  });
  test('burger does not imply fried', () {
    final meal = MealRecord(
      mealId: 'b',
      mealType: 'lunch',
      timestamp: DateTime(2026),
      dishes: [
        MealDish(
          name: '汉堡',
          contributionsKnown: false,
          food: const FoodObservation(
            facts: FoodFacts(name: '汉堡', category: 'burger'),
          ),
        ),
      ],
    );
    expect(Exposure.families(meal), isEmpty);
  });
}
