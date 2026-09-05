> **本轮有效契约见第 11 节（schema 2、Dart 离线适配）。第 1–10 节为已交付的 P1 前半段历史设计；发生冲突以第 11 节及后半段验收报告为准。**

# 餐盘 V1 P1：FoodKnowledge 分层管线设计

日期：2026-09-05。状态：**原料验收与设计交付；等待产品复评，不实施 App 菜库替换**。
冻结基线：功能 `2814db0`，文档 `22952a9`。本文件不改变 GuidelinePolicy、推荐引擎、用户数据库或发布范围。

## 1. 现状与边界

当前 App 为 1004 道、种子 schema v2、数据库 v3；`FoodDatabase.schemaVersion` 同时承担结构与重播种触发职责。`syncSeedCatalog` 按 dish_id 增量 upsert 并保留旧菜，不删除用户数据；名称索引用 `putIfAbsent`，因此把多个同名来源直接拼进去会产生输入顺序依赖。

本次仅新增仓库中的验收脚本、合成测试、统计及设计文件。raw、normalized、distilled、curated 的实际数据均不得进入仓库或 APK；目前没有可发布的新增菜库。`scripts/nutridata/contract.py` 是独立设计契约检查器，不被 App 引用，也不是 P3 推荐引擎实现。

机器可读结构见 `scripts/nutridata/food-knowledge-draft.schema.json`；29个必需字段与可执行契约做字段集合一致性校验。通用JSON Schema引擎未安装，声明文件只完成语法/结构一致性检查；跨字段安全、未知、区间和版本约束由独立Python测试覆盖。

## 2. raw → normalized → distilled → curated

| 层 | 内容及身份 | 进入条件 | 退出与隔离规则 |
|---|---|---|---|
| raw | 仓库外只读 JSONL、来源文件 SHA-256、爬虫源代码摘要、采集时刻；身份为来源命名空间+菜品ID | 固定目标清单；同一批输入停止写入并出现结束标记，另核实进程退出 | 坏行不丢弃、不抛弃整批；隔离清单只记文件、行号、哈希和错误类型；原字节仍在仓库外原文件 |
| normalized | 中文字段解析、名称检索键、结构化配料、原营养基准与单位、占位/冲突标记 | 原料许可允许相应用途；结构可读；无冲突源ID | 缺失为 null/unknown；保留原值引用；不靠修正数值制造完整记录；冲突ID隔离、候选不准出库 |
| distilled | 自有紧凑字段：类别贡献区间、份量档位、做法事实、风险线索、别名候选、来源与版本 | 分类映射表/份量假设/做法规则已获产品确认；所有变换可追溯 | 只有审核候选，不能把“字段全”转成 eligible；没有许可时不生成或打包真实派生数据集 |
| curated | 人工审核的高频外卖核心集、正式 canonical_id 和精确匹配别名 | 许可证据、配料/做法一致性、份量依据、安全政策、去重及迁移测试均过；PM 复评通过 | 仍分可记录集与可推荐子集；审批后由独立发布步骤输出 App 所需字段 |

输入事实、政策判断和用户确认三者分开。P2 的 UserFoodProfile 只存在用户本机；不把本机纠错回流为内置 curated。

## 3. 字段映射与未知值

