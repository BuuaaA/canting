import 'dart:math' as math;

import 'package:canting/core_engine.dart';

import 'pet_data.dart';
import 'pet_dialogues.dart';
import 'pet_update_result.dart';
import 'vitality_log.dart';

class PetStateMachine {
  PetStateMachine({
    PetDialogues? dialogues,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _dialogues = dialogues ?? PetDialogues.defaults(),
       _clock = clock ?? DateTime.now,
       _customIdGenerator = idGenerator;

  static const int minimumVitality = 15;
  static const int maximumVitality = 100;
  static const int initialVitality = 60;
  static const Duration petTapCooldown = Duration(hours: 4);
  static const int maximumDailyPetTaps = 3;

  final PetDialogues _dialogues;

  /// 台词数据源（模块 7 当日台词需要 daily 区块）。
  PetDialogues get dialogues => _dialogues;

  final DateTime Function() _clock;
  final String Function()? _customIdGenerator;
  int _idCounter = 0;

  PetData createPet({required String petType, required String petName}) {
    final now = _clock();
    return PetData(
      petType: petType,
      petName: petName,
      growthStage: GrowthStage.egg,
      vitality: initialVitality,
      growth: 0,
      lastVitalityUpdate: now,
      createdAt: now,
    );
  }

  PetUpdateResult onCompletionRecorded({
    required PetData pet,
    required CompletionResult completion,
    required String mealId,
  }) {
    return onMealRecorded(
      pet: pet,
      completionRate: completion.overall,
      completionByCategory: completion.byCategory,
      mealId: mealId,
    );
  }

  PetUpdateResult onMealRecorded({
    required PetData pet,
    required double completionRate,
    required Map<String, double> completionByCategory,
    required String mealId,
  }) {
    _validateMealInput(completionRate, completionByCategory, mealId);
    final now = _clock();
    final vitalityDelta = vitalityChangeForCompletion(completionRate);
    final growthDelta = growthChangeForCompletion(completionRate);
    final vitalityAfter = _boundedVitality(pet.vitality, vitalityDelta);
    final mealLog = VitalityLog(
      logId: _nextId(now),
      timestamp: now,
      changeType: _mealChangeType(completionRate),
      changeValue: vitalityAfter - pet.vitality,
      vitalityBefore: pet.vitality,
      vitalityAfter: vitalityAfter,
      relatedMealId: mealId,
      completionRate: completionRate,
    );

    final counters = _updatedCounters(
      good: pet.consecutiveGoodMeals,
      bad: pet.consecutiveBadMeals,
      completionRate: completionRate,
    );
    final isSameMealDay =
        pet.lastMealTime != null && _isSameDay(pet.lastMealTime!, now);
    final todayCount = isSameMealDay ? pet.todayMealCount + 1 : 1;
    final previousTotal = isSameMealDay
        ? pet.todayCompletionRate * pet.todayMealCount
        : 0.0;
    final todayRate = (previousTotal + completionRate) / todayCount;

    var updatedPet = pet.copyWith(
      vitality: vitalityAfter,
      growth: pet.growth + growthDelta,
      lastVitalityUpdate: mealLog.changeValue == 0
          ? pet.lastVitalityUpdate
          : now,
      lastMealTime: now,
      consecutiveGoodMeals: counters.good,
      consecutiveBadMeals: counters.bad,
      consecutiveNoRecordDays: 0,
      todayMealCount: todayCount,
      todayCompletionRate: todayRate,
    );
    final evolution = _applyEvolution(
      pet: updatedPet,
      now: now,
      relatedMealId: mealId,
    );
    updatedPet = evolution.pet;
    final continuous = checkContinuousBehavior(pet: updatedPet);

    return PetUpdateResult(
      pet: updatedPet,
      logs: [mealLog, ...evolution.logs],
      vitalityChange: updatedPet.vitality - pet.vitality,
      growthChange: growthDelta,
      dialogue: getMealReactionDialogue(
        petType: pet.petType,
        completionRate: completionRate,
      ),
      gapDialogue: getGapDialogue(
        petType: pet.petType,
        completionByCategory: completionByCategory,
      ),
      visualReaction: evolution.previousStage == null
          ? _visualForCompletion(completionRate)
          : PetVisualReaction.evolve,
      continuousBehavior: continuous,
      previousGrowthStage: evolution.previousStage,
    );
  }

  PetUpdateResult onMealDeleted({
    required PetData pet,
    required String mealId,
    required List<VitalityLog> logs,
  }) {
    final target = _latestActiveMealLog(logs, mealId);
    if (target == null) {
      return _unchanged(pet);
    }

    final now = _clock();
    final markedTarget = target.copyWith(isReversed: true);
    final vitalityAfter = _boundedVitality(pet.vitality, -target.changeValue);
    final rollbackLog = VitalityLog(
      logId: _nextId(now),
      timestamp: now,
      changeType: VitalityChangeType.mealDelete,
      changeValue: vitalityAfter - pet.vitality,
      vitalityBefore: pet.vitality,
      vitalityAfter: vitalityAfter,
      relatedMealId: mealId,
      reversesLogId: target.logId,
    );

    final effectiveLogs = [...logs, markedTarget];
    var updatedPet = pet.copyWith(
      vitality: vitalityAfter,
      lastVitalityUpdate: rollbackLog.changeValue == 0
          ? pet.lastVitalityUpdate
          : now,
    );
    updatedPet = _rebuildMealDerivedState(
      pet: updatedPet,
      activeMealLogs: _activeMealLogs(effectiveLogs),
      now: now,
    );
    final continuous = checkContinuousBehavior(pet: updatedPet);

    return PetUpdateResult(
      pet: updatedPet,
      logs: [markedTarget, rollbackLog],
      vitalityChange: updatedPet.vitality - pet.vitality,
      growthChange: 0,
      dialogue:
          continuous?.dialogue ??
          getStatusDialogue(
            petType: pet.petType,
            state: getVitalityState(updatedPet.vitality),
          ),
      visualReaction:
          continuous?.visualReaction ??
          _visualForState(getVitalityState(updatedPet.vitality)),
      continuousBehavior: continuous,
    );
  }

  PetUpdateResult onMealEdited({
    required PetData pet,
    required String mealId,
    required List<VitalityLog> logs,
    required double newCompletionRate,
    required Map<String, double> newCompletionByCategory,
  }) {
    _validateMealInput(newCompletionRate, newCompletionByCategory, mealId);
    final target = _latestActiveMealLog(logs, mealId);
    if (target == null) {
      return _unchanged(pet);
    }

    final now = _clock();
    final markedTarget = target.copyWith(isReversed: true);
    final vitalityAfterRollback = _boundedVitality(
      pet.vitality,
      -target.changeValue,
    );
    final rollbackLog = VitalityLog(
      logId: _nextId(now),
      timestamp: now,
      changeType: VitalityChangeType.mealEdit,
      changeValue: vitalityAfterRollback - pet.vitality,
      vitalityBefore: pet.vitality,
      vitalityAfter: vitalityAfterRollback,
      relatedMealId: mealId,
      reversesLogId: target.logId,
    );

    final newRuleDelta = vitalityChangeForCompletion(newCompletionRate);
    final finalVitality = _boundedVitality(vitalityAfterRollback, newRuleDelta);
    final newEffectLog = VitalityLog(
      logId: _nextId(now),
      timestamp: target.timestamp,
      changeType: VitalityChangeType.mealEdit,
      changeValue: finalVitality - vitalityAfterRollback,
      vitalityBefore: vitalityAfterRollback,
      vitalityAfter: finalVitality,
      relatedMealId: mealId,
      completionRate: newCompletionRate,
    );

    final effectiveLogs = [...logs, markedTarget, newEffectLog];
    var updatedPet = pet.copyWith(
      vitality: finalVitality,
      lastVitalityUpdate:
          rollbackLog.changeValue == 0 && newEffectLog.changeValue == 0
          ? pet.lastVitalityUpdate
          : now,
    );
    updatedPet = _rebuildMealDerivedState(
      pet: updatedPet,
      activeMealLogs: _activeMealLogs(effectiveLogs),
      now: now,
    );
    final continuous = checkContinuousBehavior(pet: updatedPet);

    return PetUpdateResult(
      pet: updatedPet,
      logs: [markedTarget, rollbackLog, newEffectLog],
      vitalityChange: updatedPet.vitality - pet.vitality,
      growthChange: 0,
      dialogue: getMealReactionDialogue(
        petType: pet.petType,
        completionRate: newCompletionRate,
      ),
      gapDialogue: getGapDialogue(
        petType: pet.petType,
        completionByCategory: newCompletionByCategory,
      ),
      visualReaction: _visualForCompletion(newCompletionRate),
      continuousBehavior: continuous,
    );
  }

  PetUpdateResult checkOfflineDecay({
    required PetData pet,
    required DateTime now,
  }) {
    final previousCheck = pet.lastOfflineDecayCheck;
    if (previousCheck != null &&
        (_isSameDay(previousCheck, now) || now.isBefore(previousCheck))) {
      return _unchanged(pet);
    }
    if (_isBeforeKnownActivity(pet, now)) {
      return _unchanged(pet);
    }

    final reference = pet.lastMealTime ?? pet.createdAt;
    final elapsed = now.difference(reference);
    final decay = elapsed > const Duration(hours: 48)
        ? -5
        : elapsed >= const Duration(hours: 24)
        ? -3
        : 0;
    final noRecordDays = elapsed.isNegative
        ? pet.consecutiveNoRecordDays
        : elapsed.inHours ~/ 24;
    final vitalityAfter = _boundedVitality(pet.vitality, decay);

    var updatedPet = pet.copyWith(
      vitality: vitalityAfter,
      lastVitalityUpdate: vitalityAfter == pet.vitality
          ? pet.lastVitalityUpdate
          : now,
      lastOfflineDecayCheck: now,
      consecutiveNoRecordDays: noRecordDays,
      todayMealCount: _isSameDay(reference, now) ? pet.todayMealCount : 0,
      todayCompletionRate: _isSameDay(reference, now)
          ? pet.todayCompletionRate
          : 0,
    );
    final resultLogs = <VitalityLog>[];
    if (decay != 0) {
      resultLogs.add(
        VitalityLog(
          logId: _nextId(now),
          timestamp: now,
          changeType: VitalityChangeType.noRecord,
          changeValue: vitalityAfter - pet.vitality,
          vitalityBefore: pet.vitality,
          vitalityAfter: vitalityAfter,
        ),
      );
    }
    final continuous = checkContinuousBehavior(pet: updatedPet);
    updatedPet = updatedPet.copyWith(
      growthStage: getGrowthStage(updatedPet.growth),
    );

    return PetUpdateResult(
      pet: updatedPet,
      logs: resultLogs,
      vitalityChange: vitalityAfter - pet.vitality,
      growthChange: 0,
      dialogue:
          continuous?.dialogue ??
          getStatusDialogue(
            petType: pet.petType,
            state: getVitalityState(vitalityAfter),
          ),
      visualReaction:
          continuous?.visualReaction ??
          _visualForState(getVitalityState(vitalityAfter)),
      continuousBehavior: continuous,
    );
  }

  PetUpdateResult onPetTap({required PetData pet, required DateTime now}) {
    final lastTap = pet.lastPetTapTime;
    if (lastTap != null &&
        (now.isBefore(lastTap) || now.difference(lastTap) < petTapCooldown)) {
      return _unchanged(pet);
    }

    final sameTapDay =
        pet.petTapCountDate != null && _isSameDay(pet.petTapCountDate!, now);
    final currentCount = sameTapDay ? pet.petTapsToday : 0;
    if (currentCount >= maximumDailyPetTaps) {
      return _unchanged(pet);
    }

    final vitalityAfter = _boundedVitality(pet.vitality, 1);
    final tapLog = VitalityLog(
      logId: _nextId(now),
      timestamp: now,
      changeType: VitalityChangeType.petTap,
      changeValue: vitalityAfter - pet.vitality,
      vitalityBefore: pet.vitality,
      vitalityAfter: vitalityAfter,
    );
    var updatedPet = pet.copyWith(
      vitality: vitalityAfter,
      growth: pet.growth + 1,
      lastVitalityUpdate: tapLog.changeValue == 0
          ? pet.lastVitalityUpdate
          : now,
      lastPetTapTime: now,
      petTapCountDate: now,
      petTapsToday: currentCount + 1,
    );
    final evolution = _applyEvolution(pet: updatedPet, now: now);
    updatedPet = evolution.pet;

    return PetUpdateResult(
      pet: updatedPet,
      logs: [tapLog, ...evolution.logs],
      vitalityChange: updatedPet.vitality - pet.vitality,
      growthChange: 1,
      dialogue: getStatusDialogue(
        petType: pet.petType,
        state: getVitalityState(updatedPet.vitality),
      ),
      visualReaction: evolution.previousStage == null
          ? PetVisualReaction.happy
          : PetVisualReaction.evolve,
      previousGrowthStage: evolution.previousStage,
    );
  }

  PetUpdateResult onDailyLogin({required PetData pet, required DateTime now}) {
    final lastLogin = pet.lastDailyLogin;
    if (lastLogin != null &&
        (_isSameDay(lastLogin, now) || now.isBefore(lastLogin))) {
      return _unchanged(pet);
    }

    var updatedPet = pet.copyWith(growth: pet.growth + 2, lastDailyLogin: now);
    final evolution = _applyEvolution(pet: updatedPet, now: now);
    updatedPet = evolution.pet;

    return PetUpdateResult(
      pet: updatedPet,
      logs: evolution.logs,
      vitalityChange: updatedPet.vitality - pet.vitality,
      growthChange: 2,
      dialogue: getStatusDialogue(
        petType: pet.petType,
        state: getVitalityState(updatedPet.vitality),
      ),
      visualReaction: evolution.previousStage == null
          ? PetVisualReaction.idle
          : PetVisualReaction.evolve,
      previousGrowthStage: evolution.previousStage,
    );
  }

  VitalityState getVitalityState(int vitality) {
    if (vitality < minimumVitality || vitality > maximumVitality) {
      throw RangeError.range(
        vitality,
        minimumVitality,
        maximumVitality,
        'vitality',
      );
    }
    if (vitality >= 80) return VitalityState.energetic;
    if (vitality >= 50) return VitalityState.good;
    if (vitality >= 25) return VitalityState.low;
    return VitalityState.expecting;
  }

  GrowthStage getGrowthStage(int growth) {
    if (growth < 0) {
      throw RangeError.value(growth, 'growth', 'Must not be negative');
    }
    if (growth >= 200) return GrowthStage.adult;
    if (growth >= 50) return GrowthStage.baby;
    return GrowthStage.egg;
  }

  String getStatusDialogue({
    required String petType,
    required VitalityState state,
  }) {
    return _dialogues.statusDialogue(petType, state);
  }

  String getMealReactionDialogue({
    required String petType,
    required double completionRate,
  }) {
    return _dialogues.mealReactionDialogue(petType, completionRate);
  }

  String getGapDialogue({
    required String petType,
    required Map<String, double> completionByCategory,
  }) {
    return _dialogues.gapDialogue(petType, completionByCategory);
  }

  ContinuousBehavior? checkContinuousBehavior({required PetData pet}) {
    if (pet.consecutiveNoRecordDays >= 3) {
      return ContinuousBehavior(
        code: 'no_record_days_3',
        dialogue: _dialogues.continuousDialogue(
          pet.petType,
          'no_record_days_3',
        ),
        visualReaction: PetVisualReaction.expecting,
      );
    }
    if (pet.consecutiveBadMeals >= 3) {
      return ContinuousBehavior(
        code: 'bad_meals_3',
        dialogue: _dialogues.continuousDialogue(pet.petType, 'bad_meals_3'),
        visualReaction: PetVisualReaction.curious,
      );
    }
    if (pet.consecutiveGoodMeals >= 3) {
      return ContinuousBehavior(
        code: 'good_meals_3',
        dialogue: _dialogues.continuousDialogue(pet.petType, 'good_meals_3'),
        visualReaction: PetVisualReaction.sparkle,
      );
    }
    return null;
  }

  static int vitalityChangeForCompletion(double completionRate) {
    _validateCompletionRate(completionRate);
    if (completionRate >= 0.8) return 10;
    if (completionRate >= 0.6) return 6;
    if (completionRate >= 0.4) return 2;
    if (completionRate >= 0.2) return -2;
    return -4;
  }

  /// 活力值合法区间钳制（[minimumVitality, maximumVitality]）。
  ///
  /// 所有会改写活力值的路径（记录/删除回退/重算/衰减）都必须走这里，
  /// 保证落在 PetData 构造器接受的区间内。
  static int clampVitality(int value) =>
      math.max(minimumVitality, math.min(maximumVitality, value));

  static int growthChangeForCompletion(double completionRate) {
    _validateCompletionRate(completionRate);
    if (completionRate >= 0.7) return 10;
    if (completionRate >= 0.4) return 5;
    return 3;
  }

  ({PetData pet, List<VitalityLog> logs, GrowthStage? previousStage})
  _applyEvolution({
    required PetData pet,
    required DateTime now,
    String? relatedMealId,
  }) {
    final targetStage = getGrowthStage(pet.growth);
    if (targetStage.index <= pet.growthStage.index) {
      return (pet: pet, logs: const [], previousStage: null);
    }

    final vitalityAfter = _boundedVitality(pet.vitality, 20);
    final evolveLog = VitalityLog(
      logId: _nextId(now),
      timestamp: now,
      changeType: VitalityChangeType.evolve,
      changeValue: vitalityAfter - pet.vitality,
      vitalityBefore: pet.vitality,
      vitalityAfter: vitalityAfter,
      relatedMealId: relatedMealId,
    );
    return (
      pet: pet.copyWith(
        growthStage: targetStage,
        vitality: vitalityAfter,
        lastVitalityUpdate: evolveLog.changeValue == 0
            ? pet.lastVitalityUpdate
            : now,
        evolvedAt: now,
      ),
      logs: [evolveLog],
      previousStage: pet.growthStage,
    );
  }

  PetData _rebuildMealDerivedState({
    required PetData pet,
    required List<VitalityLog> activeMealLogs,
    required DateTime now,
  }) {
    var good = 0;
    var bad = 0;
    for (final log in activeMealLogs) {
      final counters = _updatedCounters(
        good: good,
        bad: bad,
        completionRate: log.completionRate!,
      );
      good = counters.good;
      bad = counters.bad;
    }

    final lastMealTime = activeMealLogs.isEmpty
        ? null
        : activeMealLogs.last.timestamp;
    final todayLogs = activeMealLogs
        .where((log) => _isSameDay(log.timestamp, now))
        .toList();
    final todayRate = todayLogs.isEmpty
        ? 0.0
        : todayLogs
                  .map((log) => log.completionRate!)
                  .reduce((left, right) => left + right) /
              todayLogs.length;
    final noRecordReference = lastMealTime ?? pet.createdAt;
    final elapsed = now.difference(noRecordReference);

    return pet.copyWith(
      lastMealTime: lastMealTime,
      consecutiveGoodMeals: good,
      consecutiveBadMeals: bad,
      consecutiveNoRecordDays: elapsed.isNegative
          ? pet.consecutiveNoRecordDays
          : elapsed.inHours ~/ 24,
      todayMealCount: todayLogs.length,
      todayCompletionRate: todayRate,
    );
  }

  List<VitalityLog> _activeMealLogs(List<VitalityLog> logs) {
    final latestById = <String, VitalityLog>{};
    for (final log in logs) {
      latestById[log.logId] = log;
    }
    final active = latestById.values
        .where((log) => log.isActiveMealEffect)
        .toList();
    active.sort((left, right) => left.timestamp.compareTo(right.timestamp));
    return active;
  }

  VitalityLog? _latestActiveMealLog(List<VitalityLog> logs, String mealId) {
    final matching = _activeMealLogs(logs)
        .where((log) => log.relatedMealId == mealId)
        .toList();
    return matching.isEmpty ? null : matching.last;
  }

  PetUpdateResult _unchanged(PetData pet) {
    final state = getVitalityState(pet.vitality);
    return PetUpdateResult(
      pet: pet,
      logs: const [],
      vitalityChange: 0,
      growthChange: 0,
      dialogue: getStatusDialogue(petType: pet.petType, state: state),
      visualReaction: _visualForState(state),
      wasApplied: false,
    );
  }

  static ({int good, int bad}) _updatedCounters({
    required int good,
    required int bad,
    required double completionRate,
  }) {
    var updatedGood = good;
    var updatedBad = bad;

    if (completionRate >= 0.7) {
      updatedGood += 1;
    } else if (completionRate < 0.6) {
      updatedGood = 0;
    }

    if (completionRate < 0.4) {
      updatedBad += 1;
    } else if (completionRate >= 0.6) {
      updatedBad = 0;
    }

    return (good: updatedGood, bad: updatedBad);
  }

  static VitalityChangeType _mealChangeType(double completionRate) {
    if (completionRate >= 0.6) return VitalityChangeType.mealGood;
    if (completionRate >= 0.4) return VitalityChangeType.mealMid;
    return VitalityChangeType.mealPoor;
  }

  static PetVisualReaction _visualForCompletion(double completionRate) {
    if (completionRate >= 0.8) return PetVisualReaction.bounce;
    if (completionRate >= 0.6) return PetVisualReaction.happy;
    if (completionRate >= 0.4) return PetVisualReaction.eat;
    if (completionRate >= 0.2) return PetVisualReaction.curious;
    return PetVisualReaction.expecting;
  }

  static PetVisualReaction _visualForState(VitalityState state) {
    return switch (state) {
      VitalityState.energetic => PetVisualReaction.bounce,
      VitalityState.good => PetVisualReaction.idle,
      VitalityState.low => PetVisualReaction.curious,
      VitalityState.expecting => PetVisualReaction.expecting,
    };
  }

  static int _boundedVitality(int vitality, int change) =>
      clampVitality(vitality + change);

  static bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  static bool _isBeforeKnownActivity(PetData pet, DateTime now) {
    final timestamps = [
      pet.createdAt,
      pet.lastVitalityUpdate,
      if (pet.lastMealTime != null) pet.lastMealTime!,
      if (pet.lastPetTapTime != null) pet.lastPetTapTime!,
      if (pet.lastDailyLogin != null) pet.lastDailyLogin!,
    ];
    return timestamps.any(now.isBefore);
  }

  static void _validateMealInput(
    double completionRate,
    Map<String, double> completionByCategory,
    String mealId,
  ) {
    _validateCompletionRate(completionRate);
    if (mealId.trim().isEmpty) {
      throw ArgumentError.value(mealId, 'mealId', 'Must not be empty');
    }
    for (final entry in completionByCategory.entries) {
      if (!entry.value.isFinite || entry.value < 0) {
        throw RangeError.value(
          entry.value,
          'completionByCategory[${entry.key}]',
          'Must be finite and non-negative',
        );
      }
    }
  }

  static void _validateCompletionRate(double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw RangeError.range(value, 0, 1, 'completionRate');
    }
  }

  String _nextId(DateTime now) {
    final customId = _customIdGenerator;
    if (customId != null) return customId();
    final sequence = _idCounter++;
    return 'pet-${now.microsecondsSinceEpoch}-$sequence';
  }
}

class PetEngine extends PetStateMachine {
  PetEngine({super.dialogues, super.clock, super.idGenerator});
}
