import 'portions.dart';

class MealDish {
  const MealDish({
    this.name = '',
    this.quantity = 1,
    this.portionSize = 'normal',
    this.matchedDishId,
    this.matchConfidence = 0,
    this.portions = Portions.zero,
  });

  final String name;
  final double quantity;
  final String portionSize;
  final String? matchedDishId;
  final double matchConfidence;
  final Portions portions;

  MealDish copyWith({
    String? name,
    double? quantity,
    String? portionSize,
  }) => MealDish(
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    portionSize: portionSize ?? this.portionSize,
    matchedDishId: matchedDishId,
    matchConfidence: matchConfidence,
    portions: portions,
  );

  factory MealDish.fromJson(Map<String, dynamic> json) => MealDish(
    name: json['name'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    portionSize: json['portion_size'] as String,
    matchedDishId: json['matched_dish_id'] as String?,
    matchConfidence: (json['match_confidence'] as num).toDouble(),
    portions: Portions.fromJson(
      (json['portions'] as Map).cast<String, dynamic>(),
    ),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    'portion_size': portionSize,
    'matched_dish_id': matchedDishId,
    'match_confidence': matchConfidence,
    'portions': portions.toJson(),
  };
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
  }) : portionsTotal = portionsTotal ?? _sumDishes(dishes);

  final String mealId;
  final String mealType;
  final DateTime timestamp;

  /// Takeaway merchant name, when known; optional for manual entries.
  final String? merchant;
  final List<MealDish> dishes;
  final Portions portionsTotal;
  final double completionRate;
  final String sodiumLevel;

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
    );
  }

  Map<String, dynamic> toJson() => {
    'meal_id': mealId,
    'meal_type': mealType,
    'timestamp': timestamp.toIso8601String(),
    if (merchant != null) 'merchant': merchant,
    'dishes': dishes.map((dish) => dish.toJson()).toList(growable: false),
    'portions_total': portionsTotal.toJson(),
    'completion_rate': completionRate,
    'sodium_level': sodiumLevel,
  };

  static Portions _sumDishes(List<MealDish> dishes) => dishes.fold(
    Portions.zero,
    (total, dish) => total + dish.portions.scale(dish.quantity),
  );
}
