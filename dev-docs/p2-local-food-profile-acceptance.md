# 餐盘 V1 P2：本地商品归类、订单规格与记忆复用验收

日期：2026-09-05。状态：P2 阶段产品验收通过，R1/R2 已关闭，获准固化本地基线；未 push，未进入 P3。最终批准结论见第 9 节；第 1–8 节保留实施/复评时点的记录，含当时的未提交状态，不代表当前批准状态。

## 1. P1 冻结与工作区

实际仓库为 `D:/dev/canting`。任务工作目录中的 `p1-adapter-work`、`p1-delivery`、`p1-verification-repeat` 是临时副本，不是 Flutter 主仓库。

开始时主仓库 HEAD 为 `22952a9`，main 比 origin/main 超前 5 个提交。逐项核对 `food-knowledge-adapter-changes.json` 中 30 个文件的最终 SHA-256，全部一致；再加该清单本身，共 31 个明确路径执行 `git add -- <paths>`。本地提交为 **`6e0a0b8`，`P1 原料验收与离线知识契约适配`**。提交后工作区干净，无新重叠改动。未包含真实原料、账号配置、缓存、工作目录或构建产物；没有 push。

P1 文件清单见 `git show --name-only 6e0a0b8` 和原适配变更清单。P2 文件及摘要见 [P2 变更清单](p2-local-food-profile-changes.json)。

## 2. 可操作的闭环

- 分享/选图共用的 OCR 草稿在显示前做本地决策；原始商品名、数量保留。精确且无身份歧义的旧库条目可以填入原有估算，仍能编辑。
- 未知或近似商品保留行。点击“归类 / 确认候选”打开底部面板，先选商品类别；饮品显示糖型、杯型；食品显示实际食用份量；汉堡、三明治等支持做法、酱料。
- 商品类别与六类贡献分开。保存奶茶、汉堡、甜品不需要填写营养数值。所有不确定项可保持未知。无糖选项不代表总糖为零；大杯不转换成 500ml；蛋糕尺寸不转换成实际食用量。
- 点“确认本次商品”仅更新草稿；整餐保存成功才同时写入餐食和本机记忆。保存失败保留草稿；重复点击保存被禁用。
- 仍有未确认项时，保存会要求明确选择“保留未知并保存”，或者返回归类。删除行是用户主动跳过，不会自动丢掉未解决项。
- “我的 → 数据管理 → 本机商品记忆”支持查看、点击编辑、删除确认、复制完整记忆 JSON。修改只影响以后匹配，历史餐食保留当时快照。
- 全量导出改为查询数据库全部记录，不依赖已加载日期缓存；包含旧自定义菜品、新记忆、全部餐食、用户资料和宠物。全部清除采用事务，并清除内存匹配与草稿状态。

## 3. 数据字典与迁移

采用独立 `user_food_profiles` 表。既有 `user_custom_dishes` 依赖旧菜品结构与标量贡献，直接复用会要求未知商品伪造份数。新归类不向旧表复制第二份菜品；旧高级手动录入数据原样保留，也随全量导出/清除处理。

| 对象 / 字段 | 含义与边界 |
|---|---|
| `user_food_profiles.match_key` | 规范化品牌与标准化名称组成的 JSON 二元组，主键；空品牌是独立身份，不匹配任意品牌配方 |
| `json_data` / `LocalFoodProfile` | 单份个人记忆 JSON，schema 1，与 P1 知识 schema 2 独立 |
| `facts.brand / name / category` | 品牌原文、标准名称、商品类别；匹配键负责小写与有限空白标点规范化，不移除做法冲突词 |
| `facts.preparation / sauce` | 用户明确适用于商品的做法与酱料，允许 unknown；不是营养或推荐结论 |
| `raw_names` | 产生确认的原始商品行；按相同品牌复用别名，标准名编辑后仍能识别原始输入；多命中不能自动接受 |
| `last_spec_suggestion` | 上次订单糖型、杯型、份量，仅供展示；不自动填入本次缺失规格 |
| `created_at / updated_at / use_count` | 创建时间、最后确认/编辑时间、确认保存使用次数；编辑不重置创建时间与计数 |
| `source / confirmation_scope` | user_confirmed，明确列出非 unknown 的商品事实范围；没有内置审核、配方完整、许可或推荐资格含义 |
| `confidence / matched_by / policy_version` | 无校准依据则 confidence=null；匹配方法可追溯；策略版本 local-food-v1 |
| `MealDish.food` / `FoodObservation` | 独立餐食快照：商品事实、本次 `spec`、建议、确认状态/时间、原始行、方法、决策、版本 |
| `spec.sugar / cup / size` | 本次事实；unknown 与 notApplicable 分开。杯型不包含虚构容积，份量是食用档位 |
| `knowledge_snapshot` | 如精确命中 P1 知识变体，保留完整不可变知识快照，包括区间、单位、来源与 estimated。参考食用情境未验证时不进入标量汇总 |
| `contributions_known / portions` | 未知为 false/null。未知商品访问旧 `portions` 标量接口会抛错，不能悄悄读出零 |
| `structure_complete / total_scope` | 任一行贡献未知则 false / known_subtotal；旧 `portions_total` 仅是已知部分小计，不是整餐已知总量 |
| `match_score / match_confidence` | 旧匹配器数值作为算法分数保留，新序列化置信度为 null；兼容读取旧 match_confidence，不伪称已经校准 |

