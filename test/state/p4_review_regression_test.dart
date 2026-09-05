import 'package:canting/ui/record/dish_edit_list.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:canting/ui/record/record_detail_page.dart';

import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/platform/android_native_bridge.dart';
import 'package:canting/services/ocr_pipeline.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ControlledBridge extends AndroidNativeBridge {
  final calls = <Completer<NativeOcrResult>>[];
  @override
  Future<NativeOcrResult> recognizeImage(String uri) {
    final c = Completer<NativeOcrResult>();
    calls.add(c);
    return c.future;
  }
}

NativeOcrResult result(String name) => NativeOcrResult(
  fullText: name,
  engine: 'controlled',
  merchant: name,
  dishes: [NativeRecognizedDish(name: name, quantity: 1)],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  late DatabaseHelper db;
  late ControlledBridge bridge;
  late OcrPipeline pipeline;
  setUp(() async {
    sqfliteFfiInit();
    db = DatabaseHelper(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
    await db.initialize(
      seedData: FoodDatabase.fromJson(
        dishesJson: File('assets/data/dishes.json').readAsStringSync(),
        categoriesJson: File('assets/data/categories.json').readAsStringSync(),
      ),
    );
    state = AppState(
      databaseHelper: db,
      guidelines: DietaryGuidelines.fromJson(
        (jsonDecode(
          File('assets/data/dietary_guidelines.json').readAsStringSync(),
        ) as Map).cast<String, dynamic>(),
      ),
    );
    await state.loadFromDatabase();
    bridge = ControlledBridge();
    pipeline = OcrPipeline(appState: state, bridge: bridge);
  });
  tearDown(() async {
    state.dispose();
    await db.close();
  });
  test('review: parser uncertain item retains merchant identity', () async {
    pipeline.begin('a');
    final pending = pipeline.recognize('a');
    bridge.calls.single.complete(
      const NativeOcrResult(
        fullText: '米饭×100',
        engine: 'controlled',
        merchant: '甲餐厅',
        dishes: [
          NativeRecognizedDish(
            name: '米饭×100',
            quantity: 1,
            requiresConfirmation: true,
          ),
        ],
      ),
    );
    await pending;
    final food = state.recognitionDraft!.dishes.single.food!;
    debugPrint(
      'REVIEW brand=${food.facts.brand} origin=${food.brandOrigin} context=${food.merchantContext}',
    );
    expect(food.facts.brand, '甲餐厅');
    expect(food.brandOrigin, 'merchant');
    expect(food.confirmed, false);
  });
  testWidgets('review: accepted replacement clears old meal note', (t) async {
    state.startSharedRecognition('a');
    state.completeSharedRecognition(
      imageUri: 'a',
      merchant: '甲',
      dishes: const [],
    );
    final router = GoRouter(
      initialLocation: '/record',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Scaffold()),
        GoRoute(
          path: '/record',
          builder: (_, _) => const RecordDetailPage(isSharedRecognition: true),
        ),
      ],
    );
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await t.pumpAndSettle();
    final note = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '记一句：这顿吃得怎么样？',
    );
    await t.scrollUntilVisible(
      note,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.enterText(note, '旧订单独有备注');
    final replace = state.mayReplaceRecognition();
    await t.pumpAndSettle();
    await t.tap(find.text('替换'));
    await t.pumpAndSettle();
    expect(await replace, true);
    state.startSharedRecognition('b');
    state.completeSharedRecognition(
      imageUri: 'b',
      merchant: '乙',
      dishes: const [],
    );
    await t.pumpAndSettle();
    final actual = t.widget<TextField>(note).controller!.text;
    debugPrint('REVIEW replacement note=$actual');
    await t.pumpWidget(const SizedBox());
    router.dispose();
    expect(actual, isEmpty);
  });
  for (final same in [true, false]) {
    test('A then B then B success then A success sameUri=$same', () async {
      pipeline.begin('a');
      final a = pipeline.recognize('a');
      final uri = same ? 'a' : 'b';
      pipeline.begin(uri);
      final b = pipeline.recognize(uri);
      bridge.calls[1].complete(result('新商品'));
      await b;
      bridge.calls[0].complete(result('旧商品'));
      await a;
      expect(state.recognitionDraft!.merchant, '新商品');
      expect(await db.database.query('meal_records'), isEmpty);
    });
  }
  test('same URI stale failure cannot replace newer loading', () async {
    pipeline.begin('a');
    final a = pipeline.recognize('a');
    pipeline.begin('a');
    final b = pipeline.recognize('a');
    bridge.calls[0].completeError(StateError('old'));
    await a;
    expect(state.recognitionDraft!.isLoading, true);
    bridge.calls[1].complete(result('新商品'));
    await b;
  });
  test('timeout and cancel do not resurrect draft or save meals', () async {
    pipeline.begin('a');
    final a = pipeline.recognize('a', timeout: const Duration(milliseconds: 1));
    await a;
    expect(state.recognitionDraft!.error, isNotNull);
    state.clearSharedRecognition();
    bridge.calls[0].complete(result('迟到'));
    await Future<void>.delayed(Duration.zero);
    expect(state.recognitionDraft, isNull);
    expect(await db.database.query('meal_records'), isEmpty);
  });
  testWidgets(
    'manual edit survives late result; replacement cancel preserves page; discard leaves no DB rows',
    (t) async {
      pipeline.begin('a');
      final pending = pipeline.recognize('a');
      final router = GoRouter(
        initialLocation: '/record',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/record',
            builder: (_, _) =>
                const RecordDetailPage(isSharedRecognition: true),
          ),
        ],
      );
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await t.pump();
      await t.enterText(find.byType(TextField).first, '我的手动商家');
      await t.pump();
      bridge.calls[0].complete(result('迟到商家'));
      await pending;
      await t.pump();
      expect(find.text('我的手动商家'), findsOneWidget);
      final replacing = state.mayReplaceRecognition();
      await t.pumpAndSettle();
      expect(find.text('替换当前未保存内容？'), findsOneWidget);
      await t.tap(find.text('继续编辑'));
      await t.pumpAndSettle();
      expect(await replacing, false);
      expect(find.text('我的手动商家'), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      await t.tap(find.text('放弃'));
      await t.pumpAndSettle();
      expect(state.recognitionDraft, isNull);
      expect(await db.database.query('meal_records'), isEmpty);
      await t.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets('leaving loading production page invalidates callback', (
    t,
  ) async {
    pipeline.begin('a');
    final pending = pipeline.recognize('a');
    final router = GoRouter(
      initialLocation: '/record',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/record',
          builder: (_, _) => const RecordDetailPage(isSharedRecognition: true),
        ),
      ],
    );
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await t.pump();
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    bridge.calls[0].complete(result('迟到'));
    await pending;
    await t.pump();
    expect(find.text('home'), findsOneWidget);
    expect(state.recognitionDraft, isNull);
    expect(await db.database.query('meal_records'), isEmpty);
    await t.pumpWidget(const SizedBox());
    router.dispose();
  });
  test(
    'native parser uncertain item remains unresolved through production state',
    () async {
      pipeline.begin('a');
      final pending = pipeline.recognize('a');
      bridge.calls[0].complete(
        const NativeOcrResult(
          fullText: '米饭×100',
          engine: 'controlled',
          merchant: '',
          warnings: ['数量需确认'],
          dishes: [
            NativeRecognizedDish(
              name: '米饭×100',
              quantity: 1,
              requiresConfirmation: true,
            ),
          ],
        ),
      );
      await pending;
      final d = state.recognitionDraft!.dishes.single;
      expect(d.contributionsKnown, false);
      expect(d.food!.confirmed, false);
      expect(d.food!.matchedBy, 'parser_uncertain');
      expect(state.recognitionDraft!.warning, '数量需确认');
    },
  );
  testWidgets(
    'double save opens one unknown confirmation and writes one meal',
    (t) async {
      state.startSharedRecognition('a');
      state.completeSharedRecognition(
        imageUri: 'a',
        merchant: '',
        dishes: const [MealDish(name: '完全未知商品')],
      );
      final router = GoRouter(
        initialLocation: '/record',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/record',
            builder: (_, _) =>
                const RecordDetailPage(isSharedRecognition: true),
          ),
        ],
      );
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await t.pump();
      final button = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, '保存并更新今日结构'),
      );
      button.onPressed!();
      button.onPressed!();
      await t.pumpAndSettle();
      expect(find.text('保留待确认商品？'), findsOneWidget);
      expect(await state.mayReplaceRecognition(), false);
      await t.tap(find.text('明确保留未知并保存'));
      await t.pumpAndSettle();
      expect(await db.database.query('meal_records'), hasLength(1));
      expect(await db.database.query('user_food_profiles'), isEmpty);
      expect(state.recognitionDraft, isNull);
      await t.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  Future<GoRouter> mountPage(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final router = GoRouter(
      initialLocation: '/record',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('saved')),
        ),
        GoRoute(
          path: '/record',
          builder: (_, _) => const RecordDetailPage(isSharedRecognition: true),
        ),
      ],
    );
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await t.pumpAndSettle();
    return router;
  }

  Finder merchantField() => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == '商家名称',
  );
  Finder noteField() => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == '记一句：这顿吃得怎么样？',
  );
  Future<void> savePage(WidgetTester t) async {
    await t.tap(find.text('保存并更新今日结构'));
    await t.pumpAndSettle();
    if (find.text('明确保留未知并保存').evaluate().isNotEmpty) {
      await t.tap(find.text('明确保留未知并保存'));
      await t.pumpAndSettle();
    }
  }

  for (final mode in [
    'merchant',
    'change',
    'clear',
    'explicit',
    'keep-unknown',
  ]) {
    testWidgets('R1 production confirmation SQLite $mode', (t) async {
      pipeline.begin('a');
      final pending = pipeline.recognize('a');
      bridge.calls[0].complete(
        const NativeOcrResult(
          fullText: '商品套餐无糖小杯×100',
          engine: 'controlled',
          merchant: '甲餐厅',
          dishes: [
            NativeRecognizedDish(
              name: '商品套餐无糖小杯×100',
              quantity: 1,
              requiresConfirmation: true,
            ),
          ],
        ),
      );
      await pending;
      final router = await mountPage(t);
      final target = mode == 'clear'
          ? ''
          : mode == 'change'
          ? '乙餐厅'
          : '甲餐厅';
      if (mode == 'clear' || mode == 'change') {
        await t.enterText(merchantField(), target);
        await t.pumpAndSettle();
      }
      final dish = t
          .widget<DishEditList>(find.byType(DishEditList))
          .dishes
          .single;
      expect(dish.food!.facts.brand, target);
      expect(dish.food!.brandOrigin, 'merchant');
      expect(dish.food!.merchantContext, target);
      expect(dish.food!.matchedBy, 'parser_uncertain');
      expect(dish.food!.confirmed, false);
      expect(dish.contributionsKnown, false);
      expect(dish.food!.spec.sugar, 'none');
      expect(dish.food!.spec.cup, 'small');
      expect(dish.name, contains('×100'));
      if (mode != 'keep-unknown') {
        await t.tap(
          find
              .descendant(
                of: find.byType(DishEditList),
                matching: find.byType(ListTile),
              )
              .first,
        );
        await t.pumpAndSettle();
        final brand = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '品牌（不确定可留空）',
        );
        expect(t.widget<TextField>(brand).controller!.text, target);
        if (mode == 'explicit') await t.enterText(brand, '单品品牌');
        await t.tap(find.byKey(const ValueKey('商品类别-unknown')));
        await t.pumpAndSettle();
        await t.tap(find.text('奶茶').last);
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('确认本次商品'));
        await t.tap(find.text('确认本次商品'));
        await t.pumpAndSettle();
      }
      if (mode == 'explicit') {
        await t.enterText(merchantField(), '乙餐厅');
        await t.pumpAndSettle();
      }
      await savePage(t);
      final record = jsonDecode(
        (await db.database.query('meal_records')).single['record_json']!
            as String,
      ) as Map;
      final stored = (record['dishes'] as List).single as Map;
      final food = stored['food'] as Map;
      expect(
        (food['facts'] as Map)['brand'],
        mode == 'explicit' ? '单品品牌' : target,
      );
      expect(stored['name'], contains('×100'));
      expect(stored['quantity'], 1);
      expect((food['spec'] as Map)['sugar'], 'none');
      expect((food['spec'] as Map)['cup'], 'small');
      expect(state.localFoods.length, mode == 'keep-unknown' ? 0 : 1);
      if (mode != 'keep-unknown') {
        expect(
          state.localFoods.single.facts.brand,
          mode == 'explicit' ? '单品品牌' : target,
        );
      }
      await t.pumpWidget(const SizedBox());
      router.dispose();
    });
  }
  for (final mode in ['accept', 'cancel', 'late-date', 'late-time']) {
    testWidgets('R2 replacement full order defaults SQLite $mode', (t) async {
      state.startSharedRecognition('a');
      state.completeSharedRecognition(
        imageUri: 'a',
        merchant: '旧商家',
        dishes: const [MealDish(name: '旧商品')],
      );
      final router = await mountPage(t);
      await t.ensureVisible(noteField());
      await t.enterText(noteField(), '旧订单独有备注');
      await t.pumpAndSettle();
      t
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .onSelectionChanged!({'snack'});
      await t.pump();
      final dateButton = find.widgetWithIcon(
        OutlinedButton,
        Icons.calendar_today_outlined,
      );
      await t.ensureVisible(dateButton);
      await t.tap(dateButton);
      await t.pumpAndSettle();
      Navigator.of(t.element(find.byType(DatePickerDialog)))
          .pop(DateTime(2021, 2, 3));
      await t.pumpAndSettle();
      final timeButton = find.widgetWithIcon(OutlinedButton, Icons.schedule);
      await t.tap(timeButton);
      await t.pumpAndSettle();
      Navigator.of(t.element(find.byType(TimePickerDialog)))
          .pop(const TimeOfDay(hour: 2, minute: 17));
      await t.pumpAndSettle();
      if (mode == 'late-date') {
        await t.tap(dateButton);
        await t.pumpAndSettle();
      }
      if (mode == 'late-time') {
        await t.tap(timeButton);
        await t.pumpAndSettle();
      }
      final decision = state.mayReplaceRecognition();
      await t.pumpAndSettle();
      await t.tap(find.text(mode == 'cancel' ? '继续编辑' : '替换'));
      await t.pumpAndSettle();
      expect(await decision, mode != 'cancel');
      final now = DateTime.now();
      if (mode != 'cancel') {
        state.startSharedRecognition('b');
        state.completeSharedRecognition(
          imageUri: 'b',
          merchant: '新商家',
          dishes: const [MealDish(name: '新商品')],
        );
        await t.pumpAndSettle();
      }
      if (mode == 'late-date') {
        Navigator.of(t.element(find.byType(DatePickerDialog)))
            .pop(DateTime(2022, 3, 4));
        await t.pumpAndSettle();
      }
      if (mode == 'late-time') {
        Navigator.of(t.element(find.byType(TimePickerDialog)))
            .pop(const TimeOfDay(hour: 1, minute: 2));
        await t.pumpAndSettle();
      }
      await savePage(t);
      final row = (await db.database.query('meal_records')).single;
      final record = jsonDecode(row['record_json']! as String) as Map;
      expect(row['note'], mode == 'cancel' ? '旧订单独有备注' : isNull);
      expect(record['merchant'], mode == 'cancel' ? '旧商家' : '新商家');
      expect(
        ((record['dishes'] as List).single as Map)['name'],
        mode == 'cancel' ? '旧商品' : '新商品',
      );
      final timestamp = DateTime.parse(record['timestamp'] as String);
      if (mode == 'cancel') {
        expect(timestamp, DateTime(2021, 2, 3, 2, 17));
        expect(record['meal_type'], 'snack');
      } else {
        expect(timestamp.year, now.year);
        expect(timestamp.month, now.month);
        expect(timestamp.day, now.day);
        expect(timestamp.difference(now).inMinutes.abs(), lessThan(2));
        expect(
          record['meal_type'],
          now.hour < 10
              ? 'breakfast'
              : now.hour < 15
              ? 'lunch'
              : now.hour < 21
              ? 'dinner'
              : 'snack',
        );
      }
      await t.pumpWidget(const SizedBox());
      router.dispose();
    });
  }
}
