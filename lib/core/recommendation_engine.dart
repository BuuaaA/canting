import '../data/food_database.dart';
import 'models/daily_intake.dart';
import 'models/food_data.dart';
import 'models/meal_record.dart';
import 'models/portions.dart';
import 'models/recommendation.dart';

/// Recommends the next meal time and dishes from today's intake gaps.
class RecommendationEngine {
  const RecommendationEngine(this.foodDatabase);

  static const List<String> _foodGroups = [
    'grains',
    'vegetables',
    'fruits',
    'protein',
    'protein_soy',
  ];

  static const Map<String, String> _groupLabels = {
    'grains': '主食',
    'vegetables': '蔬菜',
    'fruits': '水果',
    'protein': '动物蛋白',
    'protein_soy': '大豆及坚果',
  };

  final FoodDatabase foodDatabase;

  Recommendation recommend({
    required List<MealRecord> todayMeals,
    required DailyIntake dailyIntake,
    required DateTime now,
    required String lastMealType,
  }) {
    if (todayMeals.isNotEmpty &&
        !const {
          'breakfast',
          'lunch',
          'dinner',
          'snack',
        }.contains(lastMealType)) {
      throw ArgumentError.value(
        lastMealType,
        'lastMealType',
        'must be breakfast, lunch, dinner, or snack',
      );
    }

    final eaten = todayMeals.fold(
      Portions.zero,
      (total, meal) => total + meal.portionsTotal,
    );
    final timePlan = _recommendTime(
      meals: todayMeals,
      now: now,
      lastMealType: lastMealType,
    );
    final rankedGroups = _rankFoodGroups(
      eaten: eaten,
      target: dailyIntake.portions,
      lastMeal: _latestMeal(todayMeals),
      mealType: timePlan.mealType,
    );

    final previousDishNames = todayMeals
        .expand((meal) => meal.dishes)
        .map((dish) => dish.name)
        .toSet();
    final oilRatio = dailyIntake.oil <= 0 ? 0.0 : eaten.oil / dailyIntake.oil;
    final hasHighSodiumMeal = todayMeals.any(
      (meal) => meal.sodiumLevel == 'high',
    );
    final suggestions = <DishSuggestion>[];
    final usedDishIds = <String>{};

    for (final group in rankedGroups) {
      final dish = _bestDishForGroup(
        group: group,
        mealType: timePlan.mealType,
        oilRatio: oilRatio,
        hasHighSodiumMeal: hasHighSodiumMeal,
        previousDishNames: previousDishNames,
        usedDishIds: usedDishIds,
      );
      if (dish == null) {
        continue;
      }
      usedDishIds.add(dish.id);
      final category = foodDatabase.categoryForDish(dish)!;
      suggestions.add(
        DishSuggestion(
          dishName: dish.name,
          searchKeyword: dish.searchKeywords.firstOrNull ?? dish.name,
          primaryCategory: group,
          oilLevel: category.oilLevel,
        ),
      );
      if (suggestions.length == 3) {
        break;
      }
    }

    // A valid seed database has candidates for every group. This fallback also
    // keeps the result usable if a caller supplies a smaller custom database.
    if (suggestions.length < 3) {
      for (final dish in foodDatabase.dishes) {
        if (!usedDishIds.add(dish.id)) {
          continue;
        }
        final group = _primaryNutrient(dish);
        final category = foodDatabase.categoryForDish(dish)!;
        suggestions.add(
          DishSuggestion(
            dishName: dish.name,
            searchKeyword: dish.searchKeywords.firstOrNull ?? dish.name,
            primaryCategory: group,
            oilLevel: category.oilLevel,
          ),
        );
        if (suggestions.length == 3) {
          break;
        }
      }
    }

    final biggestGap = rankedGroups.first;
    final balanceNote = oilRatio > 1.2 || hasHighSodiumMeal
        ? '；今日油盐已偏高，已优先选择较清淡菜品'
        : '';
    final shortIntervalNote = timePlan.shortInterval
        ? '；距离上一餐不足2小时，暂不建议提前进食'
        : '';

    return Recommendation(
      suggestedTime: timePlan.time,
      suggestedMealType: timePlan.mealType,
      primary: suggestions.take(1).toList(growable: false),
      alternatives: suggestions.skip(1).take(2).toList(growable: false),
      reason:
          '今日${_groupLabels[biggestGap]}缺口最大，下一餐优先补充'
          '$balanceNote$shortIntervalNote',
    );
  }

