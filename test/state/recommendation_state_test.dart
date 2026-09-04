import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// AppState.recommendationFor 的换一批排除逻辑。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late DatabaseHelper helper;
  late AppState appState;

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
    appState = AppState(
      databaseHelper: helper,
      guidelines: DietaryGuidelines.fromJson(
        (jsonDecode(guidelinesJson) as Map).cast<String, dynamic>(),
      ),
    );
    await appState.loadFromDatabase();
  });

  tearDown(() => helper.close());

  test('无排除项时返回引擎原始推荐（1 主推 + 2 备选）', () {
    final recommendation = appState.recommendationFor(DateTime(2026, 9, 4));

    expect(recommendation, isNotNull);
    expect(recommendation!.primary, hasLength(1));
    expect(recommendation.alternatives, hasLength(2));
    expect(recommendation.reason, isNotEmpty);
    for (final suggestion in [
      ...recommendation.primary,
      ...recommendation.alternatives,
    ]) {
      expect(suggestion.searchKeyword, isNotEmpty);
    }
  });

  test('换一批：已展示的菜不再出现，补足到 3 道', () {
    final first = appState.recommendationFor(DateTime(2026, 9, 4))!;
    final shownNames = [
      ...first.primary,
      ...first.alternatives,
    ].map((suggestion) => suggestion.dishName).toSet();

    final second = appState.recommendationFor(
      DateTime(2026, 9, 4),
      excludeDishNames: shownNames,
    )!;

    final secondNames = [
      ...second.primary,
      ...second.alternatives,
    ].map((suggestion) => suggestion.dishName).toSet();
    expect(secondNames.intersection(shownNames), isEmpty);
    expect(secondNames, hasLength(3));
    // 推荐时间与餐次保持不变，只换菜。
    expect(second.suggestedTime, first.suggestedTime);
    expect(second.suggestedMealType, first.suggestedMealType);
    expect(second.reason, isNotEmpty);
    // 引擎 v2：每道推荐带槽位分类与建议份数（每槽位只取 1 道）。
    for (final suggestion in [
      ...second.primary,
      ...second.alternatives,
    ]) {
      expect(suggestion.slotCategory, isNotNull);
      expect(suggestion.servings, isNotNull);
    }
    // 注：「水果类候选不足」提示的确定性覆盖在引擎测试
    // （recommendation_engine_test.dart）， AppState 层的槽位排序
    // 依赖真实时钟，不在此处断言具体提示语。
  });

  test('推荐时间落在合理餐段（未来或餐口起点）', () {
    final recommendation = appState.recommendationFor(DateTime.now())!;
    expect(
      const {'breakfast', 'lunch', 'dinner', 'snack'}.contains(
        recommendation.suggestedMealType,
      ),
      isTrue,
    );
  });
}
