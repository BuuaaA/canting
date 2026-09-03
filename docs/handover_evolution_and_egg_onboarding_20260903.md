# 餐盘 APP 功能开发交接文档

| 项目 | 内容 |
|------|------|
| 文档名称 | 进化动画接入首页 + 新玩家从蛋开始 |
| 项目名称 | 餐盘（canting） |
| 文档版本 | v1.0 |
| 创建日期 | 2026-09-03 |
| 作者 | 谷笑宇（产品侧）+ AI 协助 |
| 代码仓库 | d:\dev\canting |
| 技术栈 | Flutter 3.47.2 / Dart / Kotlin（Android 原生小组件） |
| 当前分支 | main |

---

## 目录

1. [功能概述](#1-功能概述)
2. [详细需求说明](#2-详细需求说明)
3. [技术实现要点](#3-技术实现要点)
4. [验收标准](#4-验收标准)
5. [相关资源](#5-相关资源)
6. [进度与优先级](#6-进度与优先级)
7. [版本历史](#7-版本历史)

---

## 1. 功能概述

本次需要实现两个紧密关联的功能点，均围绕"宠物成长"这一核心体验：

### 功能一：进化动画接入首页
将已实现但未集成的 `EvolutionAnimationWidget` 接入应用首页，在宠物跨越成长阶段（蛋→幼年 / 幼年→成年）时自动播放 2 秒进化动画。

### 功能二：新玩家从蛋开始
为新注册玩家设计"从蛋开始"的初始体验流程，移除当前原型中强制将宠物覆盖为"幼年期"的逻辑，让玩家从蛋的孵化开始陪伴宠物成长。

### 两个功能的关系
功能二是功能一的**前置条件**：只有让新玩家从蛋开始，进化动画的"蛋→幼年"分支才有真实触发场景。功能一则是功能二的**体验闭环**：从蛋孵化时必须有动画反馈，否则用户无法感知"孵化完成"。建议作为一组关联需求统一实现。

---

## 2. 详细需求说明

### 2.1 进化动画接入首页

#### 2.1.1 动画触发条件

**判定逻辑**：当一次状态更新操作（记录餐食 / 摸宠物 / 每日登录）导致宠物 `growthStage` 发生跨越时触发。

**参数阈值**（已由 `PetStateMachine.getGrowthStage` 定义，无需新增）：

| 成长值（growth）区间 | 成长阶段 | 触发进化 |
|----------------------|----------|----------|
| 0 - 49 | 蛋（egg） | — |
| 50 - 199 | 幼年（baby） | 蛋→幼年（growth 跨越 50） |
| ≥ 200 | 成年（adult） | 幼年→成年（growth 跨越 200） |

**已有信号源**：`PetUpdateResult.previousGrowthStage` 字段。当该字段非 null 时，`shouldPlayEvolution` getter 返回 true。该信号已在 `PetStateMachine._applyEvolution`（[pet_engine.dart](file:///d:/dev/canting/lib/pet/pet_engine.dart) 第 506-539 行）中正确生成，但 **AppState 层目前未消费此信号**。

**触发场景**：
| 场景 | 方法 | 当前是否生成 previousGrowthStage |
|------|------|----------------------------------|
| 记录餐食 | `onMealRecorded` | 是 |
| 摸宠物 | `onPetTap` | 是 |
| 每日登录 | `onDailyLogin` | 是 |
| 删除/编辑餐食 | `onMealDeleted` / `onMealEdited` | 否（不产生进化） |
| 离线衰减 | `checkOfflineDecay` | 否（仅同步阶段，不触发动画） |

#### 2.1.2 动画展示位置与层级

**展示位置**：首页（`HomePage`）全屏遮罩层，覆盖在 `PetArea` 及其他内容之上。

**层级关系**：
```
Scaffold (HomePage)
└── body: PixelBackdrop
    └── Stack  ← 新增
        ├── ListView (现有首页内容，含 PetArea)
        └── EvolutionAnimationWidget (顶层遮罩，触发时显示)
```

**尺寸**：`EvolutionAnimationWidget` 已使用 `SizedBox.expand` + `ColoredBox` 实现全屏半透明白色遮罩（`Color(0xEFFFFFFF)`），精灵图居中 128×128，无需调整。

#### 2.1.3 交互规则

| 规则 | 说明 |
|------|------|
| 是否可跳过 | 不可跳过（动画仅 2 秒，且为高价值时刻） |
| 是否可暂停 | 不可暂停 |
| 点击穿透 | 已用 `IgnorePointer` 包裹，动画期间底层不可点击 |
| 动画期间其他操作 | 状态更新（如继续记录餐食）可正常进行，但下一次进化动画需排队或覆盖（见技术难点） |
| 动画结束 | 自动移除，恢复首页交互 |
| 无障碍模式 | `MediaQuery.disableAnimationsOf` 为 true 时应立即跳过动画，直接显示新阶段 |

#### 2.1.4 资源加载策略

**当前实现**：`EvolutionAnimationWidget` 内部使用 `PetSpriteWidget`，后者已内置：
- 像素画 `CustomPainter` 作为占位（无需资源文件，即时绘制）
- `AssetManifest` 异步加载的精灵图 PNG 覆盖层（如存在则替换占位画）
- `gaplessPlayback: true` 避免闪烁

**性能优化要求**：
- 进化动画**无需预加载**：占位画由代码即时绘制，不依赖外部资源
- 若存在 PNG 精灵图，首次播放可能有一帧延迟，但因占位画兜底，用户不会感知
- `EvolutionAnimationWidget` 使用 `SingleTickerProviderStateMixin`，控制器在 `dispose` 时正确释放，无内存泄漏风险

---

### 2.2 新玩家从蛋开始

#### 2.2.1 蛋的初始状态展示

**初始数据**（`createPet` 已正确定义）：
- `growthStage: GrowthStage.egg`
- `growth: 0`
- `vitality: 60`（initialVitality）
- `lastVitalityUpdate: now`
- `createdAt: now`

**当前问题**：`AppState` 构造函数和 `completeOnboarding` 方法都强制 `.copyWith(growthStage: GrowthStage.baby, growth: 68, vitality: 76)` 覆盖了蛋状态，需要移除这两处覆盖。

**展示形式**：
- 首页 `PetArea` 中的 `PetSpriteWidget` 已支持 `growthStage: 'egg'`（16×16 像素蛋形，含绿色和红色装饰斑点）
- 蛋的帧动画为 2 帧（`PetSpriteWidget.frameCountFor('egg') == 2`）
- 状态标签显示"萌芽期"（`_stageLabel` 已正确映射）

#### 2.2.2 蛋的孵化流程

**孵化条件**：`growth >= 50` 时由 `getGrowthStage` 自动转为 `baby`。

**growth 获取来源**（无需新增）：
| 行为 | growth 增量 | 触发频率 |
|------|-------------|----------|
| 记录餐食（完成率≥0.7） | +10 | 每餐 |
| 记录餐食（完成率≥0.4） | +5 | 每餐 |
| 记录餐食（完成率<0.4） | +3 | 每餐 |
| 摸宠物 | +1 | 每 4 小时一次，每日最多 3 次 |
| 每日登录 | +2 | 每日一次 |

**孵化时长预估**：
- 最快路径：5 餐高完成率餐食（5×10=50），约 2-3 天
- 正常路径：混合完成率，约 5-7 天
- 仅靠摸宠物和登录：每日最多 3×1 + 2 = 5，约 10 天（兜底体验）

**孵化触发时**：播放"蛋→幼年"进化动画（依赖功能一）。

#### 2.2.3 过渡动画效果

**已实现**：`EvolutionAnimationWidget` 内置：
- 2 秒持续时间的 `AnimationController`
- `TweenSequence` 缩放动画：0.75 → 1.15（easeOutBack）→ 1.0
- 50% 进度时切换 `fromStage` → `toStage` 的精灵图
- 文字提示"${petName}长大了！"
- 完成后 `onFinished` 回调

**蛋→幼年的特殊文案**：当前固定为"XX长大了！"。产品侧建议考虑蛋孵化时使用"XX破壳而出！"等差异化文案，但这属于可选优化，非阻塞项。

#### 2.2.4 新玩家引导与蛋系统结合

**当前 onboarding 流程**（5 步）：
1. 欢迎（展示 baby 形态宠物 + APP 功能介绍）
2. 身体信息
3. 活动水平
4. 饮食目标
5. 选择伙伴（Step0PetSelection）

**修改要点**：
- `_WelcomeStep` 中展示的 `PetSpriteWidget` 应从 `growthStage: 'baby'` 改为 `growthStage: 'egg'`，与新玩家初始状态一致
- `completeOnboarding` 后跳转到首页，首页 `PetArea` 直接展示蛋形态
- **不新增 onboarding 步骤**，避免增加注册成本。蛋的孵化在进入首页后自然发生
- 可选：首次进入首页时通过 `PetDialogWidget` 显示一句引导文案，如"你的小伙伴还在蛋里，多记录餐盘帮它破壳吧"

---

## 3. 技术实现要点

### 3.1 技术栈与依赖

| 层级 | 技术 | 说明 |
|------|------|------|
| 框架 | Flutter 3.47.2 / Dart | 跨平台 UI |
| 状态管理 | provider | `ChangeNotifier` + `context.watch` |
| 路由 | go_router | `context.go('/home')` |
| 动画 | Flutter AnimationController | `SingleTickerProviderStateMixin` |
| 像素绘制 | `CustomPainter` | 16×16 网格，`isAntiAlias: false` |
| 测试 | flutter_test | Widget 测试 + 单元测试 |
| Android 原生 | Kotlin | 小组件（与本需求无直接关联） |

### 3.2 与现有系统的集成点

#### 集成点 1：AppState 暴露进化信号

**文件**：[app_state.dart](file:///d:/dev/canting/lib/state/app_state.dart)

**当前问题**：`saveMeal`（第 335-354 行）和 `tapPet`（第 239-251 行）调用 `_petEngine` 后，未读取 `result.previousGrowthStage`，进化信号被丢弃。

**建议修改**：
```dart
// 在 AppState 中新增字段
GrowthStage? _pendingEvolutionFrom;
GrowthStage? get pendingEvolutionFrom => _pendingEvolutionFrom;

// 在 saveMeal 中（第 340 行附近）
final result = _petEngine.onMealRecorded(...);
_pet = result.pet;
_dialogue = result.dialogue;
_pendingEvolutionFrom = result.previousGrowthStage;  // 新增

// 在 tapPet 中同理新增

// 新增方法供首页调用后清除
void clearPendingEvolution() {
  _pendingEvolutionFrom = null;
  notifyListeners();
}
```

#### 集成点 2：首页叠加进化动画

**文件**：[home_page.dart](file:///d:/dev/canting/lib/ui/home/home_page.dart)

**当前结构**：`HomePage` 是 `StatelessWidget`，直接返回 `Scaffold` + `ListView`。

**建议修改**：改为 `StatefulWidget`（或提取一个 `Widget`），用 `Stack` 包裹现有 `ListView`，根据 `state.pendingEvolutionFrom` 决定是否叠加 `EvolutionAnimationWidget`：

```dart
// 伪代码
Stack(
  children: [
    // 现有 ListView 内容
    ...,
    if (state.pendingEvolutionFrom != null)
      EvolutionAnimationWidget(
        petType: state.pet.petType,
        fromStage: state.pendingEvolutionFrom!.name,
        toStage: state.pet.growthStage.name,
        petName: state.pet.petName,
        onFinished: () {
          context.read<AppState>().clearPendingEvolution();
        },
      ),
  ],
)
```

#### 集成点 3：移除强制覆盖为 baby 的逻辑

**文件**：[app_state.dart](file:///d:/dev/canting/lib/state/app_state.dart)

**位置 1**：构造函数第 123-125 行
```dart
// 当前
_pet = _petEngine
    .createPet(petType: 'cat', petName: '小挑食')
    .copyWith(growthStage: GrowthStage.baby, growth: 68, vitality: 76);
// 改为
_pet = _petEngine.createPet(petType: 'cat', petName: '小挑食');
```

**位置 2**：`completeOnboarding` 第 222-224 行
```dart
// 当前
_pet = _petEngine
    .createPet(petType: petType, petName: petName.trim())
    .copyWith(growthStage: GrowthStage.baby, growth: 68, vitality: 76);
// 改为
_pet = _petEngine.createPet(petType: petType, petName: petName.trim());
```

#### 集成点 4：Onboarding 欢迎页展示蛋形态

**文件**：[onboarding_page.dart](file:///d:/dev/canting/lib/ui/onboarding/onboarding_page.dart) 第 254-258 行

```dart
// 当前
PetSpriteWidget(
  petType: 'cat',
  growthStage: 'baby',  // 改为 'egg'
  vitalityState: 'energetic',
  size: 92,
),
```

### 3.3 技术难点与建议方案

| 难点 | 说明 | 建议方案 |
|------|------|----------|
| 连续进化动画排队 | 若动画播放期间用户又触发一次进化（理论可能，如连续记录两餐），`pendingEvolutionFrom` 会被覆盖 | MVP 阶段接受覆盖（后一次进化动画覆盖前一次）。完整方案可用队列 `List<GrowthStage>` 存储，但非必要 |
| 无障碍模式跳过动画 | `MediaQuery.disableAnimationsOf(context)` 为 true 时应跳过 | `EvolutionAnimationWidget` 当前未处理此情况。建议在首页判断：若 `disableAnimations`，直接调用 `clearPendingEvolution` 而不渲染动画 |
| 测试数据注入 | 当前 `AppState` 构造函数硬编码了 mock 数据（meals、pet），测试不同进化阶段需要手动改代码 | 已有测试通过 `copyWith` 注入。开发时可临时修改构造函数的 `growth` 值观察动画 |
| 动画与 PetArea 重绘冲突 | 动画播放时底层 `PetSpriteWidget` 会因为 `growthStage` 变化而重绘，视觉上可能闪动 | `EvolutionAnimationWidget` 的半透明白色遮罩（0xEFFFFFFF）已足够遮挡底层，无需额外处理 |
| onboarding 完成后首次显示 | `completeOnboarding` 后 `context.go('/home')`，首页首次 build 时 `pendingEvolutionFrom` 为 null（新宠物是蛋，未进化） | 无需特殊处理。首次进化发生在用户记录餐食后 |

### 3.4 关键数据结构

**PetUpdateResult**（[pet_update_result.dart](file:///d:/dev/canting/lib/pet/pet_update_result.dart)）：
```dart
class PetUpdateResult {
  final PetData pet;
  final List<VitalityLog> logs;
  final int vitalityChange;
  final int growthChange;
  final String dialogue;
  final String? gapDialogue;
  final PetVisualReaction visualReaction;
  final ContinuousBehavior? continuousBehavior;
  final bool wasApplied;
  final GrowthStage? previousGrowthStage;  // 进化信号

  bool get shouldPlayEvolution => previousGrowthStage != null;
}
```

**GrowthStage 枚举**（[pet_data.dart](file:///d:/dev/canting/lib/pet/pet_data.dart) 第 1 行）：
```dart
enum GrowthStage { egg, baby, adult }
```

**EvolutionAnimationWidget 入参**（[evolution_animation_widget.dart](file:///d:/dev/canting/lib/pet/widgets/evolution_animation_widget.dart)）：
```dart
const EvolutionAnimationWidget({
  required this.petType,        // 'cat' | 'dog' | 'hamster'
  required this.fromStage,      // 'egg' | 'baby'
  required this.toStage,        // 'baby' | 'adult'
  required this.petName,        // 1-6 字符
  this.onFinished,              // 动画结束回调
})
```

---

## 4. 验收标准

### 4.1 进化动画接入首页

| 验收项 | 测试方法 | 期望结果 |
|--------|----------|----------|
| 蛋→幼年动画触发 | 临时设置 `growth: 49`，记录一餐高完成率餐食使 growth≥50 | 首页出现 2 秒全屏动画，显示蛋→幼年切换，文案"XX长大了！" |
| 幼年→成年动画触发 | 临时设置 `growth: 199`，记录一餐使 growth≥200 | 同上，显示 baby→adult 切换 |
| 动画结束后交互恢复 | 动画播放期间尝试点击首页按钮 | 动画期间按钮不可点击（IgnorePointer），结束后恢复 |
| 动画结束后状态清除 | 动画结束后检查 `pendingEvolutionFrom` | 为 null |
| 摸宠物触发进化 | `onPetTap` 使 growth 跨越阈值 | 动画播放 |
| 每日登录触发进化 | `onDailyLogin` 使 growth 跨越阈值 | 动画播放 |
| 无障碍模式 | 开启系统"移除动画"设置 | 不播放动画，直接更新宠物状态 |
| 单元测试通过 | `flutter test test/pet/evolution_animation_widget_test.dart` | 3 个测试全部通过 |
| 新增集成测试 | 编写 widget 测试验证首页动画叠加 | 动画 widget 出现在 widget 树顶层 |

### 4.2 新玩家从蛋开始

| 验收项 | 测试方法 | 期望结果 |
|--------|----------|----------|
| 新宠物初始为蛋 | 完成 onboarding 后检查 `state.pet.growthStage` | 为 `GrowthStage.egg` |
| growth 为 0 | 同上检查 `state.pet.growth` | 为 0 |
| vitality 为 60 | 同上检查 `state.pet.vitality` | 为 60 |
| 首页展示蛋形态 | 完成 onboarding 进入首页截图 | PetArea 显示蛋形像素画，标签"萌芽期" |
| onboarding 欢迎页展示蛋 | 启动到 onboarding 第一步截图 | 展示蛋形态而非 baby |
| 孵化后变为幼年 | 记录餐食使 growth≥50 | `growthStage` 变为 `baby`，触发进化动画 |
| 既有单元测试不受影响 | `flutter test` | 全部通过 |
| widget_test.dart 通过 | `flutter test test/widget_test.dart` | onboarding→home 流程测试通过（可能需要更新断言：期望"萌芽期"而非"幼年期"） |

### 4.3 性能要求

| 指标 | 要求 |
|------|------|
| 动画加载时间 | < 100ms（占位画即时绘制，无网络依赖） |
| 动画帧率 | 60fps（仅缩放 + 切换，负载极低） |
| 首页首帧渲染 | 无退化（进化动画 widget 仅在 `pendingEvolutionFrom != null` 时挂载） |

### 4.4 兼容性要求

| 平台 | 要求 |
|------|------|
| Android | minSdkVersion 及以上（与现有配置一致） |
| iOS | 与现有配置一致 |
| 横竖屏 | 均支持（`SizedBox.expand` + `Center` 自适应） |
| 深色模式 | 动画遮罩为白色半透明，深色模式下需验证可读性 |

---

## 5. 相关资源

### 5.1 代码模块

| 模块 | 文件路径 | 说明 |
|------|----------|------|
| 进化动画组件 | [evolution_animation_widget.dart](file:///d:/dev/canting/lib/pet/widgets/evolution_animation_widget.dart) | 已实现，待集成 |
| 进化动画测试 | [evolution_animation_widget_test.dart](file:///d:/dev/canting/test/pet/evolution_animation_widget_test.dart) | 3 个测试已通过 |
| 宠物状态机 | [pet_engine.dart](file:///d:/dev/canting/lib/pet/pet_engine.dart) | 进化逻辑在 `_applyEvolution` 第 506-539 行 |
| 宠物数据模型 | [pet_data.dart](file:///d:/dev/canting/lib/pet/pet_data.dart) | `GrowthStage` 枚举、`createPet` 工厂 |
| 更新结果 | [pet_update_result.dart](file:///d:/dev/canting/lib/pet/pet_update_result.dart) | `previousGrowthStage` + `shouldPlayEvolution` |
| 精灵图组件 | [pet_sprite_widget.dart](file:///d:/dev/canting/lib/pet/widgets/pet_sprite_widget.dart) | 支持蛋/baby/adult 三阶段 |
| 首页 | [home_page.dart](file:///d:/dev/canting/lib/ui/home/home_page.dart) | 集成点：需改 StatelessWidget → StatefulWidget |
| 首页宠物区 | [pet_area.dart](file:///d:/dev/canting/lib/ui/home/widgets/pet_area.dart) | 已支持蛋形态展示，无需修改 |
| 应用状态 | [app_state.dart](file:///d:/dev/canting/lib/state/app_state.dart) | 集成点：暴露进化信号 + 移除 baby 覆盖 |
| Onboarding | [onboarding_page.dart](file:///d:/dev/canting/lib/ui/onboarding/onboarding_page.dart) | 修改欢迎页展示蛋形态 |
| 对话气泡 | [pet_dialog_widget.dart](file:///d:/dev/canting/lib/pet/widgets/pet_dialog_widget.dart) | 可选：用于新玩家引导文案 |

### 5.2 资源文件

- 精灵图 PNG（可选）：`assets/sprites/pet_{type}_{stage}_{state}_{frame}.png`
- 像素画占位：代码内绘制，无需资源文件
- 设计稿：当前无独立设计稿，沿用现有像素风 UI 规范

### 5.3 参考文档

- [core_engine_api.md](file:///d:/dev/canting/docs/core_engine_api.md)：核心引擎 API 说明
- [ios_module_c_delivery_20260903.md](file:///d:/dev/canting/docs/ios_module_c_delivery_20260903.md)：iOS 小组件交付文档（参考其文档结构）

---

## 6. 进度与优先级

### 6.1 优先级

| 功能 | 优先级 | 依赖 |
|------|--------|------|
| 功能二：移除 baby 覆盖（让新宠物为蛋） | P0 | 无 |
| 功能一：AppState 暴露进化信号 | P0 | 无 |
| 功能一：首页叠加进化动画 | P0 | 上一项 |
| 功能二：onboarding 欢迎页展示蛋 | P1 | 功能二 P0 |
| 功能二：新玩家引导文案（可选） | P2 | 功能二 P0 |
| 功能一：无障碍模式跳过动画 | P1 | 功能一 P0 |

### 6.2 建议开发顺序

1. **第一步：移除 baby 覆盖**
   - 修改 `app_state.dart` 构造函数和 `completeOnboarding`
   - 运行 `flutter test` 确认既有测试通过（可能需更新 widget_test.dart 断言）
   - 模拟器验证首页显示蛋形态

2. **第二步：暴露进化信号**
   - 在 `AppState` 新增 `_pendingEvolutionFrom` 字段和 `clearPendingEvolution` 方法
   - 在 `saveMeal` 和 `tapPet` 中赋值 `result.previousGrowthStage`
   - 编写单元测试验证信号正确暴露

3. **第三步：首页叠加动画**
   - 将 `HomePage` 改为 `StatefulWidget`（或新增包裹 widget）
   - 用 `Stack` 叠加 `EvolutionAnimationWidget`
   - 临时注入 `growth: 49` 测试蛋→幼年动画
   - 临时注入 `growth: 199` 测试幼年→成年动画

4. **第四步：onboarding 展示蛋**
   - 修改 `_WelcomeStep` 的 `PetSpriteWidget.growthStage`
   - 验证完整注册流程

5. **第五步：无障碍与收尾**
   - 处理 `disableAnimationsOf` 跳过逻辑
   - 补充集成测试
   - 全量 `flutter test` 回归

### 6.3 依赖关系图

```
[移除 baby 覆盖] ──┐
                   ├──→ [首页叠加动画] ──→ [无障碍收尾]
[暴露进化信号] ───┘
                                          ↑
[onboarding 展示蛋] ──────────────────────┘
```

功能一和功能二可并行启动，但"首页叠加动画"依赖"暴露进化信号"完成，且完整体验依赖"移除 baby 覆盖"完成。

---

## 7. 版本历史

| 版本 | 日期 | 修改内容 | 作者 |
|------|------|----------|------|
| v1.0 | 2026-09-03 | 初始版本，基于代码现状完成需求分析与实现规划 | 谷笑宇 + AI |

---

## 附录 A：已知待决问题

1. **进化文案个性化**：当前所有进化统一显示"XX长大了！"，蛋→幼年是否需要"XX破壳而出！"等差异化文案？待产品确认。
2. **widget_test.dart 断言更新**：[widget_test.dart](file:///d:/dev/canting/test/widget_test.dart) 可能断言了首页出现"幼年期"文案，移除 baby 覆盖后需更新为"萌芽期"。开发时需检查。
3. **连续进化排队**：MVP 接受覆盖策略，后续若用户反馈丢失体验，再引入队列。
4. **深色模式遮罩**：动画遮罩 `Color(0xEFFFFFFF)` 为白色半透明，深色模式下可能过亮，需视觉验证。
