import 'dart:convert';
import 'dart:io';

import 'package:canting/core/models/meal_draft_v2.dart';
import 'package:canting/core_engine.dart';
import 'package:canting/services/recognition_contract.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/intake/today_plate_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(AppState, DatabaseHelper, DietaryGuidelines, ServingEstimator)>
_realState() async {
  sqfliteFfiInit();
  final helper = DatabaseHelper(
    factory: databaseFactoryFfiNoIsolate,
    databasePath: inMemoryDatabasePath,
  );
  await helper.initialize();
  final guidelines = DietaryGuidelines.fromJson(
    jsonDecode(File('assets/data/dietary_guidelines.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final state = AppState(
    databaseHelper: helper,
    guidelines: guidelines,
    clock: () => DateTime(2026, 9, 12, 12),
  );
  await state.loadFromDatabase();
  final estimator = ServingEstimator(
    DishMatcher(FoodDatabase(dishes: [], categories: [])),
    guidelines,
  );
  return (state, helper, guidelines, estimator);
}

MealRecord _riceMeal(ServingEstimator estimator, DietaryGuidelines guidelines) {
  final schema = jsonDecode(
    File('dev-docs/recognition-v2/recognition.schema.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final example =
      jsonDecode(
            File('dev-docs/recognition-v2/examples.json').readAsStringSync(),
          )['personal_half_bowl']
          as Map<String, dynamic>;
  final component =
      example['products'][0]['components'][0] as Map<String, dynamic>;
  component['name']['value'] = '米饭';
  final draft =
      MealDraftV2(RecognitionContract(schema), example, simulated: true)
        ..setIntake(
          'c-rice',
          basis: 'personal_consumed',
          portion: {'value': 150, 'unit': 'g', 'band': 'unknown'},
        );
  return draft.toMeal(
    mealType: 'lunch',
    timestamp: DateTime(2026, 9, 12, 12),
    estimator: estimator,
    policyVersion: guidelines.version,
    knowledgeVersion: 'test-existing-exchange',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real AppState save/delete refreshes mounted today page', (
    tester,
  ) async {
    final (state, helper, guidelines, estimator) = await _realState();
    addTearDown(() async {
      state.dispose();
      await helper.close();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: TodayPlateView())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await state.saveMeal(_riceMeal(estimator, guidelines));
    await tester.pumpAndSettle();
    expect(find.text('已记录150g；50g'), findsOneWidget);
    await state.deleteMeal('00000000-0000-4000-8000-000000000001');
    await tester.pumpAndSettle();
    expect(find.text('未记录'), findsWidgets);
  });
  test('view event is persisted as a bounded local entry', () async {
    SharedPreferences.setMockInitialValues({});
    final (state, helper, _, _) = await _realState();
    state.recordIntakeViewEvent('today_plate_view');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final stored =
        (await SharedPreferences.getInstance()).getStringList(
          'intake_view_events',
        ) ??
        const [];
    expect(stored, hasLength(1));
    expect(stored.single, contains('today_plate_view'));
    state.dispose();
    await helper.close();
  });
}
