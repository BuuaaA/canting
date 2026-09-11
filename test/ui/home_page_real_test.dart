import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/services/delivery_jump_service.dart';
import 'package:canting/services/next_meal_recommendation.dart';
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
Future<(AppState, DatabaseHelper)> _buildState({
  NextMealRecommendationService? nextMealService,
}) async {
  sqfliteFfiInit();
  final dishesJson = File('assets/data/dishes.json').readAsStringSync();
  final categoriesJson = File('assets/data/categories.json').readAsStringSync();
  final guidelinesJson = File('assets/data/dietary_guidelines.json')
      .readAsStringSync();
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
    nextMealService: nextMealService,
  );
  await state.loadFromDatabase();
  await state.completeOnboarding(
    profile: _profile(),
    petType: 'cat',
    petName: '小挑食',
  );
  return (state, helper);
}

Widget _wrap(
  WidgetTester tester,
  AppState state, {
  DeliveryJumpService? jumpService,
  String initialLocation = '/home',
}) {
  // 首页内容较长，放大视口让列表内容全部构建（避免懒加载导致找不到）。
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/home', builder: (context, state) => const HomePage()),
      GoRoute(
        path: '/manual_add',
        builder: (context, state) => const ManualAddPage(),
      ),
      GoRoute(
        path: '/recommendation',
        builder: (context, state) =>
            RecommendationDetailPage(jumpService: jumpService),
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
    expect(find.text('未记录'), findsWidgets);
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
    // 新首页使用十类统计；旧 MealDish 没有可验证的克重换算，不伪造份数。
    expect(find.textContaining('/5份'), findsNothing);
    expect(find.text('2/5份'), findsNothing);
    expect(find.text('40%'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部「+」弹出截图 / 实拍 / 手动添加', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);

    await tester.pumpWidget(_wrap(tester, state));
    await pumpUiTransition(tester);

    await tester.tap(find.byTooltip('记一餐'));
    await pumpUiTransition(tester);

    // 首页空状态按钮和弹层入口都叫「手动添加」，共 2 处。
    expect(find.text('手动添加'), findsNWidgets(2));
    expect(find.text('拍照记餐'), findsOneWidget);
    expect(find.text('识别订单截图'), findsOneWidget);
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

    await tester.tap(find.textContaining('下一餐可选'));
    await pumpUiTransition(tester);
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('下一餐推荐'), findsOneWidget);
    expect(find.text('推荐菜品'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /* testWidgets('推荐详情：平台打开成功后按关键词只记录一次 accept', (tester) async {
    final feedback = <NextMealFeedback>[];
    final service = NextMealRecommendationService(
      remote: (_) async => jsonEncode({
        'suggestions': [
          {
            'dishName': '清蒸鱼配时蔬',
            'searchKeyword': '清蒸鱼 时蔬 少油',
            'primaryCategory': 'animal_food',
            'estimatedServing': '一掌心（估算）',
            'reason': '补充动物性食物并控制油盐。',
          },
          {
            'dishName': '西兰花鸡胸肉饭',
            'searchKeyword': '西兰花鸡胸肉 少油少盐',
            'primaryCategory': 'vegetable',
            'estimatedServing': '一小盘（估算）',
            'reason': '补充蔬菜。',
          },
        ],
        'guidance': {
          'primary': '优先补足已知缺口。',
          'oilSalt': '选择少油少盐做法。',
          'reduceStaple': '主食按常规份量。',
        },
      }),
      feedbackSink: (event) async => feedback.add(event),
    );
    final (state, helper) = await _buildState(nextMealService: service);
    addTearDown(helper.close);
    final jump = DeliveryJumpService(
      configStore: const DefaultDeliveryPlatformConfig(),
      canLaunch: (_) async => false,
      launch: (uri, {mode = LaunchMode.platformDefault}) async => true,
    );
    await tester.pumpWidget(
      _wrap(
        tester,
        state,
        jumpService: jump,
        initialLocation: '/recommendation',
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('去外卖平台看看'), findsWidgets);
    await tester.tap(find.text('去外卖平台看看').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(
      feedback.where((event) => event.action == NextMealFeedbackAction.accept),
      hasLength(1),
    );
    expect(feedback.single.dishNames, contains('清蒸鱼配时蔬'));
    expect(tester.takeException(), isNull);
  }); */
}
