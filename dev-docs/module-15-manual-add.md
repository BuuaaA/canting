# 模块 15：手动添加餐食 + 用户数据反馈

> 状态：新增模块（V1.0 必须有）
> 预计工时：4h
> 优先级：高

---

## 一、为什么需要这个

1. **用户场景刚需**：不是每顿都点外卖，自己做饭、食堂打饭、外食都需要能手动记录
2. **数据飞轮**：用户填写的克数越准确，我们的「菜名 → 份数」映射就越准
3. **推荐精准度**：有了真实的用户数据，推荐引擎才能从「规则驱动」进化到「数据驱动」

---

## 二、用户手动添加餐食

### 2.1 入口

- 首页右下角「+」按钮 → 弹出选项：
  - 📸 截图识别（已有）
  - ✍️ 手动添加 ← 新增
  - 📷 拍照识别（V1.1）

### 2.2 手动添加页面

**两种模式：简单模式 / 详细模式**

#### 简单模式（默认，快速记录）

用户只需要做 3 件事：
1. **选餐次**（早餐/午餐/晚餐/加餐）
2. **搜菜名**（从 L2 菜品库搜索，支持模糊匹配）
3. **调份量**（小份/常规/大份 三档，默认常规）

点击「添加」就完成了。

#### 详细模式（高级用户，精确记录）

在简单模式基础上，展开「详细填写」可以看到：

| 字段 | 类型 | 说明 |
|------|------|------|
| 菜名 | 文本 | 可手动输入，不一定从库里选 |
| 分类 | 下拉 | 谷薯/蔬菜/水果/蛋白质/大豆坚果（可多选） |
| 重量(g) | 数字输入 | 用户自己估重，**选填** |
| 份量 | 滑块/数字 | APP 自动根据重量推算，用户也可以手动调整 |
| 备注 | 文本 | 选填，比如「少油少盐」 |

**核心交互：重量 ↔ 份数 双向联动**
- 用户输入重量 → APP 根据该菜品的标准份量自动推算份数
- 用户调整份数 → APP 反推对应的重量
- 两种方式用户任选一种

### 2.3 自己做饭的场景支持

**「自制餐食」标签**：
- 用户手动添加时，可以勾选「这是自己做的」
- 勾选后，可以选择：
  - 单一菜品（比如「清炒西兰花」）
  - 混合菜品（比如「西红柿鸡蛋面」）—— 可以拆分成多种食材

**混合菜品拆分**（V1.0 简化版）：
- 用户输入菜名后，如果库里没有，APP 会提示「要不要拆成食材？」
- 用户可以添加多种食材，每种填重量
- APP 根据每种食材的分类和重量，累加计算总份数

> V1.0 先做简单版：单一菜品 + 重量输入。混合菜品拆分放到 V1.1。

### 2.4 数据存储

**meal_records 表增加字段**：

```sql
ALTER TABLE meal_records ADD COLUMN source TEXT NOT NULL DEFAULT 'ocr';
-- source: 'ocr' / 'manual' / 'mixed'

ALTER TABLE meal_records ADD COLUMN user_adjusted INTEGER NOT NULL DEFAULT 0;
-- 用户是否手动调整过分量：0=否，1=是

ALTER TABLE meal_records ADD COLUMN user_weight_g REAL;
-- 用户填写的重量（克），NULL 表示未填写

ALTER TABLE meal_records ADD COLUMN note TEXT;
-- 用户备注
```

**user_custom_dishes 表（新增，用户自定义菜品）**：

```sql
CREATE TABLE user_custom_dishes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    category TEXT NOT NULL,           -- 主分类
    categories_json TEXT,             -- 多分类JSON（如果一道菜跨多个分类）
    default_servings REAL NOT NULL,   -- 默认份数
    default_weight_g REAL,            -- 默认重量（克）
    is_homemade INTEGER DEFAULT 0,    -- 是否自制
    usage_count INTEGER DEFAULT 1,    -- 使用次数
    last_used_at INTEGER,             -- 最后使用时间
    created_at INTEGER NOT NULL
);
```

---

## 三、用户数据反馈机制（数据飞轮）

### 3.1 核心思路

> 用户每一次手动填写重量，都是一次「标注」。积累得多了，我们的菜品份数估算就越来越准。

### 3.2 收集什么数据

每次用户手动添加或调整了餐食，我们记录：