SQLite **v3 → v4** 仅新增上述表；v1/v2 继续先执行既有迁移。建表可重复执行；既有用户表、种子库和历史 `record_json` 不重写。数据库升级由 sqflite 升级事务承载。

新餐食、个人记忆与宠物写入处于同一事务；内存状态在提交后更新。故障注入覆盖记忆写入失败及全部清除中途失败，验证用户表和内存不部分更新。编辑重名记忆会报错，不能覆盖另一个品牌/名称主键。

## 4. 匹配决策与规格优先级

决策入口：`LocalFoodMatcher.resolve`；集中方法配置：`FoodMatchPolicy`。旧 `MatchResult.shouldAutoAdd` 不再使用 confidence >= 0.5。

| 情况 | 决策 |
|---|---|
| 唯一的同品牌、同标准名/已确认原始名 | 复用商品事实；本次规格独立解析，历史仅作建议 |
| 明确本次糖型/杯型/份量 | 采用本次输入，覆盖上次建议；同字段同时出现冲突值则保持未知并要求确认 |
| P1 同名知识中的唯一精确规格变体 | 仅在所需规格与本次明确输入一致时填入事实；不以旧建议挑选变体 |
| P1 规格缺失、冲突或多个变体 | 候选确认，不选第一条当事实；品牌字段不足时不借用无品牌知识配方 |
| 无品牌、无其他歧义的旧内置精确名/别名 | 自动填入既有估算；不升级成新知识已审核 |
| 包含、字符相似、类别关键词、品牌/做法冲突 | 显示候选，允许用户归类；0.7 仅是召回相似候选的算法门槛，不是置信度或自动接受门槛 |
| 没有候选 | 保留原名，手动归类或明确保留未知 |

个人记忆优先提供用户确认过的商品事实；规格遵循“本次明确输入/修改 → 精确规格变体 → 上次选择建议”。最后一项仅是提示，不晋升为本次事实。用户在面板修改事实后不沿用可能失效的知识估算。

原生 `DishNameExtractor` 原先会删除括号规格、口味尾缀和任意数字。P2 保留这些商品事实，只清理明确价格/数量标记；因此“大份”“无糖小杯”“30寸”能到达 Dart 确认界面。没有引入新 OCR 引擎。

## 5. 已记录但贡献未知

个人归类不推导精确营养或六类份数。未知行完整写入餐食，`portions=null`，整餐 `structure_complete=false`，汇总明确为已知小计。保存提示、行提示、首页小结、历史详情/统计均标识估算不完整；不能凭已知小计宣称当天结构达标。不完整餐食/日期不用于新增宠物饮食质量评价。

没有 `?? Portions.zero` 接入未知值，没有区间取中点。旧库有依据的原标量估算继续兼容，并标明来源 ID、食物组份数单位和 estimated。P1 区间与来源在知识快照保留，未确认当前食用情境时不强行纳入原标量汇总。未来 P3 必须读取完整性与未知状态，不能只看 `portions_total`。

## 6. 测试与设备证据

最终机器结果、日志摘要和文件摘要见 [验证证据](p2-evidence/validation.json)。

| 检查 | 结果 |
|---|---|
| 本轮 Dart 格式检查 | 31 文件，0 改动 |
| flutter analyze --no-pub | No issues found |
| flutter test --no-pub | 404 项通过（含全部旧回归） |
| Android :app:testDebugUnitTest --offline | 20 项通过，0 failures/errors |
| git diff --check | 通过 |
| Android debug APK | 独立验收入口构建成功；不作为生产发布包 |