| raw 字段/新增字段 | normalized | distilled/curated | 性质与限制 |
|---|---|---|---|
| 菜品ID | source_id，字符串；source_type=nutridata | source_id、独立 canonical_id | 来源标识原值；绝不假定原字段为 id；不同来源相同数字不合并 |
| 菜品名称 | display_name、NFKC/casefold/去空白标点检索键 | canonical_name、经审核 aliases | 名称原文/规范化计算值；营销名≠品牌别名关系；地区、糖型、做法修饰词保留 |
| 成分 | ingredients[{name,amount_g,source_ref}]；ingredient_completeness | semantic_category、category_contributions | 克重是原站报告值，类别映射是推断，份数是估算；商品自身+100g不能视为完整配料表 |
| 菜肴做法 | 真实步骤、占位状态、多阶段做法候选和证据行引用 | preparation、risk_tags、field_provenance | 来源文本不打包；标签是规则推断/人工确认，不能只凭菜名或“炸”字判定整菜做法 |
| 计量单位 | nutrient_basis_g、basis_type=source_edible_mass | 份量估算的输入引用 | 当前形式为每 X 克可食部分；不是每100g、不是用户本次实际食量，也不能默认就是熟重 |
| 单位量 | source_unit_options[{label,grams}]、generic_template 标记 | size_bucket=small/regular/large/unknown；portion_range_g 可null；杯型另补 | 是页面下拉选项原值；大量重复通用模板，不能直接映射外卖小/中/大份或杯型 |
| 能量及宏量营养素 | energy_kcal、protein_g、fat_g、carbohydrate_g（各可 null）及基准 | 通常不打包，保留审核用途 | 解析 NRV 后含量，不把 NRV% 当克重；缺失不补0；碳水不是糖、更不是添加糖 |
| 维生素/矿物质 | 各营养素可 null；钠统一 mg，保留基准 | 审核风险时按政策使用，非核心字段不打包 | 未声明为实验室实测；原站值≠独立验证值；钠推盐是计算值且有适用条件，不暗改政策阈值 |
| 爬取时间 | source_observed_at，附原始时区是否确认 | 批次 manifest | 原值没有时区时记录 unknown，机器运行时区只能作为假设；不冒称配方最近更新日期 |
| source_sha256 | 输入文件摘要+源行引用 | 内部 provenance；发布可使用短来源字典键 | 确认具体来源批次，不包含账号/密码/登录态 |
| estimated | 任一推断或估算字段存在即 true | true 保持贯穿 | 人工审核不会把估算自动变为实测；字段级性质比总开关更精确 |
| confidence | null，或经标注集校准的0–1数值及校准证据 | 匹配/分类/份量分别评估 | 当前没有校准样本，禁止默认拍成0.9或1.0；字段覆盖率不是置信度 |
| review_status | unreviewed / needs_review / reviewed / rejected | 与 review_evidence 配对 | reviewed 需要审核人/日期/范围/证据；不意味着许可通过或健康 |
| license_status | unknown / restricted / approved | 独立发布门 | approved 要权利方授权范围、版本、归属与有效期证据；PM 同意本身不能代替许可 |
| schema_version / data_version / transform_version / policy_version | 分别版本化 | manifest 与数据包共同携带 | schema 描述结构；data 描述内容；transform 描述清洗映射；policy 描述准入规则，禁止混用 |

`unknown` 表示无法确定；`notApplicable` 仅表示已确认不适用。例如普通固体食物的杯型可为 notApplicable，而奶茶缺规格为 unknown。数值未知用 null；不得把 null 转成 [0,0] 或“0份”。已知真实零值在 normalized 保留来源状态，如水的宏量营养素全零不等于抓取失败；记录不承担六类贡献时走明确的非贡献语义，不拿全零普通菜对象占位。

## 4. 确定性去重（已实现的边界）

`acceptance.py:deduplicate` 已实现以下规则，并以合成测试验证顺序独立性：

1. 同 source_id、内容相同（仅排除爬取时间）时折叠重复尝试。候选按完整规范 JSON 字节序选择固定代表，不按文件最后一行覆盖；统计保留重复次数。
2. 同 source_id 有不同内容时，全部进入冲突ID清单，不静默选最新或“最完整”版本；该ID标待核实。后续经源站重核或人工裁决提供显式决议文件。
3. 同名不同ID、只有标点不同的名字只构建 collision groups，**不自动合并**。它们可能是同菜不同配方、品牌食品或不同来源条目；不能靠名字去掉真实变体。
4. 地区前后缀、做法、糖型、规格是语义，保留在检索键中；“四川版/清蒸/油炸/少糖”等不能自动剥离。需要别名归并时走人工 alias_decisions（source_ids、canonical_id、reason、reviewer、date、rule_version），按 canonical_id 再按 source_id 排序。
5. canonical_id 一旦发布必须稳定；后续合并使用 redirect/crosswalk，废止使用 tombstone，不复用ID。未发布前暂用 `nutridata:<source_id>`，不是现有 dish_id 的替代值。
6. curated 内一个精确别名键最多对应一个 canonical_id；有歧义则从精确自动命中索引退出，返回候选。不得利用当前 `putIfAbsent` 的先到先得作为冲突策略。

现有统计：91 个原文同名冲突组、94 个规范化名称冲突组；同名超额100条不等于100条可删除记录。详情以机器统计为准。

## 5. 份量与类别推导设计

类别：把可解析成分映射到经审核的食品字典，处理同义词、复合调味料、生熟状态和多类别贡献。可食克重总和相符仅验证算术，不证明成分完整、做法准确或食用份量真实。总脂肪也不能直接当添加烹调油。

