# 餐盘 V1 基线冻结与交接审计报告

- **日期**：2026-09-05（凌晨审计，会话期间 01:58 起仅本报告写入 dev-docs/）
- **性质**：只读审计 + 交接资料整理。未修改任何业务源代码、数据文件；未 commit、未 push、未 reset。
- **HEAD**：`bcae4e1`（V1.0 Phase4+小项：OCR识别系统收尾与遗留清尾，2026-09-04 15:08）
- **分支**：`main`，领先 `origin/main` 3 个提交（`a3ec00` Phase1 基线 → `cb26a3c` Phase2-3 → `bcae4e1` Phase4），均未推送。

## 1. 当前结论

**完成。** 工作树处于「双线开发完成、集成提交未做」状态：A 线（菜库蒸馏）与 B 线（滚动平衡引擎）的全部改动均已在位且自洽，`flutter analyze --no-pub` 零问题，`flutter test --no-pub` **340/340 全过**（本环境重新验证，非引用旧报告）。工作树可安全冻结，等待产品经理确认提交拆分方案。

## 2. 并行会话冲突检查

- 最后一次源代码写入：2026-09-04 23:48（测试文件）。01:41–01:46 仅有任务书/路线图文档与构建产物写入（任务准备动作），审计会话期间无第三方写入。
- 常驻 dart 进程 5 个（语言服务器 VS-Code 客户端、tooling-daemon、devtools、flutter_tools daemon、dartvm），启动于 09-04 22:48，均为 IDE 分析服务，**非写会话**，不影响冻结。
- 结论：**无活跃写进程，本阶段可继续，未触发停止条件。**

## 3. Git 基础命令结果

| 命令 | 结果 |
|---|---|
| `git status --short --branch` | `main...origin/main [ahead 3]`；16 个已跟踪文件 M，12 个未跟踪路径 |
| `git diff --stat` | 16 文件，+34,809 / −809（其中 dishes.json 占 +33,590） |
| `git diff --check` | 无空白错误、无冲突标记（仅 CRLF→LF 换行提示，见风险 R4） |

## 4. 当前功能矩阵（以代码与测试为准）

| 模块 | 实现要点（代码证据） | 状态 |
|---|---|---|
| 初始设置 | 6 步 onboarding → `IntakeCalculator.calculate(guidelines:)` 五档 TDEE 线性插值 → `user_profiles` 落库（daily_intake_json 快照） | ✅ |
| 食物数据库 | dishes.json schema v2 **1004 道**（recommendable 707/297，estimated 1001）；`FoodDatabase.fromJson` 双格式兼容 | ✅ |
| 菜品匹配 | DishMatcher 四级管线：自定义精确 → 标准精确 → 包含/模糊（0.8）→ 关键词 0.5；归一化统一入口 | ✅ |
| 份量估算 | ServingEstimator 交换份两级换算（中英文映射表 → 分类克重兜底） | ✅ |
| OCR 识别 | 分享 + APP 内拍照/相册共用 `OcrPipeline`；原生 **ML Kit 中文识别**（`text-recognition-chinese:16.0.1`，Kotlin OCRService）；5s 超时降级手动添加 | ✅（真机 E2E 已过 09-04） |
| 餐食记录 | 手动添加/识别保存、备注编辑、删除回退活力值收敛；source/confidence 可解释链路 | ✅ |
| 下一餐推荐 | 引擎 v2：槽位制（≤3 槽、缺口>0.15）、light 模式硬排除 fried/high_sodium、欠账还债/盈余反馈 ±30% 限幅、whole_grain×1.3/light×1.2/fried×0.6、油脂当日预算、`recommendable=false` 永不推荐、候选耗尽出「XX类候选不足」提示 | ✅ |
| 7 天滚动台账 | `BalanceLedger`：盈余衰减 50%/日、欠账 20%/日、当日净额先对冲反向结转、**无记录日=无信息**；30 天仿真收敛断言在引擎测试 | ✅ |
| 膳食指南数据 | dietary_guidelines.json 新增 weekly_targets / whole_grain / added_sugar / weekly_balance / oil_salt_limits 五区块（旧 JSON 兼容解析） | ✅ |
| 宠物 | 活力值 3 天重算 + clamp[15,100]、成长/进化、日常台词 + 滚动台账台词（盈余/欠账趋势） | ✅ |
| 历史 | 日历月视图、日详情、周统计 | ✅ |
| 通知 | 保存成功通知 + 用餐/缺口提醒；三开关落盘（shared_preferences） | ✅ |
| 设置 | 个人资料、宠物改名、外卖平台开关+排序（落盘）、数据管理、关于 | ✅ |
| 外卖跳转 | DeliveryJumpService 按用户配置顺序跳转 | ✅ |
| 离线承诺 | AndroidManifest **仅有 POST_NOTIFICATIONS 权限，无 INTERNET**；无遥测/云上传依赖 | ✅ 已验证 |
| 包体 | dishes.json 625KB / guidelines 10KB，1004 道 < 5000 道懒加载阈值，无需改 FoodDatabase | ✅ |

