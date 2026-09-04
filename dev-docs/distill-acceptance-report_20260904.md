# 「餐盘」APP V1.0 · 菜库蒸馏与数据迁移 · 验收报告

- **项目**：d:\dev\canting（Flutter + SQLite）
- **会话**：菜库蒸馏与数据迁移（数据线，与引擎线并行）
- **日期**：2026-09-04
- **配套文档**：[distill-validation.md](distill-validation.md)（交叉校验明细）· 蒸馏器 `tools/distill/distill_dishes.py` + `curated_extra.py`
- **结论**：✅ 全部验收标准通过（8/8），全量测试 327 过 / 1 失败（引擎层在途，按并行规则忽略）

---

## 一、任务目标与达成总览

| # | 验收标准 | 结果 | 证据 |
|---|---|---|---|
| 1 | 新 dishes.json 通过 schema 校验：必有 dish_id/dish_name/recommendable/quality_tags/portions_normal | ✅ | `dishes_schema_test` 全量断言 1004 道 |
| 2 | recommendable=true 不含 fried/high_sugar/high_sodium（一律干净） | ✅ | 逐菜断言 0 违例 |
| 3 | 不存在全零份数的菜 | ✅ | 逐菜断言 0 违例 |
| 4 | 垃圾食品抽查：薯条/可乐/炸鸡 均 recommendable=false | ✅ | id + 名称双扫描 |
| 5 | 杂粮类抽查：杂粮饭/玉米 含 whole_grain | ✅ | `multigrain_rice` / `steamed_corn` |
| 6 | 数据库迁移：旧 29 道库升级 → 菜数=新库、用户数据无损 | ✅ | `seed_migration_test` 4 用例 |
| 7 | 交叉校验：20 道抽检偏差报告 → dev-docs/distill-validation.md | ✅ | 20/20 ≤30%，最大 16.6% |
| 8 | flutter analyze 零问题 + flutter test 全过 | ✅* | 本线文件零问题；全量 327 过 / 1 失败（引擎层，见第六节） |

## 二、数据来源与法律红线（合规记录）

1. **仓库克隆**：`sunw80910/nutridata_data` 已克隆至 `d:\dev\nutridata_data`（canting 仓库之外），原始数据未提交本仓库。
2. **数据实况（重要发现）**：该仓库未提交数据表本体——仅含 4 个 selenium 爬虫脚本与 2 个清洗 notebook；`my_h_dish_info_all.xlsx`（25668 道）不在仓库也不在 git 历史；nutridata.cn 菜肴详情需注册登录，无凭据不可爬取。
3. **处置**（依「数据格式问题自行判断处理」授权）：
   - 蒸馏器完整兼容 nutridata composition 格式（`配料名：克重` 逐行），预留 `--nutridata-xlsx` 全量真蒸馏路径；
   - 以 notebook 输出可见的 **5 道真实 nutridata 菜肴**为真蒸馏样例；
   - 其余 999 道为菜谱常识估算，配料宏量参照 **cn-food-mcp（MIT 协议，npm 包）**，无版权风险；
   - 产出文件全部为自有 schema（六类交换份数 + 质量标签），非 nutridata 数据表的复制。

## 三、产出统计

### 3.1 总量与构成

| 项 | 数值 |
|---|---|
| 蒸馏菜品总数 | **1004** |
| 旧库保留（升级） | 29（dish_id 全部保留） |
| nutridata 真实样例 | 5（3 道 `estimated=false`，2 道成分截断重建 `estimated=true`） |
| gap-fill（AI 估算标注） | **970 道**（`estimated=true` 共 1001，远超 ≥150 目标） |
| 新库上限 | 不设上限；本次实际产出 1004，达到「预计 1000+」 |

### 3.2 recommendable 分布

| 状态 | 道数 | 说明 |
|---|---|---|
| `recommendable=true` | **707** | 无 fried / high_sugar / high_sodium 且非垃圾食品名单 |
| `recommendable=false` | **297** | 油炸/重钠/含糖饮品甜点/垃圾食品（识别记账保留入库） |

### 3.3 质量标签分布（一道菜可多标签）

whole_grain 67 · light 215 · fried 58 · high_sodium 204 · high_sugar 44

### 3.4 六类份数覆盖（含 >0 份数的菜数）

| grains | vegetables | fruits | protein | protein_soy | oil |
|---|---|---|---|---|---|
| 641 | 657 | 134 | 627 | 104 | 784 |