| 必测场景 | 证据 |
|---|---|
| 青青糯山未知 → 奶茶/常规糖/大杯 → 重启复用 | SQLite 重开测试；模拟器实际选择、保存、强停重启，截图 01–05 |
| 再次无糖/小杯，历史不变化 | 数据测试；模拟器截图 06，设备导出显示前后两餐规格不同 |
| 规格缺失不沿用历史 | 数据/面板测试；截图 05 的糖型杯型仍待确认 |
| 汉堡与做法、巴斯克小份 | 数据保存测试，商品类别与份量保留、贡献 null、旧推荐候选库不变 |
| 奶油蛋糕30寸 | Kotlin 保留尺寸；Dart/面板测试；真实原生 OCR 与截图 09 提示实际食用部分 |
| 混合已知/未知 | 数据/界面回归；模拟器截图 01、08、10，明确保留后完整保存三行 |
| 跨品牌、无品牌、规格/字符冲突 | local_food_flow_test、local_food_knowledge_match_test 的正反例与边界 |
| 删除/编辑记忆、历史保留 | 数据测试；模拟器截图 11–12；设备前后导出逐行对比，3 餐完全不变，记忆从 2 条变 1 条 |
| 旧库升级、重启、导出、清除、失败回滚 | 既有升级全回归与新增 SQLite 事务故障注入；导出覆盖未加载日期 |
| 飞行模式 | sdk_gphone64_x86_64 模拟器，airplane=1、wifi=0、mobile_data=0；真实页面/SQLite/ML Kit 跑通，见 emulator-verification.json |

### 实际界面截图

以下均为 **Android 模拟器 1080×2400 截屏**，不是组件测试截图或真机验收。`tool/p2_emulator_smoke.dart` 使用独立 `p2_acceptance_only.db`，合成订单和生产业务页面/存储代码；不包含真实用户订单。截图中的模拟器时钟为 UTC，宿主为 Asia/Shanghai。

- [未知归类面板](p2-evidence/02-unknown-classification.png)
- [首次选择常规糖大杯](p2-evidence/03-first-confirmation.png)
- [重启后复用](p2-evidence/04-reuse-after-restart.png)
- [缺规格保持未知](p2-evidence/05-missing-specs-remain-unknown.png)
- [本次无糖小杯优先](p2-evidence/06-current-spec-overrides-history.png)
- [记忆管理](p2-evidence/07-memory-management.png)
- [原生离线 OCR](p2-evidence/08-native-offline-ocr.png)
- [蛋糕实际食用确认](p2-evidence/09-cake-consumption-confirmation.png)
- [明确保留未解决项](p2-evidence/10-explicitly-preserve-unresolved.png)
- [编辑记忆](p2-evidence/11-edit-memory.png) / [删除确认](p2-evidence/12-delete-memory-confirmation.png)

实际 ML Kit 将合成图中的“青青糯山”读成“青責糯山”；原始输出保留为未确定商品，未据此生成配方。后续相似匹配也仅返回候选。另两行为“白斩鸡”“奶油蛋糕30寸”。这不是品牌 OCR 准确率验收，真实截图集仍待 P4。

设备完整导出仅含本轮合成数据：`emulator-export-before.json`、`emulator-export-after.json`；比较结论见 `emulator-verification.json`。实际系统相册选择器、系统分享选择器与真机权限流程本轮未手工验收，原有平台通道模拟测试全部通过，不能冒充真机证据。原生 OCR 验收通过生产 `copyIntoSharedImages` 的 FileProvider 路径调用。

## 7. P3 接口、限制与回退

P3 可消费 `MealDish.food` 中的品牌、商品类、做法/酱料、本次糖型/杯型/食用档位、确认时间与方法、知识快照，以及 `MealRecord.structureComplete`。商品类别不等于膳食贡献；unknown 不等于不适用、零份或安全。`LocalFoodProfile` 是个人确认，不是内置审核或推荐授权。

没有修改 `RecommendationEngine` 排序、`BalanceLedger` 7/28 天策略、指南参数或正式 1004 道菜库。本机记忆不会成为推荐候选。**本轮不声称旧推荐引擎满足 P3 新安全要求**；完整性提示不能代替新的推荐安全门。

仍有限制：缺少真实品牌菜单/容量/配方依据；本机个人类别不自动产生贡献范围；P1 无独立品牌字段的知识不用于品牌配方套用；旧高级手动营养录入及旧菜库标量继续兼容，不代表经过 P1 新审核；大规模个人记忆的性能未专项测量。真机与真实订单截图验收未完成。

