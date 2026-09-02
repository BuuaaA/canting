import 'dart:collection';

import 'pet_data.dart';
import 'vitality_log.dart';

enum PetVisualReaction {
  idle,
  bounce,
  happy,
  eat,
  curious,
  expecting,
  sparkle,
  evolve,
}

class ContinuousBehavior {
  const ContinuousBehavior({
    required this.code,
    required this.dialogue,
    required this.visualReaction,
  });

  final String code;
  final String dialogue;
  final PetVisualReaction visualReaction;
}

class PetUpdateResult {
  PetUpdateResult({
    required this.pet,
    required List<VitalityLog> logs,
    required this.vitalityChange,
    required this.growthChange,
    required this.dialogue,
    required this.visualReaction,
    this.gapDialogue,
    this.continuousBehavior,
    this.wasApplied = true,
    this.previousGrowthStage,
  }) : logs = UnmodifiableListView(logs);

  final PetData pet;

  /// New logs plus existing logs that must be updated, such as a reversed log.
  final List<VitalityLog> logs;
  final int vitalityChange;
  final int growthChange;
  final String dialogue;
  final String? gapDialogue;
  final PetVisualReaction visualReaction;
  final ContinuousBehavior? continuousBehavior;
  final bool wasApplied;
  final GrowthStage? previousGrowthStage;

  bool get shouldPlayEvolution => previousGrowthStage != null;
}