## 5. 未提交文件归属与目的（逐文件）

### A 线：数据蒸馏与迁移（归属：菜库蒸馏会话）

| 文件 | 状态 | 目的 |
|---|---|---|
| `assets/data/dishes.json` | M | 29 → 1004 道，schema v2 信封（+33,590 行，625KB）。5 道 nutridata 真实样例 + 999 道菜谱估算（estimated=true 共 1001）。**未导入 25,668 条 Nutradata 原始数据**（原始 xlsx 本就不在 nutridata 仓库） |
| `lib/core/models/food_data.dart` | M | StandardDish + `recommendable` / `qualityTags` / `estimated` 三字段，defensive 解析（缺字段给默认值），序列化同步 |
| `lib/data/food_database.dart` | M | fromJson 兼容 v1 裸数组 / v2 信封；`schemaVersion` 字段驱动播种 |
| `lib/data/database_helper.dart` | M | DB v2→v3：`app_meta` 表 + `seed_schema_version` 键；`syncSeedCatalog` 按 dish_id 增量 upsert（不删旧行、不动用户表）；initialize 改版本驱动 |
| `test/data/dishes_schema_test.dart` | 新 | 11 用例：全量 schema 校验、recommendable=true 零违例、无全零份数、垃圾食品抽查、杂粮标签抽查 |
| `test/data/seed_migration_test.dart` | 新 | 4 用例：旧库升级、旧库独有菜保留、同版本幂等、meta 丢失重同步 |
| `test/fixtures/legacy_dishes_29.json` | 新 | 迁移测试夹具（旧 29 道库快照） |
| `dev-docs/distill-validation.md` | 新 | 20 道交叉校验报告（20/20 ≤30%，最大 16.6%） |
| `dev-docs/distill-acceptance-report_20260904.md` | 新 | A 线验收报告（8/8 通过） |

### B 线：膳食指南重蒸馏 + 滚动平衡引擎（归属：引擎会话）

