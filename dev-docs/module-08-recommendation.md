# 模块 08：推荐详情页与外卖跳转

**预估工时**：2h
**依赖**：模块 03
**优先级**：P0

## 功能描述

推荐详情页展示下一餐的具体推荐菜品和外卖平台跳转按钮，是从"看"到"行动"的关键转化点。

## 涉及文件

```
lib/ui/recommendation/
  ├── recommendation_detail_page.dart — 推荐详情页
  ├── recommended_dish_card.dart    — 推荐菜品卡片
  └── platform_buttons.dart         — 外卖平台跳转按钮组
```

## 推荐详情页

### 页面结构

```
← 下一餐推荐

⏰ 建议 18:30 吃晚餐
🥬 今天蔬菜还差 1.5 份
推荐多吃点蔬菜哦～

─────────────────────
推荐菜品

┌─────────────────────────────┐
│ 🥦 蒜蓉西兰花               │
│ 蔬菜 1.5 份 · 低油健康       │
│ [美团外卖] [饿了么] [京东]   │  ← 点击跳外卖APP
└─────────────────────────────┘

┌─────────────────────────────┐
│ 🥬 香菇青菜                 │
│ 蔬菜 1.2 份                  │
│ [美团外卖] [饿了么] [京东]   │
└─────────────────────────────┘

┌─────────────────────────────┐
│ 🥒 凉拌黄瓜                 │
│ 蔬菜 1.0 份 · 清爽低卡       │
│ [美团外卖] [饿了么] [京东]   │
└─────────────────────────────┘

─────────────────────
[ 换一批推荐 ]  [ 不感兴趣 ]
```

### 顶部推荐说明区

- 下一餐时间 + 餐次
- 主要缺口说明（"今天蔬菜还差 1.5 份"）
- 推荐文案

### 推荐菜品列表

- 展示 3-5 道推荐菜品
- 每道菜显示：菜名 + 主要分类份数 + 标签
- 下方是外卖平台按钮组
- 菜品从 L2 库中按推荐类型筛选，随机排序

### 底部操作

- 「换一批推荐」：重新随机抽取推荐菜品
- 「不感兴趣」：减少这类推荐（V1.0 简单实现为换一批）

## 外卖平台跳转

### 支持的平台

| 平台 | Scheme | H5 Fallback |
|------|--------|-------------|
| 美团外卖 | `meituanwaimai://waimai.meituan.com/search?query={keyword}` | https://waimai.meituan.com |
| 美团 APP | `imeituan://www.meituan.com/search?q={keyword}` | https://www.meituan.com |
| 淘宝闪购（饿了么） | `eleme://search?keyword={keyword}` | https://h5.ele.me |
| 京东外卖 | `openApp.jdMobile://virtual?params={json}` | https://www.jd.com |

### 跳转逻辑

```dart
class PlatformLauncher {
  static Future<void> launchSearch(String platform, String keyword) async {
    final scheme = _buildScheme(platform, keyword);
    final fallbackUrl = _getFallbackUrl(platform, keyword);

    if (await canLaunchUrl(Uri.parse(scheme))) {
      await launchUrl(Uri.parse(scheme), mode: LaunchMode.externalApplication);
    } else {
      // 未安装APP，跳转 H5
      await launchUrl(Uri.parse(fallbackUrl), mode: LaunchMode.externalApplication);
    }
  }
}
```

### 平台按钮显示逻辑

- 从设置中读取用户选择的平台列表
- 按用户设置的顺序排列
- 最多显示 3 个按钮（空间限制）
- 未选择任何平台时：默认显示美团外卖 + 饿了么

### 平台按钮样式

```
[ 美团外卖 ]  [ 饿了么 ]  [ 京东 ]
  图标+文字    图标+文字   图标+文字
```

- 按钮高度约 36px
- 圆角 8px
- 各平台使用品牌色背景
- 白色文字 + 平台图标

## 推荐逻辑补充

### 菜品筛选

```dart
List<Dish> filterDishesByRecommendation(
  List<Dish> allDishes,
  String recommendationType,
) {
  // 根据推荐类型筛选
  List<Dish> filtered;
  switch (recommendationType) {
    case 'more_vegetables':
      filtered = allDishes.where((d) => d.primaryCategory == 'vegetables').toList();
      break;
    case 'more_protein':
      filtered = allDishes.where((d) => d.primaryCategory == 'protein').toList();
      break;
    case 'less_grains':
      filtered = allDishes.where((d) => d.primaryCategory != 'grains').toList();
      break;
    default:
      filtered = allDishes; // 均衡，随机推荐
  }

  // 优先选择 tag 含"常见"的菜品
  filtered.sort((a, b) {
    final aCommon = a.tags.contains('常见') ? 1 : 0;
    final bCommon = b.tags.contains('常见') ? 1 : 0;
    return bCommon.compareTo(aCommon);
  });

  // 随机取 3-5 道
  filtered.shuffle();
  return filtered.take(Random().nextInt(3) + 3).toList();
}
```

## 验收标准

- [ ] 推荐详情页正确显示推荐类型和文案
- [ ] 推荐菜品属于推荐的分类
- [ ] 换一批推荐能刷新菜品
- [ ] 点击美团外卖按钮能跳转到美团外卖 APP
- [ ] 未安装 APP 时跳转到 H5 网页
- [ ] 平台按钮按用户设置的顺序排列
- [ ] 用户只选了 1 个平台时只显示 1 个按钮
- [ ] 搜索关键词正确传递（菜名）
- [ ] 各平台 scheme 正确验证
