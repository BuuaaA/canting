import 'portions.dart';

/// Daily food-group targets and the energy values used to derive them.
class DailyIntake {
  const DailyIntake({
    required this.grains,
    required this.vegetables,
    required this.fruits,
    required this.protein,
    required this.proteinSoy,
    required this.oil,
    required this.bmr,
    required this.tdee,
  });

  final double grains;
  final double vegetables;
  final double fruits;
  final double protein;
  final double proteinSoy;
  final double oil;
  final double bmr;
  final double tdee;

  Portions get portions => Portions(
    grains: grains,
    vegetables: vegetables,
    fruits: fruits,
    protein: protein,
    proteinSoy: proteinSoy,
    oil: oil,
  );

  Map<String, double> toJson() => {
    ...portions.toJson(),
    'bmr': bmr,
    'tdee': tdee,
  };
}