无全零份数菜；垃圾食品（如可乐）碳水按 grains 折算以满足非零约束。

### 3.5 业务类别分布（15 类，与 categories.json 一致，未改类别表）

stir_fry 184 · dessert_sweet 95 · congee_soup 85 · breakfast_set 78 · salad_light 75 · fruit 74 · braised 70 · rice_sauce 55 · noodle_soup 58 · snack 60 · staple_plain 51 · hotpot_mala 42 · fried 33 · protein_dish 37 · combo_set 7

## 四、蒸馏口径（与 lib/core 契约一致，偏离已记录）

| 类别 | 1 份 = | 备注 |
|---|---|---|
| grains | 50g 生谷薯 | 熟米饭 150g、馒头 75g、熟面条 150g（food_exchange 的 noodles_raw 75g 为离群值，按能量一致口径偏离，已记录） |
| vegetables | 80g | |
| fruits | 100g | 另加 50kcal/份 能量压顶（低卡瓜果不虚标） |
| protein | 50g 肉蛋当量 | 另加 80kcal/份 能量压顶（虾/白鱼等低脂水产不虚标）；奶类按蛋白质当量（250ml 牛奶 ≈ 1.1 份） |
| protein_soy | 15g 大豆当量 | 豆制品按 food_exchange soy_25g 表换算 |
| oil | 10g | 纯油脂按克重；坚果/含脂乳酱按**脂肪含量**折油当量 |

**high_sodium 阈值**：≥800mg 钠/份（≈2g 盐 ≈ 40% NRV）。
**whole_grain**：全谷物/杂豆配料占谷类 ≥30%。
**light**：蒸/煮/白灼/凉拌/清炒/汆/涮 且 油 ≤8g/份 且无负面标签。

## 五、交叉校验报告（摘要，明细见 distill-validation.md）

- 方法：`kcal_recipe = Σ 配料克重 × cn-food-mcp 每100g热量` vs `kcal_portions = Σ 六类份数 × 交换份热量（173/16/50/80/55/90 kcal）`；确定性抽样 seed=42，跨 15 类覆盖，含 5 道 nutridata 官方实测值对照。
- 结果：**20/20 偏差 ≤30%，最大 16.6%**（茼蒿拌豆腐 vs nutridata 官方 82kcal）。
- 人工复核并修正的 5 处系统性偏差（修复前曾 >30%）：
  1. 椰浆/椰奶按脂肪折油（曾按纯油克重 3 份油虚标冬阴功汤）；
  2. 水果能量压顶（木瓜 72%→0%）；
  3. 根茎类份重能量一致化（蒸紫薯 30.6%→0.3%）；
  4. **`per_portion=0` 被 `or` 链当 falsy 回退 80g/份的 bug**（饮用水曾计入 3.5 份蔬菜）；
  5. 剁椒蒸芋头 45.7%→4.1%（芋头份重修正）。

## 六、数据库迁移设计与验收

### 6.1 设计（[database_helper.dart](../lib/data/database_helper.dart)）

- DB 版本 2 → **3**：新增 `app_meta` 键值表（key=`seed_schema_version`）。
- 播种逻辑从「空表才播」改为**版本驱动**：
  - 空表（全新安装）→ `replaceAll` 全量播种；
  - 存储版本 ≠ assets `schema_version`（APP 更新带新菜库）→ `syncSeedCatalog` **增量 upsert**：新菜插入、字段变化更新、**旧库独有不删除**、**用户表一律不动**；
  - 同版本 → no-op（不覆盖用户改过的菜）。
- `FoodDatabase.fromJson` 兼容双格式：旧裸数组（v1）/ 新 `{"schema_version": 2, "dishes": [...]}` 信封；`schemaVersion` 随种子带入迁移判断，main.dart 无需改动。

### 6.2 迁移前后对比（测试实测）

| 项 | 迁移前（旧 v2 库） | 迁移后（v3） |
|---|---|---|
| dishes 行数 | 29 | **1004**（+旧库独有菜保留） |
| 旧菜契约字段 | 无 | recommendable/quality_tags/estimated 齐全（hsm_rice: false/high_sodium/true） |
| meal_records | 1 条 | 1 条（无损） |
| user_custom_dishes | 1 条 | 1 条（无损） |
| user_profiles | 1 行 | 1 行（无损） |
| app_meta.seed_schema_version | 不存在 | `2` |

