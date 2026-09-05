import 'package:canting/core/models/local_food.dart';
import 'package:canting/ui/record/food_confirmation_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'unknown can be classified without nutrition; explicit sugar survives suggestion',
    (tester) async {
      FoodObservation? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await showFoodConfirmation(
                    context,
                    const FoodObservation(
                      facts: FoodFacts(name: '青青糯山'),
                      spec: OrderSpec(sugar: 'none', cup: 'small'),
                      suggestion: OrderSpec(sugar: 'regular', cup: 'large'),
                    ),
                    rawName: '青青糯山 无糖 小杯',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('商品类别-unknown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('奶茶').last);
      await tester.pumpAndSettle();
      expect(find.text('本次规格与上次不同，采用本次输入。'), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认本次商品'));
      await tester.pumpAndSettle();
      expect(result!.facts.category, 'milk_tea');
      expect(result!.spec.sugar, 'none');
      expect(result!.spec.cup, 'small');
      expect(result!.toJson()['contributions'], isNull);
      expect(result!.confirmed, true);
    },
  );
  testWidgets(
    'cake dimension shows actual consumption prompt and permits unknown',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FoodConfirmationSheet(
              initial: FoodObservation(
                facts: FoodFacts(name: '奶油蛋糕30寸', category: 'dessert'),
              ),
              rawName: '奶油蛋糕30寸',
            ),
          ),
        ),
      );
      expect(find.textContaining('蛋糕尺寸是整只商品大小'), findsOneWidget);
      expect(find.text('实际食用份量'), findsOneWidget);
      expect(find.text('未知 / 待确认'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