复现：运行 Flutter analyze/test；Android 设置正确 JAVA_HOME 后在 android 目录运行 `gradlew.bat :app:testDebugUnitTest --offline`；模拟器构建 `flutter build apk --debug --no-pub -t tool/p2_emulator_smoke.dart`，在独立入口依次操作 A/B/C/D/E/F。测试入口不会随默认 lib/main.dart 发布。

回退：P2 源码尚未提交，可基于变更清单人工回退；不要删除用户数据库。已升级 v4 的设备不应直接安装只接受 v3 的旧客户端，应先提供兼容 v4 的回退版本。即使停用记忆，新表及历史快照也应保留以便恢复/导出。

产品复评重点：轻量确认体验、未知小计提示、品牌保守匹配和个人记忆管理。批准前保留全部 P2 工作区改动，不提交、不 push、不启动 P3。


## 8. 产品复评 R1 / R2 收尾（2026-09-05）

结论：两项修复完成，等待产品复评，未授权冻结。基线仍是 `6e0a0b8`，main 领先 origin/main 6 个提交，暂存区为空。开始时原清单 57 个文件哈希全部匹配，没有新增重叠改动；审核任务空闲，Dart 进程为编辑器 language-server/tooling/daemon，未发现并发测试。修改前对业务文件再次核对基线哈希，无覆盖、reset、checkout、commit 或 push。原清单保存在 [复评前基线](p2-evidence/review-20260905/baseline-changes.json)。

### R1：商家纠错使依赖上下文的匹配失效

根因：商家 TextField 没有触发重新决策，已有 `food` 被 matcher 和面板直接复用。先新增真实 `RecordDetailPage` 的 6 项组件交互测试再修实现：修复前 1 项通过、5 项在业务断言失败（乙/空商家仍显示甲），不是删断言或改低期望。修复后全部通过。

最小实现：`FoodObservation` 新增可选 JSON 字段 `brand_origin`（merchant / explicit / legacy_unknown）和 `merchant_context`。本次匹配生成 merchant 来源；品牌输入框实际发生用户输入时标记 explicit，主动清空也属于明确输入。一般点击确认不会把商家推断升级成单品品牌声明。修改商家时仅重新决策依赖旧上下文的行，重置其类别、确认和旧建议，不复制甲的类别到乙；本次规格、原始商品行、数量保留。仅切换类别也不再丢掉商品原文中已明确的糖型/杯型。

旧快照缺少品牌来源时读取为 legacy_unknown，不批量推断或重写旧餐食；用户可在历史编辑面板明确修改品牌。新快照的品牌来源随 JSON 持久化。个人记忆仍以品牌+标准名称为键，不新增第二份事实库。

组件交互证据（不是模拟器或真机）：[完整日志](p2-evidence/review-20260905/related.txt)。测试操作商家输入框→点击商品行→读取生产确认面板→确认/明确保留未知→保存→查 SQLite，同时比较旧餐食整行不变。

| 场景 | 修正商家后的确认面板 | 保存断言 |
|---|---|---|
| 甲→乙，乙无记忆 | 品牌乙 / 类别 unknown，甲仅可作为候选 | 不生成乙的未知类别记忆，原甲记忆计数不变 |
| 甲→乙，两品牌同名 | 品牌乙 / coffee，不沿用甲的 milk_tea | 使用乙键保存确认内容 |
| 清空商家 | 空品牌 / unknown | 不套用甲专属类别 |
| 用户明确单品品牌后改商家 | 单品品牌 / milk_tea 保持 | 单品品牌独立键，历史甲不变 |
| 未解决候选 | 保持乙 / unknown | 必须点“明确保留未知并保存”才存整行 |
| 用户先改为低糖、杯型缺失，再改商家 | 低糖保留，杯型 unknown | 上次常规糖大杯仍不晋升为事实 |

上述前五个场景原文为“青青糯山 无糖 小杯”、数量 2；面板和落库仍为无糖/小杯及数量 2。第六个原文没有规格，验证用户修改值也能保留。

### R2：实际奖励凭证与原子删除

根因：保存按整日完整性决定是否调用宠物引擎，删除却根据当前完成率推算名义变化；此外先删除餐食后写宠物，故障会部分落库。新增 12 项测试初跑 5 通过 / 7 失败，复现 60→50、钳制多撤销、编辑不对称、宠物写失败餐食丢失等问题；追加 3 项边界，最终新增 R2 共 15 项通过。

