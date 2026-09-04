# 夜间自动开发进度 · A线（餐食记录与首页展示）

> A线范围：模块 6（餐食记录）、模块 8（推荐详情/外卖跳转）、模块 15（手动添加）、模块 5（首页）。
> B线并行开发中，共享文件（app_state.dart / main.dart / core_engine.dart）只做增量修改。
> 更新时间：2026-09-04 凌晨

## 任务1 · 模块6 餐食记录 — ✅ 完成

状态：完成
新增测试数：10（test/data/meal_record_flow_test.dart，全过）

### 现状判断（先读后补，未重做）
- MealRepository 的单日查询 / 日期范围查询 / 增删改查在模块01/04时已基本完成，本次只补：备注列（note）与来源（source）写入 + getNote 读取。
- 分量系数（小0.8/常规1.0/大1.3）此前只存在于 DishMatcher.calculatePortions，记录端从未应用（旧代码存零份数+假完成度）。本次在 AppState.buildMealRecord 统一接线。

### 改动文件
- lib/state/app_state.dart（共享，增量）：
  - 新增 `FoodDatabase? _foodDatabase`（_refreshDishMatcher 装配）。
  - 新增 `buildMealRecord()`：DishMatcher 匹配 → 分量系数 → 真实完成度（CompletionCalculator），已带份数的菜（手填）不覆盖。
  - 新增 `completionFor(date)`：当日真实完成度（替代静态 Mock 的正式入口）。
  - `saveMeal()`：宠物引擎的当日结构从静态 Mock 改为真实计算；新增 note/source 参数透传。
  - `deleteMeal()`：活力值回退从「固定-2」改为按该餐记录时的 `PetStateMachine.vitalityChangeForCompletion` 反向回退（0~100 钳位）；成长值不回退（只增不减）。
- lib/data/meal_repository.dart：addMeal/updateMeal 增加 note/source 可选参数；note 写独立列，source 作为扩展键写进 record_json（MealRecord.fromJson 忽略未知键，向后兼容）；新增 `getNote()`。
- lib/ui/record/record_detail_page.dart：移除 Mock 默认菜（鸡肉杂粮饭/清炒西兰花）与假商家、假完成度；保存走 buildMealRecord；商家改为选填；OCR 来源标记 source='ocr'，手动标记 'manual'。
- lib/ui/record/dish_edit_list.dart：文案「正常」→「常规」（与模块06文档一致）。
- test/data/meal_record_flow_test.dart（新文件）：10 个测试，覆盖分量系数两端一致、真实完成度、活力回退+成长不回退、删最后一条、跨日期添加、同餐重复添加、备注/来源落库。

### 边界覆盖
- 跨日期添加：saveMeal 按时间戳落对应日缓存与库表（有测试）。
- 同餐重复添加：不同 mealId 各自成条（有测试）。
- 删除当日最后一条：当日缓存与库表同时清空，完成度归零（有测试）。

### 遗留问题
1. ⚠️ test/widget_test.dart 的「saving a recognized meal returns to home」依赖旧版 Mock 默认菜（打开页面直接保存即有 2 道示例菜）。按任务要求移除 Mock 并加「至少一道菜」校验后，该测试不再成立。widget_test.dart 属禁改文件，未动；建议白天修复：在该测试里先通过添加菜品对话框加一道菜再保存（保留原断言强度）。其余断言（返回首页/记录数+1/snackbar）语义不变。
2. 记录详情页「添加菜品」对话框里的三条固定建议菜仍是静态文案（蒜蓉西兰花等），计划任务3接入真实搜索后替换。
3. 备注已落库（meal_records.note），记录详情页暂无备注展示/编辑 UI（模块06文档的备注编辑栏），待补。

### 门槛结果（任务1完成时）
- flutter analyze：A线文件 0 问题。
- flutter test 全量：+178 通过 / -5 失败，失败项全部位于 B线 文件（test/ui/settings/profile_edit_page_test ×4；widget_test 1 条见遗留1）+ test/state/app_state_settings_test.dart 为 B线 编译期错误（时有时无，B线在改）。

## 任务2 · 模块8 推荐详情页与外卖跳转 — ✅ 完成

状态：完成
新增测试数：15（delivery_jump_service_test.dart 12 个 + recommendation_state_test.dart 3 个，全过）