| 文件 | 状态 | 目的 |
|---|---|---|
| `assets/data/dietary_guidelines.json` | M | +75 行五区块：weekly_targets（5 能量档×6 类周目标）、whole_grain、added_sugar（不追踪）、weekly_balance（衰减参数）、oil_salt_limits |
| `lib/core/models/dietary_guidelines.dart` | M | +204 行对应模型（WeeklyTargets/WholeGrainRequirement/AddedSugarGuidance/WeeklyBalanceConfig/OilSaltLimits），旧 JSON 缺区块可解析 |
| `lib/core/balance_ledger.dart` | 新 | BalanceLedger/BalanceReport/CategoryBalance：7 天滚动盈亏，纯函数注入 now |
| `lib/core/intake_calculator.dart` | M | +`weeklyTargetFromDaily`（单日目标 × 7） |
| `lib/core_engine.dart` | M | re-export balance_ledger |
| `lib/core/recommendation_engine.dart` | M | 引擎 v2（+340 行）：槽位制、light 模式、双向台账修正、质量排序、油脂预算、excludeDishNames 移入引擎、温和文案规则 |
| `lib/core/models/recommendation.dart` | M | DishSuggestion + slotCategory/servings/note；Recommendation + balanceMode；BalanceMode 常量 |
| `lib/ui/recommendation/recommended_dish_card.dart` | M | 推荐卡展示建议份数与提示语（「清淡模式：主食小份」等） |
| `lib/pet/pet_engine.dart` | M | +`rollingBalanceDialogue`（按台账趋势生成气泡台词，空串回退日常台词） |
| `lib/state/app_state.dart` | M | +`_balanceReport`/`refreshBalanceLedger`（启动/saveMeal 后重建，查询失败保留旧台账）；recommendationFor 直传台账+排除集（删除旧补位循环）；_dailyDialogue 优先滚动台词 |
| `test/core/balance_ledger_test.dart` | 新 | 12 用例：衰减曲线、对冲结转、空白天、跨窗口滑动 |
| `test/data/dietary_guidelines_test.dart` | M | +6 用例：五区块解析、周目标=日×7、旧 JSON 兼容 |
| `test/core/recommendation_engine_test.dart` | M | 全量重写（915 行）：自造 fixture 库不依赖 dishes.json；属性测试（垃圾食品永不出现）、30 天随机仿真收敛（±20%，第 20 天起断言） |
| `test/state/recommendation_state_test.dart` | M | 「换一批」断言更新（槽位/份数非空；原因文案确定性断言下沉引擎层） |
| `test/pet/pet_rolling_dialogue_test.dart` | 新 | 6 用例：滚动台词分支 |

### 文档 / 指令（归属：产品经理 / 双会话调度）

| 文件 | 状态 | 说明 |
|---|---|---|
| `AGENTS.md` | 新（未跟踪） | 项目级长期指令。**建议随基线提交入库**（当前所有 Agent 依赖它却不在版本控制内） |
| `双会话指令_菜库蒸馏与引擎重造.md` | 新（未跟踪） | 双会话任务书 + 集成收尾指令（历史过程文档） |
| `dev-docs/canting_V1_roadmap_and_prompts_20260905.md` | 新（未跟踪） | 2026-09-05 V1 路线图与提示词 |
| `dev-docs/0905-Q3路线图.html` | 新（未跟踪） | Q3 路线图 HTML 版 |

**无「看不懂但先一起提交」的文件**：每个未提交文件均已归属到 A 线 / B 线 / 文档三组之一。

## 6. 文档 vs 代码：过时事实清单（只列出，不修改）

以代码与测试为准（AGENTS.md §12），以下为已证实的过时陈述：

| 位置 | 过时陈述 | 当前事实 |
|---|---|---|
| `餐盘_APP_PRD_V1.0.md`（多处：§技术栈、§3.7.2/3.7.3、验收标准 4/18、风险 2/9） | 双端首发（iOS 15 + Android）、iOS Vision OCR、Android PaddleOCR Lite、包体积 iOS<80MB | **Android 单端**；OCR 为 ML Kit 中文识别（Kotlin `OCRService.kt`，gradle `text-recognition-chinese:16.0.1`）；无 iOS 工程 |
| `餐盘_APP_PRD_V1.0.md` | 双端 OCR 方案 / Vision+PaddleOCR | PaddleOCR 方案已被否决（dev-docs/README.md 已注明），沿用 MVP 的 ML Kit |
| `README.md` L31 | 「当前餐食数据为 mock 数据，菜品识别等功能尚未接入」 | 持久化（SQLite v3）、OCR、推荐引擎全部已接入；mock 类已删除 |
| `README.md` L51 | iOS 版本（路线图） | V1 明确不做 iOS（AGENTS.md §3） |
| `docs/mvp-gap-analysis-20260903.md` | MockMeal/MockDish、iOS OCRService.swift Vision 已实现 | 历史文档，描述 09-03 演示版状态，已全部被 Phase1-4 改造取代 |
| `dev-docs/module-11-ios-ocr.md` | iOS 分享扩展 + Vision OCR 模块 | V1 范围外（README 中标「待开发，需 Mac」）；`module-12-android-ocr.md` 中 PaddleOCR 方案同样已过时（实际 ML Kit） |