采用随餐食 `record_json` 保存的最小凭证 `pet_effect`，不用新表，不引入事件溯源系统。数据库仍 v4，没有 SQL 迁移，也不重写既有历史。

| 字段 | 含义 |
|---|---|
| `pet_effect.evaluated` | 新餐保存时是否实际调用餐食质量评价；被未知餐/未知日阻断则 false |
| `vitality_delta` | 引擎该餐日志的实际活力变化（钳制后），可正/负/零；不是按当前完成率重新推算 |
| `recorded_at` | 实际处理时间 |
| `schema_version / policy_version` | 1 / meal-actual-effect-v1 |
| 整个字段缺失 | 旧数据无凭证，不能解释成曾经获得名义奖励 |

新增保存由 AppState 生成凭证，忽略调用者传来的奖励声明；编辑保留数据库中已有凭证（包括缺失），不补奖、不改写原奖励。删除先在事务中读取真实记录与宠物，只撤销有凭证的餐食实际变化。成长值、进化奖励仍不撤销；原引擎规则/上限下限不变。再删已不存在记录直接返回，不写宠物。餐食删除、既有重算和宠物写入同一事务，失败时数据库与内存都保持原状。

兼容边界调查：既有 `app_state_pet_test` 明确定义了旧完整餐删除后收敛到最近 3 天质量评分。故保留该已定义规则和公式；旧数据仅取消无依据的名义奖励撤销，仍按原完整性条件重算。新凭证 evaluated=false 的餐食删除既不撤销也不触发质量评价；evaluated=true 保留原重算。启动时原有离线衰减/3 天重算仍独立存在，本轮没有重写它；因此有档案时活力不保证永远回到最初保存前的数值。没有证据可以精确恢复旧奖励，明确不回填虚构历史。

原下限回归保留 `expect(vitality, 15)`，仅把“直接插入一餐、未发奖”的夹具改为通过 `saveMeal` 实际发奖，继续测撤销 +10 后钳制到 15；另有旧 JSON 无凭证的独立测试证明不再凭完成率扣分。不是删除断言来掩盖缺陷。

覆盖：未知日完整餐保存/删除、已有档案及可重算前一日时仍不误评、正常获奖删除、重启后删除、连续及并发重复删除、已知↔未知编辑、实际上限钳制、负向变化对称、旧 v4 JSON 逐字保留、旧记录编辑不补凭证、导出保留凭证、餐食/宠物触发器故障回滚、保存失败回滚。既有 v3→v4 迁移/历史保留测试也在全回归中通过；全部数据库测试仅使用临时/内存库。

### 本轮文件、命令和结果

实际业务/测试文件共 9 个：

- `lib/core/models/local_food.dart`
- `lib/core/local_food_matcher.dart`
- `lib/ui/record/record_detail_page.dart`
- `lib/ui/record/food_confirmation_sheet.dart`
- `lib/core/models/meal_record.dart`
- `lib/state/app_state.dart`
- `test/ui/record/brand_context_review_test.dart`（新增，6 项）
- `test/state/meal_reward_review_test.dart`（新增，15 项）
- `test/state/app_state_pet_test.dart`（既有下限测试夹具及格式）

另更新本报告、P2 变更清单，新增 `scripts/p2/collect_review_evidence.py` 及复评证据目录。逐文件 SHA、与复评前的差异、完整工作区清单见 [本轮变更](p2-evidence/review-20260905/changes.json)、[完整 P2 清单](p2-local-food-profile-changes.json) 和 [本轮验证 JSON](p2-evidence/review-20260905/validation.json)。旧 404 项/Kotlin/模拟器证据保持原样，不冒充本轮执行。

| 实际命令（D:/dev/canting） | 结果 |
|---|---|
| `dart format --output=none --set-exit-if-changed <上述9个Dart文件>` | 9 文件，0 改动 |
| `flutter analyze --no-pub` | No issues found |
| `flutter test --no-pub test/state/meal_reward_review_test.dart test/state/app_state_pet_test.dart test/ui/record/brand_context_review_test.dart test/data/local_food_flow_test.dart test/core/local_food_knowledge_match_test.dart test/ui/food_confirmation_test.dart --reporter expanded` | 47 项通过 |
| `flutter test --no-pub --reporter expanded` | 425 项通过（原404 + 新21） |
| `flutter test --no-pub C:/Users/gxy20/Documents/ChatGPT/代码审核/p2_review_probe_test.dart --plain-name "deleting an uncredited complete meal must not change vitality" --reporter expanded` | 原独立 R2 探针 1 项通过，`before=60 after=60` |
| `git diff --check` | 退出码 0 |