类别贡献键保持现有六类 `grains / vegetables / fruits / protein / protein_soy / oil`；每个键为区间或null，整组未知也可null，不把缺键默认为零。`oil` 在现有seed序列化名为 `oil_base`，下一阶段适配要明确这一映射。dairy/nuts等可作为语义类别保留，但不在本阶段擅增指南目标；其六类映射需按获批规则，否则对应贡献未知。当前 `Portions.fromJson` 的缺值默认0、`StandardDish.fromJson` 的 recommendable 默认true、estimated 默认false与新契约冲突，必须在导入前处理，而不是直接丢弃未知字段。

份量：只有在配方尺度、单位意义、食用人数和熟制损耗都有依据时，才用“用户选份量区间 / 源配方基准”缩放各类别贡献。配料到交换份采用已批准 GuidelinePolicy 的换算规则。存在生熟/烹调损耗未知、通用下拉模板或多人餐时，暂留 unknown，或使用独立审核的宽区间并标 estimated=true；未经批准不在本阶段设定具体范围。

推荐：raw 的字段完整数只是后续审核的工作量上界。必须确认配料与做法不冲突、份量可解释、风险条件明确，再由政策判断。合格汉堡/三明治不因名称排除；已确认油炸即使 recommendable=true 也必须排除。只有条件事实齐备且政策允许，conditional 才可转 eligible；有未知风险时不得主动推荐。

品牌别名、糖型和杯型：零独立结构化字段。少量带品牌的包装食品名只提供候选，不形成外卖品牌-商品-SKU-配方版本关系；糖/炼乳成分可提示添加糖，不能推断顾客选了几分糖；杯/碗的克重选项不提供真实饮料容积或冰量。需要独立且许可明确的品牌菜单/配料资料，或 P2 用户本机确认。

## 6. 版本与迁移方案（未执行 App 变更）

本次设计契约命名为 FoodKnowledge draft schema 1，与已发布 seed schema 2 不同命名空间，不可直接塞给当前 `FoodDatabase.fromJson`。manifest 至少包含四类版本、原料摘要、规则字典摘要、审核决议摘要、许可状态、记录数、构建脚本摘要。

下一阶段审批后应把 `seed_schema_version` 与 `seed_data_version`/catalog digest 拆开，避免“结构不变，内容更新却不重新播种”。当前 App 对未知字段和缺省数值的防御性默认值不能承接本设计 null；需先实现明确的未知模型与兼容适配，再导入。

建议迁移事务：校验包摘要与版本兼容→只更新内置菜与类别→按 crosswalk 保留旧ID引用→写数据版本→提交。保留 meal_records 的历史快照、user_profiles、user_custom_dishes 和 pet_states；不使用 replaceAll 重建用户库，不根据旧菜删除历史记录。库更新失败应回滚事务，继续旧库；同版本且同digest幂等，版本相同digest不同视为发布错误。降级须有显式兼容方案，不能让旧客户端读取新结构后把未知值默认为零。

迁移必测：旧29道→当前1004道（已有）；当前库→获批新库（后续）；用户画像/备注/记录/时间戳逐值不变；旧菜ID重定向；同版本幂等；崩溃事务回滚；meta 缺失；结构相同内容版本升级；错误哈希、重复ID、全零占位、非法枚举、风险冲突拒绝导入。本次已运行现有完整343测试，包括当前4条 seed migration 测试，但不能当作新 schema 迁移已通过。

## 7. 体积与性能预算

| 指标 | 当前1004道库（实测） | 新 curated（尚未生成） | 审批后验证方法 |
|---|---|---|---|
| JSON 字节 | 639,757 | unknown | UTF-8 确定性紧凑序列化后测文件字节 |
| gzip 字节 | 50,155（mtime=0） | unknown | 同算法比较；gzip仅用于比较，不等同APK实际压缩 |
| SQLite 首次导入耗时 | 本次未测性能，功能测试通过 | unknown | 隔离临时DB、同设备同构建，至少10轮，报告中位数/p95，区分首次导入与已有版本打开 |
| Android 冷启动影响 | 本次无真机计时 | unknown | 小米目标机：同ABI同release、固定数据、30次强停冷启，测首次绘制与可交互时间；分别空库/已播种 |

建议而非已批准的预算：先审核500–1000道核心条目，未压缩 JSON ≤640KB、gzip ≤64KB；超过预算必须说明核心收益。来源公共字段用包级字典去重，App 不带长做法、原营养面板或中间层。Android 冷启动p95相对基线增量暂定≤50ms、首次导入p95暂定≤500ms，待真机基线与产品确认。不能拿31MB原始JSONL大小推算新库大小，也不能用桌面脚本耗时冒充手机冷启动。

