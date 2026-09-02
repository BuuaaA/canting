import 'package:canting/pet/widgets/pet_sprite_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(PetSpriteWidget sprite) {
    return MaterialApp(
      home: Scaffold(body: Center(child: sprite)),
    );
  }

  group('PetSpriteWidget', () {
    test('builds the documented asset path and frame counts', () {
      expect(PetSpriteWidget.frameCountFor('egg'), 2);
      expect(PetSpriteWidget.frameCountFor('baby'), 4);
      expect(PetSpriteWidget.frameCountFor('adult'), 5);
      expect(
        PetSpriteWidget.assetPath(
          petType: 'cat',
          growthStage: 'baby',
          vitalityState: 'energetic',
          frame: 1,
        ),
        'assets/sprites/pet_cat_baby_energetic_1.png',
      );
    });

    testWidgets('uses a fixed-size color placeholder for missing sprites', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const PetSpriteWidget(
            petType: 'dog',
            growthStage: 'baby',
            vitalityState: 'good',
            size: 96,
            animate: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('pet-sprite-placeholder')), findsOne);
      expect(
        tester.getSize(find.byKey(const ValueKey('pet-sprite-frame-0'))),
        const Size.square(96),
      );
      expect(find.bySemanticsLabel('dog good'), findsOneWidget);
    });

    testWidgets('advances one frame every 200 milliseconds', (tester) async {
      await tester.pumpWidget(
        host(
          const PetSpriteWidget(
            petType: 'cat',
            growthStage: 'adult',
            vitalityState: 'energetic',
          ),
        ),
      );

      expect(find.byKey(const ValueKey('pet-sprite-frame-0')), findsOne);
      await tester.pump(const Duration(milliseconds: 210));
      expect(find.byKey(const ValueKey('pet-sprite-frame-1')), findsOne);
      expect(find.byKey(const ValueKey('pet-sprite-placeholder')), findsOne);
    });

    testWidgets('keeps frame zero when animation is disabled', (tester) async {
      await tester.pumpWidget(
        host(
          const PetSpriteWidget(
            petType: 'hamster',
            growthStage: 'egg',
            vitalityState: 'expecting',
            animate: false,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byKey(const ValueKey('pet-sprite-frame-0')), findsOne);
      expect(find.bySemanticsLabel('hamster expecting'), findsOneWidget);
    });
  });
}
