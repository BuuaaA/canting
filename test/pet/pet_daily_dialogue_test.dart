import 'dart:io';
import 'dart:math';

import 'package:canting/pet/pet_daily_dialogue.dart';
import 'package:canting/pet/pet_dialogues.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PetDialogues fromAsset;

  setUpAll(() {
    fromAsset = PetDialogues.fromJsonString(
      File('assets/data/pet_dialogues.json').readAsStringSync(),
    );
  });

  group('daily 文案数据完整性', () {
    test('三种宠物 × 12 种场景，每种场景至少 3 条', () {
      for (final petType in const ['cat', 'dog', 'hamster']) {
        for (final scenario in DailyDialogScenario.values) {
          final key = switch (scenario) {
            DailyDialogScenario.fulfilled => 'fulfilled',
            DailyDialogScenario.gapVegetables => 'gap_vegetables',
            DailyDialogScenario.gapProtein => 'gap_protein',
            DailyDialogScenario.gapFruits => 'gap_fruits',
            DailyDialogScenario.gapGrains => 'gap_grains',
            DailyDialogScenario.gapOil => 'gap_oil',
            DailyDialogScenario.noRecord => 'no_record',
            DailyDialogScenario.morning => 'morning',
            DailyDialogScenario.midday => 'midday',
            DailyDialogScenario.afternoon => 'afternoon',
            DailyDialogScenario.evening => 'evening',
            DailyDialogScenario.night => 'night',
          };
          expect(
            fromAsset.dailyLines(petType, key),
            hasLength(greaterThanOrEqualTo(3)),
            reason: '$petType.$key 应至少有 3 条文案',
          );
        }
      }
    });

    test('随机取句一定落在文案池内，且池子轮换能覆盖多条', () {
      final dialogue = PetDailyDialogue(
        dialogues: fromAsset,
        random: Random(7),
      );
      final pool = fromAsset.dailyLines('cat', 'fulfilled');
      final picked = <String>{
        for (var i = 0; i < 40; i++) dialogue.lineFor('cat', DailyDialogScenario.fulfilled),
      };

      expect(picked.union(pool.toSet()), equals(pool.toSet()));
      expect(picked.length, greaterThanOrEqualTo(2));
    });
  });

  group('PetDailyDialogue.scenarioFor（场景选择优先级）', () {
    final balanced = <String, double>{
      'grains': 0.9,
      'vegetables': 0.9,
      'fruits': 0.9,
      'protein': 0.9,
      'protein_soy': 0.9,
      'oil': 0.9,
    };

    test('22 点以后优先说晚安', () {
      expect(
        PetDailyDialogue.scenarioFor(
          completionByCategory: balanced,
          mealCount: 3,
          hour: 23,
        ),
        DailyDialogScenario.night,
      );
    });

    test('没有记录时说想吃东西（但深夜仍是晚安）', () {
      expect(
        PetDailyDialogue.scenarioFor(
          completionByCategory: balanced,
          mealCount: 0,
          hour: 15,
        ),
        DailyDialogScenario.noRecord,
      );
      expect(
        PetDailyDialogue.scenarioFor(
          completionByCategory: const {},
          mealCount: 0,
          hour: 23,
        ),
        DailyDialogScenario.night,
      );
    });

    test('蔬菜缺口最大时提醒补蔬菜', () {
      expect(
        PetDailyDialogue.scenarioFor(
          completionByCategory: {
            'vegetables': 0.1,
            'protein': 0.9,
            'fruits': 0.8,
          },
          mealCount: 1,
          hour: 14,
        ),
        DailyDialogScenario.gapVegetables,
      );
    });

    test('油脂超标时提醒太油', () {
      expect(
        PetDailyDialogue.scenarioFor(
          completionByCategory: {'oil': 1.5, 'vegetables': 0.5},
          mealCount: 2,
          hour: 14,
        ),
        DailyDialogScenario.gapOil,
      );
    });

    test('全部分类 ≥70% 判定达标', () {
      expect(
        PetDailyDialogue.scenarioFor(
          completionByCategory: balanced,
          mealCount: 2,
          hour: 14,
        ),
        DailyDialogScenario.fulfilled,
      );
    });

    test('不算达标也无缺口时按时段走', () {
      final soSo = <String, double>{
        'grains': 0.5,
        'vegetables': 0.5,
        'protein': 0.5,
        'fruits': 0.5,
        'oil': 0.5,
      };
      expect(
        PetDailyDialogue.scenarioFor(
          completionByCategory: soSo,
          mealCount: 1,
          hour: 8,
        ),
        DailyDialogScenario.morning,
      );
      expect(
        PetDailyDialogue.scenarioFor(
          completionByCategory: soSo,
          mealCount: 1,
          hour: 12,
        ),
        DailyDialogScenario.midday,
      );
      expect(
        PetDailyDialogue.scenarioFor(
          completionByCategory: soSo,
          mealCount: 1,
          hour: 16,
        ),
        DailyDialogScenario.afternoon,
      );
      expect(
        PetDailyDialogue.scenarioFor(
          completionByCategory: soSo,
          mealCount: 1,
          hour: 20,
        ),
        DailyDialogScenario.evening,
      );
    });
  });

  group('pickDaily 一站式出口', () {
    test('给定场景返回对应池内文案', () {
      final dialogue = PetDailyDialogue(dialogues: fromAsset, random: Random(3));
      final text = dialogue.pickDaily(
        petType: 'dog',
        completionByCategory: {'vegetables': 0.1},
        mealCount: 1,
        hour: 15,
      );
      final pool = fromAsset.dailyLines('dog', 'gap_vegetables');
      expect(pool, contains(text));
    });
  });

  test('默认对话数据与资产 JSON 的 daily 区块保持一致', () {
    final defaults = PetDialogues.defaults().toJsonSafe();
    final asset = fromAsset.toJsonSafe();
    expect(defaults['cat']['daily'], asset['cat']['daily']);
    expect(defaults['dog']['daily'], asset['dog']['daily']);
    expect(defaults['hamster']['daily'], asset['hamster']['daily']);
  });
}
