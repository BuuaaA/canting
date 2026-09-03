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

  factory DailyIntake.fromJson(Map<String, dynamic> json) => DailyIntake(
    grains: (json['grains'] as num).toDouble(),
    vegetables: (json['vegetables'] as num).toDouble(),
    fruits: (json['fruits'] as num).toDouble(),
    protein: (json['protein'] as num).toDouble(),
    proteinSoy: (json['protein_soy'] as num).toDouble(),
    oil: (json['oil'] as num).toDouble(),
    bmr: (json['bmr'] as num).toDouble(),
    tdee: (json['tdee'] as num).toDouble(),
  );

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
