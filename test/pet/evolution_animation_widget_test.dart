import 'package:canting/pet/widgets/evolution_animation_widget.dart';
import 'package:canting/pet/widgets/pet_sprite_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('EvolutionAnimationWidget', () {
    testWidgets('shows the old stage during the first half', (tester) async {
      await tester.pumpWidget(
        host(
          const EvolutionAnimationWidget(
            petType: 'cat',
            fromStage: 'egg',
            toStage: 'baby',
            petName: 'Mimi',
          ),
        ),
      );

      final sprite = tester.widget<PetSpriteWidget>(
        find.byType(PetSpriteWidget),
      );
      expect(sprite.growthStage, 'egg');
      expect(find.text('Mimi长大了！'), findsOne);
    });

    testWidgets('switches to the new stage during the second half', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const EvolutionAnimationWidget(
            petType: 'dog',
            fromStage: 'baby',
            toStage: 'adult',
            petName: 'Pup',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1100));

      final sprite = tester.widget<PetSpriteWidget>(
        find.byType(PetSpriteWidget),
      );
      expect(sprite.growthStage, 'adult');
    });

    testWidgets('finishes and removes itself after two seconds', (
      tester,
    ) async {
      var finishCount = 0;
      await tester.pumpWidget(
        host(
          EvolutionAnimationWidget(
            petType: 'hamster',
            fromStage: 'egg',
            toStage: 'baby',
            petName: 'Nibbles',
            onFinished: () => finishCount += 1,
          ),
        ),
      );
      await tester.pump(
        EvolutionAnimationWidget.duration + const Duration(milliseconds: 1),
      );

      expect(finishCount, 1);
      expect(find.text('Nibbles长大了！'), findsNothing);
      expect(
        find.byKey(const ValueKey('evolution-animation-finished')),
        findsOne,
      );
    });
  });
}
