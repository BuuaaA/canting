# 餐盘 V1 P1 后半段：数据契约与离线适配验收

日期：2026-09-05。结论：**本阶段工程验收完成，提交产品复评；未进入 P2。**

本轮仅使用自写合成知识记录完成 schema 2、Dart 校验及 SQLite 同步。未生成或导入 Nutradata 真实派生库，未替换正式菜库，未修改 UI、推荐排序、用户数据库或引入 AI / 联网能力。`crypto 3.0.7` 已在 lock 中，本轮只从间接依赖声明为直接依赖，用于本地 SHA-256，离线 pub get 未改变其版本。

## 1. 基线与本轮边界

开始时 HEAD 为 `22952a9`（功能基线 `2814db0`），`main...origin/main [ahead 5]`。上一阶段 P1 的两份报告、原料统计和 scripts/nutridata 已存在且未提交。本轮保留它们：原料验收报告、audit 统计/ID 清单/观察证据、acceptance.py、render_report.py、test_acceptance.py 未改；仅更新契约、契约测试、README 和蒸馏设计说明，并新增本轮文件。逐文件前后摘要见 [修改清单](food-knowledge-adapter-changes.json)。

原料验收结论沿用已通过的 24,611 条结构可读、1,057 个待核实，不重新爬取或把待核实改成不存在。真实数据许可和再分发依据仍未明确；本阶段没有可发布的新真实菜库。

正式 `assets/data/dishes.json` 仍为 1004 道，SHA-256：

`7cdef0bd03f4df72270020b0b42a67be4aa119049ebdfb3b88eec5acc368079a`

## 2. 已修复的契约问题

- 先用合成测试复现：低糖、常规糖、risk_tags=[] 的饮品在旧契约中未抛错，出现两个失败子例。新 Python / Dart 校验均依据 sugar_level 事实拒绝 low / regular / high 的 eligible 声明；fried 做法也独立拒绝。
- sugar_level 定义为所选甜度/加糖选项。none 不等于总糖 0。增加 beverage_type 与有证据的 recipe_known；无糖选项但奶茶配方未知仍拒绝；咖啡不会仅因属于饮品一概排除，仍须同时通过审核、来源、配方、风险和贡献等条件。
- portion_range 包含 min/max、g 或 ml、consumed 食用情境。未知保留 null，拒绝负数、倒置、非有限值、布尔、错误单位和整只商品情境。没有 g/ml 转换、默认 500ml 或蛋糕尺寸推算。真实 0 值在有证据时有效。
- semantic_category 明确为商品类别，新增 burger；milk_tea / coffee 是 beverage 子类，dessert 为甜品。category_contributions 独立保存膳食贡献，汉堡可以同时有主食、蔬菜与蛋白质贡献。
- 新记录不得绕过新解析器进入旧 StandardDish；附带知识时，未知/区间贡献或与旧标量不一致的贡献会被拒绝。exactPortions 只转换完整且精确的六维贡献，未知和区间返回 null。

完整字段、映射、糖型语义、准入门槛、摘要字节定义和迁移方案见 [蒸馏设计第 11 节](food-knowledge-distillation.md)。schema 文件保留历史名称，但版本与 `$id` 明确为 2；共 31 个必需字段。

## 3. 离线接口与同步结果

| 场景 | 实现与验证结果 |
|---|---|
| 原有 1004 道加载 | 原有字段和 recommendable 行为保留；来源、审核、糖型、食用量等知识缺失如实为 unknown/null；不把旧 estimated=false 解释为已经审核 |
| 新知识独立读取 | FoodKnowledgePackage.fromJson 验证内容 SHA-256、schema、内容版本、记录唯一性；FoodDatabase.withKnowledgePackage / findKnowledgeById 和 DatabaseHelper.loadKnowledgePackage 可用 |
| schema 相同，内容版本变化 | synthetic-v1 → synthetic-v2 在相同结构 2 下更新可见知识名称；旧 dishes 表内容不变 |
| 同版本同摘要 | 返回 0，幂等；已接受旧版本重播也不降级当前包 |
| 同版本不同摘要 | StateError；活动包、摘要账本和用户数据均保持原状 |
| 写包后、写摘要账本前失败 | 用 SQLite BEFORE INSERT + RAISE(ABORT) 注入故障，活动包写入被回滚，失败版本没有账本记录 |
| 旧种子更新后、写版本标记前失败 | 数据行和 seed_schema_version 一起回滚 |
| initialize 同时含旧种子与冲突知识包 | 同一事务撤销旧种子更新；连接关闭后可重新打开旧库 |
| SQLite v2 → v3 | 在可丢弃测试库重建 pre-app_meta 状态，既有升级后合成包可加载；用户数据逐字段不变 |
| 历史快照、备注及用户资料 | meal_records（含原 record_json、note、时间）、user_custom_dishes、user_profiles、pet_states 全行 JSON 在成功、幂等、冲突、故障与升级前后相等；知识更新从不重算历史快照 |

知识包使用既有 v3 的 app_meta 保存单个活动包及版本—摘要账本，不需要再升数据库结构版本。包是完整知识快照，删除某知识 ID 不会删除旧菜品或历史引用。版本字符串不推断大小，显式调用方负责发布顺序。公开 `syncKnowledgePackage` 供已初始化数据库使用；已经打开的 initialize 保持原有 no-op 行为。

