import 'models/completion_result.dart';
import 'models/daily_intake.dart';
import 'models/portions.dart';

/// Calculates per-group and overall daily dietary completion.
class CompletionCalculator {
  CompletionResult calculate({
    required Portions eatenPortions,
    required DailyIntake dailyIntake,
    String sodiumLevel = 'mid',
  }) {
    if (!const {'low', 'mid', 'high'}.contains(sodiumLevel)) {
      throw ArgumentError.value(
        sodiumLevel,
        'sodiumLevel',
        'must be low, mid, or high',
      );
    }

    final target = dailyIntake.portions;
    final completion = <String, double>{
      for (final category in target.byCategory.keys)
        category: _completionRate(
          eatenPortions.valueFor(category),
          target.valueFor(category),
        ),
    };
    final average =
        completion.values.reduce((sum, value) => sum + value) /
        completion.length;
    final hasVeryLowCategory = completion.values.any((value) => value < 0.3);
    final overall = hasVeryLowCategory && average > 0.7 ? 0.7 : average;

    String? biggestGap;
    var lowestCompletion = 1.0;
    for (final entry in completion.entries) {
      if (entry.value < lowestCompletion) {
        biggestGap = entry.key;
        lowestCompletion = entry.value;
      }
    }

    return CompletionResult(
      overall: overall,
      byCategory: Map.unmodifiable(completion),
      biggestGap: biggestGap,
      sodiumLevel: sodiumLevel,
    );
  }

  static double _completionRate(double eaten, double target) {
    if (target <= 0) {
      return 1;
    }
    return (eaten / target).clamp(0.0, 1.0).toDouble();
  }
}
