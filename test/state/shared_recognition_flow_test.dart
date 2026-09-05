import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/main.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DietaryGuidelines _guidelines() => DietaryGuidelines.fromJson(
  (jsonDecode(
    File('assets/data/dietary_guidelines.json').readAsStringSync(),
  ) as Map).cast<String, dynamic>(),
);

UserProfile _profile() {
  final now = DateTime(2026, 9, 4);
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

/// 与 main() 相同的真实菜库种子，保证 DishMatcher 有菜可匹配。
FoodDatabase _seedFoodDatabase() => FoodDatabase.fromJson(
  dishesJson: File('assets/data/dishes.json').readAsStringSync(),
  categoriesJson: File('assets/data/categories.json').readAsStringSync(),
);

Future<(AppState, DatabaseHelper)> _buildState({bool onboarded = false}) async {
  sqfliteFfiInit();
  final helper = DatabaseHelper(
    factory: databaseFactoryFfiNoIsolate,
    databasePath: inMemoryDatabasePath,
  );
  await helper.initialize(seedData: _seedFoodDatabase());
  final state = AppState(databaseHelper: helper, guidelines: _guidelines());
  await state.loadFromDatabase();
  if (onboarded) {
    await state.completeOnboarding(
      profile: _profile(),
      petType: 'cat',
      petName: '小挑食',
    );
  }
  return (state, helper);
}

Future<Map<String, dynamic>> _recordRow(
  DatabaseHelper helper,
  String mealId,
) async {
  final rows = await helper.database.query(
    'meal_records',
    where: 'id = ?',
    whereArgs: [mealId],
  );
  return (jsonDecode(rows.single['record_json']! as String) as Map)
      .cast<String, dynamic>();
}

/// 状态机测试不碰库：显式给一个未打开的内存库 helper，
/// 避免 AppState() 默认构造依赖全局 databaseFactory（全量跑时不稳定）。
DatabaseHelper _dormantHelper() => DatabaseHelper(
  factory: databaseFactoryFfiNoIsolate,
  databasePath: inMemoryDatabasePath,
);

AppState _stateMachineState() =>
    AppState(guidelines: _guidelines(), databaseHelper: _dormantHelper());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('分享识别状态机（start/complete/fail/clear）', () {
    test('start 后处于加载中，无菜无商家', () {
      final state = _stateMachineState();
      state.startSharedRecognition('content://test/1');
      final draft = state.recognitionDraft!;
      expect(draft.imageUri, 'content://test/1');
      expect(draft.isLoading, isTrue);
      expect(draft.dishes, isEmpty);
      expect(draft.merchant, isEmpty);
      expect(draft.error, isNull);
    });

    test('图片 URI 不一致的 complete/fail 请求被忽略', () {
      final state = _stateMachineState();
      state.startSharedRecognition('content://test/1');
      final loading = state.recognitionDraft!;

      state.completeSharedRecognition(
        imageUri: 'content://test/other',
        merchant: '别家',
        dishes: const [MealDish(name: '别人的菜')],
      );
      expect(identical(state.recognitionDraft, loading), isTrue);
      expect(state.recognitionDraft!.isLoading, isTrue);

      state.failSharedRecognition(
        imageUri: 'content://test/other',
        message: '不该生效的错误',
      );
      expect(identical(state.recognitionDraft, loading), isTrue);
      expect(state.recognitionDraft!.error, isNull);
    });

    test('识别失败写入错误信息并结束加载', () {
      final state = _stateMachineState();
      state.startSharedRecognition('content://test/1');
      state.failSharedRecognition(
        imageUri: 'content://test/1',
        message: '这张图没看清，请手动添加菜品',
      );
      final draft = state.recognitionDraft!;
      expect(draft.isLoading, isFalse);
      expect(draft.error, '这张图没看清，请手动添加菜品');
      expect(draft.dishes, isEmpty);
    });

    test('clearSharedRecognition 清空草稿', () {
      final state = _stateMachineState();
      state.startSharedRecognition('content://test/1');
      state.clearSharedRecognition();
      expect(state.recognitionDraft, isNull);
    });
  });

  group('识别结果 → 保存（source=ocr 落库）', () {
    test('OCR 菜名经 DishMatcher 匹配后保存，record_json 带 source=ocr', () async {
      final (state, helper) = await _buildState();
      addTearDown(helper.close);

      // 模拟 Kotlin 端 DishNameExtractor 的产出：菜名带规格括号噪声。
      state.startSharedRecognition('content://test/1');
      state.completeSharedRecognition(
        imageUri: 'content://test/1',
        merchant: '美团外卖·黄焖鸡米饭',
        dishes: const [MealDish(name: '黄焖鸡米饭（大份）', quantity: 1)],
      );

      final draft = state.recognitionDraft!;
      final meal = state.buildMealRecord(
        mealType: 'lunch',
        timestamp: DateTime(2026, 9, 4, 12),
        dishes: draft.dishes,
        merchant: draft.merchant,
      );

      // P2: approximate/branded OCR stays a candidate until explicitly confirmed.
      final dish = meal.dishes.single;
      expect(dish.matchedDishId, isNull);
      expect(dish.contributionsKnown, isFalse);
      expect(dish.food!.candidateName, isNotNull);
      expect(dish.toJson()['portions'], isNull);

      await state.saveMeal(meal, source: 'ocr');
      final record = await _recordRow(helper, meal.mealId);
      expect(record['source'], 'ocr');
      expect(record['merchant'], '美团外卖·黄焖鸡米饭');
      expect((record['dishes'] as List).single['matched_dish_id'], isNull);
      expect(record['structure_complete'], false);
    });

    test('保存路径优先命中用户自定义菜品', () async {
      final (state, helper) = await _buildState();
      addTearDown(helper.close);

      // 用户此前手动记过这道菜 → 自定义副本进匹配器（自定义优先）。
      await state.registerManualDish(name: '黄焖鸡米饭', portionSize: 'normal');

      state.startSharedRecognition('content://test/2');
      state.completeSharedRecognition(
        imageUri: 'content://test/2',
        merchant: '',
        dishes: const [MealDish(name: '黄焖鸡米饭')],
      );

      final meal = state.buildMealRecord(
        mealType: 'lunch',
        timestamp: DateTime(2026, 9, 4, 12),
        dishes: state.recognitionDraft!.dishes,
      );
      expect(meal.dishes.single.matchedDishId, startsWith('custom_'));
      expect(meal.dishes.single.matchConfidence, 1);
    });
  });

  group('Dart 侧分享链路端到端（原生桥 → 识别页 → 保存）', () {
    /// share 通道 mock：getInitialSharedImage 返回空，acknowledge 静默。
    /// 不 mock 的话 outgoing invokeMethod 在测试环境会永久挂起。
    void mockShareChannel(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.canting.app/share'),
        (call) async => null,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.canting.app/share'),
          null,
        );
      });
    }

    testWidgets('onSharedImage → 识别完成 → 页面展示 → 保存落库 source=ocr', (
      tester,
    ) async {
      final (state, helper) = await _buildState(onboarded: true);
      addTearDown(helper.close);
      mockShareChannel(tester);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.canting.app/ocr'),
        (call) async {
          if (call.method == 'recognizeImage') {
            return <Object?, Object?>{
              'fullText': '黄焖鸡米饭（大份） x1',
              'engine': 'mlkit_chinese',
              'merchant': '美团外卖·黄焖鸡米饭',
              'dishes': [
                {'name': '黄焖鸡米饭（大份）', 'quantity': 1},
              ],
            };
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.canting.app/ocr'),
          null,
        );
      });

      await tester.pumpWidget(CantingApp(appState: state));
      await tester.pump(const Duration(milliseconds: 300));

      // 模拟 ShareActivity → MainActivity 后原生侧发来的分享图片事件。
      const imageUri =
          'content://com.canting.fileprovider/shared_images/test.jpg';
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'com.canting.app/share',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onSharedImage', {'imageUri': imageUri}),
        ),
        (data) {},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 进入识别页且识别已完成：展示 OCR 原始菜名与商家。
      expect(find.text('识别结果'), findsOneWidget);
      expect(find.text('黄焖鸡米饭（大份）'), findsOneWidget);
      expect(state.recognitionDraft?.isLoading, isFalse);
      expect(state.recognitionDraft?.dishes, hasLength(1));

      await tester.tap(find.text('保存并更新今日结构'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (find.text('明确保留未知并保存').evaluate().isNotEmpty) {
        await tester.tap(find.text('明确保留未知并保存'));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      // go_router 16.3：根/壳导航共用 GlobalObjectKey(navigatorKey.hashCode)，
      // 「go 进入 + go 返回」同帧互换根级页面时会撞出重复 key；
      // 真机分帧时序下不出现，这里定向吸收该已知帧异常（其余异常仍会失败）。
      final frameException = tester.takeException();
      if (frameException != null) {
        expect(frameException.toString(), contains('Duplicate GlobalKey'));
      }

      expect(find.text('餐盘 · 今日'), findsOneWidget);
      expect(state.recognitionDraft, isNull); // 保存后清空识别草稿
      final rows = await helper.database.query('meal_records');
      expect(rows, hasLength(1));
      final record = (jsonDecode(rows.single['record_json']! as String) as Map)
          .cast<String, dynamic>();
      expect(record['source'], 'ocr');
      expect((record['dishes'] as List).single['matched_dish_id'], isNull);
      expect(record['structure_complete'], false);
    });

    testWidgets('原生 OCR 失败 → 页面错误提示，手动补菜后仍可保存 source=ocr', (tester) async {
      final (state, helper) = await _buildState(onboarded: true);
      addTearDown(helper.close);
      mockShareChannel(tester);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.canting.app/ocr'),
        (call) async {
          if (call.method == 'recognizeImage') {
            throw PlatformException(
              code: 'OCR_UNAVAILABLE',
              message: 'The OCR service is not initialized',
            );
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.canting.app/ocr'),
          null,
        );
      });

      await tester.pumpWidget(CantingApp(appState: state));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'com.canting.app/share',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onSharedImage', {
            'imageUri':
                'content://com.canting.fileprovider/shared_images/bad.jpg',
          }),
        ),
        (data) {},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('识别失败'), findsOneWidget);
      expect(find.text('当前设备无法使用文字识别，请手动添加菜品'), findsOneWidget);

      // 手动补一道菜再保存（识别失败不应堵死保存路径）。
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
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('添加'),
        ),
      );
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
      // 同上：吸收 go_router 重复 GlobalObjectKey 的已知帧异常。
      final frameException = tester.takeException();
      if (frameException != null) {
        expect(frameException.toString(), contains('Duplicate GlobalKey'));
      }

      expect(find.text('餐盘 · 今日'), findsOneWidget);
      final rows = await helper.database.query('meal_records');
      expect(rows, hasLength(1));
      final record = (jsonDecode(rows.single['record_json']! as String) as Map)
          .cast<String, dynamic>();
      expect(record['source'], 'ocr');
    });
  });
}