## 8. 许可与数据保护

2026-09-05 核查本地采集参考仓库 remote 为 `sunw80910/nutridata_data`；[其公开README](https://github.com/sunw80910/nutridata_data) 将数据用途限定为学习参考、非商业。未发现该仓库 LICENSE 文件；即使爬虫代码另有开源许可，也不能自动覆盖站点数据。

[nutridata.cn 首页](https://nutridata.cn/) 在本次公开文本抓取没有返回可核实的授权条款；`/home`、`/login` 抓取失败，未据此推断没有协议。尚未取得权利方对批量采集、转换、商业使用、离线内置和再分发的明确授权。相似名称的 nutridata.io 或其他 NutriData 项目许可不适用于本源。

结论为 license_status=unknown / redistribution_blocked。获取许可需明确授权主体、数据及字段范围、允许的转换/派生、App内置及商业/非商业再分发、署名、有效期、更新及撤回安排；未获证据前不把 raw 或派生数据包提交、传共享站点或打入 APK。当前交付仅自编脚本/合成fixture、统计和ID审计索引，无菜名配料做法批量复制。账号配置、含凭据交接文档不读入分析输出、不入库、不复制；不执行 git add/commit/push。

## 9. P3 待办登记（本阶段不改）

| 待办 | 问题与未来验收 |
|---|---|
| 主食保底与首推排序分离 | 保底决定是否保留主食名额；首推按获批排序策略决定。覆盖水果缺口最大且主食仍有缺口的共存场景 |
| 推荐原因与输出一致 | reason code、文案和实际首推/清淡标签来自同一决策；不得“水果缺口最大”却不解释主食置首 |
| 油炸确定性排除优先 | 所有模式先安全过滤；即使 recommendable=true，也不放行已知油炸；用正反例及属性测试覆盖 |
| 更换分类测试夹具 | 用合格的非油炸、少/无酱混合菜保留“槽位grains、自身主导protein”的区分，替换当前“香辣炸鸡排必须被推荐”夹具；不删除分类断言 |

## 10. 交付与复评入口

原料结果和精确摘要见 `nutridata-raw-acceptance.md`、`nutridata-audit/statistics.json`。设计契约与去重/未知/风险边界由独立Python合成测试覆盖。本次无业务数据或界面变化；回滚只需移除本次新增交付文件，原菜库和用户数据不受影响。

产品需复评：原料仅用于后续审核的结论、缺失ID继续标待核实、核心集范围、份量证据门槛、置信度校准方案、版本拆分与性能预算。许可责任人应补可核实授权；许可与产品复评未通过前不启动实际蒸馏发布和 App 替换。


## 11. P1 后半段定稿：FoodKnowledge schema 2（2026-09-05）

本节替代前半段关于 draft schema 1、`portion_range_g`、全零一律拒绝、尚无 Dart 适配的描述。前文作为原料验收时的历史设计保留。数据库仍为 v3，正式种子仍为原来的 schema v2、1004 道。知识 schema 2 与旧种子 schema 2 是不同命名空间，不能因为数字相同就互相导入。

### 11.1 字段与事实边界

完整记录具有 31 个必需字段，字段缺失直接拒绝；未知用 `null` 或对应 `unknown`，不能省略后依赖默认值。机器结构文件保留原文件名 `food-knowledge-draft.schema.json`，其 `$id` 已改为 `urn:canting:food-knowledge:2`。Python `contract.validate` 与 Dart `FoodKnowledge.fromJson` 是跨字段语义校验入口；33 个相同合成正反例在两侧执行。

| 字段 | 定稿含义 / Dart 接口 | 缺失或未知规则 |
|---|---|---|
| canonical_id / canonical_name / aliases | 稳定知识 ID、标准展示名称和别名；`id` / `name` / `toJson()` | ID、名称必填；空别名表不是已经核实没有别名 |
| semantic_category | **商品类别**；Dart `productCategory`。新增 `burger`；奶茶和咖啡为 beverage 下的子类，甜品为 dessert | `unknown`；不从旧菜库 category 自动升级，不据此分配膳食份数 |
| beverage_type | milk_tea / coffee / tea / milk / water / other / unknown / notApplicable | beverage 不能 notApplicable；非 beverage 只能 unknown / notApplicable |
| sugar_level | 用户所选甜度 / 加糖选项：none / low / regular / high / unknown / notApplicable | none 只代表“无糖选项”；不代表实测总糖为 0。饮品不得 notApplicable |
| recipe_known | true / false / null，关键配方事实是否已被核实；`recipeKnown` | true 必须有配方证据引用；null 未核实，false 已知配方仍不完整。单独的 true 不是准入许可 |
| preparation | 做法枚举；`preparation` | unknown；fried 是直接排除事实，不依赖 risk_tags |
| cup_size / size_bucket | 杯型 / 份量档位标签；`cupSize` / `sizeBucket` | unknown；large 没有默认体积，蛋糕尺寸没有默认食用重量 |
| portion_range | `null` 或 `{min, max, unit: g\|ml, scope: consumed}`；`ConsumedPortion` + `KnowledgeRange` + `PortionUnit` | 只描述实际食用范围，需来源证据；不接受整只商品尺寸、cm、kg 等隐式换算输入。0 ≤ min ≤ max、有限数字，布尔不是数值；[0,0] 可表达有证据的实际零摄入 |
| category_contributions | **膳食贡献**；六键 grains / vegetables / fruits / protein / protein_soy / oil，值为 null 或非负区间；Dart `contributions` | 整体 null 或个别维度 null 均可保存，但不能 eligible；真实 [0,0] 与未知不同。贡献以该条事实的食用情境为基准，依据写入 provenance，不把营养克数直接充作份数 |
| source_type / source_id / source_sha256 | 来源类型、来源 ID、源文件摘要 | 原值可追溯，不用旧 recommendable 推断来源；纯合成 fixture 的 0 摘要不代表真实文件 |
| schema_version / data_version | 记录结构版本 2 / 与包 content_version 相等的内容版本 | 不能用结构版本触发每次内容更新 |
| transform_version / policy_version | 数据变换版本 / 契约政策版本引用 | 必填；不表示已经更改 App 的推荐引擎 |
| estimated / confidence / confidence_evidence | 估算标记、可校准置信度及校准证据 | confidence 无依据为 null；来源 inferred / estimated 时 estimated 必须 true |
| field_provenance | 九组关键事实的 kind 与 evidence：商品类、饮品子类、配方、做法、糖型、杯型、档位、食用量、贡献 | 数值存在就必须有证据；真实零也一样。证据是引用字符串，校验器不替人工核实证据真伪 |
| review_status / review_evidence | 审核状态和审核证据 | 旧库未知；新记录可 unreviewed / needs_review / reviewed / rejected；reviewed 必须有证据 |
| license_status / license_evidence | 用途与许可审查结论及证据 | unknown / restricted / approved；approved 需要证据。代码测试不构成真实 Nutradata 数据授权 |
| risk_tags / eligibility / eligibility_reasons / facts_complete | 风险线索、声明准入、原因、事实完整性声明 | 声明必须与事实一致；标签为空不是安全证明；合成原因码不直接展示给用户 |

`portion_range` 的 g 和 ml 没有转换方法。需要密度、分食比例、品牌杯型容量等新证据时，后续阶段另行设计；本阶段不填 500ml，不把 8 寸蛋糕当作用户食用了整只。

### 11.2 准入校验与推荐边界

声明 eligible 必须同时满足：做法明确且非油炸、无风险标签、配方已核实且有证据、事实完整、已审核且有审核证据、许可通过且有证据、商品类别明确、六项贡献全部已知、相关来源明确、提供原因。low / regular / high 甜度事实均不能 eligible，漏填标签也会拒绝。beverage 额外要求明确子类及有证据的 none 选项；糖型未知同样拒绝。

奶茶选 none 而 recipe_known 为 null / false 时继续拒绝；审核缺失同样拒绝。咖啡、茶等不会只因属于 beverage 被一律拒绝，但仍须满足所有独立条件。没有实测总糖字段，不能声称总糖为零；已核实配方是否仍有高糖等风险必须由审核证据支撑，不可只勾 facts_complete。

这是一项**数据导入一致性门槛**，不等于 P3 推荐过滤已完成。保留原有 recommendable、推荐排序与推荐原因生成逻辑；新知识包没有被插入现有推荐候选。P3 仍须实现：主食保底与首推排序分开；原因和实际输出一致；油炸事实优先于 recommendable；用合格混合菜替换“炸鸡必须被推荐”的旧分类夹具。

### 11.3 包、摘要和同步

包包含且仅包含 `schema_version: 2`、`content_version`、`content_sha256`、`content_json`。`content_json` 是 UTF-8 JSON 字符串，内部为 `{records: [...]}`；摘要为该字符串**原始 UTF-8 字节**的 SHA-256，不含外层转义。数字表示、记录顺序或空白改变都会改变摘要，发布方必须冻结序列化字节。读取时先校验摘要，再校验所有记录、ID 唯一性及记录 data_version 与包版本一致性。不同来源同名仍保持不同 ID，不凭名称合并。

包元信息只存一份；本阶段为便于审计保留记录内来源/审核信息，没有强求将所有审计元信息加入旧 StandardDish。结构版本决定解析器，内容版本标识不可变发布内容；版本是非空不透明字符串，不做字典序或 SemVer 大小推断。接受过的版本永久绑定摘要；已接受旧包重播为 no-op，不降级当前包。未见过的版本是显式同步请求，调用方负责选择发布序列，不是自动更新服务。

`DatabaseHelper.syncKnowledgePackage` 在现有 v3 的 app_meta 中保存活动包 `food_knowledge_package`，并记录 `food_knowledge_digest:<content_version>`。同版本同摘要返回 0；同版本不同摘要抛 StateError；新内容版本原子替换活动知识快照。包内删掉的 ID 不再出现在新知识快照中，旧 dishes 表和历史餐食 JSON 不变。完整内容写入和版本账本写入处于同一 SQLite 事务；错误回滚二者。SHA-256 校验错误在数据库写入前发生。

`initialize(seedData: legacy.withKnowledgePackage(package))` 将旧种子和知识包同步放在同一事务；失败关闭连接，允许重新打开旧库。旧 seed_schema_version 仍兼容原菜库，但其元数据写入已移入种子更新事务。已有 v1/v2 SQLite 仍通过既有迁移升到 v3，无新增数据库结构版本；不自动改变旧记录的来源或审核状态。

### 11.4 P2 可用的离线接口

```dart
final package = FoodKnowledgePackage.fromJson(decodedPackage);
await helper.syncKnowledgePackage(package); // 已初始化的本地库
final catalog = await helper.loadFoodDatabase();
final knowledge = catalog.findKnowledgeById('synthetic:1');
final product = knowledge?.productCategory;
final contributionIntervals = knowledge?.contributions;
final consumed = knowledge?.portion; // unit 明确为 g 或 ml，或 null
```

旧 `StandardDish` 的 `knowledgeSource`、`knowledgeReviewStatus`、`sugarLevel`、`productCategory` 缺失时明确为 unknown，`consumedPortion` 为 null，原数据序列化不增加虚构来源。`FoodKnowledge.exactPortions` 仅在六维都已知且各自上下界相等时返回旧标量 Portions；有未知或非单点区间时返回 null，绝不取中点。`Portions.fromKnownJson` 拒绝缺键、null、负值和非有限值。旧 StandardDish 入口明确拒绝知识记录形状；若附带知识，则只有完全已知且与旧标量一致的贡献才允许解析。

P2 应消费 FoodKnowledge 的商品类别/子类和事实，不用旧 category 代替用户可纠正商品类别，不把 nullable exactPortions 通过 `?? Portions.zero` 兜底。未知提示和用户确认存储由 P2 实现，本阶段未开始 UI 或 UserFoodProfile 开发。

### 11.5 迁移限制与回退

draft 1 没有真实派生记录，因此不存在要自动升级的真实知识包。以后若读取 draft 1，不可机械把 portion_range_g 搬为 consumed g：先核实它是实际食用量还是整份配方重量；不能确定则置 null。新加 beverage_type / recipe_known 默认 unknown / null，不提升为已审核。由人工审核形成 schema 2 后再走正常验证。

本轮合成小包采用整包读写和线性 ID 查找，足以验证工程契约；没有宣称通过 24,611 条真实包的体积、加载时延或 Android 真机性能验收。真实发布前仍需独立许可依据、人工复核、压缩/体积及设备基准测试。品牌别名、所选甜度、杯型容量、密度、分食比例、实际份量与总糖依然需要独立证据。

失败自动回滚；功能回退可恢复本轮变更前的代码，原菜库与用户表没有变化。若将来已同步知识包，停用知识读取即可继续旧库路径；不删除 app_meta 或用户数据库来“回退”。需要正式回退内容时以新的内容版本发布经审核的旧内容，保持版本账本不可变。
