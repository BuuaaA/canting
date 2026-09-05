import 'dart:async';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/platform/android_native_bridge.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class QueryFailureBridge extends AndroidNativeBridge {
  final snapshots = StreamController<Map<String, Object?>>.broadcast();

  @override
  Future<bool> savePetStatus(Map<String, Object?> status) async {
    snapshots.add(Map.of(status));
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'uninitialized and failed queries invalidate date until recovery',
    () async {
      sqfliteFfiInit();
      final temp = Directory.systemTemp.createTempSync(
        'canting-query-failure-',
      );
      final helper = DatabaseHelper(
        factory: databaseFactoryFfiNoIsolate,
        databasePath: '${temp.path}/test.db',
      );
      final bridge = QueryFailureBridge();
      final initialSnapshot = bridge.snapshots.stream.first;
      final now = DateTime(2026, 9, 6, 12);
      final state = AppState(
        databaseHelper: helper,
        androidNativeBridge: bridge,
        clock: () => now,
      );
      try {
        expect(helper.isOpen, isFalse);
        expect((await initialSnapshot)['record_date'], isNull);
        final seed = FoodDatabase.fromJson(
          dishesJson: File('assets/data/dishes.json').readAsStringSync(),
          categoriesJson: File('assets/data/categories.json')
              .readAsStringSync(),
        );
        await helper.initialize(seedData: seed);
        var snapshot = bridge.snapshots.stream.first;
        await state.loadFromDatabase();
        expect((await snapshot)['record_date'], '2026-09-06');

        // Real SQLite query failure, isolated to this temporary database.
        await helper.database.execute(
          'ALTER TABLE meal_records RENAME TO injected_unavailable_records',
        );
        await expectLater(
          helper.database.query('meal_records'),
          throwsA(isA<DatabaseException>()),
        );
        snapshot = bridge.snapshots.stream.first;
        await state.resumeRecords();
        expect(state.windowFor(now, 7)!.dataStatus, 'error');
        expect(state.windowFor(now, 28)!.dataStatus, 'error');
        expect((await snapshot)['record_date'], isNull);

        await helper.database.execute(
          'ALTER TABLE injected_unavailable_records RENAME TO meal_records',
        );
        snapshot = bridge.snapshots.stream.first;
        await state.resumeRecords();
        expect(state.windowFor(now, 7)!.dataStatus, isNot('error'));
        final recovered = await snapshot;
        expect(recovered['record_date'], '2026-09-06');
        expect(
          recovered['record_utc_offset_minutes'],
          now.timeZoneOffset.inMinutes,
        );
        expect(recovered['today_meal_count'], 0);
      } finally {
        state.dispose();
        await helper.close();
        await bridge.snapshots.close();
        temp.deleteSync(recursive: true);
      }
    },
  );
}
