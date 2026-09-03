import 'dart:convert';
import 'dart:io';

import 'package:canting/core/models/dietary_guidelines.dart';
import 'package:test/test.dart';

void main() {
  late DietaryGuidelines guidelines;

  setUpAll(() {
    guidelines = DietaryGuidelines.fromJson(
      (jsonDecode(
            File('assets/data/dietary_guidelines.json').readAsStringSync(),
          )
          as Map)
          .cast<String, dynamic>(),
    );
  });

  group('DietaryGuidelines.fromJson', () {
    test('parses version, source, and the six food categories', () {
      expect(guidelines.version, '2022');
      expect(guidelines.source, contains('中国居民膳食指南'));
      expect(guidelines.foodCategories, hasLength(6));
      expect(guidelines.foodCategories.first.id, 'grain_tuber');
      expect(guidelines.foodCategories.first.name, '谷薯类');
      expect(guidelines.foodCategories.first.isCore, isTrue);
    });

    test('parses serving reference grams per category', () {
      expect(guidelines.gramsPerServingFor('grain_tuber'), 50);
      expect(guidelines.gramsPerServingFor('vegetable'), 80);
      expect(guidelines.gramsPerServingFor('fruit'), 100);
      expect(guidelines.gramsPerServingFor('protein_meat_egg'), 50);
      expect(guidelines.gramsPerServingFor('dairy'), 150);
      expect(guidelines.gramsPerServingFor('soy'), 15);
      // 油脂没有「份」定义。
      expect(guidelines.gramsPerServingFor('oil'), isNull);
    });

    test('parses daily intake ranges by energy level', () {
      final level2000 = guidelines.recommendationsByEnergyLevel['2000'];
      expect(level2000, isNotNull);
      expect(level2000!.energyLevelKcal, 2000);

      final grains = level2000.intakeRanges['grain_tuber']!;
      expect(grains.min, 250);
      expect(grains.max, 300);
      expect(grains.servings, 5);

      // 盐只有上限。
      final salt = level2000.intakeRanges['salt']!;
      expect(salt.min, isNull);
      expect(salt.max, 5);
      expect(salt.servings, isNull);
    });

    test('rejects malformed JSON', () {
      expect(
        () => DietaryGuidelines.fromJson(const {}),
        throwsFormatException,
      );
    });
  });

  group('food exchange lookup', () {
    test('finds exchangeable foods with their grams per serving', () {
      final rice = guidelines.findExchangeEntry('cooked_rice');
      expect(rice, isNotNull);
      expect(rice!.groupId, 'grain_tuber');
      expect(rice.gramsPerServing, 150);

      final yogurt = guidelines.findExchangeEntry('yogurt');
      expect(yogurt!.groupId, 'dairy_products');
      expect(yogurt.gramsPerServing, 100);

      final tofu = guidelines.findExchangeEntry('firm_tofu');
      expect(tofu!.groupId, 'soy_products');
      expect(tofu.gramsPerServing, 105);
    });

    test('finds base foods themselves as exchange entries', () {
      final milk = guidelines.findExchangeBase('milk_100ml');
      expect(milk, isNotNull);
      expect(milk!.gramsPerServing, 100);

      final rawRice = guidelines.findExchangeBase('rice_50g_raw');
      expect(rawRice!.gramsPerServing, 50);
    });

    test('returns null for unknown foods', () {
      expect(guidelines.findExchangeEntry('pizza'), isNull);
      expect(guidelines.findExchangeBase('pizza_100g'), isNull);
    });
  });
}
