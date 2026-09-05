import 'dart:math' as math;

import 'balance_ledger.dart';
import 'recommendation_safety.dart';
import '../data/food_database.dart';
import 'models/daily_intake.dart';
import 'models/food_data.dart';
import 'models/meal_record.dart';
import 'models/portions.dart';
import 'models/recommendation.dart';

/// Recommends the next meal time and dishes from today's intake gaps,
/// with a 7-day rolling balance ledger driving long-term convergence
/// (指南口径：一周内平衡即可；一次不健康的影响持续传导到后面几天的推荐)。
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
    'protein_soy': '大豆坚果',
  };

  /// 台账里参与清淡模式激活与主食减量的两类。
  static const String _oilGroup = 'oil';
  static const String _grainGroup = 'grains';

  /// 台账盈余激活清淡模式的阈值（份）：油脂或谷薯盈余 ≥ 0.5 时 light。
  /// 持续天数由盈余衰减（50%/日）决定：+2.0 → 次日 1.0 → 第三日 0.5
  /// 仍 light → 第四日 0.25 回归 routine，即「大吃大喝后清淡两三天」。
  static const double lightSurplusThreshold = 0.5;

  /// 槽位最小缺口：剩余缺口 ≤ 0.15 份的分类不占推荐槽位。
  static const double _minGapForSlot = 0.15;

  /// 该类候选菜需至少贡献 0.5 份才算该类候选（防微量蹭位）。
  static const double _minCandidateContribution = 0.5;

  /// 推荐份数上限系数：不超过该菜该类贡献 × 1.5（不推远超缺口的大菜）。
  static const double _maxServingFactor = 1.5;

  /// 清淡模式主食减量：比常规推荐减少 30%（= 单餐修正限幅 ±30% 的上界）。
  static const double _lightStapleReduction = 0.3;

  /// 清淡模式保底小份主食的最小缺口：即使当日主食已吃超，
  /// 晚餐仍给一个维持性小份主食槽位（份量 ≈ 0.8 × 0.7 ≈ 0.56 份）。
  static const double _lightStapleMinGap = 0.8;

  /// routine 模式下长期欠账分类的排序加成上界（0~0.3 附加分），
  /// 让「最近一周蔬菜都欠着」的分类在同等缺口下排前面（还债轮转）。
  static const double _deficitBoostMax = 0.3;

  /// 欠账还债比例：每餐把该类结转欠账的 30% 摊进推荐份数
  /// （「一次不足的影响持续传导到后面几天的推荐」的欠账侧传动）。
  static const double _deficitRepayRate = 0.3;

  /// 盈余反馈比例：每餐把该类结转盈余的 30% 从推荐份数中抵扣
  /// （「一次吃超的影响持续传导到后面几天的推荐」的盈余侧传动）。
  static const double _surplusFeedbackRate = 0.3;

  /// 单餐修正限幅：任何方向的修正（还债加量 / 清淡减量）最多
  /// 比常规推荐 ±30%，绝不推极端方案。
  static const double _singleMealCorrectionLimit = 0.3;

  final FoodDatabase foodDatabase;
  EligibilityDecision decisionFor(StandardDish dish) =>
      RecommendationSafety.evaluate(
        dish,
        foodDatabase.categoryForDish(dish),
        knowledgeOverride: foodDatabase.findKnowledgeById(dish.id),
      );

  Recommendation recommend({
    required List<MealRecord> todayMeals,
    required DailyIntake dailyIntake,
    required DateTime now,
    required String lastMealType,
    BalanceReport? balance,
    bool dataAvailable = true,
    Set<String> excludeDishNames = const {},
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

    final coverageKnown =
        dataAvailable &&
        todayMeals.isNotEmpty &&
        todayMeals.every((m) => m.structureComplete);
    final eaten = todayMeals.fold(
      Portions.zero,
      (total, meal) => total + meal.portionsTotal,
    );
    final timePlan = _recommendTime(
      meals: todayMeals,
      now: now,
      lastMealType: lastMealType,
    );
    final ledger = coverageKnown
        ? (balance ?? BalanceReport.empty(asOf: now))
        : BalanceReport.empty(asOf: now);
    final isLight = _isLightMode(ledger);
    final rankedGroups = !coverageKnown
        ? ([..._foodGroups]..sort((a, b) {
            final order = _mealBonus(
              timePlan.mealType,
              b,
            ).compareTo(_mealBonus(timePlan.mealType, a));
            return order == 0
                ? _foodGroups.indexOf(a).compareTo(_foodGroups.indexOf(b))
                : order;
          }))
        : _rankFoodGroups(
            eaten: coverageKnown ? eaten : dailyIntake.portions,
            target: dailyIntake.portions,
            lastMeal: coverageKnown ? _latestMeal(todayMeals) : null,
            mealType: timePlan.mealType,
            ledger: ledger,
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
    final selectedDishes = <StandardDish>[];
    final usedDishIds = <String>{};
    final shortageGroups = <String>[];
    final target = dailyIntake.portions;
    double gapOf(String group) =>
        coverageKnown ? target.valueFor(group) - eaten.valueFor(group) : 1;

    // 槽位规划：按缺口排序取前 3 个有真实缺口（> 0.15 份）的分类，
    // 每槽位只取 1 道菜。谷类为主（指南核心原则）：主食缺口未满时，
    // 每餐都保底一个主食槽位。清淡模式再保底：即使当日主食吃超，
    // 也以小份维持，不让晚餐没主食。
    final slots = <String>[];
    for (final group in rankedGroups) {
      if (slots.length == 3) {
        break;
      }
      if (gapOf(group) <= _minGapForSlot) {
        continue;
      }
      slots.add(group);
    }
    if (!slots.contains(_grainGroup) && gapOf(_grainGroup) > _minGapForSlot) {
      if (slots.length == 3) slots.removeLast();
      slots.add(_grainGroup);
      while (slots.length > 3) {
        slots.removeLast();
      }
    }
    if (isLight && !slots.contains(_grainGroup)) {
      slots.insert(slots.isEmpty ? 0 : 1, _grainGroup);
      while (slots.length > 3) {
        slots.removeLast();
      }
    }

    slots.sort(
      (a, b) => rankedGroups.indexOf(a).compareTo(rankedGroups.indexOf(b)),
    );
    for (final group in slots) {
      final forcedStaple =
          isLight && group == _grainGroup && gapOf(group) <= _minGapForSlot;
      final gap = forcedStaple ? _lightStapleMinGap : gapOf(group);
      final dish = _bestDishForGroup(
        group: group,
        mealType: timePlan.mealType,
        oilRatio: oilRatio,
        hasHighSodiumMeal: hasHighSodiumMeal,
        previousDishNames: previousDishNames,
        usedDishIds: usedDishIds,
        excludeDishNames: excludeDishNames,
        isLight: isLight,
      );
      if (dish == null) {
        // 该槽位有缺口却无菜可选（候选耗尽/全部不可推荐）：
        // 不静默消失，记入「候选不足」提示（水果槽位由此保住）。
        shortageGroups.add(group);
        continue;
      }
      usedDishIds.add(dish.id);
      selectedDishes.add(dish);
      suggestions.add(
        _suggestionFor(
          dish: dish,
          group: group,
          gap: gap,
          isLight: isLight,
          ledger: ledger,
          allowRepay: !forcedStaple,
        ),
      );
    }

    // A valid seed database has candidates for every group. This fallback also
    // keeps the result usable if a caller supplies a smaller custom database.
    if (suggestions.length < 3) {
      for (final dish in foodDatabase.dishes) {
        if (!usedDishIds.add(dish.id)) {
          continue;
        }
        if (decisionFor(dish).eligibility != Eligibility.eligible ||
            excludeDishNames.contains(dish.name)) {
          continue;
        }
        if (isLight && isJunkish(dish)) {
          continue;
        }
        final group = _primaryNutrient(dish);
        final contribution = dish.correctedPortions.valueFor(group);
        if (contribution < _minCandidateContribution) {
          continue;
        }
        final category = foodDatabase.categoryForDish(dish)!;
        selectedDishes.add(dish);
        suggestions.add(
          DishSuggestion(
            dishName: dish.name,
            searchKeyword: dish.searchKeywords.firstOrNull ?? dish.name,
            primaryCategory: group,
            oilLevel: category.oilLevel,
            slotCategory: group,
            servings: contribution * 0.5,
            note: '补位：建议小份',
          ),
        );
        if (suggestions.length == 3) {
          break;
        }
      }
    }

    final biggestGap =
        suggestions.firstOrNull?.slotCategory ?? rankedGroups.first;
    final allSelectedClean =
        selectedDishes.isNotEmpty &&
        selectedDishes.every((dish) => !isJunkish(dish));
    var reason = _buildReason(
      biggestGap: biggestGap,
      ledger: ledger,
      isLight: isLight,
      oilRatio: oilRatio,
      hasHighSodiumMeal: hasHighSodiumMeal,
      allSelectedClean: allSelectedClean,
      shortageGroups: shortageGroups,
      shortInterval: timePlan.shortInterval,
    );

    if (!coverageKnown) reason = '记录不足，暂不判断缺口；以下为常规搭配建议，不按未知摄入补偿。';
    if (suggestions.length < 3) reason += '；可推荐候选不足（${suggestions.length}道）';
    if (!coverageKnown && shortageGroups.isNotEmpty) {
      reason +=
          '；${shortageGroups.map((g) => '${_groupLabels[g]}类候选不足').join('；')}';
    }
    if (suggestions.isEmpty) reason = '可推荐候选不足；可考虑主食、蔬菜与蛋白类的常规搭配，不指定商品。';
    final output = coverageKnown
        ? suggestions
        : suggestions
              .map(
                (s) => DishSuggestion(
                  dishName: s.dishName,
                  searchKeyword: s.searchKeyword,
                  primaryCategory: s.primaryCategory,
                  oilLevel: s.oilLevel,
                  slotCategory: s.slotCategory,
                  note: '常规搭配，不推算补偿份数',
                ),
              )
              .toList();
    return Recommendation(
      suggestedTime: timePlan.time,
      suggestedMealType: timePlan.mealType,
      primary: output.take(1).toList(growable: false),
      alternatives: output.skip(1).take(2).toList(growable: false),
      reason: reason,
      reasonCodes: [
        if (!coverageKnown)
          'insufficient_record_coverage'
        else
          'recorded_structure_7d',
        if (suggestions.length < 3) 'insufficient_candidates',
        if (suggestions.isEmpty) 'generic_structure_advice',
        if (suggestions.isNotEmpty)
          'selected_${suggestions.first.slotCategory}',
      ],
      balanceMode: isLight ? BalanceMode.light : BalanceMode.routine,
    );
  }

  /// 台账 → 模式：油脂或谷薯盈余 ≥ 0.5 份时进入清淡（light）模式。
  /// 盈余按 50%/日衰减，清淡的持续天数由衰减自然决定。
  static bool _isLightMode(BalanceReport ledger) =>
      ledger.balanceFor(_oilGroup).surplus >= lightSurplusThreshold ||
      ledger.balanceFor(_grainGroup).surplus >= lightSurplusThreshold;

  /// 是否「重口菜」：fried / high_sodium 标签（quality_tags 或旧库代理：
  /// 炸物分类、高钠等级）。清淡模式硬排除这类菜；「已优先清淡」文案
  /// 只在选出的菜全部不是重口菜时才允许出现。
  static bool isJunkish(StandardDish dish) {
    final tags = dish.qualityTags;
    return tags.contains('fried') ||
        tags.contains('high_sodium') ||
        dish.category == 'fried' ||
        dish.sodiumLevel == 'high';
  }

  DishSuggestion _suggestionFor({
    required StandardDish dish,
    required String group,
    required double gap,
    required bool isLight,
    required BalanceReport ledger,
    required bool allowRepay,
  }) {
    final category = foodDatabase.categoryForDish(dish)!;
    final contribution = dish.correctedPortions.valueFor(group);
    final routineServings = gap.clamp(0.0, contribution * _maxServingFactor);
    var servings = routineServings;
    String? note;
    if (isLight &&
        group == _grainGroup &&
        ledger.balanceFor(_grainGroup).surplus > 0) {
      // 清淡模式主食减量：仅当谷薯台账确有盈余时生效（比常规推荐少
      // 30%，单餐修正限幅上界）；谷薯本就欠账时不减，避免油超日把
      // 主食一起压垮。
      servings = routineServings * (1 - _lightStapleReduction);
      note = '清淡模式：主食小份（比常规少三成）';
    } else {
      // 台账双向修正（都在单餐 ±30% 限幅内）：
      // - 还债：该类 7 天结转欠账的 30% 摊进本餐份数；
      // - 盈余反馈：该类结转盈余（前些天吃超的余量）按 30% 抵扣本餐，
      //   让「一次吃超」在后续几天持续少推该类（盈余侧传导）。
      if (allowRepay) {
        final balance = ledger.balanceFor(group);
        final repay = math.min(
          math.max(balance.deficit, 0) * _deficitRepayRate,
          routineServings * _singleMealCorrectionLimit,
        );
        final surplusFeedback = math.min(
          math.max(balance.surplus, 0) * _surplusFeedbackRate,
          routineServings * _singleMealCorrectionLimit,
        );
        // 重油菜不放大：油贡献大的菜最多建议正常一份，避免推荐端
        // 放大当日油脂摄入（油脂无独立槽位，只能靠份量约束）。
        final oilCapFactor = dish.correctedPortions.oil >= 1.0
            ? 1.0
            : dish.correctedPortions.oil >= 0.6
            ? 1.2
            : _maxServingFactor;
        servings = (routineServings + repay - surplusFeedback).clamp(
          routineServings * (1 - _singleMealCorrectionLimit),
          routineServings * (1 + _singleMealCorrectionLimit),
        );
        // 重油菜上限叠加在限幅带之外单独收紧（油大的菜宁小勿大）。
        servings = math.min(servings, contribution * oilCapFactor);
        servings = math.max(servings, 0);
      }
      if (servings < contribution * 0.75) {
        note = '贴合剩余缺口，建议小份';
      }
    }
    // 菜品标签用菜品自身主导分类，不用槽位分类。
    return DishSuggestion(
      dishName: dish.name,
      searchKeyword: dish.searchKeywords.firstOrNull ?? dish.name,
      primaryCategory: _primaryNutrient(dish),
      oilLevel: category.oilLevel,
      slotCategory: group,
      servings: servings,
      note: note,
    );
  }

  String _buildReason({
    required String biggestGap,
    required BalanceReport ledger,
    required bool isLight,
    required double oilRatio,
    required bool hasHighSodiumMeal,
    required bool allSelectedClean,
    required List<String> shortageGroups,
    required bool shortInterval,
  }) {
    var reason =
        '基于已记录餐食的估算、比例缺口及餐次/多样性加成，实际首推${_groupLabels[biggestGap]}类搭配；7天台账仅使用可估算的记录日';

    if (isLight) {
      // 温和、不指责；说明影响会持续几天（滚动调控）。
      final overs = <String>[
        if (ledger.balanceFor(_grainGroup).surplus >= lightSurplusThreshold)
          '主食',
        if (ledger.balanceFor(_oilGroup).surplus >= lightSurplusThreshold) '油',
      ];
      if (overs.length == 1) {
        reason +=
            '；近期已记录餐食中${overs.first}估算偏多，'
            '晚饭清爽一点就好～这两天咱们吃清淡点';
      } else {
        reason +=
            '；近期已记录餐食中${overs.join('和')}估算偏多，'
            '晚饭清爽一点就好～这两天咱们吃清淡点';
      }
    } else if ((oilRatio > 1.2 || hasHighSodiumMeal) && allSelectedClean) {
      // 只有实际选出的菜全部不重口，才允许说「已优先清淡」。
      reason += '；今日油盐已偏高，已优先选择较清淡菜品';
    }

    if (shortageGroups.isNotEmpty) {
      final notes = [
        for (final group in shortageGroups)
          group == 'fruits'
              ? '水果类候选不足，可以在记录里手动补个水果'
              : '${_groupLabels[group]}类候选不足',
      ];
      reason += '；${notes.join('；')}';
    }

    if (shortInterval) {
      reason += '；距离上一餐不足2小时，暂不建议提前进食';
    }
    return reason;
  }

  List<String> _rankFoodGroups({
    required Portions eaten,
    required Portions target,
    required MealRecord? lastMeal,
    required String mealType,
    required BalanceReport ledger,
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
      // 台账欠账驱动（routine 也生效）：长期不足的分类获得 0~0.15
      // 的附加分，把「未来一个月结构收敛」的欠账还进排序。
      var deficitBoost = 0.0;
      final dailyTarget = targetValue / BalanceLedger.windowDays;
      if (dailyTarget > 0) {
        final deficit = ledger.balanceFor(group).deficit;
        deficitBoost =
            _deficitBoostMax * (deficit / dailyTarget).clamp(0.0, 1.0);
      }
      scores[group] = gap * diversityFactor * (1 + mealBonus) + deficitBoost;
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
    required Set<String> excludeDishNames,
    required bool isLight,
  }) {
    StandardDish? best;
    var bestScore = double.negativeInfinity;
    for (final dish in foodDatabase.dishesForNutrient(group)) {
      if (usedDishIds.contains(dish.id) ||
          excludeDishNames.contains(dish.name)) {
        continue;
      }
      // recommendable=false 的菜永远不进推荐（薯条/可乐/奶茶）。
      if (decisionFor(dish).eligibility != Eligibility.eligible) {
        continue;
      }
      final contribution = dish.correctedPortions.valueFor(group);
      // 该类份数 ≥ 0.5 才算该类候选（防微量蹭位）。
      if (contribution < _minCandidateContribution) {
        continue;
      }
      // 清淡模式硬规则：重口菜直接排除（不是打折）。
      if (isLight && isJunkish(dish)) {
        continue;
      }
      final category = foodDatabase.categoryForDish(dish)!;
      var score = contribution;

      if (dish.tags.contains(mealType)) {
        score *= 1.2;
      }
      if (previousDishNames.contains(dish.name)) {
        score *= 0.5;
      }
      // 类内质量排序（routine 也生效）：
      // whole_grain 压过精白（杂粮饭 > 白米饭），light 压过 fried。
      if (dish.qualityTags.contains('whole_grain')) {
        score *= 1.3;
      }
      if (dish.qualityTags.contains('light')) {
        score *= 1.2;
      }
      if (dish.qualityTags.contains('fried') || dish.category == 'fried') {
        score *= 0.6;
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
      // 油脂当日预算：oilRatio 越高越偏向低油菜（routine 的当日油脂
      // 调控；跨日盈余由 light 模式与盈余反馈处理）。
      final dishOil = dish.correctedPortions.oil;
      if (oilRatio >= 0.6 && dishOil >= 0.8) {
        score *= 0.7;
      }
      if (oilRatio >= 1.0 && dishOil >= 0.5) {
        score *= 0.7;
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
