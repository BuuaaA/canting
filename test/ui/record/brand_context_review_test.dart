import 'dart:convert';

import 'package:canting/core_engine.dart';
import 'package:canting/core/models/local_food.dart';
import 'package:canting/data/local_food_repository.dart';
import 'package:canting/data/meal_repository.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/record/record_detail_page.dart';
import 'package:canting/ui/record/dish_edit_list.dart';
import 'package:canting/ui/record/food_confirmation_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Finder get merchant => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == '商家名称',
);
Finder get classify => find
    .descendant(of: find.byType(DishEditList), matching: find.byType(ListTile))
    .first;
Future<void> openSheet(WidgetTester t) async {
  await t.tap(classify);
  await t.pumpAndSettle();
}

Future<void> confirm(WidgetTester t) async {
  await t.ensureVisible(find.text('确认本次商品'));
  await t.tap(find.text('确认本次商品'));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in [
    'no-memory',
    'other-category',
    'clear',
    'explicit-brand',
    'preserve-unresolved',
    'edited-spec',
  ]) {
    testWidgets('R1 real record page: $scenario', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      sqfliteFfiInit();
      final db = DatabaseHelper(
        factory: databaseFactoryFfiNoIsolate,
        databasePath: inMemoryDatabasePath,
      );
      await db.initialize();
      addTearDown(db.close);
      Future<void> memory(String brand, String category) =>
          LocalFoodRepository.remember(
            db.database,
            FoodObservation(
              facts: FoodFacts(brand: brand, name: '青青糯山', category: category),
              spec: const OrderSpec(sugar: 'regular', cup: 'large'),
              confirmed: true,
            ),
          );
      await memory('品牌甲', 'milk_tea');
      if (scenario == 'other-category') await memory('品牌乙', 'coffee');
      final state = AppState(databaseHelper: db);
      await state.loadFromDatabase();
      final repo = MealRepository(database: () => db.database);
      await repo.addMeal(
        MealRecord(
          mealId: 'history',
          mealType: 'lunch',
          timestamp: DateTime(2020),
          dishes: const [MealDish(name: '旧记录')],
        ),
      );
      final history = jsonEncode(
        (await db.database.query('meal_records')).single,
      );
      state.startSharedRecognition('synthetic');
      state.completeSharedRecognition(
        imageUri: 'synthetic',
        merchant: '品牌甲',
        dishes: [
          MealDish(
            name: scenario == 'edited-spec' ? '青青糯山' : '青青糯山 无糖 小杯',
            quantity: 2,
          ),
        ],
      );
      final router = GoRouter(
        initialLocation: '/record',
        routes: [
          GoRoute(
            path: '/record',
            builder: (c, s) =>
                const RecordDetailPage(isSharedRecognition: true),
          ),
          GoRoute(
            path: '/home',
            builder: (c, s) => const Scaffold(body: Text('saved')),
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
      if (scenario == 'explicit-brand' || scenario == 'edited-spec') {
        await openSheet(t);
        if (scenario == 'explicit-brand') {
          await t.enterText(field('品牌（不确定可留空）'), '单品品牌');
        } else {
          await t.tap(find.byKey(const ValueKey('本次糖型-unknown')));
          await t.pumpAndSettle();
          await t.tap(find.text('低糖').last);
          await t.pumpAndSettle();
        }
        await confirm(t);
      }
      final corrected = scenario == 'clear' ? '' : '品牌乙';
      await t.enterText(merchant, corrected);
      await t.pumpAndSettle();
      await openSheet(t);
      final brand = t.widget<TextField>(field('品牌（不确定可留空）')).controller!.text;
      final observation = t
          .widget<FoodConfirmationSheet>(find.byType(FoodConfirmationSheet))
          .initial;
      expect(brand, scenario == 'explicit-brand' ? '单品品牌' : corrected);
      expect(
        observation.facts.category,
        scenario == 'explicit-brand'
            ? 'milk_tea'
            : scenario == 'other-category'
            ? 'coffee'
            : 'unknown',
      );
      expect(
        observation.spec.sugar,
        scenario == 'edited-spec' ? 'low' : 'none',
      );
      expect(
        observation.spec.cup,
        scenario == 'edited-spec' ? 'unknown' : 'small',
      );
      // This is production page interaction in a widget test, not device evidence.
      // ignore: avoid_print
      print(
        'R1 widget evidence $scenario merchant=$corrected brand=$brand category=${observation.facts.category} spec=${observation.spec.toJson()}',
      );
      if (scenario == 'preserve-unresolved') {
        Navigator.pop(t.element(find.byType(FoodConfirmationSheet)));
        await t.pumpAndSettle();
      } else {
        await confirm(t);
      }
      await t.tap(find.text('保存并更新今日结构'));
      await t.pumpAndSettle();
      if (scenario == 'preserve-unresolved') {
        expect(find.text('明确保留未知并保存'), findsOneWidget);
        await t.tap(find.text('明确保留未知并保存'));
        await t.pumpAndSettle();
      }
      final meals = await repo.getMealsByDate(DateTime.now());
      expect(meals, hasLength(1));
      final dish = meals.single.dishes.single;
      expect(dish.name, scenario == 'edited-spec' ? '青青糯山' : '青青糯山 无糖 小杯');
      expect(dish.quantity, 2);
      expect(dish.food!.facts.brand, brand);
      expect(dish.food!.spec.sugar, observation.spec.sugar);
      expect(dish.food!.spec.cup, observation.spec.cup);
      final profiles = await LocalFoodRepository(() => db.database).all();
      expect(profiles.where((p) => p.facts.brand == '品牌甲').single.useCount, 1);
      if (scenario == 'other-category' || scenario == 'explicit-brand') {
        expect(profiles.any((p) => p.facts.key == dish.food!.facts.key), true);
      } else {
        expect(profiles.any((p) => p.facts.brand == corrected), false);
      }
      expect(
        jsonEncode(
          (await db.database.query(
            'meal_records',
            where: 'id = ?',
            whereArgs: ['history'],
          )).single,
        ),
        history,
      );
      await t.pumpWidget(const SizedBox());
      router.dispose();
      state.dispose();
      await db.close();
    });
  }
}
