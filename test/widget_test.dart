import 'package:canting/main.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/home/widgets/nutrition_ring_chart.dart';
import 'package:canting/ui/home/widgets/pet_area.dart';
import 'package:canting/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpUiTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  test('dark overlays use translucent themed surfaces', () {
    final theme = AppTheme.dark();

    expect(theme.dialogTheme.backgroundColor?.a, lessThan(1));
    expect(theme.bottomSheetTheme.backgroundColor?.a, lessThan(1));
  });

  testWidgets('first launch shows the five-step setup flow', (tester) async {
    await tester.pumpWidget(CantingApp(appState: AppState()));
    await tester.pump();

    expect(find.text('餐盘'), findsOneWidget);
    expect(find.text('1 / 5  欢迎'), findsOneWidget);

    await tester.tap(find.text('开始设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('2 / 5  身体信息'), findsOneWidget);
    expect(find.text('身体信息'), findsWidgets);
  });

  testWidgets('completed setup opens the home tab', (tester) async {
    final state = AppState()
      ..completeOnboarding(
        setupProfile: SetupProfile(
          gender: 'female',
          heightCm: 165,
          weightKg: 55,
          age: 28,
          activityLevel: 'light',
          dietGoal: 'balanced',
          breakfast: const TimeOfDay(hour: 8, minute: 0),
          lunch: const TimeOfDay(hour: 12, minute: 0),
          dinner: const TimeOfDay(hour: 18, minute: 30),
          dayBoundaryHour: 1,
        ),
        petType: 'cat',
        petName: '小挑食',
      );

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

    await tester.pumpWidget(CantingApp(appState: AppState()));
    await tester.pump();

    for (final title in ['身体信息', '活动水平', '饮食目标', '选择伙伴']) {
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

    final state = AppState()
      ..completeOnboarding(
        setupProfile: SetupProfile(
          gender: 'female',
          heightCm: 165,
          weightKg: 55,
          age: 28,
          activityLevel: 'light',
          dietGoal: 'balanced',
          breakfast: const TimeOfDay(hour: 8, minute: 0),
          lunch: const TimeOfDay(hour: 12, minute: 0),
          dinner: const TimeOfDay(hour: 18, minute: 30),
          dayBoundaryHour: 1,
        ),
        petType: 'cat',
        petName: '小挑食',
      );

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
    final state = AppState()
      ..completeOnboarding(
        setupProfile: SetupProfile(
          gender: 'female',
          heightCm: 165,
          weightKg: 55,
          age: 28,
          activityLevel: 'light',
          dietGoal: 'balanced',
          breakfast: const TimeOfDay(hour: 8, minute: 0),
          lunch: const TimeOfDay(hour: 12, minute: 0),
          dinner: const TimeOfDay(hour: 18, minute: 30),
          dayBoundaryHour: 1,
        ),
        petType: 'cat',
        petName: '小挑食',
      );
    final initialMealCount = state.meals.length;

    await tester.pumpWidget(CantingApp(appState: state));
    await pumpUiTransition(tester);
    await tester.tap(find.byTooltip('添加一餐'));
    await pumpUiTransition(tester);

    expect(find.text('识别结果'), findsOneWidget);
    await tester.tap(find.text('保存并更新今日结构'));
    await pumpUiTransition(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    debugPrint(
      tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(find.text('餐盘 · 今日'), findsOneWidget);
    expect(find.text('识别结果'), findsNothing);
    expect(state.meals, hasLength(initialMealCount + 1));
    expect(find.text('这顿已经保存好啦'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
