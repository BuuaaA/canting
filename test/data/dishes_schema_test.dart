import 'dart:convert';
import 'dart:io';

import 'package:canting/core/models/food_data.dart';
import 'package:canting/data/food_database.dart';
import 'package:test/test.dart';

/// 菜库蒸馏 schema 验收测试（契约字段，会话 B 依赖）。
void main() {
  late Map<String, dynamic> root;
  late List<Map<String, dynamic>> dishes;
  late Map<String, Map<String, dynamic>> byId;
  late Set<String> categoryIds;

  setUpAll(() {
    root =
        jsonDecode(File('assets/data/dishes.json').readAsStringSync())
            as Map<String, dynamic>;
    dishes = (root['dishes'] as List).cast<Map<String, dynamic>>();
    byId = {for (final d in dishes) d['dish_id'] as String: d};
    categoryIds = (jsonDecode(
              File('assets/data/categories.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>()
        .map((c) => c['category_id'] as String)
        .toSet();
  });

  test('顶层为 {schema_version: 2, dishes: [...]} 信封', () {
    expect(root['schema_version'], 2);
    expect(dishes, hasLength(greaterThanOrEqualTo(1000)));
  });

  test('FoodDatabase.fromJson 解析对象根并携带 schemaVersion=2', () {
    final db = FoodDatabase.fromJson(
      dishesJson: File('assets/data/dishes.json').readAsStringSync(),
      categoriesJson: File('assets/data/categories.json').readAsStringSync(),
    );
    expect(db.schemaVersion, 2);
    expect(db.dishes, hasLength(1004));
  });

  test('所有菜必有 dish_id/dish_name/recommendable/quality_tags/portions_normal', () {
    for (final dish in dishes) {
      expect(dish['dish_id'], isA<String>(),
          reason: 'dish 缺 dish_id: $dish');
      expect(dish['dish_name'], isA<String>(),
          reason: '${dish['dish_id']} 缺 dish_name');
      expect(dish['recommendable'], isA<bool>(),
          reason: '${dish['dish_id']} 缺 recommendable');
      expect(dish['quality_tags'], isA<List>(),
          reason: '${dish['dish_id']} 缺 quality_tags');
      expect(dish['portions_normal'], isA<Map>(),
          reason: '${dish['dish_id']} 缺 portions_normal');
      // 契约 portions_normal 含六类键（oil 或 oil_base 至少其一）
      final pn = (dish['portions_normal'] as Map).cast<String, dynamic>();
      expect(
        pn.keys.toSet().contains('oil_base') || pn.keys.contains('oil'),
        isTrue,
        reason: '${dish['dish_id']} portions 缺油脂键',
      );
    }
  });

  test('dish_id 为稳定 slug 且唯一，category 合法，数值范围合法', () {
    final ids = <String>{};
    final slugPattern = RegExp(r'^[a-z][a-z0-9_]*$');
    for (final dish in dishes) {
      final id = dish['dish_id'] as String;
      expect(slugPattern.hasMatch(id), isTrue, reason: '非 slug: $id');
      expect(ids.add(id), isTrue, reason: '重复 dish_id: $id');
      expect(categoryIds.contains(dish['category']), isTrue,
          reason: '$id 引用未知 category ${dish['category']}');
      expect(
        const {'low', 'mid', 'high'}.contains(dish['sodium_level']),
        isTrue,
        reason: '$id 非法 sodium_level',
      );
      final ratio = (dish['cooking_oil_ratio'] as num).toDouble();
      expect(ratio, inInclusiveRange(0, 1), reason: '$id 非法 cooking_oil_ratio');
      expect(dish['oil_factor'], greaterThan(0), reason: '$id oil_factor');
    }
  });

  test('recommendable=true 的菜不含有 fried/high_sugar/high_sodium 标签', () {
    for (final dish in dishes) {
      if (dish['recommendable'] as bool) {
        final tags = (dish['quality_tags'] as List).cast<String>().toSet();
        expect(
          tags.intersection({'fried', 'high_sugar', 'high_sodium'}),
          isEmpty,
          reason: '${dish['dish_id']} recommendable=true 却含负面标签 $tags',
        );
      }
    }
  });

  test('不存在全零份数的菜', () {
    for (final dish in dishes) {
      final pn = (dish['portions_normal'] as Map).cast<String, dynamic>();
      final sum = (pn['grains'] as num? ?? 0).toDouble() +
          (pn['vegetables'] as num? ?? 0).toDouble() +
          (pn['fruits'] as num? ?? 0).toDouble() +
          (pn['protein'] as num? ?? 0).toDouble() +
          (pn['protein_soy'] as num? ?? 0).toDouble() +
          (pn['oil'] as num? ?? pn['oil_base'] as num? ?? 0).toDouble();
      expect(sum, greaterThan(0), reason: '${dish['dish_id']} 全零份数');
    }
  });

  test('垃圾食品抽查：薯条/可乐/炸鸡 均 recommendable=false', () {
    for (final id in ['french_fries', 'cola', 'crispy_fried_chicken']) {
      expect(byId[id], isNotNull, reason: '缺少垃圾食品样本 $id');
      expect(byId[id]!['recommendable'], isFalse, reason: '$id 应不可推荐');
    }
    // 名称兜底扫描
    for (final dish in dishes) {
      final name = dish['dish_name'] as String;
      if (const ['薯条', '可乐', '炸鸡'].any(name.contains)) {
        expect(dish['recommendable'], isFalse, reason: '$name 应不可推荐');
      }
    }
  });

  test('杂粮类抽查：杂粮饭/玉米 含 whole_grain 标签', () {
    for (final id in ['multigrain_rice', 'steamed_corn']) {
      expect(byId[id], isNotNull, reason: '缺少杂粮样本 $id');
      expect(
        (byId[id]!['quality_tags'] as List).cast<String>(),
        contains('whole_grain'),
        reason: '$id 应含 whole_grain',
      );
    }
  });

  test('gap-fill 规模：estimated=true ≥ 150 道，推荐池 ≥ 300 道', () {
    final estimatedCount =
        dishes.where((d) => d['estimated'] == true).length;
    expect(estimatedCount, greaterThanOrEqualTo(150),
        reason: 'gap-fill 不足 150 道');
    final recommendableCount =
        dishes.where((d) => d['recommendable'] == true).length;
    expect(recommendableCount, greaterThanOrEqualTo(300));
  });

  test('契约示例：hsm_rice 补「黄焖鸡」别名；错字「黄闷鸡米饭」留给模糊匹配', () {
    expect(byId['hsm_rice'], isNotNull);
    expect(
      (byId['hsm_rice']!['aliases'] as List).cast<String>(),
      contains('黄焖鸡'),
    );
    // 错字变体不落精确别名：DishMatcher 走 Levenshtein 模糊路径（0.8），
    // 与 test/core/dish_matcher_test 的 OCR 错字语义一致。
    expect(
      (byId['hsm_rice']!['aliases'] as List).cast<String>(),
      isNot(contains('黄闷鸡米饭')),
    );

    final dish = StandardDish.fromJson(byId['hsm_rice']!);
    expect(dish.recommendable, isFalse); // 钠超标 → 不可推荐
    expect(dish.qualityTags, contains('high_sodium'));
    expect(dish.estimated, isTrue);

    // round-trip 保留契约字段
    final reparsed = StandardDish.fromJson(
      jsonDecode(jsonEncode(dish.toJson())) as Map<String, dynamic>,
    );
    expect(reparsed.recommendable, dish.recommendable);
    expect(reparsed.qualityTags, dish.qualityTags);
    expect(reparsed.estimated, dish.estimated);
  });

  test('旧库 29 道 dish_id 全部保留在新库中', () {
    final legacy =
        jsonDecode(File('test/fixtures/legacy_dishes_29.json').readAsStringSync())
            as List;
    for (final entry in legacy.cast<Map<String, dynamic>>()) {
      expect(byId.containsKey(entry['dish_id']), isTrue,
          reason: '旧菜丢失: ${entry['dish_id']}');
    }
  });
}