## 4. 修改清单

| 文件 | 本轮变化 |
|---|---|
| lib/core/models/food_knowledge.dart | 新增单位区间、知识记录、事实校验、包解析/摘要验证及严格标量桥接 |
| lib/core/models/food_data.dart | 旧菜缺失知识的 unknown 接口；可选知识序列化与入口一致性检查 |
| lib/core/models/portions.dart | 新增 fromKnownJson，拒绝未知被当成零；原解析器保留旧行为 |
| lib/data/food_database.dart | 独立知识包和 ID 查询，不加入现有推荐候选 |
| lib/data/database_helper.dart | 内容版本/摘要同步，知识与旧种子组合事务，元数据原子写入，失败可重开 |
| pubspec.yaml / pubspec.lock | 将已缓存的 crypto 3.0.7 声明为直接依赖，无新增版本或联网依赖 |
| scripts/nutridata/contract.py、test_contract.py、food-knowledge-draft.schema.json | 上一阶段文件，修订为知识 schema 2；原 raw 审计脚本保留 |
| scripts/nutridata/test_adapter_contract.py、build_synthetic_fixtures.py、verify_adapter.py | 新增跨语言合成测试、fixture 重建、离线验证与证据输出 |
| test/data/food_knowledge_test.dart、food_knowledge_sync_test.dart | 新增契约、兼容、版本、事务回滚与用户数据保留测试 |
| test/fixtures/food_knowledge_contract_cases.json | 33 个自写合成正反例，非真实菜谱数据，不列入 APK assets |
| dev-docs/food-knowledge-distillation.md、scripts/nutridata/README.md | 保留前半段历史，增加本轮有效契约及运行说明 |
| 本报告、food-knowledge-adapter-validation.json、food-knowledge-adapter-changes.json | 本轮交付和机器证据 |

## 5. 测试证据与复现

最终统一验证命令：`python scripts/nutridata/verify_adapter.py`。无需启动 App、联网或连接用户数据库。

| 检查 | 结果 |
|---|---|
| Python unittest discover（含旧验收脚本） | 30 项通过，其中 1 项逐一执行共享的 33 个契约子例 |
| Dart format --output=none --set-exit-if-changed | 7 个本轮 Dart 文件，0 改动 |
| 相关 Dart 测试：新契约/同步 + seed_migration + database_migration | 50 项通过 |
| flutter analyze --no-pub | No issues found |
| flutter test --no-pub | 386 项全部通过（基线 343 项，本轮新增 43 项） |
| git diff --check | 通过 |

最终命令起止时间、参数、退出码、输出摘要和受测文件 SHA-256 见 [机器验证证据](food-knowledge-adapter-validation.json)。验证开始于 2026-09-05 12:28:24（Asia/Shanghai）；JSON 保存 UTC 时间。首次 analyze 的 14 处 if 括号风格提示已修正；最终检查无遗留提示。部分 Windows 子进程中文日志尾部存在编码替换，英文成功行、测试数、退出码和原输出字节摘要可核对。

共享 fixture 可用 `python scripts/nutridata/build_synthetic_fixtures.py` 重建；此脚本仅使用人工构造对象，不读取任何 Nutradata 原文件。声明式 JSON Schema 未使用第三方 JSON Schema 引擎做完整语义验证；跨字段规则以 Python/Dart 可执行校验及共享用例为准，不能只跑编辑器 schema 检查。

## 6. P2 可直接使用与仍未知的内容

P2 可直接调用 `FoodKnowledgePackage.fromJson`、`FoodDatabase.withKnowledgePackage`、`findKnowledgeById`、`DatabaseHelper.syncKnowledgePackage` / `loadKnowledgePackage`，读取 `productCategory`、`beverageType`、`sugarLevel`、`recipeKnown`、`portion`、`contributions` 及来源/审核信息。消费端须保留 null 和区间，不能用 `?? Portions.zero` 补齐。

仍未知：真实商品品牌别名、商家所选甜度、实际杯型容量、分食比例、食用份量、总糖及配方证据。原料结构可读不证明这些信息已具备。旧菜库没有经过新审核，不能因这次适配而升级为真实已审事实。无校准证据的 confidence 保持 null。

未做且不宣称完成：真实派生库制作/授权、Android 真机加载性能和体积验收、用户纠错 UI/持久化、P2 业务接入、P3 推荐引擎安全改造。当前整包存储和线性知识查找只以小型合成包验证，真实发布前需要独立规模测试。

P3 待办继续保留：主食保底名额与首推排序分开；推荐原因与输出一致；已知油炸事实优先于 recommendable；使用合格混合菜替换“炸鸡必须被推荐”的分类夹具。本轮未修改这些旧引擎测试或策略。

## 7. 回滚与复评

同步失败由事务自动回滚，不需要清库。功能回退可恢复本轮受影响代码并停止读取新知识包；原 assets 和用户表没有变化，勿删除用户数据库或上一阶段 P1 成果。若未来回退已发布内容，以新的内容版本承载审核过的旧内容，避免复用版本配不同摘要。

本轮没有 commit、push 或自动进入 P2。请产品复评 schema 2、事实准入边界、未知值消费约束及包版本约定；通过后再单独启动 P2。真实 Nutradata 库的许可与发布仍是独立门槛。
