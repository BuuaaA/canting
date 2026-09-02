import 'package:canting/pet/vitality_log.dart';
import 'package:test/test.dart';

void main() {
  final timestamp = DateTime.utc(2026, 9, 1, 12);

  VitalityLog buildLog() {
    return VitalityLog(
      logId: 'log-1',
      timestamp: timestamp,
      changeType: VitalityChangeType.mealGood,
      changeValue: 10,
      vitalityBefore: 70,
      vitalityAfter: 80,
      relatedMealId: 'meal-1',
      completionRate: 0.85,
    );
  }

  group('VitalityLog', () {
    test('round-trips JSON including the stable change type code', () {
      final restored = VitalityLog.fromJson(buildLog().toJson());

      expect(restored.changeType, VitalityChangeType.mealGood);
      expect(restored.toJson()['change_type'], 'meal_good');
      expect(restored.relatedMealId, 'meal-1');
      expect(restored.completionRate, 0.85);
    });

    test('marks a copied meal log as reversed', () {
      final reversed = buildLog().copyWith(isReversed: true);

      expect(reversed.isReversed, isTrue);
      expect(reversed.isActiveMealEffect, isFalse);
    });

    test('only a non-reversed meal record is an active meal effect', () {
      expect(buildLog().isActiveMealEffect, isTrue);
      expect(
        VitalityLog(
          logId: 'log-2',
          timestamp: timestamp,
          changeType: VitalityChangeType.mealDelete,
          changeValue: -10,
          vitalityBefore: 80,
          vitalityAfter: 70,
          relatedMealId: 'meal-1',
          reversesLogId: 'log-1',
        ).isActiveMealEffect,
        isFalse,
      );
    });

    test('rejects a change value inconsistent with before and after', () {
      expect(
        () => VitalityLog(
          logId: 'bad-log',
          timestamp: timestamp,
          changeType: VitalityChangeType.petTap,
          changeValue: 2,
          vitalityBefore: 70,
          vitalityAfter: 71,
        ),
        throwsArgumentError,
      );
    });
  });
}