  List<String> _rankFoodGroups({
    required Portions eaten,
    required Portions target,
    required MealRecord? lastMeal,
    required String mealType,
  }) {
    final lastMealFoodTotal = lastMeal == null
        ? 0.0
        : _foodGroups.fold(
            0.0,
            (total, group) => total + lastMeal.portionsTotal.valueFor(group),
          );

    final scores = <String, double>{};
    for (final group in _foodGroups) {
      final targetValue = target.valueFor(group);
      final gap = targetValue <= 0
          ? 0.0
          : ((targetValue - eaten.valueFor(group)) / targetValue).clamp(
              0.0,
              1.0,
            );

      var diversityFactor = 1.0;
      if (lastMeal != null && lastMealFoodTotal > 0) {
        final share =
            lastMeal.portionsTotal.valueFor(group) / lastMealFoodTotal;
        if (share >= 0.5) {
          diversityFactor = 0.5;
        } else if (share >= 0.3) {
          diversityFactor = 0.7;
        }
      }

      final mealBonus = _mealBonus(mealType, group);
      scores[group] = gap * diversityFactor * (1 + mealBonus);
    }

    final ranked = [..._foodGroups]
      ..sort((left, right) {
        final scoreOrder = scores[right]!.compareTo(scores[left]!);
        if (scoreOrder != 0) {
          return scoreOrder;
        }
        return _foodGroups.indexOf(left).compareTo(_foodGroups.indexOf(right));
      });
    return ranked;
  }

  StandardDish? _bestDishForGroup({
    required String group,
    required String mealType,
    required double oilRatio,
    required bool hasHighSodiumMeal,
    required Set<String> previousDishNames,
    required Set<String> usedDishIds,
  }) {
    StandardDish? best;
    var bestScore = double.negativeInfinity;
    for (final dish in foodDatabase.dishesForNutrient(group)) {
      if (usedDishIds.contains(dish.id)) {
        continue;
      }
      final category = foodDatabase.categoryForDish(dish)!;
      var score = dish.correctedPortions.valueFor(group);

      if (dish.tags.contains(mealType)) {
        score *= 1.2;
      }
      if (previousDishNames.contains(dish.name)) {
        score *= 0.5;
      }
      if (const {'high', 'extreme'}.contains(category.oilLevel)) {
        if (oilRatio > 1.2) {
          score *= 0.6;
        } else if (oilRatio >= 0.8) {
          score *= 0.8;
        }
      }
      if (hasHighSodiumMeal && dish.sodiumLevel == 'high') {
        score *= 0.75;
      }

      if (score > bestScore) {
        best = dish;
        bestScore = score;
      }
    }
    return best;
  }

  static double _mealBonus(String mealType, String group) => switch (mealType) {
    'breakfast' when group == 'grains' || group == 'protein' => 0.05,
    'lunch' when group == 'vegetables' || group == 'grains' => 0.05,
    'dinner' when group == 'vegetables' => 0.10,
    'dinner' when group == 'protein' => 0.05,
    'snack' when group == 'fruits' => 0.15,
    'snack' when group == 'protein' => 0.10,
    _ => 0,
  };

  static String _primaryNutrient(StandardDish dish) {
    var primary = _foodGroups.first;
    var highest = double.negativeInfinity;
    for (final group in _foodGroups) {
      final contribution = dish.correctedPortions.valueFor(group);
      if (contribution > highest) {
        primary = group;
        highest = contribution;
      }
    }
    return primary;
  }

  static MealRecord? _latestMeal(List<MealRecord> meals) {
    if (meals.isEmpty) {
      return null;
    }
    return meals.reduce(
      (latest, meal) =>
          meal.timestamp.isAfter(latest.timestamp) ? meal : latest,
    );
  }

