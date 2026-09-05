# P3 确定性推荐安全与 7/28 天反馈闭环

日期：2026-09-05。结论：**实施和自动化验证完成；产品复评 R1 已修正，返回单项复评；未 commit / push，未进入 P4。** 基线 `d7077e221bab45226ba0a16a881588418d61460a`；开始时工作树干净，main 领先 origin/main 7 个提交。

产品复评 R1 指出 28 天摘要无条件显示“记录不足”。现已采用批准文案“仅展示已记录餐食结构，暂不判断改善趋势；28天差额不分摊到下一餐。”连续 28 个本地日历日都有贡献已知记录时，组件严格显示 recordedDays=28、partialDays=0、missingDays=0、unknownItemCount=0，不再出现“记录不足”；仍显示“不代表全天摄入”，不生成改善百分比。部分未知、全空和数据库读取失败的生产组件场景继续分别显示其真实覆盖、空窗口说明和 error/retry 状态。

## 1. 输入、差距与实施范围

完整阅读仓库 AGENTS.md、P2 验收报告。用户消息中的 P3 嵌套路径不存在，找到并读取实际文件 `C:/Users/gxy20/Documents/ChatGPT/代码审核/餐盘_P3_PRD_V1.0.md` 和 `餐盘_P3_待确认项.md`。采用已授权产品默认。

审计确认：旧安全排除分散且部分仅 light 生效；台账累加未知小计；删除不刷新台账；主食强制置首；理由不取实际输出。依 A→B→C 顺序先添加反例/边界测试，再接通生产业务与数据库。初次测试失败日志保留，包含尚无新接口时的编译失败，不声称这些全部是业务断言失败。

A：集中 `RecommendationSafety.evaluate`，两个选择出口统一通过 `RecommendationEngine.decisionFor`，涵盖 routine/light、主推、备选、换一批、补位。个人记忆仍只进入匹配器，不能加入候选池。

B：`RecordWindow` 按本地日历构造 7/28 天边界、记录覆盖、未知条目与已知小计。AppState 从 SQLite 最多读取 28 天，重建台账和窗口；partial 日不产生新盈亏，旧结转照旧衰减。今日 missing/partial/error 时建议份数为 null，不用假设缺口补偿。主食只保留名额，之后按原有效优先级排序。理由取实际首推槽位，卡片标签取实际菜品主导类别。推荐页和历史页复用同一个摘要组件；28 天分成四个 7 天样本，不计算补偿差额或改善百分比。

C：当天新餐保存成功之后，根据餐食快照计数并领取一次提醒；同餐同族一次、不同餐至少两次，多族合并。两个生产保存入口均接通。提示可关闭、各族暂停 7×24 小时，下次不另外加糖偏好只影响后续提示文案。我的页面提供查看、修改、恢复、清除。未新增系统通知或权限。

## 2. 规则、字段和兼容表

| 输入/条件 | 结果与原因 | 来源边界 |
|---|---|---|
| recommendable=false | ineligible / not_recommendable | 排序、light、换批、补位均不能覆盖 |
| fried、high_oil、high_sodium、high_sugar、alcohol、sugary_drink/sugary | ineligible / 对应风险码 | tags、quality_tags、知识风险事实均保留；light 不解禁 |
| category=fried、sodium_level=high | ineligible / fried、high_sodium | 旧结构化字段 |
| category oil_level=high/extreme | ineligible / high_oil | 已批准旧库代理；mid_high 不升格；不新增 oil_factor 阈值 |
| 有边界的明确油炸/酒精名称 | ineligible / fried、alcohol | 标记 legacy_name_proxy；不把“非油炸”当油炸，不把啤酒鸭当酒精饮品 |
| 奶茶等饮品配方不明 | conditional / unknown_ingredients | 无糖规格不构成配方完整证明 |
| 汉堡/三明治缺必要事实 | conditional / unknown_preparation | 不编配方，不硬编码品牌白名单 |
| 准确 ID、有来源、非油炸蛋白+主食+蔬菜、少/无酱 | 可 eligible / confirmed_light_composition | 可选 CandidateFacts；所有反向排除仍优先；正式库未加入任何合成配方 |
| 不同知识来源冲突/身份冲突 | conditional 或明确风险 ineligible / source_conflict、identity_conflict | 不采用后一个来源覆盖前一个风险 |
| 无效分类/标量/等级 | conditional / invalid_candidate | 非有限数、负数、缺分类不默认放行 |
| 老库低风险通用项 | eligible / legacy_low_risk | 兼容策略，不伪造 reviewed 状态 |
| 知识已排除/未满足准入 | ineligible / knowledge_ineligible 或 conditional / knowledge_not_eligible | 知识区间仍不自动取中点 |

