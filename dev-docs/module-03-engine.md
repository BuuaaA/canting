# 模块 03：营养计算与推荐引擎

**预估工时**：2h
**依赖**：模块 01、02
**优先级**：P0

## 功能描述

包含两大核心算法：
1. **每日建议摄入量计算** — 根据用户身体数据算出各分类的目标份数
2. **下一餐推荐引擎** — 根据当日缺口推荐下一顿的类型和菜品

**核心原则**：不追求精确，只给方向性引导。

## 涉及文件

```
lib/logic/
  ├── intake_calculator.dart    — 已有，完善：接入真实计算
  ├── recommendation_engine.dart — 已有，完善：接入真实推荐逻辑
  └── completion_calculator.dart — 已有，完善：完成度计算
lib/models/
  ├── daily_intake.dart         — 每日建议摄入量模型
  └── recommendation_result.dart — 推荐结果模型
```

## 每日建议摄入量计算

### 计算公式

**Step 1：BMR（Mifflin-St Jeor 公式）**
```
男: BMR = 10 × 体重 + 6.25 × 身高 - 5 × 年龄 + 5
女: BMR = 10 × 体重 + 6.25 × 身高 - 5 × 年龄 - 161
```

**Step 2：TDEE**
```
TDEE = BMR × 活动系数
  sedentary:  1.2
  light:      1.375
  moderate:   1.55
  heavy:      1.725
```

**Step 3：缩放系数**
```
scale = TDEE / 2000  (以 2000kcal 为基准)
```

**Step 4：基准份数 × 缩放系数**

| 分类 | 基准份数(2000kcal) | 低限系数 | 高限系数 |
|------|-------------------|---------|---------|
| grains | 5.0 | 0.8 | 1.2 |
| vegetables | 4.0 | 0.75 | 1.25 |
| fruits | 2.5 | 0.8 | 1.4 |
| protein | 4.0 | 0.75 | 1.25 |
| soyNut | 1.0 | 0.8 | 1.2 |
| oil | 2.5 | 0.8 | 1.2 |

**Step 5：饮食目标微调**

| 目标 | 调整 |
|------|------|
| balanced | 无调整 |
| more_veg | vegetables × 1.2 |
| more_protein | protein × 1.2 |
| less_carb | grains × 0.8 |

### DailyIntake 模型

```dart
class DailyIntake {
  final double bmr;
  final double tdee;
  final Map<String, double> targetServings;   // 目标份数
  final Map<String, double> minServings;      // 下限
  final Map<String, double> maxServings;      // 上限

  // 判断某分类是否达标 (80%-120%)
  bool isOnTrack(String category, double current) {
    final target = targetServings[category] ?? 0;
    if (target == 0) return true;
    final ratio = current / target;
    return ratio >= 0.8 && ratio <= 1.2;
  }

  // 计算缺口（正数=不够，负数=超标）
  double deficit(String category, double current) {
    final target = targetServings[category] ?? 0;
    return target - current;
  }
}
```

### IntakeCalculator 接口

```dart
class IntakeCalculator {
  static DailyIntake calculate({
    required String gender,
    required int age,
    required double heightCm,
    required double weightKg,
    required String activityLevel,
    required String dietGoal,
  });
}
```

## 完成度计算

### CompletionCalculator

```dart
class CompletionCalculator {
  // 整体完成度（0-100%）
  static double calculateOverall({
    required DailyIntake intake,
    required Map<String, double> currentServings,
  }) {
    // 加权平均：蔬菜和蛋白质权重最高
    final weights = {
      'vegetables': 0.25,
      'protein': 0.25,
      'grains': 0.2,
      'fruits': 0.15,
      'soyNut': 0.1,
      'oil': 0.05, // 油脂只算很小权重，避免焦虑
    };

    double total = 0;
    weights.forEach((cat, weight) {
      final target = intake.targetServings[cat] ?? 1;
      final current = currentServings[cat] ?? 0;
      final ratio = (current / target).clamp(0.0, 1.2);
      // 超过 120% 不算额外分，但也不扣分
      final score = ratio > 1.0 ? 1.0 : ratio;
      total += score * weight;
    });

    return total * 100; // 0-100
  }

  // 各分类完成率
  static Map<String, double> calculateByCategory({
    required DailyIntake intake,
    required Map<String, double> currentServings,
  }) {
    return {
      for (final cat in FoodCategory.values.map((e) => e.name))
        cat: _clamp((currentServings[cat] ?? 0) / (intake.targetServings[cat] ?? 1), 0, 1.5)
    };
  }
}
```

