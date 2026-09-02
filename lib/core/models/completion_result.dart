class CompletionResult {
  const CompletionResult({
    required this.overall,
    required this.byCategory,
    required this.biggestGap,
    required this.sodiumLevel,
  });

  final double overall;
  final Map<String, double> byCategory;
  final String? biggestGap;
  final String sodiumLevel;
}