### 改动文件
- lib/services/delivery_jump_service.dart（新）：
  - 四平台：美团外卖（meituanwaimai://）、美团（imeituan://）、饿了么（eleme://）、京东外卖（openapp.jdmobile://），H5 兜底链接与模块08文档一致。
  - 跳转逻辑：canLaunch(scheme) → externalApplication 拉起；未安装或拉起失败 → H5 兜底；返回 DeliveryJumpResult（实际用的链接 + 是否兜底）。
  - 平台配置做成可注入接口 `DeliveryPlatformConfigStore`（loadOrderedPlatformIds / saveOrderedPlatformIds 签名留好）；今晚用 DefaultDeliveryPlatformConfig（全启用、固定优先级）。SharedPreferences 持久化与设置页 UI 为遗留项。
  - canLaunch/launch 可注入（测试用假实现）。
- lib/ui/recommendation/recommendation_detail_page.dart（重写，去 Mock）：
  - 数据源改为 AppState.recommendationFor（RecommendationEngine 结果）；顶部：建议时间 + 餐次 + 缺口说明（"今天蔬菜还差 1.5 份"，按真实 completionFor 计算）+ 推荐理由。
  - 主推 1 道 + 备选 2 道（主推带「主推」角标）；「换一批」/「不感兴趣」= 排除已展示菜名再取一批（补足到 3 道）；池子耗尽时给「重新开始推荐」。
- lib/ui/recommendation/recommended_dish_card.dart（新）：菜名 + 分类/油量标签 + 平台按钮组。
- lib/ui/recommendation/platform_buttons.dart（新）：品牌色按钮组，最多 3 个（文档口径）。
- lib/state/app_state.dart（共享，增量）：新增 `recommendationFor(date, {excludeDishNames})`——引擎结果 + 换一批排除补位逻辑（与引擎同口径的缺口排序补位）；配合任务1新增的 `_foodDatabase`。
- android/app/src/main/AndroidManifest.xml：`<queries>` 补四个 scheme 的 VIEW intent 声明。

### 美团跳转失效 Bug 修复（已知 Bug 重点修复）
根因两个，都已修：
1. scheme 用错：旧代码用 `meituan://waimai.meituan.com/search`，美团外卖实际是 `meituanwaimai://`、美团 APP 是 `imeituan://`。
2. Android 11+ 包可见性：manifest 没有 `<queries>` 声明时 canLaunchUrl 对这些 scheme 恒返回 false，永远走不到已安装分支。
另注意：Dart Uri 会把 scheme 归一化为小写，且 Android scheme 匹配区分大小写，京东 scheme 必须写小写 openapp.jdmobile（manifest 与 Dart 两端一致）。

### 门槛结果（任务2完成时）
- flutter analyze 全项目：No issues found!（B线此前的 settings 报错已被对方修复）
- flutter test 全量：+197 / -1，唯一失败仍是遗留1（widget_test 依赖已删除的 Mock 默认菜，禁改文件）。

### 遗留问题
4. 平台启用/顺序的 SharedPreferences 持久化 + 设置页 UI（接口已留好，注入即可用）。
5. 京东外卖 params 里的 des=searchMall 是按京东开放文档通用搜索跳转写的，真机行为需在白天验证（模拟器上无外卖 APP，只验证了 H5 兜底分支）。

## 任务3 · 模块15 手动添加餐食 — ✅ 完成

状态：完成
新增测试数：9（test/data/manual_add_flow_test.dart，全过）

### 改动文件
- lib/ui/manual_add/manual_add_page.dart（新）：
  - 简单模式：餐次（默认按当前小时）→ 搜索 → 分量（小/常规/大）→ 添加；空结果时可直接用输入的菜名。
  - 详细模式：克重↔份数双向联动（两个输入框互算）、菜品分类下拉、标记「自制」、备注。
  - 添加后经 buildMealRecord + saveMeal 落库（source='manual'，备注进 note 列），并刷新当日数据；随后 registerManualDish 登记数据飞轮。
- lib/state/app_state.dart（共享，增量）：
  - `searchDishesForManualAdd(query)`：自定义菜在前（按使用次数降序），标准菜在后，同名去重。
  - `manualDishUsage(name)` / `registerManualDish(...)`：新菜名写入 user_custom_dishes；标准库命中的菜复制成「用户名字」的副本（别名清空，避免遮蔽标准菜匹配）；累计使用次数；记住分量偏好。
  - `resolveManualServings` / `resolveManualGrams` + `ManualServingLink`：详细模式克重↔份数三级依据（食物交换份精确换算 → 匹配菜品正常份缩放 → 分类平均结构兜底）；奶/坚果交换食物不进六类目标（与 IntakeCalculator 口径一致）。
  - `dishCategories` getter（分类下拉数据源）。
