import 'package:flutter_test/flutter_test.dart';
import 'package:canting/core/record_window.dart';
import 'package:canting/core/models/meal_record.dart';
import 'package:canting/core/models/portions.dart';

void main() {
  test('calendar windows include leap day and exclude end boundary', () {
    final asOf = DateTime(2024, 3, 1, 15);
    final w = RecordWindow.build(
      [
        MealRecord(
          mealId: 'before',
          mealType: 'lunch',
          timestamp: DateTime(2024, 2, 23),
          portionsTotal: const Portions(grains: 20),
        ),
        MealRecord(
          mealId: 'start',
          mealType: 'lunch',
          timestamp: DateTime(2024, 2, 24),
          portionsTotal: const Portions(grains: 1),
        ),
        MealRecord(
          mealId: 'leap',
          mealType: 'lunch',
          timestamp: DateTime(2024, 2, 29),
          portionsTotal: const Portions(grains: 2),
        ),
        MealRecord(
          mealId: 'end',
          mealType: 'lunch',
          timestamp: DateTime(2024, 3, 2),
          portionsTotal: const Portions(grains: 30),
        ),
      ],
      days: 7,
      asOf: asOf,
    );
    expect(w.recordedDays, 2);
    expect(w.missingDays, 5);
    expect(w.knownSubtotal.grains, 3);
  });
  test('unknown is partial and never a ledger zero', () {
    final day = DateTime(2026, 1, 1);
    final w = RecordWindow.build(
      [
        MealRecord(
          mealId: 'unknown',
          mealType: 'lunch',
          timestamp: day,
          dishes: [MealDish(name: '未知', contributionsKnown: false)],
        ),
      ],
      days: 7,
      asOf: day,
    );
    expect(w.partialDays, 1);
    expect(w.unknownItemCount, 1);
    expect(w.knownDays, isEmpty);
    expect(w.todayKnown, false);
  });
  test('empty 28 days means insufficient, not 100 percent', () {
    final w = RecordWindow.build([], days: 28, asOf: DateTime(2026, 1, 1));
    expect(w.dataStatus, 'insufficient');
    expect(w.missingDays, 28);
    expect(w.recordedDays, 0);
  });
  for (final date in [
    DateTime(2026, 1, 1),
    DateTime(2024, 3, 1),
    DateTime(2026, 5, 1),
  ]) {
    test('inclusive start exclusive end for 7 and 28 at $date', () {
      for (final days in [7, 28]) {
        final start = DateTime(date.year, date.month, date.day - days + 1),
            end = DateTime(date.year, date.month, date.day + 1);
        final meals = [
          for (final entry in {
            'before': start.subtract(const Duration(microseconds: 1)),
            'start': start,
            'last': end.subtract(const Duration(microseconds: 1)),
            'end': end,
          }.entries)
            MealRecord(
              mealId: entry.key,
              mealType: 'lunch',
              timestamp: entry.value,
              portionsTotal: const Portions(grains: 1),
            ),
        ];
        final w = RecordWindow.build(meals, days: days, asOf: date);
        expect(w.meals.map((m) => m.mealId), ['start', 'last']);
        expect(w.knownSubtotal.grains, 2);
      }
    });
  }
}
