import 'models/meal_record.dart';

class Exposure {
  static const labels = {
    'sugary_drink': '含糖饮品',
    'fried_food': '油炸食品',
    'alcohol': '酒精',
  };
  static const messages = {
    'sugary_drink': '最近7天已记录过含糖饮品。下次想试试不另外加糖吗？',
    'fried_food': '最近7天已记录过油炸食品。下一次也可以考虑非油炸做法。',
    'alcohol': '最近7天已记录过饮酒。下次可以考虑减少饮酒。',
  };
  static Set<String> families(MealRecord meal) {
    final result = <String>{};
    for (final d in meal.dishes) {
      final food = d.food, facts = d.food?.facts, k = d.food?.knowledge;
      final tags = [
        ...(k?.toJson()['risk_tags'] as List? ?? const []),
        ...(d.riskEvidence?['tags'] as List? ?? const []),
      ];
      if ({
                'milk_tea',
                'coffee',
                'beverage',
                'other_beverage',
                'drink',
              }.contains(facts?.category) &&
              {'low', 'regular', 'high'}.contains(food?.spec.sugar) ||
          tags.contains('sugary_drink') ||
          (k?.productCategory == 'beverage' &&
              {'low', 'regular', 'high'}.contains(k?.sugarLevel) &&
              (food?.spec.sugar == 'unknown'))) {
        result.add('sugary_drink');
      }
      if (facts?.preparation == 'fried' ||
          k?.preparation == 'fried' ||
          tags.contains('fried')) {
        result.add('fried_food');
      }
      if (facts?.category == 'alcohol' || tags.contains('alcohol')) {
        result.add('alcohol');
      }
      // Old snapshots have no structured preparation; only affirmative bounded names.
      if (food == null) {
        final n = d.name.replaceAll(RegExp(r'非油炸|不油炸|无油炸'), '');
        if (RegExp(r'^(油炸|炸鸡|炸鱼|炸虾|炸猪|炸肉|炸薯|薯条|油条)|油炸$').hasMatch(n)) {
          result.add('fried_food');
        }
        if (RegExp(r'^(啤酒|白酒|红酒|葡萄酒|威士忌|伏特加|鸡尾酒)$').hasMatch(n)) {
          result.add('alcohol');
        }
      }
    }
    return result;
  }

  static Map<String, int> counts(Iterable<MealRecord> meals) {
    final ids = <String, Set<String>>{};
    for (final meal in meals) {
      for (final f in families(meal)) {
        ids.putIfAbsent(f, () => {}).add(meal.mealId);
      }
    }
    return {for (final e in ids.entries) e.key: e.value.length};
  }
}

class ExposurePrompt {
  ExposurePrompt(this.mealId, this.counts, {this.nextTimePreference});
  final String? nextTimePreference;
  final String mealId;
  final Map<String, int> counts;
}
