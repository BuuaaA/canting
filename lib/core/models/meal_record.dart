import 'local_food.dart';
import 'portions.dart';

class MealDish {
  const MealDish({
    this.name = '',
    this.quantity = 1,
    this.portionSize = 'normal',
    this.matchedDishId,
    this.matchConfidence = 0,
    Portions portions = Portions.zero,
    this.food,
    this.riskEvidence,
    this.contributionsKnown = true,
    // Public name is retained for existing callers; unknown values cannot be read as scalars.
    // ignore: prefer_initializing_formals
  }) : _portions = portions;

  final FoodObservation? food;

  /// Facts captured from an exact legacy candidate at save time, never a live lookup.
  final Map<String, dynamic>? riskEvidence;
  final bool contributionsKnown;
  final String name;
  final double quantity;
  final String portionSize;
  final String? matchedDishId;
  final double matchConfidence;
  final Portions _portions;
  Portions get portions {
    if (!contributionsKnown) {
      throw StateError('Unknown contribution has no scalar portions');
    }
    return _portions;
  }

  MealDish copyWith({
    String? name,
    double? quantity,
    String? portionSize,
    FoodObservation? food,
  }) => MealDish(
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    portionSize: portionSize ?? this.portionSize,
    matchedDishId: matchedDishId,
    matchConfidence: matchConfidence,
    portions: contributionsKnown && matchedDishId != null && portionSize != null
        ? _portions.scale(
            _portionFactor(portionSize) / _portionFactor(this.portionSize),
          )
        : _portions,
    food: food ?? this.food,
    riskEvidence: riskEvidence,
    contributionsKnown: contributionsKnown,
  );

  static double _portionFactor(String size) => switch (size) {
    'small' => 0.8,
    'large' => 1.3,
    _ => 1.0,
  };

  factory MealDish.fromJson(Map<String, dynamic> json) => MealDish(
    riskEvidence: json['risk_evidence'] is Map
        ? Map<String, dynamic>.unmodifiable(json['risk_evidence'] as Map)
        : null,
    name: json['name'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    portionSize: json['portion_size'] as String,
    matchedDishId: json['matched_dish_id'] as String?,
    matchConfidence:
        ((json['match_score'] ?? json['match_confidence']) as num?)
            ?.toDouble() ??
        0,
    contributionsKnown: json['contributions_known'] != false,
    food: json['food'] == null
        ? null
        : FoodObservation.fromJson(
            Map<String, dynamic>.from(json['food'] as Map),
          ),
    portions: json['portions'] == null
        ? const Portions()
        : Portions.fromJson((json['portions'] as Map).cast<String, dynamic>()),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    'portion_size': portionSize,
    'matched_dish_id': matchedDishId,
    'match_confidence': null,
    'match_score': food == null ? matchConfidence : null,
    'estimated': contributionsKnown,
    'contribution_unit': 'food_group_servings',
    'contribution_source': contributionsKnown
        ? (matchedDishId ?? 'legacy_or_manual')
        : null,
    'portions': contributionsKnown ? _portions.toJson() : null,
    'contributions_known': contributionsKnown,
    if (food != null) 'food': food!.toJson(),
    if (riskEvidence != null) 'risk_evidence': riskEvidence,
  };
}

/// Actual meal-only vitality effect. Evolution/growth rewards are not reversed.
/// Absent on old JSON means unknown, never an inferred completion-rate reward.
class MealPetEffect {
  const MealPetEffect({
    required this.evaluated,
    required this.vitalityDelta,
    required this.recordedAt,
  });
  final bool evaluated;
  final int vitalityDelta;
  final DateTime recordedAt;
  Map<String, dynamic> toJson() => {
    'evaluated': evaluated,
    'vitality_delta': vitalityDelta,
    'recorded_at': recordedAt.toIso8601String(),
    'schema_version': 1,
    'policy_version': 'meal-actual-effect-v1',
  };
  factory MealPetEffect.fromJson(Map<String, dynamic> json) => MealPetEffect(
    evaluated: json['evaluated'] as bool,
    vitalityDelta: json['vitality_delta'] as int,
    recordedAt: DateTime.parse(json['recorded_at'] as String),
  );
}

/// One persisted meal in the module-to-module JSON format.
class MealRecord {
  MealRecord({
    required this.mealId,
    required this.mealType,
    required this.timestamp,
    this.merchant,
    this.dishes = const [],
    Portions? portionsTotal,
    this.completionRate = 0,
    this.sodiumLevel = 'mid',
    this.petEffect,
  }) : portionsTotal = portionsTotal ?? _sumDishes(dishes);

  final String mealId;
  final String mealType;
  final DateTime timestamp;

  /// Takeaway merchant name, when known; optional for manual entries.
  final String? merchant;
  final List<MealDish> dishes;
  final Portions portionsTotal;
  bool get structureComplete => dishes.every((dish) => dish.contributionsKnown);
  final double completionRate;
  final String sodiumLevel;
  final MealPetEffect? petEffect;
  MealRecord withPetEffect(MealPetEffect? effect) => MealRecord(
    mealId: mealId,
    mealType: mealType,
    timestamp: timestamp,
    merchant: merchant,
    dishes: dishes,
    portionsTotal: portionsTotal,
    completionRate: completionRate,
    sodiumLevel: sodiumLevel,
    petEffect: effect,
  );

  factory MealRecord.fromJson(Map<String, dynamic> json) {
    final dishes = (json['dishes'] as List? ?? const [])
        .map((item) => MealDish.fromJson((item as Map).cast<String, dynamic>()))
        .toList(growable: false);

    return MealRecord(
      mealId: json['meal_id'] as String,
      mealType: json['meal_type'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      merchant: json['merchant'] as String?,
      dishes: dishes,
      portionsTotal: json['portions_total'] == null
          ? null
          : Portions.fromJson(
              (json['portions_total'] as Map).cast<String, dynamic>(),
            ),
      completionRate: (json['completion_rate'] as num?)?.toDouble() ?? 0,
      sodiumLevel: json['sodium_level'] as String? ?? 'mid',
      petEffect: json['pet_effect'] == null
          ? null
          : MealPetEffect.fromJson(
              Map<String, dynamic>.from(json['pet_effect'] as Map),
            ),
    );
  }

  Map<String, dynamic> toJson() => {
    'meal_id': mealId,
    'meal_type': mealType,
    'timestamp': timestamp.toIso8601String(),
    if (merchant != null) 'merchant': merchant,
    'dishes': dishes.map((dish) => dish.toJson()).toList(growable: false),
    'portions_total': portionsTotal.toJson(),
    'total_scope': structureComplete ? 'complete' : 'known_subtotal',
    'structure_complete': structureComplete,
    'completion_rate': completionRate,
    'sodium_level': sodiumLevel,
    if (petEffect != null) 'pet_effect': petEffect!.toJson(),
  };

  static Portions _sumDishes(List<MealDish> dishes) => dishes
      .where((dish) => dish.contributionsKnown)
      .fold(
        Portions.zero,
        (total, dish) => total + dish.portions.scale(dish.quantity),
      );
}