## 7. 测试证据（本环境实测）

```
flutter analyze --no-pub
→ Analyzing canting... No issues found! (ran in 4.8s)

flutter test --no-pub
→ 00:10 +340: All tests passed!
```

- 测试总数 340，与最近一次独立验证一致，全部通过，无失败、无跳过、无豁免。
- 本轮新增测试合计 39 个：balance_ledger 12 + dishes_schema 11 + seed_migration 4 + pet_rolling_dialogue 6 + dietary_guidelines 6。
- 命令执行环境：Windows，C:\flutter，工作树即审计时快照。

## 8. 已知风险

| # | 风险 | 说明与建议 |
|---|---|---|
| R1 | **工作树未冻结保护** | 双线改动全部未提交，历史上发生过并行会话互相覆盖丢失改动（project_memory 有两次记录）。建议尽快按 §9 拆分提交完成冻结 |
| R2 | 30 天仿真为随机种子测试 | 依赖 `Random(42)` 固定种子，收敛断言窗口第 20–23 天。引擎参数再调可能需重调种子；参数变更须记录在提交说明 |
| R3 | dishes.json 无尾随换行 | 文件末尾缺 `\n`，未来编辑会产生整行 diff 噪音。可在提交前顺手补（1 字符，无逻辑影响，需 PM 同意） |
| R4 | CRLF 换行警告 | 13 个文件 LF→CRLF 提示，属仓库 autocrlf 行为，非内容问题；不影响测试。如要消除需统一 .gitattributes，本阶段不动 |
| R5 | 集成收尾测试未单独落盘 | 双会话指令第 3 步要求的「场景回归集成测试 a–e」没有独立集成测试文件。a（垃圾食品不出现）/b（Day1→Day5 模式切换）/e（杂粮饭>白米饭）已被引擎测试覆盖；**c（换一批标签=菜品自身主导分类）与 d（水果缺口最大时水果首推）无直接断言**，逻辑存在于引擎（`_suggestionFor` 用 `_primaryNutrient(dish)`），属覆盖缺口而非功能缺陷 |
| R6 | 真机验收项未闭环 | 通知真机验证、京东外卖跳转真机验证仍未执行（Phase4 报告遗留，本审计只验单测/widget 层） |
| R7 | 数据精度天花板 | 1001/1004 道为菜谱估算（estimated=true），钠为推算值；这是既有设计决策（`estimated` 贯穿模型/测试），非缺陷，但对外解释口径需保持「粗粒度估算」 |

## 9. 提交拆分建议（供产品经理选择，本审计不执行）

**方案一（推荐，符合双会话指令第 3 步原计划）：单集成提交**

```
V1.0 菜库蒸馏+滚动平衡引擎：双线集成（1004道菜库，340测试全过）
```

- 范围：§5 全部 A/B 线文件（AGENTS.md 与路线图文档建议一并入库或另行 docs 提交）。
- 优点：提交点必然全绿（已验证）；不承担中间态风险。缺点：单提交约 34k 行，主要体积是 dishes.json 数据。

**方案二：三段拆分（依赖排序）**