政策版本 `p3-v1`。决策包含 `eligibility / reasonCodes / policyVersion / evidenceRefs`；引用包含事实字段、来源和菜品身份。推荐另输出 `insufficient_record_coverage`、`recorded_structure_7d`、`insufficient_candidates`、`generic_structure_advice`、`selected_<实际槽位>`。可审核知识结果代码为 `reviewed_knowledge`。未知做法/配料代码亦可来自知识风险标签。

| 新状态 | 持久化/兼容 |
|---|---|
| RecordWindow | 运行时重建，含 windowStart/windowEnd/asOf、recordedDays/partialDays/missingDays、unknownItemCount、knownSubtotal、dataStatus；partialDays 为 recordedDays 子集 |
| CandidateFacts | StandardDish 可选 candidate_facts，准确 identity、source、non_fried_protein、grains、vegetables、sauce；缺失保持未知，不扩展配料录入 UI |
| MealDish.risk_evidence | 新餐精确旧库命中时捕获 identity/source/tags/category/policy_version；编辑不回查菜库重写旧事实；旧字段缺失不回填 |
| p3.exposure.preferences | 现有 app_meta 命名空间；enabled、muted_<族> 的 UTC 到期时间、next_time_preference |
| p3.exposure.shown.<mealId> | 成功保存后的领取时间；领取先于呈现，崩溃可漏一次、不重播；删除重建相同 ID 也不重播 |

数据库仍 **v4**，没有 SQL schema 升级，没有重写旧 record_json、身份、规格、知识快照或 pet_effect。全量导出增加 p3_exposure_state，清除全部数据的同一事务删除这个命名空间，保留菜库版本元信息。保存提醒状态失败返回不提示，不撤销已保存餐食；偏好保存失败面板提示可重试。后续偏好不改变任何历史/本次 spec，也不改变安全门。

## 3. 真实链路与刷新

- 记录详情页：保存→SQLite 餐食/记忆/宠物事务提交→窗口刷新→领取提醒→面板→原保存完成导航。未知行仍需要 P2 的明确保留流程。
- 高级手动添加页：同一保存结果接入提醒；自定义菜仍不会自动成为推荐候选。
- 保存/编辑/日期移动/删除/档案目标变化清除旧窗口并重建；并发窗口读取等待后重建，不吞掉保存后的刷新。
- 启动读取数据库；恢复 App 清除日期缓存重建；运行时每分钟只检测是否跨日，跨日才重建。同一日期反复渲染使用缓存。
- 读取失败窗口标记 error、取消旧台账补偿，UI 给出重试；旧数据不显示为刚更新。
- 历史日期摘要独立查询，不依赖当前已载月份；自然周统计面板替换为滚动 7/28 天。日历自身保持既有分组。
- 日切沿用当前历史页的**本地零点**。`UserProfile.dayStartTime` 是已有设置字段，但这条既有历史分组未使用它；本轮不改变其全局含义。
- Widget 对数据不足使用中性下一餐文案；没有重写宠物引擎及原三天公式。

## 4. 测试、候选审核和仿真

最终命令与证据见 [validation.json](p3-evidence/validation.json)，实际变更和 SHA-256 见 [p3-changes.json](p3-changes.json)。

| 命令 | 结果 |
|---|---|
| dart format --output=none --set-exit-if-changed 本轮Dart文件 | 29 文件，0 改动 |
| dart format --output=none --set-exit-if-changed R1 两个Dart文件 | 2 文件，0 改动 |
| flutter test --no-pub test/ui/p3_production_pages_test.dart --reporter expanded | 7 项通过，含 R1 完整/空/未知/错误摘要组件场景 |
| flutter analyze --no-pub | No issues found |
| flutter test --no-pub --reporter expanded | **464 项通过**：冻结 425 + 新增 39 |
| git diff --check 及每个新文件 no-index --check | 见 validation.json 的实际退出码 |

新增测试涵盖集中排除反例、完整/缺失组合事实、0/1/2 个安全候选、routine/light 全出口、换批/补位、闰日/跨月/跨年起止边界、全空/未知窗口、真实 SQLite 重启/编辑/日期移动/删除、静音到期/导出/清除、同 ID 并发保存、提示写入失败、数据库读取失败、多族独立静音、旧 v4 JSON 原样保留、目标变化和并发刷新。R1/R2、旧库迁移、事务、知识与奖励凭证测试在全回归中通过。