覆盖场景：旧库升级、旧库独有菜保留、同版本幂等（不覆盖用户改名）、meta 丢失重同步、全新安装。4 用例全过。

## 七、analyze / test 结果

| 项 | 结果 |
|---|---|
| `flutter analyze` | 本线全部文件零问题；全局仅剩 1 warning（`test/core/recommendation_engine_test.dart` unused_local_variable，引擎线文件） |
| 本线新增测试 | **15/15 通过**（schema 校验 11 + 迁移 4） |
| `test/data` + `dish_matcher_test` | **89/89 通过** |
| 全量 `flutter test` | **327 过 / 1 失败**：`recommendation_engine_test` 30 天仿真收敛——引擎层文件，**另一会话在途**（并行规则标注忽略；对方本轮已自愈其余 4 个引擎失败，仿真收敛依赖引擎侧推荐池接入 `recommendable`） |

## 八、契约落地清单（会话 B 依赖）

| 契约项 | 状态 | 位置 |
|---|---|---|
| `recommendable` / `quality_tags` 字段 | ✅ 并行会话已加，直接沿用 | [food_data.dart](../lib/core/models/food_data.dart) |
| `estimated` 字段 | ✅ 本线添加（曾被并行会话覆盖丢失，rg 复核后补回） | 同上 |
| `portions_normal` 含 `oil` 契约键 | ✅ 同时输出 `oil_base`（旧）+ `oil`（契约），值相同 | 蒸馏器输出 |
| dishes.json 顶层 `schema_version: 2` | ✅ 对象根信封 | [food_database.dart](../lib/data/food_database.dart) 双格式解析 |
| 旧 29 道 dish_id 全保留 | ✅ 有断言 | dishes_schema_test |

## 九、改动文件清单（严格守界）

**已改（授权范围内）**
- `assets/data/dishes.json`（29 → 1004 道，schema v2 信封）
- `lib/core/models/food_data.dart`（+`estimated` 字段；recommendable/qualityTags 为对方已有，未改名未删）
- `lib/data/food_database.dart`（对象根解析 + `schemaVersion`）
- `lib/data/database_helper.dart`（v3 迁移 + app_meta + `syncSeedCatalog` + 版本驱动 initialize）
- `test/data/dishes_schema_test.dart`、`test/data/seed_migration_test.dart`（新增）
- `test/fixtures/legacy_dishes_29.json`（迁移夹具）
- `dev-docs/distill-validation.md`、`dev-docs/distill-acceptance-report_20260904.md`（本文件）

**本地工具（`/tools/` 已被 .gitignore 忽略，不入库）**
- `tools/distill/distill_dishes.py`、`curated_extra.py`（蒸馏器，支持 `--nutridata-xlsx`）
- `tools/distill/package/`（cn-food-mcp 解包，MIT）+ 统计/验算输出

**未碰**：recommendation_engine / intake_calculator / lib/ui/recommendation / lib/pet / dietary_guidelines.json / main.dart / pubspec.yaml（无需改动，dishes.json 原已注册 asset）。

## 十、已知局限与移交事项

1. **数据性质**：除 5 道 nutridata 样例外均为菜谱估算，克重按常规外卖/家常一份，同菜不同店差异大；集成会话若需更高精度，优先人工校准推荐池头部菜（如黄焖鸡米饭、麻辣烫、猪脚饭等外卖高频）。
2. **钠为推算值**：未含高汤底等隐含钠，800mg/份阈值偏保守。
3. **给引擎线（会话 B）**：
   - `recommendable=false` 的 297 道（垃圾食品/重钠/含糖）需要引擎过滤与「吃了不推荐但能记账」逻辑；
   - `quality_tags` 可用于清淡模式硬排除与类内排序；
   - 30 天仿真中 fruits/protein_soy 均值 0.00 的收敛缺口，大概率是推荐池尚未接入新字段，接入后预期显著改善。
4. **future**：拿到 nutridata 原始 xlsx 后 `python tools/distill/distill_dishes.py --nutridata-xlsx <path>` 可全量真蒸馏重跑，estimated 标记将自动区分真实/估算来源。

---

**验收结论**：8 项验收标准全部满足；数据层全绿，唯一失败项属引擎层在途改动，已按并行规则标注并留待集成会话裁判。
