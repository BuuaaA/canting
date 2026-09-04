import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/data/meal_repository.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 模块 15 手动添加餐食的数据流测试：
/// 搜索排序（自定义优先+使用次数）、克重↔份数联动、落库与登记。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late DatabaseHelper helper;
  late AppState appState;
  late MealRepository mealRepo;

  setUp(() async {
    final dishesJson = await File('assets/data/dishes.json').readAsString();
    final categoriesJson = await File(
      'assets/data/categories.json',
    ).readAsString();
    final guidelinesJson = await File(
      'assets/data/dietary_guidelines.json',
    ).readAsString();

    helper = DatabaseHelper(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await helper.initialize(
      seedData: FoodDatabase.fromJson(
        dishesJson: dishesJson,
        categoriesJson: categoriesJson,
      ),
    );
    mealRepo = MealRepository(database: () => helper.database);
    appState = AppState(
      databaseHelper: helper,
      guidelines: DietaryGuidelines.fromJson(
        (jsonDecode(guidelinesJson) as Map).cast<String, dynamic>(),
      ),
    );
    await appState.loadFromDatabase();
  });

  tearDown(() => helper.close());

  group('搜索排序', () {
    test('自定义菜在前、按使用次数降序，同名标准菜去重', () async {
      // 用标准库里的菜累计使用次数（黄焖鸡米饭 2 次，卤肉饭 1 次）。
      await appState.registerManualDish(
        name: '黄焖鸡米饭',
        portionSize: 'large',
      );
      await appState.registerManualDish(
        name: '黄焖鸡米饭',
        portionSize: 'large',
      );
      await appState.registerManualDish(name: '卤肉饭', portionSize: 'small');

      final results = await appState.searchDishesForManualAdd('饭');

      final names = results.map((dish) => dish.name).toList();
      // 「黄焖鸡米饭」在库里有同名标准菜：只出现一次（自定义副本）。
      expect(names.where((name) => name == '黄焖鸡米饭'), hasLength(1));
      // 用过 2 次的排在用过 1 次的前面，都排在没用过的标准菜前面。
      expect(names.indexOf('黄焖鸡米饭'), lessThan(names.indexOf('卤肉饭')));
      final customCount = results
          .sublist(0, 2)
          .where(
            (dish) =>
                dish.name == '黄焖鸡米饭' || dish.name == '卤肉饭',
          )
          .length;
      expect(customCount, 2);
      // 标准菜仍在结果里（不会丢库）。
      expect(results, contains(containsName('饭')));
    });

    test('空查询返回空列表', () async {
      expect(await appState.searchDishesForManualAdd('  '), isEmpty);
    });
  });

  group('克重↔份数联动', () {
    test('食物交换份：米饭 300g = 2 份谷薯，反向回到 300g', () {
      final link = appState.resolveManualServings('米饭', grams: 300);

      expect(link, isNotNull);
      expect(link!.servings, closeTo(2, 0.01));
      expect(link.portions.grains, closeTo(2, 0.01));

      final grams = appState.resolveManualGrams('米饭', servings: 2);
      expect(grams, closeTo(300, 0.5));
    });

    test('匹配菜品：克重与份数按同源基准往返一致', () {
      const name = '黄焖鸡米饭';
      final grams = appState.resolveManualGrams(name, servings: 1);
      expect(grams, isNotNull);
      expect(grams!, greaterThan(0));

      final link = appState.resolveManualServings(name, grams: grams);
      expect(link, isNotNull);
      expect(link!.servings, closeTo(1, 0.01));
      // 结构与匹配菜的正常份一致。
      final match = appState.dishMatcher!.match([name]).single;
      expect(link.portions.grains, closeTo(match.portionsNormal.grains, 1e-9));
      expect(link.matchedDishId, match.matchedDishId);
    });

    test('新菜按分类兜底：克重换算出份数并给出结构', () {
      // 「阿婆秘制拿手菜」在菜库和关键词里都无命中，走分类兜底。
      final link = appState.resolveManualServings(
        '阿婆秘制拿手菜',
        grams: 300,
        categoryId: 'stir_fry',
      );

      expect(link, isNotNull);
      expect(link!.servings, greaterThan(0));
      expect(link.matchedDishId, isNull);
      expect(link.categoryId, 'stir_fry');
      // 往返一致：份数 → 克重 → 份数。
      final grams = appState.resolveManualGrams(
        '阿婆秘制拿手菜',
        servings: link.servings,
        categoryId: 'stir_fry',
      )!;
      expect(grams, closeTo(300, 0.5));
      final link2 = appState.resolveManualServings(
        '阿婆秘制拿手菜',
        grams: grams,
        categoryId: 'stir_fry',
      )!;
      expect(link2.servings, closeTo(link.servings, 0.01));
    });

    test('非正数克重直接拒绝', () {
      expect(appState.resolveManualServings('米饭', grams: 0), isNull);
      expect(appState.resolveManualGrams('米饭', servings: -1), isNull);
    });
  });

  group('登记与落库', () {
    test('新菜名登记进自定义表，累计使用次数并记住分量偏好', () async {
      final link = appState.resolveManualServings(
        '阿婆秘制拿手菜',
        grams: 300,
        categoryId: 'stir_fry',
      );
      await appState.registerManualDish(
        name: '阿婆秘制拿手菜',
        portionSize: 'normal',
        manualPortions: link!.portions,
        category: 'stir_fry',
        homemade: true,
      );
      await appState.registerManualDish(
        name: '阿婆秘制拿手菜',
        portionSize: 'large',
      );

      final usage = await appState.manualDishUsage('阿婆秘制拿手菜');
      expect(usage, isNotNull);
      expect(usage!.usageCount, 2);
      expect(usage.preferredPortion, 'large');
      expect(usage.dish.tags, contains('homemade'));
      expect(usage.dish.category, 'stir_fry');

      // 登记后匹配引擎能精确命中新菜，份数就是登记时的结构。
      final match = appState.dishMatcher!.match(['阿婆秘制拿手菜']).single;
      expect(match.matchedDishId, usage.dish.id);
      expect(match.confidence, 1);
      expect(
        match.portionsNormal.grains,
        closeTo(usage.dish.portionsNormal.grains, 1e-9),
      );
    });

    test('标准库的菜登记为同内容副本，不改变匹配结果', () async {
      await appState.registerManualDish(
        name: '黄焖鸡米饭',
        portionSize: 'normal',
      );
      final usage = await appState.manualDishUsage('黄焖鸡米饭');
      expect(usage!.usageCount, 1);
      expect(usage.preferredPortion, 'normal');

      final standard = await helper.getDishById('hsm_rice');
      expect(standard, isNotNull);
      // 副本内容与标准菜一致（份量没被改动）。
      expect(
        usage.dish.portionsNormal.grains,
        closeTo(standard!.portionsNormal.grains, 1e-9),
      );
      // 匹配仍然精确命中。
      final match = appState.dishMatcher!.match(['黄焖鸡米饭']).single;
      expect(match.confidence, 1);
    });

    test('手动添加落库并刷新当日数据，备注与来源可读回', () async {
      const name = '阿婆秘制拿手菜';
      final link = appState.resolveManualServings(
        name,
        grams: 300,
        categoryId: 'stir_fry',
      )!;
      final now = DateTime.now();
      final meal = appState.buildMealRecord(
        mealType: 'dinner',
        timestamp: now,
        dishes: [
          MealDish(
            name: name,
            portionSize: 'normal',
            matchedDishId: link.matchedDishId,
            portions: link.portions,
          ),
        ],
      );

      await appState.saveMeal(meal, note: '少辣', source: 'manual');
      await appState.registerManualDish(
        name: name,
        portionSize: 'normal',
        manualPortions: link.portions,
        category: 'stir_fry',
        homemade: true,
      );

      // 当日缓存与库表都有一条。
      expect(appState.mealsFor(now), hasLength(1));
      expect(await mealRepo.getMealsByDate(now), hasLength(1));
      expect(appState.mealsFor(now).single.portionsTotal.protein, greaterThan(0));
      expect(await mealRepo.getNote(meal.mealId), '少辣');

      // 再次搜索时自定义菜排最前。
      final results = await appState.searchDishesForManualAdd('拿手');
      expect(results.first.name, name);
    });
  });
}

Matcher containsName(String part) => _NameContains(part);

class _NameContains extends Matcher {
  const _NameContains(this.part);

  final String part;

  @override
  bool matches(dynamic item, Map matchState) =>
      item is StandardDish && item.name.contains(part);

  @override
  Description describe(Description description) =>
      description.add('a dish whose name contains ').addDescriptionOf(part);
}
