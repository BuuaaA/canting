import 'dart:io';

import 'package:canting/core/models/daily_intake.dart';
import 'package:canting/core/models/meal_record.dart';
import 'package:canting/core/models/portions.dart';
import 'package:canting/core/recommendation_engine.dart';
import 'package:canting/data/food_database.dart';
import 'package:test/test.dart';

void main() {
  late RecommendationEngine engine;

  const dailyIntake = DailyIntake(
    grains: 6,
    vegetables: 4,
    fruits: 2,
    protein: 4,
    proteinSoy: 1,
    oil: 2.5,
    bmr: 1500,
    tdee: 2000,
  );

  setUpAll(() {
    final database = FoodDatabase.fromJson(
      dishesJson: File('assets/data/dishes.json').readAsStringSync(),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
    engine = RecommendationEngine(database);
  });

  group('RecommendationEngine time recommendation', () {
    test('uses the next regular meal window when there are no records', () {
      final result = engine.recommend(
        todayMeals: const [],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 2, 10),
        lastMealType: '',
      );

      expect(result.suggestedMealType, 'lunch');
      expect(result.suggestedTime, DateTime(2026, 9, 2, 12));
    });

    test('moves lunch-to-dinner timing into the dinner window', () {
      final result = engine.recommend(
        todayMeals: [
          _meal(id: 'lunch', type: 'lunch', time: DateTime(2026, 9, 2, 12)),
        ],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 2, 12, 30),
        lastMealType: 'lunch',
      );

      expect(result.suggestedMealType, 'dinner');
      expect(result.suggestedTime, DateTime(2026, 9, 2, 18));
      expect(result.reason, contains('不足2小时'));
    });

    test('extends the interval by one hour after four meals', () {
      final result = engine.recommend(
        todayMeals: [
          _meal(
            id: 'breakfast',
            type: 'breakfast',
            time: DateTime(2026, 9, 2, 7, 30),
          ),
          _meal(id: 'snack1', type: 'snack', time: DateTime(2026, 9, 2, 9)),
          _meal(
            id: 'snack2',
            type: 'snack',
            time: DateTime(2026, 9, 2, 10, 30),
          ),
          _meal(id: 'lunch', type: 'lunch', time: DateTime(2026, 9, 2, 12)),
        ],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 2, 13),
        lastMealType: 'lunch',
      );

      expect(result.suggestedTime, DateTime(2026, 9, 2, 18, 30));
    });

    test('delays breakfast after a snack at or after 22:00', () {
      final result = engine.recommend(
        todayMeals: [
          _meal(
            id: 'late-snack',
            type: 'snack',
            time: DateTime(2026, 9, 2, 22, 15),
          ),
        ],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 2, 22, 30),
        lastMealType: 'snack',
      );

      expect(result.suggestedMealType, 'breakfast');
      expect(result.suggestedTime, DateTime(2026, 9, 3, 8, 30));
    });

    test('does not recommend a same-day regular meal after 21:00', () {
      final result = engine.recommend(
        todayMeals: [
          _meal(
            id: 'late-lunch',
            type: 'lunch',
            time: DateTime(2026, 9, 2, 16),
          ),
        ],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 2, 20),
        lastMealType: 'lunch',
      );

      expect(result.suggestedMealType, 'breakfast');
      expect(result.suggestedTime, DateTime(2026, 9, 3, 7, 30));
    });
  });

  group('RecommendationEngine content recommendation', () {
    test(
      'prioritizes the largest gap and avoids high-oil dishes when over',
      () {
        final result = engine.recommend(
          todayMeals: [
            _meal(
              id: 'lunch',
              type: 'lunch',
              time: DateTime(2026, 9, 2, 12),
              portions: const Portions(
                grains: 6,
                vegetables: 0,
                fruits: 2,
                protein: 4,
                proteinSoy: 1,
                oil: 4,
              ),
              sodiumLevel: 'high',
            ),
          ],
          dailyIntake: dailyIntake,
          now: DateTime(2026, 9, 2, 14),
          lastMealType: 'lunch',
        );

        expect(result.primary, hasLength(1));
        expect(result.alternatives, hasLength(2));
        expect(result.primary.single.primaryCategory, 'vegetables');
        expect(result.primary.single.oilLevel, 'low');
        expect(result.reason, contains('蔬菜缺口最大'));
        expect(result.reason, contains('油盐已偏高'));
      },
    );

    test('applies diversity penalty to a group dominating the last meal', () {
      final result = engine.recommend(
        todayMeals: [
          _meal(
            id: 'earlier',
            type: 'breakfast',
            time: DateTime(2026, 9, 2, 8),
            portions: const Portions(
              grains: 6,
              fruits: 0.8,
              protein: 4,
              proteinSoy: 1,
              oil: 1,
            ),
          ),
          _meal(
            id: 'latest',
            type: 'lunch',
            time: DateTime(2026, 9, 2, 12),
            portions: const Portions(vegetables: 2),
          ),
        ],
        dailyIntake: const DailyIntake(
          grains: 6,
          vegetables: 10,
          fruits: 2,
          protein: 4,
          proteinSoy: 1,
          oil: 2.5,
          bmr: 1500,
          tdee: 2000,
        ),
        now: DateTime(2026, 9, 2, 15),
        lastMealType: 'lunch',
      );

      expect(result.primary.single.primaryCategory, 'fruits');
    });
  });
}

MealRecord _meal({
  required String id,
  required String type,
  required DateTime time,
  Portions portions = Portions.zero,
  String sodiumLevel = 'mid',
}) => MealRecord(
  mealId: id,
  mealType: type,
  timestamp: time,
  portionsTotal: portions,
  sodiumLevel: sodiumLevel,
);
