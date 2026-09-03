import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/main.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/home/widgets/nutrition_ring_chart.dart';
import 'package:canting/ui/home/widgets/pet_area.dart';
import 'package:canting/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> pumpUiTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

UserProfile _testProfile() {
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
    createdAt: now,
    updatedAt: now,
  );
}

/// Loads the real dietary-guidelines asset the same way main() does.
DietaryGuidelines _loadGuidelines() => DietaryGuidelines.fromJson(
  (jsonDecode(
        File('assets/data/dietary_guidelines.json').readAsStringSync(),
      )
      as Map)
      .cast<String, dynamic>(),
);

/// Builds an [AppState] backed by an in-memory SQLite database so persistence
/// code paths run for real inside widget tests.
Future<(AppState, DatabaseHelper)> _buildState({bool onboarded = false}) async {
  sqfliteFfiInit();
  final helper = DatabaseHelper(
    factory: databaseFactoryFfiNoIsolate,
    databasePath: inMemoryDatabasePath,
  );
  await helper.initialize();
  final state = AppState(
    databaseHelper: helper,
    guidelines: _loadGuidelines(),
  );
  await state.loadFromDatabase();
  if (onboarded) {
    await state.completeOnboarding(
      profile: _testProfile(),
      petType: 'cat',
      petName: '小挑食',
    );
  }
  return (state, helper);
}

void main() {
  test('dark overlays use translucent themed surfaces', () {
    final theme = AppTheme.dark();

    expect(theme.dialogTheme.backgroundColor?.a, lessThan(1));
    expect(theme.bottomSheetTheme.backgroundColor?.a, lessThan(1));
  });

  testWidgets('first launch shows the six-step setup flow', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);
    await tester.pumpWidget(CantingApp(appState: state));
    await tester.pump();

    expect(find.text('餐盘'), findsOneWidget);
    expect(find.text('1 / 6  欢迎'), findsOneWidget);

    await tester.tap(find.text('开始设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('2 / 6  身体信息'), findsOneWidget);
    expect(find.text('身体信息'), findsWidgets);
  });

  testWidgets('completing setup persists the profile with guideline targets', (
    tester,
  ) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);
    await tester.pumpWidget(CantingApp(appState: state));
    await tester.pump();

    expect(state.onboardingComplete, isFalse);

    Future<void> next() async {
      await tester.tap(
        find.text('开始设置').evaluate().isNotEmpty
            ? find.text('开始设置')
            : find.text('下一步'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await next(); // 欢迎 → 身体信息
    await next(); // 身体信息 → 活动水平
    await next(); // 活动水平 → 饮食目标

    // 选择「多吃蔬菜」：页面发出的编码必须是计算器认识的 more_veg。
    await tester.tap(find.text('多吃蔬菜'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await next(); // 饮食目标 → 作息习惯
    expect(find.text('作息习惯'), findsWidgets);
    await next(); // 作息习惯 → 选择伙伴
    expect(find.text('6 / 6  选择伙伴'), findsOneWidget);

    // 最后一步按钮文案为「一起开始」，完成后落库并跳首页。
    await tester.tap(find.text('一起开始'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(state.onboardingComplete, isTrue);
    expect(state.profile, isNotNull);
    expect(state.profile!.onboardingCompleted, isTrue);
    expect(state.profile!.dietGoal, 'more_veg');
    // 目标份数快照已计算（默认女/165cm/55kg/28岁/轻活动 → TDEE≈1760，
    // 落在 1600~1800 档之间）；蔬菜目标在均衡档基础上 ×1.2。
    final intake = state.profile!.dailyIntake!;
    expect(intake.grains, inInclusiveRange(4, 5));
    expect(intake.vegetables, greaterThan(4.5)); // 4.40 × 1.2 ≈ 5.28
    expect(intake.fruits, inInclusiveRange(2, 2.5));
    expect(intake.protein, inInclusiveRange(3, 3.5));
    expect(intake.proteinSoy, inInclusiveRange(1, 1.5));
    expect(intake.oil, 2.5);
    // 作息时间使用草稿默认值落库。
    expect(state.profile!.breakfastTime, '08:00');
    expect(state.profile!.dayStartTime, '01:00');

    expect(find.text('今日'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed setup opens the home tab', (tester) async {
    final (state, helper) = await _buildState(onboarded: true);
    addTearDown(helper.close);

    await tester.pumpWidget(CantingApp(appState: state));
    await pumpUiTransition(tester);

    expect(find.text('今日'), findsWidgets);
    expect(find.text('今日小结'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('all onboarding steps fit a 375px-wide viewport', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final (state, helper) = await _buildState();
    addTearDown(helper.close);
    await tester.pumpWidget(CantingApp(appState: state));
    await tester.pump();

    for (final title in [
      '身体信息',
      '活动水平',
      '饮食目标',
      '作息习惯',
      '选择伙伴',
    ]) {
      await tester.tap(
        find.text('开始设置').evaluate().isNotEmpty
            ? find.text('开始设置')
            : find.text('下一步'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(title), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('main pages fit an iPhone SE-sized viewport', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final (state, helper) = await _buildState(onboarded: true);
    addTearDown(helper.close);

    await tester.pumpWidget(CantingApp(appState: state));
    await pumpUiTransition(tester);

    expect(tester.takeException(), isNull);
    final petHeight = tester.getSize(find.byType(PetArea)).height;
    expect(petHeight, inInclusiveRange(126, 127));
    expect(petHeight / 667, inInclusiveRange(0.15, 0.20));
    final ringTop = tester.getTopLeft(find.byType(NutritionRingChart)).dy;
    expect(ringTop, lessThan(560));

    await tester.tap(find.byTooltip('收起伙伴区'));
    await pumpUiTransition(tester);
    expect(tester.getSize(find.byType(PetArea)).height, lessThan(60));

    await tester.tap(find.text('记录').last);
    await pumpUiTransition(tester);
    expect(find.text('历史记录'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('我的').last);
    await pumpUiTransition(tester);
    expect(find.text('个人信息'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('今日').last);
    await pumpUiTransition(tester);
    await tester.tap(find.byTooltip('添加一餐'));
    await pumpUiTransition(tester);
    expect(find.text('识别结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving a recognized meal returns to home', (tester) async {
    final (state, helper) = await _buildState(onboarded: true);
    addTearDown(helper.close);
    final initialMealCount = state.mealsFor(DateTime.now()).length;

    await tester.pumpWidget(CantingApp(appState: state));
    await pumpUiTransition(tester);
    await tester.tap(find.byTooltip('添加一餐'));
    await pumpUiTransition(tester);

    expect(find.text('识别结果'), findsOneWidget);
    await tester.tap(find.text('保存并更新今日结构'));
    await pumpUiTransition(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('餐盘 · 今日'), findsOneWidget);
    expect(find.text('识别结果'), findsNothing);
    expect(state.mealsFor(DateTime.now()), hasLength(initialMealCount + 1));
    expect(find.text('这顿已经保存好啦'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
