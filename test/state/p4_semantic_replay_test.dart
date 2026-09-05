import '../support/evidence.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:canting/core_engine.dart';
import 'package:canting/core/models/local_food.dart';
import 'package:canting/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'write paired production semantic decisions for frozen text replays',
    () async {
      sqfliteFfiInit();
      final helper = DatabaseHelper(
        factory: databaseFactoryFfiNoIsolate,
        databasePath: inMemoryDatabasePath,
      );
      await helper.initialize(
        seedData: FoodDatabase.fromJson(
          dishesJson: File('assets/data/dishes.json').readAsStringSync(),
          categoriesJson: File('assets/data/categories.json')
              .readAsStringSync(),
        ),
      );
      final state = AppState(
        databaseHelper: helper,
        guidelines: DietaryGuidelines.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(
              File('assets/data/dietary_guidelines.json').readAsStringSync(),
            ) as Map,
          ),
        ),
      );
      await state.loadFromDatabase();
      final rows = <Map<String, Object?>>[];
      for (final phase in ['baseline-parser', 'parser-actual']) {
        for (final line in File(
          'dev-docs/p4-evidence/repair-20260905/$phase.tsv',
        ).readAsLinesSync()) {
          final parts = line.split('\t');
          final dishes = <MealDish>[];
          if (parts[2].isNotEmpty) {
            for (final encoded in parts[2].split('|')) {
              final fields = encoded.split(':');
              final name = utf8.decode(base64.decode(fields[0]));
              final uncertain = fields.length > 2 && fields[2] == 'true';
              dishes.add(
                MealDish(
                  name: name,
                  quantity: double.parse(fields[1]),
                  contributionsKnown: !uncertain,
                  food: uncertain
                      ? FoodObservation(
                          facts: FoodFacts(name: name),
                          rawName: name,
                          spec: OrderSpec.parse(name),
                          matchedBy: 'parser_uncertain',
                        )
                      : null,
                ),
              );
            }
          }
          state.startSharedRecognition('text');
          state.completeSharedRecognition(
            imageUri: 'text',
            merchant: '',
            dishes: dishes,
          );
          rows.add({
            'case_id': parts[0],
            'repeat': int.parse(parts[1]),
            'parser_phase': phase,
            'actual': state.recognitionDraft!.dishes
                .map((d) => d.toJson())
                .toList(),
          });
        }
      }
      File(evidencePath('semantic-actual.json'))
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
      expect(rows.length, 40);
      state.dispose();
      await helper.close();
    },
  );
}
