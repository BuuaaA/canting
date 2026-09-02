import 'package:canting/core/models/completion_result.dart';
import 'package:canting/pet/pet_data.dart';
import 'package:canting/pet/pet_engine.dart';
import 'package:canting/pet/pet_update_result.dart';
import 'package:canting/pet/vitality_log.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;
  late int nextId;
  late PetStateMachine engine;

  const balanced = {
    'grains': 0.8,
    'vegetables': 0.8,
    'protein': 0.8,
    'fruits': 0.8,
    'oil': 0.8,
  };

  PetData pet({
    String petType = 'cat',
    int vitality = 60,
    int growth = 0,
    DateTime? createdAt,
    DateTime? lastMealTime,
    DateTime? lastVitalityUpdate,
    DateTime? lastPetTapTime,
    DateTime? lastOfflineDecayCheck,
    DateTime? lastDailyLogin,
    DateTime? petTapCountDate,
    int consecutiveGoodMeals = 0,
    int consecutiveBadMeals = 0,
    int consecutiveNoRecordDays = 0,
    int petTapsToday = 0,
  }) {
    final created = createdAt ?? now;
    return PetData(
      petType: petType,
      petName: 'Mimi',
      growthStage: engine.getGrowthStage(growth),
      vitality: vitality,
      growth: growth,
      lastVitalityUpdate: lastVitalityUpdate ?? created,
      lastMealTime: lastMealTime,
      lastPetTapTime: lastPetTapTime,
      lastOfflineDecayCheck: lastOfflineDecayCheck,
      lastDailyLogin: lastDailyLogin,
      petTapCountDate: petTapCountDate,
      createdAt: created,
      consecutiveGoodMeals: consecutiveGoodMeals,
      consecutiveBadMeals: consecutiveBadMeals,
      consecutiveNoRecordDays: consecutiveNoRecordDays,
      petTapsToday: petTapsToday,
    );
  }

  setUp(() {
    now = DateTime.utc(2026, 9, 2, 8);
    nextId = 0;
    engine = PetStateMachine(
      clock: () => now,
      idGenerator: () => 'log-${nextId++}',
    );
  });

  group('PetStateMachine creation and boundaries', () {
    test('creates an egg with a safe starting vitality', () {
      final created = engine.createPet(petType: 'cat', petName: 'Mimi');

      expect(created.vitality, PetStateMachine.initialVitality);
      expect(created.growth, 0);
      expect(created.growthStage, GrowthStage.egg);
      expect(created.createdAt, now);
    });

    test('maps vitality and growth stage boundaries', () {
      expect(engine.getVitalityState(80), VitalityState.energetic);
      expect(engine.getVitalityState(50), VitalityState.good);
      expect(engine.getVitalityState(25), VitalityState.low);
      expect(engine.getVitalityState(15), VitalityState.expecting);
      expect(engine.getGrowthStage(49), GrowthStage.egg);
      expect(engine.getGrowthStage(50), GrowthStage.baby);
      expect(engine.getGrowthStage(200), GrowthStage.adult);
    });

    test('uses all five vitality changes and three growth changes', () {
      expect(PetStateMachine.vitalityChangeForCompletion(0.8), 10);
      expect(PetStateMachine.vitalityChangeForCompletion(0.6), 6);
      expect(PetStateMachine.vitalityChangeForCompletion(0.4), 2);
      expect(PetStateMachine.vitalityChangeForCompletion(0.2), -2);
      expect(PetStateMachine.vitalityChangeForCompletion(0.19), -4);

      expect(PetStateMachine.growthChangeForCompletion(0.7), 10);
      expect(PetStateMachine.growthChangeForCompletion(0.4), 5);
      expect(PetStateMachine.growthChangeForCompletion(0.39), 3);
    });

    test('applies the 15 to 100 vitality protection formula', () {
      final lower = engine.onMealRecorded(
        pet: pet(vitality: 16),
        completionRate: 0.1,
        completionByCategory: balanced,
        mealId: 'poor',
      );
      final upper = engine.onMealRecorded(
        pet: pet(vitality: 98),
        completionRate: 0.9,
        completionByCategory: balanced,
        mealId: 'good',
      );

      expect(lower.pet.vitality, 15);
      expect(lower.logs.first.changeValue, -1);
      expect(upper.pet.vitality, 100);
      expect(upper.logs.first.changeValue, 2);
    });
  });

  group('PetStateMachine meal updates', () {
    test('keeps numerical rules identical for all pet types', () {
      for (final petType in PetData.supportedPetTypes) {
        final result = engine.onMealRecorded(
          pet: pet(petType: petType),
          completionRate: 0.75,
          completionByCategory: balanced,
          mealId: 'meal-$petType',
        );

        expect(result.pet.vitality, 66);
        expect(result.pet.growth, 10);
      }
    });

    test('poor meals still add growth and never reduce existing growth', () {
      final result = engine.onMealRecorded(
        pet: pet(growth: 20),
        completionRate: 0.1,
        completionByCategory: balanced,
        mealId: 'meal-1',
      );

      expect(result.pet.vitality, 56);
      expect(result.pet.growth, 23);
      expect(result.growthChange, 3);
    });

    test('evolves at 50 and grants one 20 point vitality reward', () {
      final result = engine.onMealRecorded(
        pet: pet(vitality: 55, growth: 45),
        completionRate: 0.5,
        completionByCategory: balanced,
        mealId: 'meal-1',
      );

      expect(result.pet.growth, 50);
      expect(result.pet.growthStage, GrowthStage.baby);
      expect(result.pet.vitality, 77);
      expect(result.previousGrowthStage, GrowthStage.egg);
      expect(result.logs.last.changeType, VitalityChangeType.evolve);
    });

    test('evolves at 200 without ever lowering growth', () {
      final result = engine.onMealRecorded(
        pet: pet(vitality: 70, growth: 190),
        completionRate: 0.75,
        completionByCategory: balanced,
        mealId: 'meal-1',
      );

      expect(result.pet.growth, 200);
      expect(result.pet.growthStage, GrowthStage.adult);
      expect(result.pet.vitality, 96);
    });

    test('applies the explicit counter increment and reset rules', () {
      final between = engine.onMealRecorded(
        pet: pet(consecutiveGoodMeals: 2, consecutiveBadMeals: 2),
        completionRate: 0.65,
        completionByCategory: balanced,
        mealId: 'between',
      );
      expect(between.pet.consecutiveGoodMeals, 2);
      expect(between.pet.consecutiveBadMeals, 0);

      final middle = engine.onMealRecorded(
        pet: pet(consecutiveGoodMeals: 2, consecutiveBadMeals: 2),
        completionRate: 0.5,
        completionByCategory: balanced,
        mealId: 'middle',
      );
      expect(middle.pet.consecutiveGoodMeals, 0);
      expect(middle.pet.consecutiveBadMeals, 2);

      final good = engine.onMealRecorded(
        pet: pet(consecutiveGoodMeals: 2, consecutiveBadMeals: 2),
        completionRate: 0.75,
        completionByCategory: balanced,
        mealId: 'good',
      );
      expect(good.pet.consecutiveGoodMeals, 3);
      expect(good.pet.consecutiveBadMeals, 0);

      final bad = engine.onMealRecorded(
        pet: pet(consecutiveGoodMeals: 2, consecutiveBadMeals: 2),
        completionRate: 0.3,
        completionByCategory: balanced,
        mealId: 'bad',
      );
      expect(bad.pet.consecutiveGoodMeals, 0);
      expect(bad.pet.consecutiveBadMeals, 3);
    });

    test('accepts module A CompletionResult directly', () {
      const completion = CompletionResult(
        overall: 0.65,
        byCategory: balanced,
        biggestGap: null,
        sodiumLevel: 'mid',
      );

      final result = engine.onCompletionRecorded(
        pet: pet(),
        completion: completion,
        mealId: 'meal-1',
      );

      expect(result.pet.vitality, 66);
      expect(result.pet.growth, 5);
    });
  });

  group('PetStateMachine deletion and editing', () {
    test('deletion reverses the actual meal vitality but not growth', () {
      final recorded = engine.onMealRecorded(
        pet: pet(),
        completionRate: 0.85,
        completionByCategory: balanced,
        mealId: 'meal-1',
      );
      final deleted = engine.onMealDeleted(
        pet: recorded.pet,
        mealId: 'meal-1',
        logs: recorded.logs,
      );

      expect(deleted.pet.vitality, 60);
      expect(deleted.pet.growth, 10);
      expect(deleted.pet.todayMealCount, 0);
      expect(deleted.logs.first.isReversed, isTrue);
      expect(deleted.logs.last.changeType, VitalityChangeType.mealDelete);
    });

    test('a meal cannot be reversed twice', () {
      final recorded = engine.onMealRecorded(
        pet: pet(),
        completionRate: 0.85,
        completionByCategory: balanced,
        mealId: 'meal-1',
      );
      final deleted = engine.onMealDeleted(
        pet: recorded.pet,
        mealId: 'meal-1',
        logs: recorded.logs,
      );
      final secondDelete = engine.onMealDeleted(
        pet: deleted.pet,
        mealId: 'meal-1',
        logs: [...recorded.logs, ...deleted.logs],
      );

      expect(secondDelete.wasApplied, isFalse);
      expect(secondDelete.pet.vitality, 60);
    });

    test('editing rolls back old vitality then applies the new rule', () {
      final recorded = engine.onMealRecorded(
        pet: pet(),
        completionRate: 0.85,
        completionByCategory: balanced,
        mealId: 'meal-1',
      );
      final edited = engine.onMealEdited(
        pet: recorded.pet,
        mealId: 'meal-1',
        logs: recorded.logs,
        newCompletionRate: 0.1,
        newCompletionByCategory: const {'vegetables': 0.1},
      );

      expect(edited.pet.vitality, 56);
      expect(edited.pet.growth, 10);
      expect(edited.vitalityChange, -14);
      expect(edited.logs, hasLength(3));
      expect(edited.logs.first.isReversed, isTrue);

      final deletedEdit = engine.onMealDeleted(
        pet: edited.pet,
        mealId: 'meal-1',
        logs: [...recorded.logs, ...edited.logs],
      );
      expect(deletedEdit.pet.vitality, 60);
      expect(deletedEdit.pet.growth, 10);
    });
  });

  group('PetStateMachine offline decay', () {
    test('does not decay before 24 hours', () {
      final created = DateTime.utc(2026, 9, 1, 9);
      final result = engine.checkOfflineDecay(
        pet: pet(createdAt: created),
        now: DateTime.utc(2026, 9, 2, 8),
      );

      expect(result.vitalityChange, 0);
      expect(result.logs, isEmpty);
      expect(result.pet.lastOfflineDecayCheck, DateTime.utc(2026, 9, 2, 8));
    });

    test('decays by 3 at 24 through 48 hours only once per day', () {
      final created = DateTime.utc(2026, 9, 1, 8);
      final first = engine.checkOfflineDecay(
        pet: pet(createdAt: created),
        now: DateTime.utc(2026, 9, 2, 8),
      );
      final repeated = engine.checkOfflineDecay(
        pet: first.pet,
        now: DateTime.utc(2026, 9, 2, 20),
      );
      final exactly48 = engine.checkOfflineDecay(
        pet: pet(createdAt: created),
        now: DateTime.utc(2026, 9, 3, 8),
      );

      expect(first.pet.vitality, 57);
      expect(first.logs.single.changeValue, -3);
      expect(repeated.wasApplied, isFalse);
      expect(repeated.pet.vitality, 57);
      expect(exactly48.pet.vitality, 57);
    });

    test('decays by 5 after 48 hours and protects the lower bound', () {
      final created = DateTime.utc(2026, 8, 30, 8);
      final result = engine.checkOfflineDecay(
        pet: pet(vitality: 16, createdAt: created),
        now: DateTime.utc(2026, 9, 2, 8),
      );

      expect(result.pet.vitality, 15);
      expect(result.logs.single.changeValue, -1);
      expect(result.pet.consecutiveNoRecordDays, 3);
      expect(result.continuousBehavior?.code, 'no_record_days_3');
    });

    test('ignores a system clock that moved before known activity', () {
      final future = DateTime.utc(2026, 9, 3, 8);
      final result = engine.checkOfflineDecay(
        pet: pet(lastVitalityUpdate: future),
        now: now,
      );

      expect(result.wasApplied, isFalse);
      expect(result.pet.vitality, 60);
    });
  });

  group('PetStateMachine pet taps and daily login', () {
    test('enforces four hour cooldown and three taps per day', () {
      var current = pet();

      var result = engine.onPetTap(pet: current, now: now);
      current = result.pet;
      result = engine.onPetTap(
        pet: current,
        now: now.add(const Duration(hours: 3)),
      );
      expect(result.wasApplied, isFalse);

      for (final hours in [4, 8]) {
        result = engine.onPetTap(
          pet: current,
          now: now.add(Duration(hours: hours)),
        );
        current = result.pet;
        expect(result.wasApplied, isTrue);
      }
      result = engine.onPetTap(
        pet: current,
        now: now.add(const Duration(hours: 12)),
      );

      expect(result.wasApplied, isFalse);
      expect(current.petTapsToday, 3);
      expect(current.growth, 3);
      expect(current.vitality, 63);
    });

    test('resets the tap allowance on a new calendar day', () {
      final previousDay = now.subtract(const Duration(hours: 12));
      final result = engine.onPetTap(
        pet: pet(
          lastPetTapTime: previousDay,
          petTapCountDate: previousDay,
          petTapsToday: 3,
        ),
        now: now,
      );

      expect(result.wasApplied, isTrue);
      expect(result.pet.petTapsToday, 1);
    });

    test('a tap adds growth and can trigger evolution', () {
      final result = engine.onPetTap(pet: pet(growth: 49), now: now);

      expect(result.pet.growth, 50);
      expect(result.pet.growthStage, GrowthStage.baby);
      expect(result.pet.vitality, 81);
      expect(result.shouldPlayEvolution, isTrue);
    });

    test('daily login adds two growth only once per day', () {
      final first = engine.onDailyLogin(pet: pet(growth: 48), now: now);
      final repeated = engine.onDailyLogin(pet: first.pet, now: now);

      expect(first.pet.growth, 50);
      expect(first.pet.growthStage, GrowthStage.baby);
      expect(first.pet.vitality, 80);
      expect(repeated.wasApplied, isFalse);
      expect(repeated.pet.growth, 50);
    });
  });

  group('PetStateMachine gentle feedback', () {
    test('returns numerical, visual, and dialogue feedback together', () {
      final result = engine.onMealRecorded(
        pet: pet(),
        completionRate: 0.1,
        completionByCategory: const {'vegetables': 0.1},
        mealId: 'meal-1',
      );

      expect(result.vitalityChange, -4);
      expect(result.visualReaction, PetVisualReaction.expecting);
      expect(result.dialogue, isNotEmpty);
      expect(result.gapDialogue, isNotEmpty);
      expect(result.pet.vitalityState, isNotNull);
    });

    test('detects three good and three poor meals', () {
      final good = engine.checkContinuousBehavior(
        pet: pet(consecutiveGoodMeals: 3),
      );
      final bad = engine.checkContinuousBehavior(
        pet: pet(consecutiveBadMeals: 3),
      );

      expect(good?.visualReaction, PetVisualReaction.sparkle);
      expect(bad?.visualReaction, PetVisualReaction.curious);
      expect(good?.dialogue, isNot(contains('应该')));
      expect(bad?.dialogue, isNot(contains('生病')));
    });
  });

  group('PetEngine compatibility class', () {
    test('exposes the same state machine API', () {
      final compatibilityEngine = PetEngine(clock: () => now);

      expect(
        compatibilityEngine.createPet(petType: 'dog', petName: 'Pup'),
        isA<PetData>(),
      );
    });
  });
}
