import 'models/daily_intake.dart';

/// Calculates a user's recommended daily food-group portions.
class IntakeCalculator {
  static const Map<String, double> _activityFactors = {
    'sedentary': 1.2,
    'light': 1.375,
    'moderate': 1.55,
    'heavy': 1.725,
  };

  static const Set<String> _dietGoals = {
    'balanced',
    'more_veg',
    'more_protein',
    'less_carb',
  };

  DailyIntake calculate({
    required String gender,
    required int heightCm,
    required double weightKg,
    required int age,
    required String activityLevel,
    required String dietGoal,
  }) {
    _validateInputs(
      gender: gender,
      heightCm: heightCm,
      weightKg: weightKg,
      age: age,
      activityLevel: activityLevel,
      dietGoal: dietGoal,
    );

    final genderConstant = gender == 'male' ? 5 : -161;
    final bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + genderConstant;
    final tdee = bmr * _activityFactors[activityLevel]!;

    // Interpolate continuously between the guideline's lower and upper bounds.
    final rangePosition = ((tdee - 1600) / (2400 - 1600))
        .clamp(0.0, 1.0)
        .toDouble();
    var grains = _interpolate(5, 8, rangePosition);
    var vegetables = _interpolate(3, 5, rangePosition);
    final fruits = _interpolate(2, 3.5, rangePosition);
    var protein = _interpolate(3, 5, rangePosition);
    const proteinSoy = 1.0;
    final oil = _interpolate(2.5, 3, rangePosition);

    switch (dietGoal) {
      case 'more_veg':
        vegetables *= 1.2;
        break;
      case 'more_protein':
        protein *= 1.2;
        break;
      case 'less_carb':
        grains *= 0.8;
        break;
      case 'balanced':
        break;
    }

    return DailyIntake(
      grains: grains,
      vegetables: vegetables,
      fruits: fruits,
      protein: protein,
      proteinSoy: proteinSoy,
      oil: oil,
      bmr: bmr,
      tdee: tdee,
    );
  }

  static double _interpolate(double min, double max, double position) =>
      min + (max - min) * position;

  static void _validateInputs({
    required String gender,
    required int heightCm,
    required double weightKg,
    required int age,
    required String activityLevel,
    required String dietGoal,
  }) {
    if (gender != 'male' && gender != 'female') {
      throw ArgumentError.value(gender, 'gender', 'must be male or female');
    }
    if (heightCm <= 0) {
      throw ArgumentError.value(heightCm, 'heightCm', 'must be positive');
    }
    if (!weightKg.isFinite || weightKg <= 0) {
      throw ArgumentError.value(weightKg, 'weightKg', 'must be positive');
    }
    if (age <= 0) {
      throw ArgumentError.value(age, 'age', 'must be positive');
    }
    if (!_activityFactors.containsKey(activityLevel)) {
      throw ArgumentError.value(
        activityLevel,
        'activityLevel',
        'unsupported activity level',
      );
    }
    if (!_dietGoals.contains(dietGoal)) {
      throw ArgumentError.value(dietGoal, 'dietGoal', 'unsupported diet goal');
    }
  }
}
