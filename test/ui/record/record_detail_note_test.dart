import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/record/record_detail_page.dart';
import 'package:canting/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _noteHint = '记一句：这顿吃得怎么样？';

UserProfile _profile() {
  final now = DateTime(2026, 9, 1);
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

DietaryGuidelines _guidelines() => DietaryGuidelines.fromJson(
  (jsonDecode(
    File('assets/data/dietary_guidelines.json').readAsStringSync(),
  ) as Map).cast<String, dynamic>(),
);

Future<(AppState, DatabaseHelper)> _buildState() async {
  sqfliteFfiInit();
  final helper = DatabaseHelper(
    factory: databaseFactoryFfiNoIsolate,
    databasePath: inMemoryDatabasePath,
  );
  await helper.initialize();
  final state = AppState(databaseHelper: helper, guidelines: _guidelines());
  await state.loadFromDatabase();
  await state.completeOnboarding(
    profile: _profile(),
    petType: 'cat',
    petName: '小挑食',
  );
  return (state, helper);
}

Widget _wrap(AppState state, {String? mealId}) {
  final router = GoRouter(
    initialLocation: mealId == null
        ? '/record_detail'
        : '/record_detail?mealId=$mealId',
    routes: [
      GoRoute(
        path: '/record_detail',
        builder: (context, state) => RecordDetailPage(
          mealId: state.uri.queryParameters['mealId'],
          returnLocation: '/home',
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(body: Text('首页占位')),
      ),
    ],
  );
  return ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
  );
}

TextField _noteField(WidgetTester tester) => tester.widget<TextField>(
  find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == _noteHint,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 放大视口让页面底部的备注输入框构建出来（ListView 懒加载）。
  void useBigViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('新记录：备注默认为空，保存时写入 note 列', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);
    useBigViewport(tester);

    await tester.pumpWidget(_wrap(state));
    await tester.pump();
    await tester.pump();

    expect(_noteField(tester).controller!.text, isEmpty);

    // 先加一道菜，保存按钮才可用（与 widget_test 的保存流程一致）。
    await tester.tap(find.text('添加'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '清炒土豆丝',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('添加')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(_noteFieldFinder(), '微辣少油');
    await tester.pump();
    await tester.tap(find.text('保存并更新今日结构'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    if (find.text('明确保留未知并保存').evaluate().isNotEmpty) {
      await tester.tap(find.text('明确保留未知并保存'));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final mealId = state.mealsFor(DateTime.now()).single.mealId;
    expect(await state.mealNote(mealId), '微辣少油');
  });

  testWidgets('已有记录：备注从数据库回填，可编辑并再次保存', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);
    useBigViewport(tester);

    final meal = state.buildMealRecord(
      mealType: 'lunch',
      timestamp: DateTime.now(),
      dishes: const [MealDish(name: '清炒土豆丝')],
    );
    await state.saveMeal(meal, note: '微辣少油');
    final mealId = meal.mealId;

    await tester.pumpWidget(_wrap(state, mealId: mealId));
    await tester.pump();
    await tester.pump();

    // 打开即展示已存的备注。
    expect(_noteField(tester).controller!.text, '微辣少油');

    await tester.enterText(_noteFieldFinder(), '下次多放醋');
    await tester.pump();
    await tester.tap(find.text('保存并更新今日结构'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    if (find.text('明确保留未知并保存').evaluate().isNotEmpty) {
      await tester.tap(find.text('明确保留未知并保存'));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(await state.mealNote(mealId), '下次多放醋');
  });

  testWidgets('清空备注后保存，note 列回到空', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);
    useBigViewport(tester);

    final meal = state.buildMealRecord(
      mealType: 'lunch',
      timestamp: DateTime.now(),
      dishes: const [MealDish(name: '清炒土豆丝')],
    );
    await state.saveMeal(meal, note: '微辣少油');
    final mealId = meal.mealId;

    await tester.pumpWidget(_wrap(state, mealId: mealId));
    await tester.pump();
    await tester.pump();

    await tester.enterText(_noteFieldFinder(), '');
    await tester.pump();
    await tester.tap(find.text('保存并更新今日结构'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    if (find.text('明确保留未知并保存').evaluate().isNotEmpty) {
      await tester.tap(find.text('明确保留未知并保存'));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(await state.mealNote(mealId), isNull);
  });
}

Finder _noteFieldFinder() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == _noteHint,
);
