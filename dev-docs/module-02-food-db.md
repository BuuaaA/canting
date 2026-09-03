# 模块 02：食物数据库与菜品匹配

**预估工时**：2h
**依赖**：模块 01（数据持久化）
**优先级**：P0

## 功能描述

建立 L2 外卖菜品库 + 菜品匹配引擎。OCR 识别出菜名后，通过匹配引擎找到对应的 L2 菜品，拿到各分类的份数。

**核心原则**：展示用份数，不用精确营养素。cn-food-mcp 仅作为标注参考，不打包进 APP。

## 涉及文件

```
lib/data/
  ├── database_helper.dart      — 扩展：新增 dishes 表 + 预置数据
  ├── dish_repository.dart      — 新建：菜品查询
  └── dish_matcher.dart         — 新建：匹配引擎
lib/models/
  ├── dish.dart                 — 新建：菜品模型
  └── dish_match_result.dart    — 新建：匹配结果模型
assets/data/
  └── dishes_seed.json          — 新建：150 道菜品种子数据
```

## 数据模型

### Dish（L2 菜品）

```dart
class Dish {
  final String id;
  final String name;             // 标准菜名
  final List<String> aliases;    // 别名列表
  final String primaryCategory;  // 主要 L1 分类
  final Map<String, double> servings; // 各分类份数 (regular 分量)
  final String defaultSize;      // small / regular / large
  final double oilFactor;        // 油脂修正系数
  final List<String> tags;       // 标签

  // 根据分量获取实际份数
  Map<String, double> getServingsForSize(String size) {
    final factor = sizeFactors[size] ?? 1.0;
    return servings.map((key, value) => MapEntry(key, value * factor));
  }

  static const Map<String, double> sizeFactors = {
    'small': 0.8,   // 按品类区分的话这里要改
    'regular': 1.0,
    'large': 1.3,
  };
}
```

### L1 分类定义

```dart
enum FoodCategory {
  grains,      // 谷薯类
  vegetables,  // 蔬菜类
  fruits,      // 水果类
  protein,     // 畜禽鱼蛋类
  soyNut,      // 大豆及坚果类
  oil,         // 烹调油脂
}

extension FoodCategoryExt on FoodCategory {
  String get nameCn => switch (this) {
    FoodCategory.grains => '谷薯',
    FoodCategory.vegetables => '蔬菜',
    FoodCategory.fruits => '水果',
    FoodCategory.protein => '蛋白质',
    FoodCategory.soyNut => '大豆坚果',
    FoodCategory.oil => '油脂',
  };

  String get emoji => switch (this) {
    FoodCategory.grains => '🍚',
    FoodCategory.vegetables => '🥬',
    FoodCategory.fruits => '🍎',
    FoodCategory.protein => '🍗',
    FoodCategory.soyNut => '🫘',
    FoodCategory.oil => '🛢️',
  };
}
```

## 数据库表

### dishes 表

```sql
CREATE TABLE dishes (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  aliases_json TEXT NOT NULL,       -- JSON 数组
  primary_category TEXT NOT NULL,
  servings_json TEXT NOT NULL,      -- JSON 对象 {分类:份数}
  default_size TEXT NOT NULL DEFAULT 'regular',
  oil_factor REAL NOT NULL DEFAULT 1.0,
  tags_json TEXT NOT NULL           -- JSON 数组
);
CREATE INDEX idx_dish_name ON dishes(name);
```

### 种子数据格式 (dishes_seed.json)

```json
[
  {
    "id": "dish_001",
    "name": "黄焖鸡米饭",
    "aliases": ["黄焖鸡", "黄焖鸡饭"],
    "primary_category": "protein",
    "servings": {
      "grains": 1.2,
      "vegetables": 0.3,
      "protein": 1.8,
      "oil": 1.2
    },
    "default_size": "regular",
    "oil_factor": 1.6,
    "tags": ["招牌", "常见", "辣"]
  }
]
```

## 菜品匹配引擎

### 匹配优先级

```
1. 精确匹配：完全相等 → 置信度 1.0
2. 别名精确匹配 → 置信度 0.95
3. 包含匹配：OCR文本包含菜名 或 菜名包含OCR文本 → 置信度 0.8
4. 模糊匹配：编辑距离相似度 > 0.7 → 置信度 = 相似度
5. 关键词归类：匹配不到具体菜品时，按关键词归类到 L1 → 置信度 0.5
```

### DishMatcher 接口

```dart
class DishMatcher {
  final List<Dish> allDishes;

  DishMatcher(this.allDishes);

  // 单个菜名匹配
  DishMatchResult? match(String text);

  // 批量匹配（OCR 识别出的所有文本行）
  List<DishMatchResult> matchAll(List<String> lines);

  // 关键词归类（兜底）
  String? categorizeByKeyword(String text);
}

class DishMatchResult {
  final Dish dish;
  final double confidence;   // 0-1
  final MatchMethod method;  // exact / alias / contains / fuzzy / keyword
}
```

### 关键词归类规则

| 关键词 | 归类 |
|--------|------|
| 饭、面、粉、粥、饼、包、饺、馒头 | grains |
| 菜、蔬、瓜、菇、菌、笋、豆芽、豆腐 | vegetables |
| 果、苹果、香蕉、橙、梨、西瓜 | fruits |
| 鸡、鸭、鱼、肉、牛、猪、虾、蛋、肠 | protein |
| 豆、豆腐、豆浆、豆干、坚果、花生、核桃 | soyNut |
| （不单独归类，从菜品中推导） | oil |

## 标注指南（给 AI 标注用）

**每道菜需要标注的字段**：
1. `name` — 标准菜名
2. `aliases` — 常见别名（2-5 个）
3. `primaryCategory` — 主要分类
4. `servings` — 各分类份数（常规分量）
5. `defaultSize` — 默认分量
6. `oilFactor` — 油脂系数（1.0-2.0）
7. `tags` — 标签

**份数估算方法**：
1. 查这道菜的典型菜谱，知道大致用料
2. 参考 cn-food-mcp 数据验证比例合理性
3. 折算到 L1 分类份数
4. 不用精确到小数点后两位，0.5 的精度就够了

## 验收标准

- [ ] 150 道菜品种子数据完整，格式正确
- [ ] 数据库初始化时正确导入种子数据
- [ ] 精确匹配能正确返回
- [ ] 别名匹配能正确返回
- [ ] 包含匹配能正确返回
- [ ] 模糊匹配对常见错别字有效
- [ ] 完全不匹配的文本返回 null
- [ ] 关键词归类对常见食材有效
- [ ] 分量调整后份数正确变化