生产页面组件测试实际点击保存，面板出现时数据库已有两餐；点击记住偏好后两餐糖型仍是 low；关闭后导航首页，重建不重播。推荐页实际切换 7/28 天，设置页实际修改偏好；0/1/2 候选页面验证换批耗尽和恢复。R1 新增连续 28 天贡献已知组件场景，并同时保留全空、部分未知和数据库读取失败的页面断言。画面使用宿主中文字体仅供组件截图，字体没有复制到仓库/应用：

- [保存后的提醒](p3-evidence/component-save-prompt.png)
- [7天推荐摘要](p3-evidence/component-recommendation-7d.png)
- [28天推荐摘要](p3-evidence/component-recommendation-28d.png)

这些是 **1080×2400 Flutter 组件画面**，不冒充 Android 模拟器/真机。截图已检查中文可读，无溢出报错。原生通道不可用的测试降级日志属预期，不表示真机验证。

正式 **1004** 条菜库本轮输出：**569 eligible、5 conditional、430 ineligible**。按类别、原因、逐条来源和冲突列表完整保存在 [candidate-audit.json](p3-evidence/candidate-audit.json)。未修改菜库；合成明确排除样本在所有出口漏出为 **0**。实际库的代理准入统计不等于逐条人工健康认证。

[simulation.json](p3-evidence/simulation.json) 包含固定种子 42 的 7/28 天输入输出：持续偏食、稳定均衡、漏记、大量未知、候选枯竭、风险冲突。边界断言独立于引擎自评分；28 天仅传给摘要，下一餐仅使用 7 天台账和当天覆盖。性能在 Windows Flutter test JIT 测得：1004 条准入审核与 2800 条合成历史×10 次窗口重建的原始微秒数在该文件；不是低端真机 P95。

[feedback-events.json](p3-evidence/feedback-events.json) 只记录合成保存事件/族/次数；实际面板呈现由独立生产页测试核对。不新增遥测 SDK 或真实用户日志。

## 5. 明确改写的旧断言与复评关注点

P3 明确取消无记录时的精准补偿；旧空记录份数断言改为 null。仍保留有已知合成记录时的 ±30% 修正限幅测试。主食强置首断言按 PRD 改为水果有效优先级第一则水果首推、主食保留其余名额。旧“香辣炸鸡排”分类身份用例迁移到安全的合成清蒸混合配饭，槽位 grains / 主导 protein 的严格断言保留，并独立断言炸鸡排不出现。首页导航用例改用新的中性文案定位器，保留点击到真实推荐页的断言。

**旧 30 天随机依从仿真的“每个后期窗口必进目标 ±20%”不再成立。** 原目标、种子和所有偏差/逐日轨迹保存在 [legacy-convergence-diagnostic.json](p3-evidence/legacy-convergence-diagnostic.json)。例如 day20–26 蔬菜日均 2.86（原目标区间 4–6），蛋白 2.00（3.2–4.8）。本轮未调阈值/衰减/限幅来追曲线。该测试改为固定输入机制与安全/未知边界断言，旧收敛判断保留为负向诊断输出，**不是“原断言原封不动通过”**。产品复评需关注这一改变：P3 可以验收安全闭环，不应据这条仿真声称已证明长期营养改善；如要进一步提高建议采纳后的结构覆盖，需另行裁定目标和产品策略，不能放宽安全门。

## 6. 限制、未验证与回退

- 六类模型仍未完整覆盖奶类等膳食指南维度；奶茶不归为奶类达标。完整只表示已记录贡献可估算，不表示全天记录齐全。
- 旧数据缺乏风险快照时，只消费当时明确事实及有边界名称代理；不事后套用新配方重写历史。真实候选缺组合事实仍 conditional。原料许可问题未解决，本轮未导入原料或重爬菜单。
- 未做本轮 Android 原生/Kotlin、模拟器、真机、系统相册/分享、无 GMS、小米 Widget 或发布包验收：本轮没有原生或权限变化；这些仍属于原定后续验收。不进入 P4/P5。
- 没有 AI、联网、社区、后台 OCR、新增系统通知。原有 P2 通知代码保持原行为，并非宣称整个 App 从来没有通知能力。
- 回退应按变更清单人工回退应用代码，保留用户 v4 数据库、app_meta 命名空间、餐食可选字段与 pet_effect。旧版本再次编辑可能丢失新的可选风险证据，故建议使用保留可选字段的兼容回退版本，不删除用户数据。
- 没有待开发自行猜测的健康政策。需要产品复评的是本次交互、代理边界和上述负向仿真诊断；未获产品批准前继续保持未提交，不启动下一阶段。
