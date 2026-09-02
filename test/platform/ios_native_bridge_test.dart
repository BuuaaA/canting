import 'package:canting/native/ios_native_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(IOSNativeBridge.shareChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(IOSNativeBridge.petChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(IOSNativeBridge.visionChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(IOSNativeBridge.notificationChannel, null);
  });

  test('parses and acknowledges a pending meal from the App Group', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(IOSNativeBridge.shareChannel, (call) async {
          calls.add(call);
          if (call.method == 'getPendingSharedMeal') {
            return {
              'meal_id': 'meal-1',
              'merchant': '邻里小馆',
              'meal_type': 'lunch',
              'timestamp': '2026-09-03T12:30:00+08:00',
              'image_uri': 'file:///shared/shared_meal_meal-1.image',
              'dishes': [
                {
                  'name': '黄焖鸡米饭',
                  'quantity': 2,
                  'portion_size': 'large',
                  'matched_dish_id': 'hsm_rice',
                  'match_confidence': 0.95,
                },
              ],
            };
          }
          if (call.method == 'acknowledgeSharedMeal') return true;
          return null;
        });

    final meal = await IOSNativeBridge.instance.getPendingSharedMeal();
    expect(meal?.mealId, 'meal-1');
    expect(meal?.merchant, '邻里小馆');
    expect(meal?.imageUri, 'file:///shared/shared_meal_meal-1.image');
    expect(meal?.dishes.single.name, '黄焖鸡米饭');
    expect(meal?.dishes.single.quantity, 2);
    expect(meal?.dishes.single.portionSize, 'large');

    expect(
      await IOSNativeBridge.instance.acknowledgeSharedMeal('meal-1'),
      isTrue,
    );
    expect(calls.last.arguments, {'meal_id': 'meal-1'});
  });

  test('reports whether the share extension is bundled', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          IOSNativeBridge.petChannel,
          (call) async => call.method == 'getShareExtensionStatus',
        );

    expect(await IOSNativeBridge.instance.getShareExtensionStatus(), isTrue);
  });

  test(
    'sends encoded image bytes to Vision and parses recognized lines',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(IOSNativeBridge.visionChannel, (
            call,
          ) async {
            expect(call.method, 'recognizeText');
            final arguments = (call.arguments as Map).cast<String, Object?>();
            expect(arguments['image_data'], isA<Uint8List>());
            return {
              'lines': ['邻里小馆', '黄焖鸡米饭 x2'],
              'text': '邻里小馆\n黄焖鸡米饭 x2',
            };
          });

      final result = await IOSNativeBridge.instance.recognizeText(
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
      );

      expect(result.lines, ['邻里小馆', '黄焖鸡米饭 x2']);
      expect(result.text, contains('黄焖鸡米饭'));
    },
  );

  test('rejects an empty image before invoking Vision', () {
    expect(
      () => IOSNativeBridge.instance.recognizeText(Uint8List(0)),
      throwsArgumentError,
    );
  });

  test('writes pet JSON through the native bridge for WidgetKit', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(IOSNativeBridge.petChannel, (call) async {
          received = call;
          return true;
        });

    final saved = await IOSNativeBridge.instance.savePetStatus({
      'pet_type': 'cat',
      'pet_name': '小挑食',
      'growth_stage': 'baby',
      'vitality': 75,
      'vitality_state': 'good',
      'today_meal_count': 2,
      'today_completion_rate': 0.65,
      'next_meal_summary': '18:30 补蔬菜',
      'pet_sprite_name': 'pet_cat_baby_good_0',
    });

    expect(saved, isTrue);
    expect(received?.method, 'savePetStatus');
    expect((received?.arguments as Map)['vitality'], 75);
  });

  test('requests permission and sends a deep-linked notification', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(IOSNativeBridge.notificationChannel, (
          call,
        ) async {
          calls.add(call);
          return true;
        });

    expect(
      await IOSNativeBridge.instance.requestNotificationPermission(),
      isTrue,
    );
    expect(
      await IOSNativeBridge.instance.sendNotification(
        title: '已记录午餐',
        body: '打开餐盘查看',
        deepLink: 'canting:///home',
      ),
      isTrue,
    );
    expect(calls.map((call) => call.method), [
      'requestNotificationPermission',
      'sendNotification',
    ]);
    expect((calls.last.arguments as Map)['deep_link'], 'canting:///home');
  });
}
