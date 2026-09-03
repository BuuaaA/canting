# 餐盘APP MVP 缺失模块分析

> 生成时间：2026-09-03
> 基于代码 commit 986660a + 用户实际测试反馈

## 当前项目状态

5个模块（核心引擎层、UI层、宠物系统、iOS原生层、Android原生层）全部开发完成，102项测试通过。但属于"演示版"——功能能跑，但关掉就重置，推荐是写死的，跳转是坏的。

## 用户实测发现的6个问题

### 问题1：个人信息不可修改（P0）

- 现状：`settings_page.dart` 的"身体数据/饮食目标/活动量/作息习惯"4个入口点击后只弹出只读对话框（`_showInfoDialog`），只有"知道了"按钮
- `AppState.profile` 是 `SetupProfile?`，没有 `updateProfile()` 方法
- 修复：
  1. 新建 `lib/ui/settings/profile_edit_page.dart`，复用 onboarding 的 step1-step4 组件
  2. `AppState` 添加 `updateProfile(SetupProfile newProfile)` 方法
  3. 改完后 DailyIntake 和 CompletionResult 要重新计算（目前是 `static const` 硬编码）
- 工作量：中等（2-3h）

### 问题2：美团跳转失败（P0）

- 现状：`recommendation_detail_page.dart` 第19-25行 URI scheme 用的是 `meituan://waimai.meituan.com/search?keyword=xxx`
- 正确的 scheme：
  - 美团外卖APP：`meituanwaimai://waimai.meituan.com/search?query=xxx`
  - 美团主APP：`imeituan://www.meituan.com/search?q=xxx`
- 修复：scheme 从 `meituan` 改成 `meituanwaimai`，query参数名从 `keyword` 改成 `query`
- 工作量：小（10min）

### 问题3：外卖平台区分（P0）

- 现状：只有"美团"和"饿了么"两个按钮
- 需要支持的平台：

| 平台 | Scheme | 完整 URI |
|------|--------|----------|
| 美团外卖 | meituanwaimai | `meituanwaimai://waimai.meituan.com/search?query={keyword}` |
| 美团APP | imeituan | `imeituan://www.meituan.com/search?q={keyword}` |
| 淘宝闪购（原饿了么） | eleme / taobao | `eleme://search?keyword={keyword}` |
| 京东外卖 | openApp.jdMobile | `openApp.jdMobile://virtual?params={json}` |

- 建议方案：做成可配置的平台列表，设置页选择常用平台，推荐页只显示选中的。未安装APP时 fallback 到 H5 网页
- 工作量：中等（3-4h）

### 问题4+5：无数据库 + 数据无法持久化（P0）

- 现状：
  - `DatabaseHelper` 只有 categories + dishes 两张表（菜品目录）
  - 用户数据、餐食记录、宠物状态全部是内存 `MockMeal`/`MockDish`
  - `AppState` 构造函数硬编码了两条假餐食
  - APP 关闭后所有状态重置
- 修复：
  1. SQLite 新增3张表：`user_profiles`、`meal_records`、`pet_states`
  2. 新建 `lib/data/user_repository.dart`、`meal_repository.dart`、`pet_repository.dart`
  3. `AppState` 改造：构造时从 SQLite 加载，`saveMeal()`/`deleteMeal()`/`completeOnboarding()` 同步写库
  4. 简单设置用 `SharedPreferences`（`shared_preferences` 包）
  5. 删除 `MockMeal`/`MockDish`，替换为真实 `MealRecord`/`MealDish`
  6. `main.dart` 的 `main()` 里异步初始化数据库
- 工作量：大（6-8h）

### 问题6：没有 OCR 识别系统（P1）

- 现状：
  - iOS：`OCRService.swift` 用 Vision 框架，已实现
  - Android：method channel `com.canting.app/ocr` 已定义，但原生端没有实现
  - 只能通过系统分享菜单触发，没有 APP 内拍照/选图流程
- 修复：
  1. Android 原生 OCR：Google ML Kit Text Recognition（免费离线）或百度智能云 OCR
  2. APP 内拍照/选图：添加 `image_picker` 依赖，记录页增加"拍照识别"和"相册选图"入口
  3. OCR 文本 → `DishMatcher` 菜品匹配
  4. 识别结果可手动修正
- 工作量：大（8-12h）

## 代码审查额外发现

### 额外7：营养计算全是硬编码（P1）

- `AppState` 第173-196行的 `dailyIntake` 和 `completion` 是 `static const`
- 项目有 `IntakeCalculator` 和 `CompletionCalculator`，但完全没接上
- 用户改了身高体重，推荐和完成度不变
- 工作量：2-3h

### 额外8：推荐菜品写死3道菜（P1）

- `RecommendationDetailPage` 第8-12行硬编码：蒜蓉西兰花、香菇青菜、鸡胸肉时蔬碗
- `RecommendationEngine` 已实现但没调用
- 工作量：2h

### 额外9：本地通知未实现（P1）

- 设置页有"用餐提醒"和"缺口提醒"开关，只存 boolean
- 没有 `flutter_local_notifications` 或 iOS `UNUserNotificationCenter` 调度代码
- 工作量：3-4h

### 额外10：数据导出不完整（P2）

- JSON 导出能用，CSV 是占位符
- 无数据导入/恢复功能
- 工作量：2h

## 优先级与开发顺序

### 第一波：让APP基本可用

| 序号 | 任务 | 工时 |
|------|------|------|
| 1 | 修美团跳转 scheme（1行代码） | 10min |
| 2 | 数据持久化（SQLite三张表 + SharedPreferences） | 6-8h |
| 3 | 个人信息编辑页 + `updateProfile()` | 2-3h |
| 4 | 外卖平台扩展（美团外卖/美团APP/淘宝闪购/京东外卖 + fallback H5） | 3-4h |

### 第二波：让推荐和计算真正工作

| 序号 | 任务 | 工时 |
|------|------|------|
| 5 | 接入 IntakeCalculator 替换硬编码 dailyIntake | 2-3h |
| 6 | 接入 RecommendationEngine 替换硬编码3道菜 | 2h |
| 7 | 本地通知（flutter_local_notifications） | 3-4h |

### 第三波：核心卖点功能

| 序号 | 任务 | 工时 |
|------|------|------|
| 8 | Android 原生 OCR（ML Kit 或百度OCR） | 8-12h |
| 9 | APP 内拍照/选图 → OCR → 菜品匹配流程 | 含在8内 |
| 10 | 数据导入/CSV导出 | 2h |

## 关键文件清单

需要修改/新建的文件：

```
lib/state/app_state.dart              — 改造：删除Mock类，接入持久化，添加updateProfile()
lib/data/database_helper.dart         — 扩展：新增user_profiles/meal_records/pet_states表
lib/data/user_repository.dart         — 新建
lib/data/meal_repository.dart         — 新建
lib/data/pet_repository.dart          — 新建
lib/ui/settings/settings_page.dart    — 改造：个人信息入口改为跳编辑页
lib/ui/settings/profile_edit_page.dart — 新建
lib/ui/recommendation/recommendation_detail_page.dart — 改造：deep link + 接入RecommendationEngine
lib/platform/android_native_bridge.dart — 已有，OCR原生实现缺失
android/app/src/main/.../OcrActivity.kt — 新建：ML Kit OCR实现
pubspec.yaml                          — 添加 shared_preferences, image_picker
```