  static _TimePlan _recommendTime({
    required List<MealRecord> meals,
    required DateTime now,
    required String lastMealType,
  }) {
    if (meals.isEmpty) {
      return _recommendWithoutRecords(now);
    }

    final latest = _latestMeal(meals)!;
    if (lastMealType == 'snack' && latest.timestamp.hour >= 22) {
      return _TimePlan(
        time: _atTime(latest.timestamp, 8, 30, dayOffset: 1),
        mealType: 'breakfast',
        shortInterval:
            now.difference(latest.timestamp) < const Duration(hours: 2),
      );
    }

    final (nextMealType, baseInterval) = switch (lastMealType) {
      'breakfast' => ('lunch', const Duration(minutes: 270)),
      'lunch' => ('dinner', const Duration(minutes: 330)),
      'dinner' => ('breakfast', const Duration(hours: 11)),
      'snack' => _afterSnack(latest.timestamp),
      _ => throw StateError('lastMealType was validated before this call'),
    };
    final extension = meals.length >= 4
        ? const Duration(hours: 1)
        : Duration.zero;
    var suggested = latest.timestamp.add(baseInterval + extension);
    suggested = _adjustToMealWindow(suggested, nextMealType);
    var effectiveMealType = nextMealType;

    if (effectiveMealType != 'breakfast' && suggested.hour >= 21) {
      effectiveMealType = 'breakfast';
      suggested = _atTime(suggested, 7, 30, dayOffset: 1);
    } else if (suggested.isBefore(now)) {
      if (now.hour >= 21 && effectiveMealType != 'snack') {
        effectiveMealType = 'breakfast';
        suggested = _atTime(now, 7, 30, dayOffset: 1);
      } else {
        suggested = now;
      }
    }

    return _TimePlan(
      time: suggested,
      mealType: effectiveMealType,
      shortInterval:
          now.difference(latest.timestamp) < const Duration(hours: 2),
    );
  }

  static _TimePlan _recommendWithoutRecords(DateTime now) {
    if (now.hour < 9) {
      final breakfastStart = _atTime(now, 7, 30);
      return _TimePlan(
        time: breakfastStart.isAfter(now) ? breakfastStart : now,
        mealType: 'breakfast',
      );
    }
    if (now.hour < 13) {
      final lunchStart = _atTime(now, 12, 0);
      return _TimePlan(
        time: lunchStart.isAfter(now) ? lunchStart : now,
        mealType: 'lunch',
      );
    }
    if (now.hour < 21) {
      final dinnerStart = _atTime(now, 18, 0);
      return _TimePlan(
        time: dinnerStart.isAfter(now) ? dinnerStart : now,
        mealType: 'dinner',
      );
    }
    return _TimePlan(
      time: _atTime(now, 7, 30, dayOffset: 1),
      mealType: 'breakfast',
    );
  }

  static (String, Duration) _afterSnack(DateTime snackTime) {
    if (snackTime.hour < 11) {
      return ('lunch', const Duration(minutes: 210));
    }
    if (snackTime.hour < 17) {
      return ('dinner', const Duration(minutes: 210));
    }
    final nextBreakfast = _atTime(snackTime, 7, 30, dayOffset: 1);
    return ('breakfast', nextBreakfast.difference(snackTime));
  }

  static DateTime _adjustToMealWindow(DateTime value, String mealType) {
    final (hour, minute) = switch (mealType) {
      'breakfast' => (7, 30),
      'lunch' => (12, 0),
      'dinner' => (18, 0),
      _ => (value.hour, value.minute),
    };
    final windowStart = _atTime(value, hour, minute);
    return value.isBefore(windowStart) ? windowStart : value;
  }

  static DateTime _atTime(
    DateTime source,
    int hour,
    int minute, {
    int dayOffset = 0,
  }) {
    final date = source.add(Duration(days: dayOffset));
    return source.isUtc
        ? DateTime.utc(date.year, date.month, date.day, hour, minute)
        : DateTime(date.year, date.month, date.day, hour, minute);
  }
}

class _TimePlan {
  const _TimePlan({
    required this.time,
    required this.mealType,
    this.shortInterval = false,
  });

  final DateTime time;
  final String mealType;
  final bool shortInterval;
}
