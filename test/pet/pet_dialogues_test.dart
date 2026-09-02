import 'dart:io';

import 'package:canting/pet/pet_data.dart';
import 'package:canting/pet/pet_dialogues.dart';
import 'package:test/test.dart';

void main() {
  final defaults = PetDialogues.defaults();

  group('PetDialogues', () {
    test('loads the asset JSON and contains all three pet types', () {
      final source = File('assets/data/pet_dialogues.json').readAsStringSync();
      final fromAsset = PetDialogues.fromJsonString(source);

      for (final petType in PetData.supportedPetTypes) {
        expect(
          fromAsset.statusDialogue(petType, VitalityState.good),
          defaults.statusDialogue(petType, VitalityState.good),
        );
      }
    });

    test('maps meal completion boundaries to five reactions', () {
      expect(defaults.mealReactionDialogue('cat', 0.8), '好均衡！哼，还行');
      expect(defaults.mealReactionDialogue('cat', 0.6), '嗯，吃得不错嘛～');
      expect(defaults.mealReactionDialogue('cat', 0.4), '吃饱了～');
      expect(defaults.mealReactionDialogue('cat', 0.2), '好像缺点什么…');
      expect(defaults.mealReactionDialogue('cat', 0.19), '下次吃点菜好吗？');
    });

    test('uses different wording for cat, dog, and hamster', () {
      final lines = PetData.supportedPetTypes
          .map(
            (petType) =>
                defaults.statusDialogue(petType, VitalityState.energetic),
          )
          .toSet();

      expect(lines, hasLength(3));
    });

    test('returns only the largest category gap', () {
      final text = defaults.gapDialogue('dog', {
        'grains': 1.3,
        'vegetables': 0.35,
        'protein': 0.05,
        'fruits': 0.5,
        'oil': 0.9,
      });

      expect(text, '还想吃点肉肉！');
    });

    test(
      'returns the balanced line when every supplied category is at 70%',
      () {
        final text = defaults.gapDialogue('hamster', {
          'grains': 0.8,
          'vegetables': 0.7,
          'protein': 0.9,
          'fruits': 0.75,
          'oil': 0.8,
        });

        expect(text, '今天好满足呀～');
      },
    );

    test('keeps every dialogue within 15 Unicode characters', () {
      expect(
        defaults.allTexts,
        everyElement(
          predicate<String>(
            (text) => text.runes.length <= 15,
            'contains at most 15 Unicode characters',
          ),
        ),
      );
    });
  });
}
