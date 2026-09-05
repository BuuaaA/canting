import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/platform/android_native_bridge.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DateBridge extends AndroidNativeBridge {
  final values = <Map<String, Object?>>[];
  @override
  Future<bool> savePetStatus(Map<String, Object?> status) async {
    values.add(Map.of(status));
    return true;
  }

  @override
  Future<String?> saveMealRecord(Map<String, Object?> mealRecord) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('save edit delete resume and reopen publish current local business date', () async {
    sqfliteFfiInit();
    final temp = Directory.systemTemp.createTempSync('canting-p6a-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final helper = DatabaseHelper(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: '${temp.path}/test.db',
    );
    final seed = FoodDatabase.fromJson(
      dishesJson: File('assets/data/dishes.json').readAsStringSync(),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
    await helper.initialize(seedData: seed);
    var now = DateTime(2026, 9, 5, 23, 59);
    final bridge = DateBridge();
    var state = AppState(
      databaseHelper: helper,
      androidNativeBridge: bridge,
      clock: () => now,
    );
    Future<Map<String, Object?>> payload() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final value = bridge.values.last;
      expect(
        value['record_date'],
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      );
      expect(value['record_utc_offset_minutes'], now.timeZoneOffset.inMinutes);
      return value;
    }

    try {
      await state.loadFromDatabase();
      expect((await payload())['today_meal_count'], 0);
      final meal = MealRecord(
        mealId: 'p6a-date',
        mealType: 'lunch',
        timestamp: now,
        dishes: const [MealDish(name: '合成未知商品', contributionsKnown: false)],
      );
      await state.saveMeal(meal);
      expect((await payload())['today_completion_rate'], isNull);
      expect((await payload())['today_meal_count'], 1);
      now = DateTime(2026, 9, 6, 0, 1);
      await state.resumeRecords();
      expect((await payload())['today_meal_count'], 0);
      // Re-saving an existing meal uses the production edit path, without duplicating it.
      await state.saveMeal(
        MealRecord(
          mealId: meal.mealId,
          mealType: meal.mealType,
          timestamp: now,
          dishes: meal.dishes,
        ),
      );
      expect((await payload())['today_meal_count'], 1);
      state.dispose();
      await helper.close();
      await helper.initialize(seedData: seed);
      state = AppState(
        databaseHelper: helper,
        androidNativeBridge: bridge,
        clock: () => now,
      );
      await state.loadFromDatabase();
      expect((await payload())['today_meal_count'], 1);
      await state.deleteMeal('p6a-date');
      expect((await payload())['today_meal_count'], 0);
      now = DateTime(2026, 9, 4);
      await state.resumeRecords();
      expect((await payload())['today_meal_count'], 0);
    } finally {
      state.dispose();
      await helper.close();
    }
  });
}
