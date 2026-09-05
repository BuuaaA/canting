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
}
