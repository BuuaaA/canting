import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/platform/android_native_bridge.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class CapturingBridge extends AndroidNativeBridge {
  final saved = Completer<Map<String, Object?>>();
  @override
  Future<bool> savePetStatus(Map<String, Object?> status) async {
    if (status['today_meal_count'] == 1 && !saved.isCompleted) {
      saved.complete(jsonDecode(jsonEncode(status)) as Map<String, Object?>);
    }
    return true;
  }

  @override
  Future<String?> saveMealRecord(Map<String, Object?> mealRecord) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unknown meal stays unknown in Android widget payload after save and database reopen', () async {
    sqfliteFfiInit();
    final temp = Directory.systemTemp.createTempSync('canting-p5-widget-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final seed = FoodDatabase.fromJson(
      dishesJson: File('assets/data/dishes.json').readAsStringSync(),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
    for (final firstRun in [true, false]) {
      final helper = DatabaseHelper(
        factory: databaseFactoryFfiNoIsolate,
        databasePath: '${temp.path}/test.db',
      );
      await helper.initialize(seedData: seed);
      final bridge = CapturingBridge();
      final state = AppState(
        databaseHelper: helper,
        androidNativeBridge: bridge,
      );
      try {
        await state.loadFromDatabase();
        if (firstRun) {
          await state.saveMeal(
            MealRecord(
              mealId: 'p5-unknown',
              mealType: 'lunch',
              timestamp: DateTime.now(),
              dishes: const [
                MealDish(name: '合成未知商品', contributionsKnown: false),
              ],
            ),
          );
        }
        final payload = await bridge.saved.future.timeout(
          const Duration(seconds: 5),
        );
        expect(payload['today_meal_count'], 1);
        expect(payload['structure_complete'], false);
        expect(payload['today_completion_rate'], isNull);
        expect(payload['next_meal_summary'], contains('记录不足'));
        expect(await helper.database.query('meal_records'), hasLength(1));
      } finally {
        state.dispose();
        await helper.close();
      }
    }
  });
}