审核目录原探针没有改动。其 R1 定位器固定寻找旧的“已复用类别”标签，修复后该标签应失效，因此本轮 R1 证据使用新记录页面回归，通过商品行 ListTile 定位，保留品牌/类别/规格和落库的严格断言；没有声称原 R1 探针原封不动通过。

未验证：本轮未跑新模拟器/真机、系统相册/分享流程、真实菜单与品牌准确率；这些仍归原阶段验收。原生文件相对复评前哈希未变，未重复跑 Kotlin。没有修改 AGENTS.md、正式菜库、原料许可、指南、推荐或整个宠物引擎，没有 AI/网络/社区/后台功能。新增 JSON 字段允许旧读取器忽略，但旧代码再次编辑可能丢凭证，因此已产生新凭证后不建议回装旧 P2 构建；回退应保留新字段及数据库，不删除用户资料。

返回产品复评，未自行进入 P3。需要产品确认的是本次修正与所述旧数据兼容边界是否可接受，不是新阶段实施授权。


## 9. 产品批准与本地基线固化（2026-09-05）

产品批准文件：`C:/Users/gxy20/Documents/ChatGPT/代码审核/p2-product-approval-20260905.md`。
批准文件 SHA-256：`381f1eda5a605c29b1163b220ff65b49d001bfcdbd451f41078d3b73a456b2ba`。

结论：**P2 阶段产品验收通过，R1（品牌上下文纠错）/R2（实际奖励撤销与事务一致性）关闭，允许固化本地基线。** 用户已转发并确认仅创建一个本地提交，不 push、不启动 P3。

产品方独立复核：完整清单 71/71、收尾清单 11/11、日志 5/5 哈希一致；相关测试 47/47、独立探针 2/2、完整 Flutter 回归 425/425 通过；静态检查 No issues found，git diff --check 退出码 0。独立 R1 输出修正商家乙后确认品牌乙，R2 输出活力 60→60。以上是产品批准文件记载的复核结果；开发侧原有证据见第 8 节及复评证据目录。本次只更新本文批准状态和完整清单中的本文哈希，没有改变源码，不机械重跑测试。

冻结前核对：HEAD 为 `6e0a0b88fd10e38cf1c9dc09a48b16ee611b3b9e`、暂存区为空；71 个候选文件逐项 SHA-256 一致，清单覆盖全部实际未提交/未跟踪 P2 文件，没有清单外重叠改动。产品审核任务空闲。提交范围为最终完整清单的 71 个明确路径，加清单自身，共 72 个文件；包括源码、测试、验收文档、脚本、合成模拟器截图/导出及测试日志，不包含真实用户数据、账号、原始采集库、构建缓存或临时文件。没有新增单独冻结记录。

`review-20260905/changes.json`、`baseline-changes.json` 及验证 JSON 保留复评时点的历史哈希和 Git 状态，不重写它们来伪装重新验证；本文冻结时的最终哈希以 `p2-local-food-profile-changes.json` 为准。提交前检查 staged diff、路径集合、暂存内容与工作区一致及 diff --check。提交标题为“P2 本地商品归类与记忆闭环，修复品牌上下文和奖励撤销”；具体提交 ID 由 Git 日志和交付回复提供，避免文档自引用哈希。

保留边界：此批准不是 V1 发布验收。P3 推荐安全门、7/28 天完整性消费、解释与温和提醒未实施，需产品经理单独下发任务书。P4 真实截图集、P5 真机/系统相册与分享/无 GMS/小米 Widget/旧 beta 升级/包体验收仍未闭环。收尾证据是组件交互与自动化测试，没有新增模拟器或真机验收；原生未改，收尾未重复 Kotlin。个人归类不产生无来源的精确营养值或推荐资格；原料许可仍未解决。回退版本须保留新增 JSON 字段及 v4 库兼容性，不删除用户数据库。


冻结提交检查补充：完整 `git diff --cached --check` 返回 2，发现 5 份原始工具日志的行尾空格（首轮 analyze/emulator-build，以及收尾 analyze/r1-before/r2-before）。这些字符与产品已核对的原始日志 SHA 完全一致，不是新增内容差异；为保持证据原文不做去空格、改哈希或改 Git 配置。对其余明确暂存路径执行同一检查返回 0；未暂存 diff --check 返回 0。全部 72 路径及暂存 blob 与当前工作文件的 Git 规范化内容一致。此格式提示已明确披露，不声称完整暂存检查返回 0。
