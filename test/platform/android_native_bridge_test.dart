import 'dart:convert';

import 'package:canting/platform/android_native_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const petChannel = MethodChannel('com.canting.app/pet_test');
  late MethodCall? receivedCall;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    receivedCall = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(petChannel, (call) async {
          receivedCall = call;
          return switch (call.method) {
            'savePetStatus' => true,
            'saveMealRecord' => '/shared/meals/meal-1.json',
            'getShareExtensionStatus' => {'available': true},
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(petChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('parses structured OCR output from the Android channel', () {
    final result = NativeOcrResult.fromMap({
      'fullText': '邻里小馆\n黄焖鸡米饭 x2',
      'engine': 'mlkit_chinese',
      'merchant': '邻里小馆',
      'dishes': [
        {'name': '黄焖鸡米饭', 'quantity': 2},
      ],
    });

    expect(result.engine, 'mlkit_chinese');
    expect(result.merchant, '邻里小馆');
    expect(result.dishes.single.name, '黄焖鸡米饭');
    expect(result.dishes.single.quantity, 2);
  });

  test('drops malformed and empty dish results', () {
    final result = NativeOcrResult.fromMap({
      'dishes': [
        {'name': '', 'quantity': 1},
        'not-a-map',
      ],
    });

    expect(result.dishes, isEmpty);
  });

  test('sends pet status as JSON to the Android pet channel', () async {
    final bridge = AndroidNativeBridge(petChannel: petChannel);

    final saved = await bridge.savePetStatus({
      'pet_type': 'cat',
      'vitality': 75,
      'next_meal_summary': '18:30 补蔬菜',
    });

    expect(saved, isTrue);
    expect(receivedCall?.method, 'savePetStatus');
    final arguments = (receivedCall?.arguments as Map).cast<String, Object?>();
    final json =
        jsonDecode(arguments['json']! as String) as Map<String, Object?>;
    expect(json['pet_type'], 'cat');
    expect(json['vitality'], 75);
  });

  test('sends the shared meal JSON schema to Android storage', () async {
    final bridge = AndroidNativeBridge(petChannel: petChannel);

    final path = await bridge.saveMealRecord({
      'meal_id': 'meal-1',
      'meal_type': 'lunch',
      'timestamp': '2026-09-03T12:30:00',
      'dishes': [
        {'name': '黄焖鸡米饭', 'quantity': 1},
      ],
      'completion_rate': 0.65,
      'sodium_level': 'high',
    });

    expect(path, '/shared/meals/meal-1.json');
    expect(receivedCall?.method, 'saveMealRecord');
    final arguments = (receivedCall?.arguments as Map).cast<String, Object?>();
    final json =
        jsonDecode(arguments['json']! as String) as Map<String, Object?>;
    expect(json['meal_id'], 'meal-1');
    expect((json['dishes'] as List).single, containsPair('quantity', 1));
  });

  test('reports the Android image share receiver status', () async {
    final bridge = AndroidNativeBridge(petChannel: petChannel);

    expect(await bridge.getShareExtensionStatus(), isTrue);
    expect(receivedCall?.method, 'getShareExtensionStatus');
  });
}
