import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/home/home_page.dart';
import 'package:canting/ui/manual_add/manual_add_page.dart';
import 'package:canting/ui/recommendation/recommendation_detail_page.dart';
import 'package:canting/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> pumpUiTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

UserProfile _profile() {
  final now = DateTime(2026, 9, 3);
  return UserProfile(
    gender: 'female',
    age: 28,
    heightCm: 165,
    weightKg: 55,
    dietGoal: 'balanced',
    activityLevel: 'light',
    breakfastTime: '08:00',
    lunchTime: '12:00',
    dinnerTime: '18:30',
    dayStartTime: '01:00',
    onboardingCompleted: true,
    dailyIntake: const DailyIntake(
      grains: 5,
      vegetables: 4,
      fruits: 2.5,
      protein: 4,
      proteinSoy: 1,
      oil: 2.5,
      bmr: 1450,
      tdee: 1740,
    ),
    createdAt: now,
    updatedAt: now,
  );
}

/// 真实种子数据（assets/data 基准）+ 内存库，走完整数据链路。
Future<(AppState, DatabaseHelper)> _buildState() async {
  sqfliteFfiInit();
  final dishesJson = File('assets/data/dishes.json').readAsStringSync();
  final categoriesJson = File('assets/data/categories.json').readAsStringSync();
  final guidelinesJson = File(
    'assets/data/dietary_guidelines.json',
  ).readAsStringSync();
  final helper = DatabaseHelper(
    factory: databaseFactoryFfiNoIsolate,
    databasePath: inMemoryDatabasePath,
  );
  await helper.initialize(
    seedData: FoodDatabase.fromJson(
      dishesJson: dishesJson,
      categoriesJson: categoriesJson,
    ),
  );
  final state = AppState(
    databaseHelper: helper,
    guidelines: DietaryGuidelines.fromJson(
      (jsonDecode(guidelinesJson) as Map).cast<String, dynamic>(),
    ),
  );
  await state.loadFromDatabase();
  await state.completeOnboarding(
    profile: _profile(),
    petType: 'cat',
    petName: '小挑食',
  );
  return (state, helper);
}

Widget _wrap(WidgetTester tester, AppState state) {
  // 首页内容较长，放大视口让列表内容全部构建（避免懒加载导致找不到）。
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/manual_add',
        builder: (context, state) => const ManualAddPage(),
      ),
      GoRoute(
        path: '/recommendation',
        builder: (context, state) => const RecommendationDetailPage(),
      ),
    ],
  );
  return ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
  );
}

void main() {
  testWidgets('空状态：真实完成度为 0，日志为空并引导手动添加', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);

    await tester.pumpWidget(_wrap(tester, state));
    await pumpUiTransition(tester);

    expect(find.text('今天还没记录哦'), findsOneWidget);
    expect(find.text('0%'), findsWidgets);
    expect(find.text('0/5份'), findsOneWidget);
    // 推荐卡片显示真实引擎的时间行。
    expect(find.textContaining('下一餐'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('记录一餐后首页实时刷新：日志、结构、完成度同步', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);

    await tester.pumpWidget(_wrap(tester, state));
    await pumpUiTransition(tester);

    final meal = state.buildMealRecord(
      mealType: 'lunch',
      timestamp: DateTime.now(),
      dishes: const [MealDish(name: '黄焖鸡米饭', portionSize: 'normal')],
    );
    await state.saveMeal(meal, source: 'manual');
    await pumpUiTransition(tester);

    // 日志出现新记录（按菜名展示）。
    expect(find.text('黄焖鸡米饭'), findsWidgets);
    expect(state.mealsFor(DateTime.now()), hasLength(1));
    // 主食进度条是真实摄入 2/5 份，完成度 40%（不再是 0/5）。
    expect(find.text('0/5份'), findsNothing);
    expect(find.text('2/5份'), findsOneWidget);
    expect(find.text('40%'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部「+」弹出三项：拍照识别 / 相册选择 / 手动添加（模块 14）', (
    tester,
  ) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);

    await tester.pumpWidget(_wrap(tester, state));
    await pumpUiTransition(tester);

    await tester.tap(find.byTooltip('记一餐'));
    await pumpUiTransition(tester);

    // 首页空状态按钮和弹层入口都叫「手动添加」，共 2 处。
    expect(find.text('手动添加'), findsNWidgets(2));
    expect(find.text('拍照识别'), findsOneWidget);
    expect(find.text('相册选择'), findsOneWidget);
    // Phase 3 的「截图识别」占位入口已被真实识别入口取代。
    expect(find.text('截图识别'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部「+」→ 手动添加进入添加页', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);

    await tester.pumpWidget(_wrap(tester, state));
    await pumpUiTransition(tester);

    await tester.tap(find.byTooltip('记一餐'));
    await pumpUiTransition(tester);
    await tester.tap(find.text('手动添加').last);
    await pumpUiTransition(tester);

    expect(find.text('搜索菜名，或直接输入新菜名'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('推荐卡片点击进入推荐详情页（真实引擎结果）', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);

    await tester.pumpWidget(_wrap(tester, state));
    await pumpUiTransition(tester);

    await tester.tap(find.textContaining('补一补'));
    await pumpUiTransition(tester);

    expect(find.text('下一餐推荐'), findsOneWidget);
    expect(find.text('推荐菜品'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