```json
{
  "dish_name": "清炒西兰花",
  "user_category": "vegetable",
  "user_weight_g": 200,
  "user_servings": 2.5,
  "system_servings": 2.0,
  "source": "manual_input",
  "adjusted": true,
  "timestamp": 1234567890
}
```

**关键对比**：系统估算的份数 vs 用户实际填写的份数

### 3.3 数据怎么用

#### V1.0：个人级优化

- 用户常吃的自定义菜品，下次输入时自动提示
- 记住用户对某道菜的份量偏好（比如用户总把「宫保鸡丁」调成大份，下次默认就是大份）
- 纯本地，不上传

#### V1.1：匿名聚合优化（可选）

- 如果用户同意上传匿名数据
- 服务端聚合所有用户的「菜名+重量+份数」数据
- 用统计方法（中位数/加权平均）优化 L2 菜品库的标准份量
- 定期更新到 APP 的菜品库中

#### V2.0：推荐个性化

- 基于用户的历史记录，分析口味偏好
- 在结构优化的前提下，优先推荐用户爱吃的菜
- 越用越准

### 3.4 隐私设计

- **默认纯本地**：所有数据只存在用户手机上
- **可选上传**：设置页有一个「帮助改进产品」的开关，默认关闭
- 上传的数据**匿名化**：不含用户ID、不含时间戳精确到分钟以上、不含位置信息
- 用户可以随时导出和删除自己的所有数据

---

## 四、涉及文件

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `lib/data/database_helper.dart` | 修改 | 新增 user_custom_dishes 表，扩展 meal_records 字段 |
| `lib/data/repositories/meal_repository.dart` | 修改 | 支持手动添加餐食的 CRUD |
| `lib/data/repositories/custom_dish_repository.dart` | 新建 | 自定义菜品 Repository |
| `lib/pages/manual_add_page.dart` | 新建 | 手动添加页面 |
| `lib/widgets/weight_serving_toggle.dart` | 新建 | 重量/份数双向联动组件 |
| `lib/core/dish_serving_estimator.dart` | 新建 | 菜名→份数估算器（支持用户数据微调） |
| `lib/state/app_state.dart` | 修改 | 接入手动添加功能 |
| `test/core/dish_serving_estimator_test.dart` | 新建 | 单元测试 |

---

## 五、核心逻辑

### 5.1 重量 ↔ 份数换算逻辑

```dart
class DishServingEstimator {
  /// 根据菜名和重量，估算份数
  double estimateServings(String dishName, double weightGrams) {
    // 1. 先查 L2 菜品库
    final dish = dishLibrary.findByName(dishName);
    if (dish != null) {
      return weightGrams / dish.weightPerServing;
    }
    
    // 2. 查用户自定义菜品
    final custom = customDishRepo.findByName(dishName);
    if (custom != null && custom.defaultWeightG != null) {
      return weightGrams / custom.defaultWeightG! * custom.defaultServings;
    }
    
    // 3. 按分类估算（兜底）
    final category = guessCategoryByName(dishName);
    final perServing = categoryWeightMap[category] ?? 80;
    return weightGrams / perServing;
  }
  
  /// 根据份数反推重量
  double estimateWeight(String dishName, double servings) {
    // 类似的反向逻辑
  }
}
```

### 5.2 用户数据的本地积累

```dart
class UserServingData {
  /// 用户调整过的菜品份量数据（本地积累）
  Map<String, List<ServingAdjustment>> adjustments = {};
  
  /// 获取某道菜的用户偏好份数系数
  double getUserPreferenceFactor(String dishName) {
    final adjusts = adjustments[dishName];
    if (adjusts == null || adjusts.isEmpty) return 1.0;
    
    // 取最近 5 次调整的中位数
    final recent = adjusts.take(5).toList();
    final factors = recent.map((a) => a.userServings / a.systemServings).toList();
    factors.sort();
    return factors[factors.length ~/ 2];
  }
}
```

---

## 六、验收标准

- [ ] 首页有「手动添加」入口
- [ ] 可以搜索 L2 菜品库中的菜并添加
- [ ] 可以输入自定义菜名并选择分类
- [ ] 输入重量后自动推算份数
- [ ] 调整份数后自动反推重量
- [ ] 可以选择餐次（早/午/晚/加餐）
- [ ] 用户自定义的菜品会出现在搜索建议的顶部
- [ ] 手动添加的餐食在首页和历史记录中正常显示
- [ ] 标记为「用户调整过」的记录会被用于本地偏好计算
- [ ] 所有数据纯本地存储，不上传
- [ ] 设置页有「帮助改进产品」开关（默认关闭）
