# 模块 05：首页（今日）

**预估工时**：3h
**依赖**：模块 01, 02, 03, 07
**优先级**：P0

## 功能描述

APP 首页，用户打开 APP 第一眼看到的页面。核心是：宠物 + 今日膳食结构 + 下一餐推荐 + 今日餐食列表。

## 涉及文件

```
lib/ui/home/
  ├── home_page.dart              — 首页主页面
  ├── pet_banner.dart             — 宠物展示区
  ├── structure_ring.dart         — 膳食结构环形图
  ├── category_progress_list.dart — 分类进度条列表
  ├── next_meal_card.dart         — 下一餐推荐卡片
  └── today_meal_list.dart        — 今日餐食列表
```

## 页面结构

```
┌─ AppBar ────────────────────────┐
│  👋 今天过得怎么样                 │
├──────────────────────────────────┤
│  🐱 宠物展示区                    │  ← 动画 + 名字 + 状态 + 摸摸头
├──────────────────────────────────┤
│  📊 今日膳食结构                   │
│      ╭──────╮                     │
│     ╱  72%   ╲    整体完成度       │
│    │  环形图  │                    │
│     ╲        ╱                    │
│      ╰──────╯                     │
│  今天吃得还不错～                  │
├──────────────────────────────────┤
│  🥬 蔬菜  2.5/4 份  ██████░░     │
│  🍗 蛋白  3.2/4 份  ███████░     │
│  🍚 主食  3.8/5 份  ███████░     │
│  🍎 水果  1.0/2.5  ███░░░░      │
│  ▼ 展开更多                       │  ← 点击展开大豆坚果+油脂
├──────────────────────────────────┤
│  ⏰ 下一餐推荐                     │
│  18:30 · 多吃点蔬菜吧              │
│  [ 看看推荐吃什么 → ]              │
├──────────────────────────────────┤
│  🍽️ 今日餐食                      │
│  ┌────────────────────────────┐  │
│  │ 12:30  午餐                 │  │
│  │ 黄焖鸡米饭 · 共 2.8 份蛋白   │  │
│  └────────────────────────────┘  │
│  ┌────────────────────────────┐  │
│  │ 08:00  早餐                 │  │
│  │ 豆浆包子 · 共 1.5 份主食     │  │
│  └────────────────────────────┘  │
│                                  │
│  [  + 添加记录  ]                 │
└──────────────────────────────────┘
[ 🏠 今日 ] [ 📅 记录 ] [ 👤 我的 ]
```

## 核心组件

### 1. PetBanner（宠物展示区）

```dart
class PetBanner extends StatelessWidget {
  final PetState pet;
  final VoidCallback onPet;  // 摸摸头回调

  // 显示内容：
  // - 宠物动画（根据状态切换帧）
  // - 宠物名字
  // - 状态标签（开心/一般/不太开心）
  // - 点击触发摸摸头动画 + 对话气泡
}
```

**状态 → 动画映射**：
- vitality >= 80 → happy 动画
- vitality 60-79 → normal 动画
- vitality 40-59 → so-so 动画
- vitality < 40 → sad 动画

**摸摸头逻辑**：
- 冷却时间 4 小时，每日上限 3 次
- 冷却中点击显示「{昵称}已经满足啦，等会儿再摸～」
- 每次摸摸头 +1 成长值

### 2. StructureRing（膳食结构环形图）

```dart
class StructureRing extends StatelessWidget {
  final Map<String, double> currentServings;
  final Map<String, double> targetServings;
  final double overallCompletion;

  // 环形图 6 段，每段对应一个分类
  // 中心显示完成度百分比
  // 下方显示鼓励文案
}
```

**颜色方案**：

| 分类 | 颜色 |
|------|------|
| grains | #F6AD55 (橙) |
| vegetables | #68D391 (绿) |
| fruits | #FC8181 (红) |
| protein | #63B3ED (蓝) |
| soyNut | #B794F4 (紫) |
| oil | #A0AEC0 (灰) |

### 3. CategoryProgressList（分类进度条）

```dart
class CategoryProgressList extends StatelessWidget {
  final Map<String, double> current;
  final Map<String, double> target;
  final bool showAll;  // 是否显示全部（包括油脂）

  // 每个分类一行：图标 + 名称 + 当前/目标 + 进度条
  // 进度条颜色根据完成度变化
}
```

**进度条颜色规则**：
- < 50% → 红色（偏低）
- 50%-80% → 黄色（进行中）
- 80%-120% → 绿色（达标）
- > 120% → 深绿（超标，不焦虑）

### 4. NextMealCard（下一餐推荐卡片）

```dart
class NextMealCard extends StatelessWidget {
  final RecommendationResult recommendation;
  final VoidCallback onTap;  // 点击跳推荐详情

  // 显示：
  // - 下一餐时间
  // - 建议文案
  // - 「看看推荐吃什么」按钮
}
```

### 5. TodayMealList（今日餐食列表）

```dart
class TodayMealList extends StatelessWidget {
  final List<MealRecord> meals;
  final Function(MealRecord) onMealTap;
  final VoidCallback onAddMeal;

  // 按时间倒序排列
  // 每条显示：时间 + 餐次 + 主要菜品名
  // 底部 + 添加记录按钮
}
```

**空状态**：
- 当天无记录时显示空状态插画 + 文案
- 「试试手动添加」按钮

## 数据刷新

- 进入页面时自动刷新
- 下拉刷新
- 添加/删除记录后自动刷新
- 修改设置后自动刷新

## 验收标准

- [ ] 首页各模块正确显示数据
- [ ] 环形图正确展示各分类占比
- [ ] 进度条颜色随完成度变化
- [ ] 宠物动画与活力值匹配
- [ ] 点击宠物触发摸摸头（冷却前）
- [ ] 摸摸头冷却中点击有提示
- [ ] 下一餐推荐卡片显示正确时间和文案
- [ ] 点击推荐卡片跳转到推荐详情页
- [ ] 今日餐食列表正确显示
- [ ] 点击餐食跳转到详情页
- [ ] 添加/删除记录后首页数据刷新
- [ ] 下拉刷新正常工作
- [ ] 空状态显示正确
