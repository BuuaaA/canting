import '../support/evidence.dart';

import 'package:canting/ui/recommendation/recommended_dish_card.dart';
import 'package:flutter/services.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:canting/core_engine.dart';
import 'package:canting/core/models/local_food.dart';
import 'package:canting/data/meal_repository.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/record/record_detail_page.dart';
import 'package:canting/ui/history/record_summary_panel.dart';
import 'package:canting/ui/recommendation/recommendation_detail_page.dart';
import 'package:canting/ui/record/exposure_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const drink = MealDish(
  name: '合成低糖饮品',
  contributionsKnown: false,
  food: FoodObservation(
    facts: FoodFacts(name: '合成低糖饮品', category: 'milk_tea'),
    spec: OrderSpec(sugar: 'low'),
    confirmed: true,
  ),
);
Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(evidencePath('$name.png'))
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    // Screenshot-only host font; not copied into the app or repository.
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final loader = FontLoader('P3Evidence')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
    final icons = File(
      'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
  });
  Future<(AppState, DatabaseHelper)> setup() async {
    final db = DatabaseHelper(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
    await db.initialize(
      seedData: FoodDatabase.fromJson(
        dishesJson: File('assets/data/dishes.json').readAsStringSync(),
        categoriesJson: File('assets/data/categories.json').readAsStringSync(),
      ),
    );
    final state = AppState(
      databaseHelper: db,
      guidelines: DietaryGuidelines.fromJson(
        jsonDecode(
          File('assets/data/dietary_guidelines.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      ),
    );
    await state.loadFromDatabase();
    return (state, db);
  }

  testWidgets(
    'production record save presents one dismissible prompt after SQLite commit; preference leaves sugar unchanged',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final (state, db) = await setup();
      addTearDown(db.close);
      await state.saveMeal(
        MealRecord(
          mealId: 'prior',
          mealType: 'lunch',
          timestamp: DateTime.now(),
          dishes: [drink],
        ),
      );
      state.startSharedRecognition('synthetic');
      state.completeSharedRecognition(
        imageUri: 'synthetic',
        merchant: '',
        dishes: [drink],
      );
      final router = GoRouter(
        initialLocation: '/record',
        routes: [
          GoRoute(
            path: '/record',
            builder: (_, s) =>
                const RecordDetailPage(isSharedRecognition: true),
          ),
          GoRoute(
            path: '/home',
            builder: (_, s) => const Scaffold(body: Text('保存完成首页')),
          ),
        ],
      );
      final key = GlobalKey();
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: RepaintBoundary(
            key: key,
            child: MaterialApp.router(
              theme: ThemeData(fontFamily: 'P3Evidence'),
              routerConfig: router,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('保存并更新今日结构'));
      await t.pumpAndSettle();
      if (find.text('明确保留未知并保存').evaluate().isNotEmpty) {
        await t.tap(find.text('明确保留未知并保存'));
        await t.pumpAndSettle();
      }
      expect(find.text('已保存，给下次一个小建议'), findsOneWidget);
      expect((await db.database.query('meal_records')).length, 2);
      await capture(t, key, 'component-save-prompt');
      await t.tap(find.text('记住下次偏好：不另外加糖'));
      await t.pumpAndSettle();
      expect(
        (await state.exposurePreferences())['next_time_preference'],
        'no_added_sugar',
      );
      final meals = await MealRepository(database: () => db.database)
          .getMealsByDateRange(DateTime(2020), DateTime(2030));
      expect(
        meals.every((m) => m.dishes.single.food!.spec.sugar == 'low'),
        true,
      );
      await t.tap(find.text('知道了'));
      await t.pumpAndSettle();
      expect(find.text('保存完成首页'), findsOneWidget);
      await t.pump();
      expect(find.text('已保存，给下次一个小建议'), findsNothing);
      await t.pumpWidget(const SizedBox());
      router.dispose();
      state.dispose();
    },
  );
  testWidgets(
    'production recommendation switches 7/28, shows partial coverage and preferences are editable',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final (state, db) = await setup();
      addTearDown(db.close);
      await state.saveMeal(
        MealRecord(
          mealId: 'partial',
          mealType: 'lunch',
          timestamp: DateTime.now(),
          dishes: [drink],
        ),
      );
      final key = GlobalKey();
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'P3Evidence'),
              home: const RecommendationDetailPage(),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('未知条目1个'), findsOneWidget);
      await capture(t, key, 'component-recommendation-7d');
      await t.tap(find.text('最近28天'));
      await t.pumpAndSettle();
      expect(find.textContaining('28天差额不分摊'), findsOneWidget);
      await capture(t, key, 'component-recommendation-28d');
      await t.pumpWidget(
        MaterialApp(home: ExposurePreferencesPage(state: state)),
      );
      await t.pumpAndSettle();
      expect(find.text('下次偏好：不另外加糖'), findsOneWidget);
      await t.tap(find.byType(Switch).first);
      await t.pumpAndSettle();
      expect((await state.exposurePreferences())['enabled'], false);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'production 28-day summary reports complete recorded coverage without claiming insufficient data or improvement',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final (state, db) = await setup();
      addTearDown(db.close);
      final today = DateTime.now();
      final repository = MealRepository(database: () => db.database);
      for (var offset = 0; offset < 28; offset++) {
        final date = DateTime(today.year, today.month, today.day - offset, 12);
        await repository.addMeal(
          MealRecord(
            mealId: 'complete-28-$offset',
            mealType: 'lunch',
            timestamp: date,
            portionsTotal: const Portions(
              grains: 1,
              vegetables: 1,
              fruits: 1,
              protein: 1,
              proteinSoy: 1,
              oil: 1,
            ),
          ),
        );
      }
      await state.refreshBalanceLedger(reference: today);

      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'P3Evidence'),
            home: const Scaffold(body: RecordSummaryPanel()),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('最近28天'));
      await t.pumpAndSettle();

      expect(
        find.textContaining('28天：有记录28天，其中估算不完整0天；无记录0天；未知条目0个'),
        findsOneWidget,
      );
      expect(find.text('仅展示已记录餐食结构，暂不判断改善趋势；28天差额不分摊到下一餐。'), findsOneWidget);
      expect(find.textContaining('记录不足'), findsNothing);
      expect(find.textContaining('不代表全天摄入'), findsOneWidget);
      expect(find.textContaining('改善百分比'), findsNothing);

      await t.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'production summary keeps empty and database-error states explicit',
    (t) async {
      final (emptyState, emptyDb) = await setup();
      addTearDown(emptyDb.close);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: emptyState,
          child: const MaterialApp(home: Scaffold(body: RecordSummaryPanel())),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('暂无可用记录，暂不判断结构或达标'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      emptyState.dispose();
      await emptyDb.close();

      final (errorState, errorDb) = await setup();
      await errorDb.close();
      await errorState.refreshBalanceLedger();
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: errorState,
          child: const MaterialApp(home: Scaffold(body: RecordSummaryPanel())),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('记录读取失败，暂不判断缺口或趋势'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      errorState.dispose();
    },
  );
  for (final count in [0, 1, 2]) {
    testWidgets(
      'real recommendation page renders $count safe cards and never unsafe fallback',
      (t) async {
        t.view.physicalSize = const Size(1080, 2400);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final (state, db) = await setup();
        addTearDown(db.close);
        const category = FoodCategory(
          id: 'test_plain',
          name: '测试',
          oilLevel: 'low',
          oilFactor: 1,
          averagePortions: Portions(grains: 1),
          keywords: [],
        );
        StandardDish d(String id, bool safe) => StandardDish(
          id: id,
          name: id,
          aliases: [],
          category: 'test_plain',
          portionsNormal: const Portions(grains: 1, protein: 1),
          cookingOilRatio: 0,
          oilFactor: 1,
          sodiumLevel: 'low',
          searchKeywords: [],
          qualityTags: safe ? [] : ['fried', 'light'],
        );
        await db.replaceAll(
          FoodDatabase(
            dishes: [
              for (var i = 0; i < count; i++) d('safe-$i', true),
              d('blocked-fried', false),
            ],
            categories: [category],
          ),
        );
        await state.refreshDishMatcher();
        await t.pumpWidget(
          ChangeNotifierProvider.value(
            value: state,
            child: const MaterialApp(home: RecommendationDetailPage()),
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(RecommendedDishCard), findsNWidgets(count));
        expect(find.text('blocked-fried'), findsNothing);
        expect(find.textContaining('可推荐候选不足'), findsWidgets);
        if (count > 0) {
          await t.tap(find.text('换一批推荐'));
          await t.pumpAndSettle();
          expect(find.byType(RecommendedDishCard), findsNothing);
          await t.tap(find.text('重新开始推荐'));
          await t.pumpAndSettle();
          expect(find.byType(RecommendedDishCard), findsNWidgets(count));
        }
        await t.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }
}