1. `数据蒸馏与迁移`：dishes.json、food_data.dart、food_database.dart、database_helper.dart、dishes_schema_test、seed_migration_test、fixtures、两份 distill 文档
2. `指南重蒸馏+7天台账`：dietary_guidelines.json、dietary_guidelines.dart、balance_ledger.dart、intake_calculator.dart、core_engine.dart、balance_ledger_test、dietary_guidelines_test
3. `滚动平衡引擎v2+宠物/UI`：recommendation_engine.dart、recommendation.dart、pet_engine.dart、app_state.dart、recommended_dish_card.dart、recommendation_engine_test、recommendation_state_test、pet_rolling_dialogue_test

- 注意：**第 1、2 提交的中间态不保证全绿**——旧版 recommendation_engine_test（提交 3 才改写）断言基于旧 29 道库的推荐结果，配合新 dishes.json 可能失败。选此方案需接受中间提交仅保证「该段自身测试绿」，或在提交 1/2 时临时不跑引擎全量测试。这是选单提交的主要原因。

**无论哪种方案**：AGENTS.md（当前 untracked）建议单独或随首个提交入库，避免所有 Agent 依赖的约束文件游离在版本控制之外。

## 10. 回滚点建议

| 回滚点 | 位置 | 用途 |
|---|---|---|
| 双线改动全部作废 | HEAD=`bcae4e1`（Phase4 基线，296 测试全过） | 若产品判断双线成果不可用；建议用 `git stash -u` 或建分支保留现场，**不要 reset --hard** |
| Phase2-3 夜间功能 | `cb26a3c` | 通知/设置/宠物/历史功能线的回滚点 |
| Phase1 基线 | `a3ec00` | 持久化+食物库+指南接入+设置流程的回滚点 |
| 数据库升级兼容 | DB v2→v3 迁移有 `seed_migration_test` 4 用例与 v1→v2 链路测试兜底；`app_meta` 建表用 IF NOT EXISTS，旧库无损 | 已安装旧版的设备升级路径 |

## 11. 交接说明（面向不熟悉历史的新 Agent）

1. 本文件 + `AGENTS.md` + `dev-docs/README.md`（模块索引与状态）为最小阅读集。
2. 双线的技术细节分别见 `dev-docs/distill-acceptance-report_20260904.md`（A 线）与本报告 §5 的 B 线文件注释；引擎参数（衰减/限幅/阈值）集中在 `RecommendationEngine` 顶部常量与 dietary_guidelines.json 的 `weekly_balance` 区块，两处数值一致（有测试断言）。
3. `tools/distill/` 蒸馏器在仓库外（.gitignore），拿 nutridata 原始 xlsx 后可全量重跑，不影响本基线。
4. 改 `lib/core/models/food_data.dart` 或 `assets/data/dishes.json` 前先读 `test/data/dishes_schema_test.dart`——契约字段（recommendable/quality_tags/estimated/无全零份数）有全量断言。

## 12. 需产品经理确认的事项

1. 提交拆分方案：单集成提交（方案一）还是三段拆分（方案二）？
2. AGENTS.md 是否随基线入库？
3. R3（dishes.json 补尾换行）是否允许在提交前处理？
4. R5 集成测试覆盖缺口（c/d 两项断言）是否要求补齐后再提交？
5. 未跟踪的两个路线图文档与双会话指令文档：入库、忽略，还是移出仓库？

## 13. 未执行的验证及原因

- 真机 E2E（通知、京东外卖跳转、冷/热分享路径）：需设备与人工操作，Phase4 已验过一轮；本阶段为冻结审计，不再触碰设备态。
- `flutter run` 冒烟：会写入构建产物并可能持有文件锁，与冻结目标冲突；widget 测试已覆盖主要页面构建。
- 蒸馏器重跑校验：需 nutridata xlsx 与外部依赖，且超出只读范围。

---

## 14. 产品复评与冻结结果（2026-09-05 P0 收尾补记）

### 14.1 新增回归测试与结果

在 `test/core/recommendation_engine_test.dart` 新增 group「P0 基线回归：换一批标签与水果槽位（确定性）」，共 3 个用例（对应两条回归场景）：