- lib/data/custom_dish_repository.dart：`CustomDishUsage`、`getUsageByName`、`usageCountsByName`、`upsertDishWithMeta`（使用次数/分量偏好存 json_data 扩展键，不影响 StandardDish.fromJson）、`getNote` 复用任务1的 note 通道。
- lib/router/app_router.dart：新增 `/manual_add` 路由。
- lib/ui/record/record_detail_page.dart：「添加菜品」对话框的三条静态建议菜替换为实时搜索（复用 searchDishesForManualAdd，自定义优先）——遗留2 关闭。

### 本地偏好（分量记忆）
- 搜索结果点选某道菜时读 `manualDishUsage`，用户上次用的分量自动成为默认值；纯本地存储（user_custom_dishes.json_data 扩展键），不上传。

### 门槛结果（任务3完成时）
- A线文件 flutter analyze：0 问题。
- flutter test 全量：+233 / -1（widget_test 加载失败）。
- ⚠️ 全项目 analyze 出现 12 个 error，全部位于 B线 独占的 lib/ui/history/history_page.dart（day_detail 组件签名重构到一半，vitalityColor/dailyIntake 等未定义）；按并行规则未修未回滚，等 B线 完成自愈。widget_test 的加载失败与该编译错误相关（历史页被路由引用）。

### 遗留问题
6. 详细模式下，标准库命中菜的「用户手填克重」只影响当餐记录的份数；自定义副本里的份量偏好仅记分量档位（small/normal/large），未记克重中位数（模块15的 V1.0 个人级优化的完整版，白天可加）。
7. 混合菜品拆分（西红柿鸡蛋面拆食材）按文档放到 V1.1，未实现。

## 任务4 · 模块5 首页（接线去 Mock） — ✅ 完成

状态：完成
新增测试数：5（test/ui/home_page_real_test.dart widget 测试，全过）

### 改动文件
- lib/ui/home/home_page.dart：
  - `AppState.completion` 静态 Mock → `state.completionFor(now)`（真实摄入 vs IntakeCalculator 目标）。
  - 推荐卡片 → `state.recommendationFor(now)`（RecommendationEngine 真实结果）。
  - 进度列表增加真实摄入/目标份数（eaten = 当日记录份数和，target = dailyIntake.portions）。
  - 底部「+」FAB：弹出选择 手动添加（→ /manual_add）/ 截图识别（占位，Snackbar 提示 Phase 4 开放）；AppBar 原「添加一餐」入口保留（OCR/分享识别流程与旧测试依赖）。
  - 空状态「手动添加」按钮改指 /manual_add。
  - 宠物区不动（本就绑定真实 state.pet）。
- lib/ui/home/widgets/recommendation_card.dart：由静态文案改为接收 `Recommendation?`，展示真实建议时间/餐次、主推缺口标题（"补一补蔬菜"）、引擎理由；recommendation 为 null 时显示准备中文案。
- lib/ui/home/widgets/food_progress_list.dart：新增可选 `current`/`target`（Portions），每行显示「2.5/4份」真实摄入/目标份数；旧调用方（仅 values）向后兼容。
- test/ui/home_page_real_test.dart（新）：5 条 widget 测试——空状态+0 完成度+0/5份、记录后实时刷新（日志出现菜名、2/5份、40%）、FAB 弹层、截图识别占位提示、手动添加入口、推荐卡片→详情页（真实引擎结果）。测试用真实种子数据（assets/data 基准）+ 内存库，走完整链路。

### 数据刷新机制
- Provider `context.watch<AppState>`：saveMeal/deleteMeal 后 notifyListeners → 首页环形图/进度条/日志/小结全部重建；跨日切换由 mealsFor 的懒加载兜底。

### 门槛结果（任务4完成时 = 最终门槛）
- flutter analyze 全项目：No issues found!（B线 history 页的 12 个报错已被对方修完）。
- flutter test 全量：+255 / -1。唯一失败 = 遗留1（widget_test「saving a recognized meal」依赖已删除的 Mock 默认菜，断言"空页面直接保存应返回首页"，与新校验「至少一道菜」冲突；该文件禁改，已在前文给出修复建议）。

## 最终汇总

| 任务 | 状态 | 新增测试 |
|------|------|----------|
| 任务1 模块6 餐食记录 | ✅ 完成 | 10 |
| 任务2 模块8 推荐详情+外卖跳转 | ✅ 完成 | 15 |
| 任务3 模块15 手动添加 | ✅ 完成 | 9 |
| 任务4 模块5 首页去 Mock | ✅ 完成 | 5 |

- 新增测试合计 39 条，全部通过；旧测试未删除、未跳过、未弱化断言。
- 新增依赖：0（任务要求禁加，也确实没加）。
- 需白天处理：遗留1（widget_test 补一步"添加菜品"）、遗留4（平台配置持久化+设置页 UI）、遗留5（京东外卖真机验证）、遗留6/7（手动添加深度优化）。

