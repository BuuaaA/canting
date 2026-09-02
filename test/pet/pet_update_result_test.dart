import 'package:canting/pet/pet_data.dart';
import 'package:canting/pet/pet_update_result.dart';
import 'package:canting/pet/vitality_log.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 2, 8);
  final pet = PetData(
    petType: 'dog',
    petName: 'Pup',
    growthStage: GrowthStage.baby,
    vitality: 80,
    growth: 50,
    lastVitalityUpdate: now,
    createdAt: now,
  );
  final log = VitalityLog(
    logId: 'log-1',
    timestamp: now,
    changeType: VitalityChangeType.evolve,
    changeValue: 20,
    vitalityBefore: 60,
    vitalityAfter: 80,
  );

  group('ContinuousBehavior', () {
    test('carries a gentle dialogue and visual reaction', () {
      const behavior = ContinuousBehavior(
        code: 'good_meals_3',
        dialogue: 'Great meals',
        visualReaction: PetVisualReaction.sparkle,
      );

      expect(behavior.code, 'good_meals_3');
      expect(behavior.visualReaction, PetVisualReaction.sparkle);
    });
  });

  group('PetUpdateResult', () {
    test('reports all three feedback layers and evolution', () {
      final result = PetUpdateResult(
        pet: pet,
        logs: [log],
        vitalityChange: 20,
        growthChange: 10,
        dialogue: 'Great meal',
        visualReaction: PetVisualReaction.evolve,
        previousGrowthStage: GrowthStage.egg,
      );

      expect(result.vitalityChange, 20);
      expect(result.dialogue, 'Great meal');
      expect(result.visualReaction, PetVisualReaction.evolve);
      expect(result.shouldPlayEvolution, isTrue);
    });

    test('protects returned logs from accidental mutation', () {
      final result = PetUpdateResult(
        pet: pet,
        logs: [log],
        vitalityChange: 20,
        growthChange: 0,
        dialogue: 'Hello',
        visualReaction: PetVisualReaction.idle,
      );

      expect(() => result.logs.add(log), throwsUnsupportedError);
    });
  });
}