| # | 用例 | 断言要点 | 结果 |
|---|---|---|---|
| 1 | 换一批后新卡的分类来自新菜品自身数据，不继承槽位或旧卡标签 | 三轮换一批后，每道建议的 primaryCategory == 按菜品自身 correctedPortions 独立重算的主导类别；强断言：第三轮主推=香辣炸鸡排，槽位 grains、自身主导类别 protein（不等于槽位/旧卡的 grains 即失败） | ✅ |
| 2 | 水果是最大有效缺口且有合格候选时，首个槽位为水果且菜品主导类别为 fruits | 主食缺口≤0.15（保底不触发）时首槽=fruits、菜品=鲜果切、主导类别=fruits；排除鲜果切后必须出现「水果类候选不足」提示而非静默顶替 | ✅ |
| 3 | 主食缺口未满时主食槽位按设计置首，水果最大缺口槽位仍保留且标签正确 | 固化「谷类为主」保底设计（insert(0)）：主食有缺口时主食置首，水果槽位仍存在且身份/主导类别正确 | ✅ |

定向运行：`flutter test --no-pub test/core/recommendation_engine_test.dart --plain-name "P0 基线回归"` → **3/3 通过**；全文件 15/15。

### 14.2 设计解释点（需产品经理知悉/复评）

任务书场景「水果是最大有效缺口时首个槽位必须为水果」与已验收设计「谷类为主：主食缺口>0.15 份时主食槽位强制置首（insert(0)）」在主食也有缺口时冲突（实测：reason 显示「今日水果缺口最大」但主推为主食槽位）。本轮处理：**不改算法**，将用例 2 的确定性场景校准为「主食已达标（谷缺口≤0.15）时水果必居首槽」，并用用例 3 固化共存行为。**若产品要求「水果最大缺口时无条件首位」，需在 P3 调整引擎槽位逻辑并同步改写用例 2/3**——请产品经理裁决。

另注意：引擎槽位排序用的是**比例缺口**（(目标−已吃)/目标，钳 0..1），空腹时全部为 1.0，排序由餐次加成决定；测试用例已按此口径构造场景并写明注释。

### 14.3 验证结果（本机实测）

- `flutter analyze --no-pub` → No issues found（10.2s）
- `flutter test --no-pub` → **343/343 全部通过**（基线 340 + 新增 3；dishes.json 补尾换行后运行）
- `git diff --check` → 干净（仅 CRLF 提示，无空白错误/冲突标记）

### 14.4 功能基线 commit

- **`2814db0`** —「V1.0 菜库蒸馏与滚动平衡引擎集成基线」，22 个文件（A/B 线全部业务代码、数据、DB v3 迁移与自动化测试，dishes.json 含尾随换行）。
- 本报告及治理文档在随后的 docs 提交中入库。

### 14.5 产品决定（P0 授权范围）

1. 提交拆分采用**方案一（单集成提交）**承接双线改动；治理与交接文档单独成提交。
2. AGENTS.md 随治理提交入库。
3. 授权补齐两条回归测试、dishes.json 补尾换行、更新本报告冻结记录。
4. 未授权：push、发布、Nutradata 导入（P1）、生产规则修改（P3）。

### 14.6 留到 P5 的真机验收项

- 本地通知真机展示与开关行为（POST_NOTIFICATIONS 弹窗）。
- 京东外卖跳转真机验证。
- 小米真机 Widget：发现、添加、记录后刷新、杀进程/重启后显示、点击直达。
- release 包体构建分析（当前 beta 88.8MB / debug 约 215MB，须先测量再优化）。
- 旧 beta 安装包升级到本基线：DB v2→v3 迁移与用户数据保留的真机确认（已有 seed_migration_test 4 用例覆盖模拟层）。
- ML Kit 中文 OCR 在无 Google Play 服务设备上的可用性抽查。
