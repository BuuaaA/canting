import 'package:canting/pet/pet_data.dart';
import 'package:test/test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 1, 8);

  PetData buildPet({
    int vitality = 75,
    int growth = 20,
    DateTime? lastMealTime,
  }) {
    return PetData(
      petType: 'cat',
      petName: 'Mimi',
      growthStage: GrowthStage.egg,
      vitality: vitality,
      growth: growth,
      lastVitalityUpdate: createdAt,
      lastMealTime: lastMealTime,
      createdAt: createdAt,
    );
  }

  group('PetData', () {
    test('rejects unsupported types and vitality outside 15 to 100', () {
      expect(
        () => PetData(
          petType: 'rabbit',
          petName: 'Mimi',
          growthStage: GrowthStage.egg,
          vitality: 75,
          growth: 0,
          lastVitalityUpdate: createdAt,
          createdAt: createdAt,
        ),
        throwsArgumentError,
      );
      expect(() => buildPet(vitality: 14), throwsRangeError);
      expect(() => buildPet(vitality: 101), throwsRangeError);
    });

    test('round-trips the persistence JSON', () {
      final mealTime = DateTime.utc(2026, 9, 1, 12);
      final original = buildPet(lastMealTime: mealTime).copyWith(
        consecutiveGoodMeals: 2,
        todayMealCount: 2,
        todayCompletionRate: 0.75,
        nextMealSummary: '18:30 vegetables',
      );

      final restored = PetData.fromJson(original.toJson());

      expect(restored.petType, original.petType);
      expect(restored.growthStage, original.growthStage);
      expect(restored.lastMealTime, mealTime);
      expect(restored.consecutiveGoodMeals, 2);
      expect(restored.todayCompletionRate, 0.75);
    });

    test('copyWith can explicitly clear nullable timestamps', () {
      final pet = buildPet(lastMealTime: createdAt);

      expect(pet.copyWith(lastMealTime: null).lastMealTime, isNull);
    });

    test('builds the native widget JSON with derived vitality state', () {
      final widgetJson = buildPet(vitality: 22).toWidgetJson();

      expect(widgetJson['growth_stage'], 'egg');
      expect(widgetJson['vitality_state'], 'expecting');
      expect(widgetJson['today_meal_count'], 0);
      expect(widgetJson['pet_sprite_name'], 'pet_cat_egg_expecting_0');
    });

    test('maps all vitality boundaries without a sick state', () {
      expect(buildPet(vitality: 80).vitalityState, VitalityState.energetic);
      expect(buildPet(vitality: 50).vitalityState, VitalityState.good);
      expect(buildPet(vitality: 25).vitalityState, VitalityState.low);
      expect(buildPet(vitality: 15).vitalityState, VitalityState.expecting);
    });
  });
}
