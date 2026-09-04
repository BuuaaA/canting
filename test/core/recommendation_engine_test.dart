import 'dart:math' as math;

import 'package:canting/core/balance_ledger.dart';
import 'package:canting/core/intake_calculator.dart';
import 'package:canting/core/models/daily_intake.dart';
import 'package:canting/core/models/food_data.dart';
import 'package:canting/core/models/meal_record.dart';
import 'package:canting/core/models/portions.dart';
import 'package:canting/core/models/recommendation.dart';
import 'package:canting/core/recommendation_engine.dart';
import 'package:canting/data/food_database.dart';
import 'package:test/test.dart';

/// 推荐引擎 v2 多日仿真测试（核心验收）。
///
/// 全部用例只依赖本文件自造的带标签 fixture 菜品库，
/// 不依赖 dishes.json 是否已带上 recommendable / quality_tags
/// （另一会话在途改数据层，引擎层测试须在旧库状态下独立成立）。
void main() {
  // 2000kcal 能量档（与 dietary_guidelines.json 的 2000 档一致，
  // TDEE 2000 对应成人中档能量水平）。
  final dailyIntake = const DailyIntake(
    grains: 5,
    vegetables: 5,
    fruits: 3,
    protein: 4,
    proteinSoy: 2,
    oil: 3,
    bmr: 1500,
    tdee: 2000,
  );

  final weeklyTarget = IntakeCalculator.weeklyTargetFromDaily(dailyIntake);

  late FoodDatabase database;
  late RecommendationEngine engine;
  late Map<String, StandardDish> dishByName;

  setUpAll(() {
    database = _fixtureDatabase();
    engine = RecommendationEngine(database);
    dishByName = {for (final dish in database.dishes) dish.name: dish};
  });

  group('排序与候选过滤', () {
    test('杂粮饭与白米饭同时候选时杂粮饭排前（whole_grain 压过精白）', () {
      final result = engine.recommend(
        todayMeals: const [],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 4, 10),
        lastMealType: '',
      );

      expect(result.primary.single.dishName, '杂粮饭');
      expect(result.primary.single.primaryCategory, 'grains');
      // 份量贴合剩余缺口，不超过菜品贡献 × 1.5。
      expect(result.primary.single.servings, closeTo(3.0, 1e-9));
    });

    test('recommendable=false 的菜在任何模式下都不出现（属性测试）', () {
      final junkNames = {'薯条', '可乐', '珍珠奶茶', '炸鸡全家桶'};
      final ledgers = [
        null,
        BalanceReport.empty(asOf: DateTime(2026, 9, 4)),
        _ledger(oilSurplus: 3, now: DateTime(2026, 9, 4)),
        _ledger(grainSurplus: 2, now: DateTime(2026, 9, 4)),
        _ledger(vegDeficit: 6, now: DateTime(2026, 9, 4)),
      ];
      final meals = [
        const <MealRecord>[],
        [
          MealRecord(
            mealId: 'fried-lunch',
            mealType: 'lunch',
            timestamp: DateTime(2026, 9, 4, 12),
            portionsTotal: const Portions(
              grains: 3,
              protein: 2.5,
              oil: 5,
            ),
            sodiumLevel: 'high',
          ),
        ],
      ];

      for (final ledger in ledgers) {
        for (final todayMeals in meals) {
          final result = engine.recommend(
            todayMeals: todayMeals,
            dailyIntake: dailyIntake,
            now: DateTime(2026, 9, 4, 18),
            lastMealType: todayMeals.isEmpty ? '' : 'lunch',
            balance: ledger,
          );
          final names = [
            ...result.primary,
            ...result.alternatives,
          ].map((s) => s.dishName);
          expect(
            names.toSet().intersection(junkNames),
            isEmpty,
            reason: 'ledger=$ledger meals=$todayMeals 时出现了不可推荐菜品',
          );
        }
      }
    });

    test('清淡模式硬排除 fried/high_sodium 标签菜（即使 recommendable）', () {
      final result = engine.recommend(
        todayMeals: const [],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 4, 18),
        lastMealType: '',
        balance: _ledger(oilSurplus: 3, now: DateTime(2026, 9, 4)),
      );

      expect(result.balanceMode, BalanceMode.light);
      for (final suggestion in [
        ...result.primary,
        ...result.alternatives,
      ]) {
        final dish = dishByName[suggestion.dishName]!;
        final junkish =
            dish.qualityTags.contains('fried') ||
            dish.qualityTags.contains('high_sodium') ||
            dish.category == 'fried' ||
            dish.sodiumLevel == 'high';
        expect(junkish, isFalse, reason: '${dish.name} 不应进清淡推荐');
      }
    });

    test('某类候选需该类份数 ≥ 0.5 才算候选（防微量蹭位）', () {
      // 唯一的 soy 候选是 0.4 份的蹭位菜；先把谷薯/蔬菜/水果吃满，
      // 让 protein/soy 槽位浮出，验证 0.4 份不进槽位且有提示语。
      final tinyDatabase = FoodDatabase(
        dishes: [
          const StandardDish(
            id: 'soy_drizzle',
            name: '薄芡豆腐汤',
            aliases: [],
            category: 'soy_cold',
            portionsNormal: Portions(proteinSoy: 0.4),
            cookingOilRatio: 0,
            oilFactor: 1,
            sodiumLevel: 'low',
            searchKeywords: ['豆腐汤'],
          ),
          const StandardDish(
            id: 'rice',
            name: '白米饭',
            aliases: [],
            category: 'staple_plain',
            portionsNormal: Portions(grains: 2),
            cookingOilRatio: 0,
            oilFactor: 1,
            sodiumLevel: 'low',
            searchKeywords: ['米饭'],
          ),
        ],
        categories: _fixtureCategories(),
      );
      final result = RecommendationEngine(tinyDatabase).recommend(
        todayMeals: [
          MealRecord(
            mealId: 'big-meal',
            mealType: 'lunch',
            timestamp: DateTime(2026, 9, 4, 12),
            portionsTotal: const Portions(
              grains: 5,
              vegetables: 4,
              fruits: 2.5,
            ),
          ),
        ],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 4, 14),
        lastMealType: 'lunch',
      );
      final names = [
        ...result.primary,
        ...result.alternatives,
      ].map((s) => s.dishName).toSet();
      expect(names.contains('薄芡豆腐汤'), isFalse);
      // soy 槽位有缺口却无 ≥0.5 份候选 → 提示语出现，不静默消失。
      expect(result.reason, contains('大豆坚果类候选不足'));
    });
  });

  group('单日场景：中午炸鸡汉堡薯条可乐', () {
    final lunchPortions = const Portions(
      grains: 5.5, // 炸鸡 1.2 + 汉堡 2.8 + 薯条 1.5（可乐零贡献）
      vegetables: 0,
      fruits: 0,
      protein: 3.7,
      proteinSoy: 0,
      oil: 7.7,
    );
    final lunch = MealRecord(
      mealId: 'lunch',
      mealType: 'lunch',
      timestamp: DateTime(2026, 9, 4, 12),
      portionsTotal: lunchPortions,
      sodiumLevel: 'high',
    );

    Recommendation dinnerAt(DateTime time) {
      final ledger = BalanceLedger.compute(
        intakeByDay: {DateTime(time.year, time.month, time.day): lunchPortions},
        weeklyTarget: weeklyTarget,
        now: time,
      );
      return engine.recommend(
        todayMeals: [lunch],
        dailyIntake: dailyIntake,
        now: time,
        lastMealType: 'lunch',
        balance: ledger,
      );
    }

    test('晚餐 = 蔬菜类首推 + 小份 whole_grain 主食', () {
      final result = dinnerAt(DateTime(2026, 9, 4, 18));

      expect(result.balanceMode, BalanceMode.light);
      expect(result.primary.single.primaryCategory, 'vegetables');

      final staple = [
        ...result.primary,
        ...result.alternatives,
      ].firstWhere((s) => s.primaryCategory == 'grains');
      expect(staple.dishName, '杂粮饭');
      expect(staple.note, contains('清淡'));
      // 主食已吃超（缺口 0），保底维持性小份：0.8 × 0.7 ≈ 0.56。
      expect(staple.servings, closeTo(0.56, 1e-9));
    });

    test('文案温和提示油/主食超标，滚动调控，无欺骗性「已优先清淡」', () {
      final result = dinnerAt(DateTime(2026, 9, 4, 18));

      expect(result.reason, contains('今天主食和油都吃超啦'));
      expect(result.reason, contains('这两天咱们吃清淡点'));
      expect(result.reason, isNot(contains('已优先选择较清淡菜品')));
      // 全部推荐都不重口（清淡文案之外没有别的「健康话术」需要验证）。
      for (final suggestion in [
        ...result.primary,
        ...result.alternatives,
      ]) {
        expect(RecommendationEngine.isJunkish(dishByName[suggestion.dishName]!),
            isFalse);
      }
    });
  });

  group('滚动场景：大吃大喝的影响持续传导', () {
    final day1 = DateTime(2026, 9, 1);
    final feast = const Portions(
      grains: 5.5,
      vegetables: 0,
      fruits: 0,
      protein: 3.7,
      proteinSoy: 0,
      oil: 7.7,
    );
    final day1Lunch = MealRecord(
      mealId: 'day1-lunch',
      mealType: 'lunch',
      timestamp: DateTime(2026, 9, 1, 12),
      portionsTotal: feast,
      sodiumLevel: 'high',
    );

    Recommendation at(DateTime now) {
      final ledger = BalanceLedger.compute(
        intakeByDay: {day1: feast},
        weeklyTarget: weeklyTarget,
        now: now,
      );
      final todayMeals = _sameDay(now, day1) ? [day1Lunch] : const <MealRecord>[];
      return engine.recommend(
        todayMeals: todayMeals,
        dailyIntake: dailyIntake,
        now: now,
        lastMealType: todayMeals.isEmpty ? '' : 'lunch',
        balance: ledger,
      );
    }

    test('Day1 晚 → Day2（无记录）→ Day3 保持 light，主食减量', () {
      expect(at(DateTime(2026, 9, 1, 18)).balanceMode, BalanceMode.light);

      final day2 = at(DateTime(2026, 9, 2, 12));
      expect(day2.balanceMode, BalanceMode.light);
      // Day2 无新记录、油盈余衰减中，主食槽位仍在且减量。
      final day2Staple = [
        ...day2.primary,
        ...day2.alternatives,
      ].firstWhere((s) => s.slotCategory == 'grains');
      expect(day2Staple.servings, closeTo(2.1, 1e-9)); // 3.0 × 0.7
      expect(day2Staple.note, contains('清淡'));

      expect(at(DateTime(2026, 9, 3, 12)).balanceMode, BalanceMode.light);
    });

    test('Day5~7 盈余衰减殆尽 → 回归 routine', () {
      final day5 = at(DateTime(2026, 9, 5, 12));
      final day6 = at(DateTime(2026, 9, 6, 12));
      final day7 = at(DateTime(2026, 9, 7, 12));

      expect(day5.balanceMode, BalanceMode.routine);
      expect(day6.balanceMode, BalanceMode.routine);
      expect(day7.balanceMode, BalanceMode.routine);

      // routine 下无限幅/清淡话术，主食恢复正常份量（不减 30%）。
      for (final result in [day5, day6, day7]) {
        expect(result.reason, isNot(contains('吃超啦')));
        expect(result.reason, isNot(contains('清淡')));
        for (final suggestion in [
          ...result.primary,
          ...result.alternatives,
        ]) {
          expect(suggestion.note, isNot(contains('清淡')));
        }
      }
      // 注：day1 炸鸡日留下的蔬菜/水果欠账还在台账里（20%/日缓衰减），
      // 欠账加成会让缺口排序偏向还债——这正是「一次不健康传导数天」
      // 的欠账侧设计，因此这里不断言与无历史 baseline 完全同菜。
    });
  });

  group('文案规则', () {
    test('「已优先清淡」只在选出的 3 道全部不重口时出现', () {
      // 今日油盐偏高（oilRatio 1.6 + 高钠午餐）。
      final meals = [
        MealRecord(
          mealId: 'salty-lunch',
          mealType: 'lunch',
          timestamp: DateTime(2026, 9, 4, 12),
          portionsTotal: const Portions(oil: 4),
          sodiumLevel: 'high',
        ),
      ];
      final result = engine.recommend(
        todayMeals: meals,
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 4, 14),
        lastMealType: 'lunch',
      );

      final selectedClean = [
        ...result.primary,
        ...result.alternatives,
      ].every(
        (s) => !RecommendationEngine.isJunkish(dishByName[s.dishName]!),
      );
      if (selectedClean) {
        expect(result.reason, contains('已优先选择较清淡菜品'));
      } else {
        expect(result.reason, isNot(contains('已优先选择较清淡菜品')));
      }
    });

    test('水果槽位候选耗尽时显示「水果类候选不足」提示', () {
      // 先吃掉当日水果目标，鲜果切又因换一批被排除：
      // fruits 槽位只剩无候选 → 提示语保住水果的存在感。
      final result = engine.recommend(
        todayMeals: const [],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 4, 10),
        lastMealType: '',
        excludeDishNames: {'鲜果切', '杂粮饭', '清炒时蔬'},
      );

      expect(result.reason, contains('水果类候选不足'));
    });
  });

  group('清淡主食限幅', () {
    test('light 模式主食推荐份数恰好比 routine 少 30%（不超过限幅）', () {
      final routine = engine.recommend(
        todayMeals: const [],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 4, 12),
        lastMealType: '',
      );
      final light = engine.recommend(
        todayMeals: const [],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 4, 12),
        lastMealType: '',
        balance: _ledger(
          oilSurplus: 2,
          grainSurplus: 1,
          now: DateTime(2026, 9, 4),
        ),
      );

      final routineStaple = [
        ...routine.primary,
        ...routine.alternatives,
      ].firstWhere((s) => s.slotCategory == 'grains');
      final lightStaple = [
        ...light.primary,
        ...light.alternatives,
      ].firstWhere((s) => s.slotCategory == 'grains');

      expect(light.balanceMode, BalanceMode.light);
      expect(lightStaple.servings, closeTo(routineStaple.servings! * 0.7, 1e-9));
      expect(
        routineStaple.servings! - lightStaple.servings!,
        lessThanOrEqualTo(routineStaple.servings! * 0.3 + 1e-9),
      );
    });
  });

  group('30 天仿真（核心验收）', () {
    test('随机饮食 + 每餐采用推荐 → 7 天滚动均值收敛进目标 ±20%', () {
      final random = math.Random(42);
      final start = DateTime(2026, 8, 1);
      final intakeByDay = <DateTime, Portions>{};

      for (var dayIndex = 0; dayIndex < 30; dayIndex++) {
        final day = start.add(Duration(days: dayIndex));
        final meals = <MealRecord>[];
        var lastType = '';
        final plan = [
          ('breakfast', DateTime(day.year, day.month, day.day, 8, 0)),
          ('lunch', DateTime(day.year, day.month, day.day, 12, 30)),
          ('dinner', DateTime(day.year, day.month, day.day, 18, 30)),
        ];
        for (final (type, time) in plan) {
          final ledger = BalanceLedger.compute(
            intakeByDay: intakeByDay,
            weeklyTarget: weeklyTarget,
            now: time,
          );
          final recommendation = engine.recommend(
            todayMeals: meals,
            dailyIntake: dailyIntake,
            now: time,
            lastMealType: lastType,
            balance: ledger,
          );
          // 80% 餐次听推荐：吃下主推 + 首个备选（+ 一半概率第二备选，
          // 贴近真实一餐 2~3 菜结构，按引擎建议份数、至多 1.5 份正常量）。
          // 20% 随机自由发挥（含垃圾食品——用户自由，引擎要抗的扰动）。
          final adopted = <MealDish>[];
          void eat(StandardDish dish, double multiplier) {
            final scaled = dish.correctedPortions.scale(multiplier);
            adopted.add(MealDish(name: dish.name, portions: scaled));
            final day_ = DateTime(day.year, day.month, day.day);
            intakeByDay[day_] = (intakeByDay[day_] ?? Portions.zero) + scaled;
          }

          if (random.nextDouble() < 0.8) {
            // 第三道只在水果/大豆槽位时采纳（低油类别最容易长期欠着）。
            final thirdAlternative = recommendation.alternatives.length >
                    1 &&
                const {'fruits', 'protein_soy'}.contains(
                  recommendation.alternatives.last.slotCategory,
                );
            for (final suggestion in [
              recommendation.primary.single,
              if (recommendation.alternatives.isNotEmpty)
                recommendation.alternatives.first,
              if (thirdAlternative) recommendation.alternatives.last,
            ]) {
              final dish = dishByName[suggestion.dishName]!;
              final slot = suggestion.slotCategory;
              var multiplier = 1.0;
              if (slot != null && suggestion.servings != null) {
                final slotContribution =
                    dish.correctedPortions.valueFor(slot);
                if (slotContribution > 0) {
                  multiplier = math.min(
                    suggestion.servings! / slotContribution,
                    1.5,
                  );
                }
              }
              eat(dish, multiplier);
            }
          } else {
            eat(
              database.dishes[random.nextInt(database.dishes.length)],
              1,
            );
          }
          meals.add(
            MealRecord(
              mealId: 'sim-$dayIndex-$type',
              mealType: type,
              timestamp: time,
              dishes: adopted,
            ),
          );
          lastType = type;
        }
      }

      // 收敛断言：第 20 天起每个 7 天滚动窗口的日均摄入都在 ±20% 内
      // （前 19 天含冷启动与随机扰动的衰减期，收敛是渐进过程）。
      final targetPortions = dailyIntake.portions;
      final failures = <String>[];
      for (var windowStart = 19; windowStart <= 23; windowStart++) {
        final totals = <String, double>{};
        for (var i = 0; i < 7; i++) {
          final dayIntake =
              intakeByDay[start.add(Duration(days: windowStart + i))] ??
              Portions.zero;
          for (final entry in dayIntake.byCategory.entries) {
            totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
          }
        }
        for (final category in targetPortions.byCategory.keys) {
          final average = (totals[category] ?? 0) / 7;
          final goal = targetPortions.valueFor(category);
          final low = goal * 0.8;
          final high = goal * 1.2;
          if (average < low - 1e-9 || average > high + 1e-9) {
            failures.add(
              '窗口 day${windowStart + 1}~${windowStart + 7} '
              '$category 均值 ${average.toStringAsFixed(2)} '
              '目标区间 [$low, $high]',
            );
          }
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });

  group('P0 基线回归：换一批标签与水果槽位（确定性）', () {
    Set<String> namesOf(Recommendation result) => {
      ...result.primary,
      ...result.alternatives,
    }.map((s) => s.dishName).toSet();

    test('换一批后新卡的分类来自新菜品自身数据，不继承槽位或旧卡标签', () {
      Recommendation round(Set<String> exclude) => engine.recommend(
        todayMeals: const [],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 4, 10),
        lastMealType: '',
        excludeDishNames: exclude,
      );

      // 三轮「换一批」：每轮把前几轮展示过的菜全部排除。
      // 第三轮 grains 槽位只剩 香辣炸鸡排（薯条/奶茶/全家桶等
      // recommendable=false 永不进候选）。
      final first = round(const {});
      final firstNames = namesOf(first);
      expect(firstNames, hasLength(3));
      expect(first.primary.single.dishName, '杂粮饭');
      expect(first.primary.single.slotCategory, 'grains');

      final second = round(firstNames);
      final secondNames = namesOf(second);
      expect(secondNames.intersection(firstNames), isEmpty);
      expect(second.primary.single.dishName, '白米饭');

      final third = round({...firstNames, ...secondNames});
      final thirdNames = namesOf(third);
      expect(
        thirdNames.intersection({...firstNames, ...secondNames}),
        isEmpty,
        reason: '换一批不得再次给出已排除的菜',
      );

      // 通用契约：每道建议的 primaryCategory 都等于按菜品自身
      // correctedPortions 独立重算的主导类别（与引擎实现同口径的
      // 测试规约），不是槽位类别，也不是被排除旧卡的标签。
      for (final suggestion in [
        ...second.primary,
        ...second.alternatives,
        ...third.primary,
        ...third.alternatives,
      ]) {
        final dish = dishByName[suggestion.dishName]!;
        expect(
          suggestion.primaryCategory,
          dominantCategoryOf(dish),
          reason: '${dish.name} 的分类必须由菜品自身数据计算',
        );
      }

      // 强断言：第三轮主推 = 香辣炸鸡排。槽位是 grains（它被排除链
      // 顶到主食槽位），但它的蛋白质贡献(2.2)高于谷类(1.2)，自身主导
      // 类别是 protein。若实现继承槽位(grains)或旧卡白米饭(grains)的
      // 标签，此断言即失败。
      final thirdPrimary = third.primary.single;
      expect(thirdPrimary.dishName, '香辣炸鸡排');
      expect(thirdPrimary.slotCategory, 'grains');
      expect(dominantCategoryOf(dishByName[thirdPrimary.dishName]!), 'protein');
      expect(thirdPrimary.primaryCategory, 'protein');
      expect(thirdPrimary.primaryCategory, isNot(thirdPrimary.slotCategory));
    });

    test('水果是最大有效缺口且有合格候选时，首个槽位为水果且菜品主导类别为 fruits', () {
      // 引擎槽位排序用「比例缺口」((目标-已吃)/目标，钳 0..1)；空腹时五类
      // 比例全是 1.0，排序退化为餐次加成，因此先吃掉其他类一部分。
      //
      // 设计口径（双会话指令 B 线任务 3 + 集成清单 d 的交汇）：
      // - 谷类为主：主食缺口 > 0.15 份时主食槽位强制置首（insert(0)）；
      // - 水果缺口最大且主食已达标（谷缺口 ≤ 0.15，保底不触发）时，
      //   水果就是首个推荐槽位。
      // 本用例锁定前者让路、后者成立的确定性场景，并额外断言两者共存时
      // 水果槽位不丢失、身份与主导类别仍来自菜品自身。
      //
      // 场景：午餐吃掉谷 4.95/5（缺口 0.05 ≤ 0.15）、蔬 2.5、蛋白 2、
      // 大豆 0.5；水果未吃。比例缺口 fruits 1.0 > soy 0.75 > veg 0.5
      // > protein 0.5 > grains 0.01，水果唯一最大且主食保底不触发。
      final lunch = MealRecord(
        mealId: 'lunch',
        mealType: 'lunch',
        timestamp: DateTime(2026, 9, 4, 12),
        portionsTotal: const Portions(
          grains: 4.95,
          vegetables: 2.5,
          protein: 2,
          proteinSoy: 0.5,
        ),
      );

      Recommendation at({Set<String> exclude = const {}}) => engine.recommend(
        todayMeals: [lunch],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 4, 14),
        lastMealType: 'lunch',
        excludeDishNames: exclude,
      );

      final primary = at().primary.single;
      expect(primary.slotCategory, 'fruits');
      // 菜品身份：库中唯一 recommendable=true 的水果候选。
      expect(primary.dishName, '鲜果切');
      // 菜品自身主导类别也是 fruits（水果贡献 2.0 为其唯一非零类）。
      expect(dominantCategoryOf(dishByName[primary.dishName]!), 'fruits');
      expect(primary.primaryCategory, 'fruits');

      // 排除「鲜果切」后同场景换一批：水果槽位不再有合格候选，引擎必须
      // 提示而不是静默用其他类顶替水果槽位。
      final swapped = at(exclude: {'鲜果切'});
      expect(swapped.primary.single.slotCategory, isNot('fruits'));
      expect(swapped.reason, contains('水果类候选不足'));
    });

    test('主食缺口未满时主食槽位按设计置首，水果最大缺口槽位仍保留且标签正确', () {
      // 与上一用例同源的设计解释点：谷缺口 > 0.15 时「谷类为主」保底
      // 生效，主食槽位置首（双会话指令 B 线任务 3 原文 insert(0)），
      // 水果虽排序第一退居第二槽位——这是已验收的设计行为，不是回归。
      // 本用例把该行为固化，防止未来改动悄悄破坏水果槽位的身份契约。
      final lunch = MealRecord(
        mealId: 'lunch',
        mealType: 'lunch',
        timestamp: DateTime(2026, 9, 4, 12),
        portionsTotal: const Portions(
          grains: 2.5,
          vegetables: 2.5,
          protein: 2,
          proteinSoy: 0.5,
        ),
      );
      final result = engine.recommend(
        todayMeals: [lunch],
        dailyIntake: dailyIntake,
        now: DateTime(2026, 9, 4, 14),
        lastMealType: 'lunch',
      );

      // 文案确认水果确实是缺口最大的类（排序第一）。
      expect(result.reason, contains('今日水果缺口最大'));
      // 主食槽位置首（设计行为）。
      expect(result.primary.single.slotCategory, 'grains');
      // 水果槽位仍存在，且菜品身份与主导类别全部来自菜品自身。
      final fruitSuggestion = [
        ...result.primary,
        ...result.alternatives,
      ].firstWhere((s) => s.slotCategory == 'fruits');
      expect(fruitSuggestion.dishName, '鲜果切');
      expect(dominantCategoryOf(dishByName[fruitSuggestion.dishName]!), 'fruits');
      expect(fruitSuggestion.primaryCategory, 'fruits');
    });
  });
}

/// 测试规约：菜品主导营养类别 = 按 APP 五类固定顺序
/// （grains/vegetables/fruits/protein/protein_soy）取 correctedPortions
/// 贡献最大者（严格大于才替换，平局归先者）。与引擎 _primaryNutrient
/// 的契约一致，用于独立复核推荐卡标签来源。
String dominantCategoryOf(StandardDish dish) {
  const groups = ['grains', 'vegetables', 'fruits', 'protein', 'protein_soy'];
  var primary = groups.first;
  var highest = double.negativeInfinity;
  for (final group in groups) {
    final contribution = dish.correctedPortions.valueFor(group);
    if (contribution > highest) {
      primary = group;
      highest = contribution;
    }
  }
  return primary;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

BalanceReport _ledger({
  double oilSurplus = 0,
  double grainSurplus = 0,
  double vegDeficit = 0,
  required DateTime now,
}) {
  final day = DateTime(now.year, now.month, now.day);
  return BalanceReport(
    asOf: day,
    byCategory: {
      'grains': CategoryBalance(surplus: grainSurplus),
      'vegetables': CategoryBalance(deficit: vegDeficit),
      'fruits': const CategoryBalance(),
      'protein': const CategoryBalance(),
      'protein_soy': const CategoryBalance(),
      'oil': CategoryBalance(surplus: oilSurplus),
    },
  );
}

List<FoodCategory> _fixtureCategories() => [
  const FoodCategory(
    id: 'staple_plain',
    name: '主食',
    oilLevel: 'low',
    oilFactor: 1,
    averagePortions: Portions(grains: 2),
    keywords: [],
  ),
  const FoodCategory(
    id: 'stir_fry',
    name: '炒菜',
    oilLevel: 'mid_high',
    oilFactor: 1.2,
    averagePortions: Portions(vegetables: 2, oil: 0.9),
    keywords: [],
  ),
  const FoodCategory(
    id: 'salad_light',
    name: '轻食',
    oilLevel: 'low',
    oilFactor: 1,
    averagePortions: Portions(vegetables: 2, protein: 1.5, oil: 0.7),
    keywords: [],
  ),
  const FoodCategory(
    id: 'protein_dish',
    name: '蛋白菜',
    oilLevel: 'low',
    oilFactor: 1.1,
    averagePortions: Portions(protein: 2, oil: 0.9),
    keywords: [],
  ),
  const FoodCategory(
    id: 'fruit',
    name: '水果',
    oilLevel: 'low',
    oilFactor: 1,
    averagePortions: Portions(fruits: 2),
    keywords: [],
  ),
  const FoodCategory(
    id: 'soy_cold',
    name: '豆制品',
    oilLevel: 'low',
    oilFactor: 1,
    averagePortions: Portions(proteinSoy: 1.5, oil: 0.4),
    keywords: [],
  ),
  const FoodCategory(
    id: 'braised',
    name: '红烧',
    oilLevel: 'high',
    oilFactor: 1.5,
    averagePortions: Portions(proteinSoy: 1.5, oil: 1.5),
    keywords: [],
  ),
  const FoodCategory(
    id: 'fried',
    name: '油炸',
    oilLevel: 'high',
    oilFactor: 1.3,
    averagePortions: Portions(grains: 1.2, protein: 2, oil: 2.5),
    keywords: [],
  ),
  const FoodCategory(
    id: 'dessert_sweet',
    name: '甜品饮品',
    oilLevel: 'low',
    oilFactor: 1,
    averagePortions: Portions(grains: 1.2, oil: 0.8),
    keywords: [],
  ),
];

/// 自造带标签 fixture 菜品库（不依赖 dishes.json）。
FoodDatabase _fixtureDatabase() {
  final dishes = [
    const StandardDish(
      id: 'multigrain_rice',
      name: '杂粮饭',
      aliases: [],
      category: 'staple_plain',
      portionsNormal: Portions(grains: 2),
      cookingOilRatio: 0,
      oilFactor: 1,
      sodiumLevel: 'low',
      searchKeywords: ['杂粮饭'],
      tags: ['breakfast', 'lunch', 'dinner'],
      qualityTags: ['whole_grain', 'light'],
    ),
    const StandardDish(
      id: 'white_rice',
      name: '白米饭',
      aliases: [],
      category: 'staple_plain',
      portionsNormal: Portions(grains: 2),
      cookingOilRatio: 0,
      oilFactor: 1,
      sodiumLevel: 'low',
      searchKeywords: ['米饭'],
      tags: ['lunch', 'dinner'],
    ),
    const StandardDish(
      id: 'stir_greens',
      name: '清炒时蔬',
      aliases: [],
      category: 'stir_fry',
      portionsNormal: Portions(vegetables: 2, oil: 0.45),
      cookingOilRatio: 1,
      oilFactor: 1.2,
      sodiumLevel: 'mid',
      searchKeywords: ['炒青菜'],
      tags: ['lunch', 'dinner'],
      qualityTags: ['light'],
    ),
    const StandardDish(
      id: 'garlic_broccoli',
      name: '蒜蓉西兰花',
      aliases: [],
      category: 'stir_fry',
      portionsNormal: Portions(vegetables: 2, oil: 0.8),
      cookingOilRatio: 1,
      oilFactor: 1.2,
      sodiumLevel: 'mid',
      searchKeywords: ['西兰花'],
      tags: ['lunch', 'dinner'],
      qualityTags: ['light'],
    ),
    const StandardDish(
      id: 'chicken_salad',
      name: '鸡胸肉沙拉',
      aliases: [],
      category: 'salad_light',
      portionsNormal: Portions(vegetables: 1.8, protein: 1.8, oil: 0.5),
      cookingOilRatio: 0.4,
      oilFactor: 1,
      sodiumLevel: 'low',
      searchKeywords: ['鸡肉沙拉'],
      tags: ['lunch', 'dinner'],
      qualityTags: ['light'],
    ),
    const StandardDish(
      id: 'boiled_egg',
      name: '水煮蛋',
      aliases: [],
      category: 'protein_dish',
      portionsNormal: Portions(protein: 1, oil: 0.5),
      cookingOilRatio: 0,
      oilFactor: 1.1,
      sodiumLevel: 'low',
      searchKeywords: ['鸡蛋'],
      tags: ['breakfast', 'snack'],
    ),
    const StandardDish(
      id: 'steamed_fish',
      name: '清蒸鱼',
      aliases: [],
      category: 'protein_dish',
      portionsNormal: Portions(protein: 2, oil: 0.65),
      cookingOilRatio: 0.2,
      oilFactor: 1.1,
      sodiumLevel: 'mid',
      searchKeywords: ['蒸鱼'],
      tags: ['lunch', 'dinner'],
      qualityTags: ['light'],
    ),
    const StandardDish(
      id: 'fruit_cup',
      name: '鲜果切',
      aliases: [],
      category: 'fruit',
      portionsNormal: Portions(fruits: 2),
      cookingOilRatio: 0,
      oilFactor: 1,
      sodiumLevel: 'low',
      searchKeywords: ['水果拼盘'],
      tags: ['breakfast', 'snack'],
    ),
    const StandardDish(
      id: 'cold_tofu',
      name: '凉拌豆腐',
      aliases: [],
      category: 'soy_cold',
      portionsNormal: Portions(proteinSoy: 1.5, oil: 0.3),
      cookingOilRatio: 0,
      oilFactor: 1,
      sodiumLevel: 'low',
      searchKeywords: ['凉拌豆腐'],
      tags: ['lunch', 'dinner'],
      qualityTags: ['light'],
    ),
    const StandardDish(
      id: 'mapo_tofu',
      name: '麻婆豆腐',
      aliases: [],
      category: 'braised',
      portionsNormal: Portions(proteinSoy: 1.5, oil: 1.4),
      cookingOilRatio: 0.7,
      oilFactor: 1.5,
      sodiumLevel: 'high',
      searchKeywords: ['豆腐'],
      tags: ['lunch', 'dinner'],
    ),
    const StandardDish(
      id: 'spicy_fried_chicken',
      name: '香辣炸鸡排',
      aliases: [],
      category: 'fried',
      portionsNormal: Portions(grains: 1.2, protein: 2.2, oil: 2.6),
      cookingOilRatio: 0.7,
      oilFactor: 1.3,
      sodiumLevel: 'high',
      searchKeywords: ['炸鸡排'],
      tags: ['lunch', 'dinner'],
      qualityTags: ['fried', 'high_sodium'],
      // recommendable=true：routine 可低优先级出现，light 必须被硬排除。
    ),
    const StandardDish(
      id: 'fries',
      name: '薯条',
      aliases: [],
      category: 'fried',
      portionsNormal: Portions(grains: 1.5, oil: 2),
      cookingOilRatio: 0.8,
      oilFactor: 1.3,
      sodiumLevel: 'mid',
      searchKeywords: ['薯条'],
      tags: ['snack'],
      recommendable: false,
    ),
    const StandardDish(
      id: 'cola',
      name: '可乐',
      aliases: [],
      category: 'dessert_sweet',
      portionsNormal: Portions.zero,
      cookingOilRatio: 0,
      oilFactor: 1,
      sodiumLevel: 'low',
      searchKeywords: ['可乐'],
      tags: ['snack'],
      recommendable: false,
    ),
    const StandardDish(
      id: 'milk_tea',
      name: '珍珠奶茶',
      aliases: [],
      category: 'dessert_sweet',
      portionsNormal: Portions(grains: 1.5, oil: 1),
      cookingOilRatio: 0,
      oilFactor: 1,
      sodiumLevel: 'low',
      searchKeywords: ['奶茶'],
      tags: ['snack'],
      recommendable: false,
    ),
    const StandardDish(
      id: 'fried_combo',
      name: '炸鸡全家桶',
      aliases: [],
      category: 'fried',
      portionsNormal: Portions(grains: 1.2, protein: 2.2, oil: 3.1),
      cookingOilRatio: 0.7,
      oilFactor: 1.3,
      sodiumLevel: 'high',
      searchKeywords: ['炸鸡'],
      tags: ['lunch', 'dinner'],
      recommendable: false,
    ),
  ];
  return FoodDatabase(dishes: dishes, categories: _fixtureCategories());
}