## 推荐引擎

### 推荐结果模型

```dart
class RecommendationResult {
  final String nextMealType;      // breakfast / lunch / dinner
  final DateTime nextMealTime;
  final String primarySuggestion; // 主要建议类型
  final String suggestionText;    // 推荐文案
  final List<Dish> suggestedDishes; // 推荐菜品（3-5道）
  final List<String> reasons;     // 推荐理由（简单列出缺口）
}
```

### 推荐算法流程

```
1. 确定下一餐时间和类型
   → 找到距离当前最近的饭点
   → 如果已经过了所有饭点，返回明天早餐

2. 计算当日各分类缺口
   → 缺口 = 目标 - 已摄入
   → 排除已经达标的（>80%）

3. 排序缺口
   → 按缺口大小排序（份数差最大的排前面）
   → 蔬菜和蛋白质权重 × 1.2（更重要）

4. 生成推荐类型和文案
   → 取缺口最大的 1-2 个分类
   → 根据餐次调整（早餐不太可能推荐大份蔬菜）
   → 生成自然语言文案

5. 选择推荐菜品
   → 从 L2 库中筛选包含推荐分类的菜品
   → 优先选择常见/热门菜品
   → 随机取 3-5 道（增加丰富感）
```

### RecommendationEngine 接口

```dart
class RecommendationEngine {
  final List<Dish> allDishes;

  RecommendationEngine(this.allDishes);

  RecommendationResult recommend({
    required DailyIntake intake,
    required Map<String, double> todayServings,
    required DateTime now,
    required Map<String, String> mealTimes, // breakfast/lunch/dinner
  });

  // 只推荐类型和文案（不需要菜品详情时用）
  RecommendationType recommendType({
    required DailyIntake intake,
    required Map<String, double> todayServings,
    required String mealType,
  });
}
```

### 推荐文案模板

```dart
final Map<String, List<String>> suggestionTemplates = {
  'more_vegetables': [
    '今天蔬菜吃得少，下一顿多加点青菜吧～',
    '来点绿色蔬菜怎么样？',
    '蔬菜不够哦，记得多点一份菜',
  ],
  'more_protein': [
    '可以来点鱼或鸡肉，补充蛋白质',
    '蛋白质还差一点，加点肉肉吧',
    '来份鸡蛋或鱼虾？',
  ],
  'less_grains': [
    '主食已经够啦，下顿少点一点饭',
    '今天主食吃的不少，控制一下？',
  ],
  'balanced': [
    '吃得挺均衡的，继续保持～',
    '今天表现不错哦！',
    '结构很健康，继续加油',
  ],
  'more_fruits': [
    '下午啦，来份水果当加餐？',
    '水果还没吃呢，来点水果吧',
  ],
};
```

## 验收标准

- [ ] BMR 计算结果与手动计算一致（用已知数值验证）
- [ ] TDEE 计算正确
- [ ] 饮食目标调整正确（多吃蔬菜时蔬菜目标 × 1.2）
- [ ] 完成度计算在 0-100 范围内
- [ ] 各分类进度计算正确
- [ ] 推荐引擎能正确识别最大缺口
- [ ] 推荐菜品属于推荐的分类
- [ ] 不同时间点推荐的下一餐正确
- [ ] 过了晚餐时间后推荐明天早餐
