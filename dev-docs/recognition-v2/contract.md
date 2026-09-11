# 当前本地合同 recognition-n0.2 / meal-v2.1；持久化 meal-v2.2

2026-09-06。权威：餐盘_PRD_V2.1.md §6；最新用户约束覆盖旧供应商/网关预设。
本地合同完成不等于真实识别可行性通过。N1 已接本地保存，N2/N3 另阶段。历史原文见 n0.1-contract.md；当前补正依据 V2.2 与 N0_产品复评_V2.3.md R1—R3。

## 文件与调用

- recognition.schema.json：JSON Schema 2020-12，默认 Draft；$defs 包含 Request、Response、Provider、Deletion、Reservation。
- recognition_contract.dart：加载调用方明确提供的本地 schema，验证结构、白名单和关系，返回新对象，不修改输入。
- recognition_adapter.dart：unconfigured 默认不可用；mock 必须显式指定且提供合成结果；external 也返回 PROVIDER_UNAVAILABLE。无网络库、图片读取、重试、定时任务或凭证解析调用。
- examples.json：合成 screenshot、food_photo、个人半碗、empty_food，以及无云授权请求和未配置 Provider。不存在实际图片；零 hash 是合成占位，不是取样证据。
- `dart run tool/recognition_v2_mock.dart`：输出两入口及空负例的合成响应，不写产品数据。

白名单外普通结果字段先丢弃，清理后的对象满足 schema 的 additionalProperties=false；树结构越界、独立子项购买数量、非法引用等拒绝整结果。原始 JSON 结构检查与关系校验必须一起使用，不允许直接将 Map 映射 MealDish。验证器只实现此文件实际使用的 schema 关键字，不是通用 JSON Schema 库；修改关键字须同步修改校验器和测试。模型文本入口限制256 KiB，非法 JSON 返回固定错误码、不回显原文。

## 字段与来源

Fact 的 value=null 当且仅当 provenance=unknown；不会默认补1或0。所有事实必须携带 reviewStatus 与 evidenceRefs。观测必须有对应类型的存在证据；text_observed 需非空原文与 assetId，photo_observed 需照片入口、assetId 和有效区域。名称推断可引用标题原文；接受后来源仍 name_inference。结构校验无法证明图上真的存在某食物，也无法证明用户真实做过确认，后续必须通过可信 UI 命令更新本地草稿，不能接受供应商声称 user_input。

模型输入路径强制 fromModel=true：禁止 accepted/rejected、user_input、database_estimate、个人摄入或个人比例、active=true 和 selected=true。N0 无校准证据，confidence 仅 candidate/unknown，calibrated=null；N1 可以由用户明确选择。以后启用自动 accept 须按入口校准并升级合同，不能悄悄降低门槛。

草稿ID、请求ID、图片ID为客户端生成 UUID；商品/组成/证据ID为草稿内局部ID；所有定义的ID互异。数组上限3图片、20商品、每商品8组成；组成不得再包含组成或独立购买数量。bbox/crop 统一为原图归一化 [left,top,right,bottom]，满足0≤left<right≤1、0≤top<bottom≤1。crop 为处理图在原图上的裁剪范围；N0只支持轴对齐裁剪/缩放，不支持旋转透视，未来处理须另版本映射。证据bbox仍指原图坐标。

ProductUnit 另保留 specifications:Fact<string>[]，将杯型/冰/配方文字与购买数量隔离。订单状态枚举不是照片里的购买证据。模型质量（营销区排除、被遮挡米饭、数量是否真的写明）由人工金标另验，不能靠 schema 证明。

## 份量参考实现（不是营养规则）

effectiveAmounts 只输出每个有效叶子的原单位摄入量，不相加不同单位，不生成克重范围或营养贡献。

| portionBasis | 唯一计算 |
|---|---|
| personal_consumed | portion；购买2份、个人半碗仍0.5 bowl；allocationRatio/consumedRatio必须null |
| served_total | portion × allocationRatio × consumedRatio |
| per_product_unit | 单个购买商品中该叶子的portion × purchaseQuantity × allocationRatio × consumedRatio |
| unknown | null；不得视为0 |

其他必需因子未知则null；明确 consumedRatio=0可确认未吃。personal_consumed 的未吃扩展字段 notEaten:Fact<true>，只允许 accepted user_input，排除该叶子，不伪造portion=0。ordinal不数值相乘；本阶段无审核单位映射，自动范围默认null。R1：g/ml 仅接受明确用户输入，有限正数≤10000；bowl/cup/serving 仍为有限正数≤99，购买数量仍为1—99整数。ordinal/unknown 的 value 必须 null。规格473ml不自动成为个人摄入。schema 用既有 anyOf 分支表达单位约束，语义验证同限；未新增未实现关键字。

estimateRange 只能是 database_estimate，含estimated=true和knowledgeVersion；非空值必须与调用方提供的该叶子审核范围完全匹配。版本字符串本身不是审核证据；N0无实际单位映射，测试中的审核范围是测试桩。

nutritionMode=aggregate 只允许父 active；children 只允许选中商品的选中子 active；unknown 均不active。失活计算仍可存编辑历史但不能累计；部分子项未知不补父项，完整度保留partial/unknown。N1接规则时还必须核对类别映射、确认状态及knowledge/policy快照，不得把本参考的碗数直接当食物组份数。

## 凭证与模型配置边界

Provider 仅允许 mode、endpoint、model、credentialRef、delivery、region、thinking=false、inputTokenLimit≤6000、outputTokenLimit≤1200。没有默认供应商/账户。endpoint只允许HTTPS且无userinfo/query/fragment；不接受任意headers/apiKey/token/secret配置。credentialRef只能是credential:别名，无真实密钥；密钥不能进入源码、日志、测试样例、餐食导出或明文数据库。

CredentialAccess 是后续安全输入/注入边界：可信宿主通过凭证引用调用短生命周期 use(secret) 回调。真实输入控件、Android安全存储/代理短期访问凭证、传输及凭证轮换未实现；N0不调用回调，不向用户索取真实Key。后续 UI 应遮盖输入、不自动读剪贴板、不记录输入正文，关闭/提交后清空控制器；仅显式启用安全存储才持久化。Dart不可变字符串无法承诺内存零化，不能宣称实现安全存储。

BYOK 和 backend_proxy 都是待决方案；BYOK也可能把图片发到供应商云端，不能叫离线。两方案共同要求本次发图范围与目标告知、明确授权、取消后不补传。仅配了endpoint/Key不能启用真实调用。本阶段无配置空壳页面。

## 请求绑定及候选后端签发（真实接入前再评审）

Request 包含draftId/requestId/draftRevision/sourceKind/assets/hash/parameterHash/cloudConsent/consentVersion/requestTicket。所有任务响应（包括失败与删除）回显草稿、请求、版本和assetId集合。结果内部还必须匹配sourceKind与完整assets映射/hash。canApply只允许同版本、未取消且review/empty_food结果；该函数尚未接 AppState。

若最终选择餐盘代理，以下签发方式仅作历史候选，算法与窗口须在部署决定后复评，不锁死 MAC 方案：客户端生成requestId；鉴权后服务端签发requestTicket=base64url(payloadBytes).base64url(HMAC-SHA256(serverSecret,payloadBytes))。payload包含ticketVersion、kid、主体伪标识、requestId、服务器issuedAt/initialSubmitBefore、requestDigest和随机nonce。MAC校验原始payload字节，常量时间比较，kid密钥保留至少覆盖30天；服务端时钟与签发数据库记录为准。首次POST须在10分钟签发窗口内；签发时将主体+requestId唯一保留，不能为旧requestId重新签发。重复请求校验签名及绑定后查既有任务。requestDigest=SHA256(服务端规范序列化的draftId/requestId/draftRevision/sourceKind、有序assetId/hash/crop/capturePhase、consentVersion及参数)，参数键排序、数组保序、UTF-8、禁止非有限数。

同主体同键同摘要返回原结果，不二次发供应商；同键改内容409。内容清理后保留最小墓碑30天，旧键只返回cancelled/deleted/expired；签发时间超过30天直接拒绝，即使墓碑清理也不能成为新任务。过期返回RESULT_EXPIRED，需要用户主动新请求，禁止自动重传。真正签发服务、MAC代码、抗重放、时钟与并发测试属于选择后端代理后真实接入前的候选工作，不是当前N2任务。

若选择BYOK，上述服务端签发/墓碑不是当前客户端可以提供的保证。后续必须重新评审可信签发/幂等替代方式及供应商能力；客户端本地状态不能宣称阻止供应商重复计费。当前未绑定网关、部署或账户方案。

## 删除与预算（若选后端代理的真实接入候选合同）

Deletion 分别返回ownContentStatus和providerDeletionStatus。自有删除不等于供应商删除；requested不等于confirmed。服务内容建议30分钟取回窗口、24小时清理告警；公开启用前落实具体删除/安全/费用负责人、保留例外与失败演练。

Reservation 绑定requestId、priceVersion、billingPeriod（Asia/Shanghai自然月）、projectBudgetId和CNY金额。预占/结算以数据库事务和唯一结算事件实现；未知费用保持预占，取消和跨月不释放；迟到费用归原月并计项目累计。新月不能绕过项目总封顶；差额只释放一次；只有确认无需付费才全释放。过期价格/无法计算最坏费用拒绝新付费任务，80%告警、100%停止新预占。schema只检查字段，未实现资金账本、删除服务或声称并发安全。

## N1允许范围与版本迁移

本合同供N1在独立开工指令后实现领域/本地保存，允许沿用Mock，不需要真实模型效果通过；不能据此直接开启真实联网。N1需覆盖v1 legacy_aggregate、事务迁移、保存幂等、导出清除、旧快照原值不变；将未采用的旧计算路径active=false。编辑事实需append-only记录原事实快照及字段路径，接受操作只改reviewStatus，修改值生成user_input；该本地编辑历史结构与knowledge/policy快照由N1冻结，不能借模型事实替代。N0未触及数据库。

## N1 / N2 当前接入约定（2026-09-07，优先于历史措辞）

- N2 本地传输边界、Mock 和无秘密的 API 配置占位，无需选择 BYOK/代理、无需票据签发或真实 API 授权。requestTicket=null 合法；继续绑定 draftId/requestId/revision/资产集合。真实传输、生产后台、账单与供应商删除继续延后。
- 唯一模拟字段为 simulated:boolean。旧需求中的 simulation=true 是旧拼写，不能增加别名。模拟 usage=null；N1 快照保留 simulated=true，旧摘要显示[模拟]，AppState 的 release 模式拒绝保存模拟记录。Mock 不能作为真实质量/成本指标。
- MealDraftV2.fromResponse 校验模型所有权与绑定；可信 UI 通过 select/setMode/reviewFact/editFact/setIntake 更新，失败编辑不改变 revision。接受只改 reviewStatus，修改值生成 user_input，history 保留前后节点及字段路径。
- AppState.saveRecognitionMeal 是 N1 真正本地保存入口；draftId 等于 mealId，同一草稿重复提交不覆盖首个快照。N3 负责完整 UI；历史的明确编辑可用 MealDraftV2.fromMeal 恢复（保留历史）→toMeal→saveMeal。旧 UI 对 v2 降级保存会拒绝，不能丢掉组成。
- 组成、证据、事实、编辑历史及版本与标量摘要封装在同一 record_json，随现有事务一起提交，避免双表半条记录。SQLite v5 的 draft_id 唯一索引额外保护幂等；record_version=1 的旧记录原 JSON 不重写。
- 当前只桥接已有 ServingEstimator 的 foodExchange 克数换算，且名称已接受、个人有效量已知；保存每叶子的实际量/单位、换算依据、每份克数及贡献快照。单位不匹配、碗杯、ordinal、未知和无审核映射均保持贡献 null。没有新增碗转克、毫升转克、范围中点、分类兜底或营养阈值。
- children 只算选中子；aggregate 只算父；unknown 都不算。已知小计进入旧确定性引擎，未知占位让 structureComplete=false。总值字段明确 known_subtotal，不把未知解释为零。
- v4→v5 前 checkpoint、关闭旧连接、原子保存 .pre-v5.db；升级 DDL 由 SQLite onUpgrade 事务执行，失败回滚旧版本并拒绝初始化写入。清除记录/全部/单条删除会清理备份，避免已删餐食留在回滚副本。迁移时应用启动须独占写入；不在旧 APK 中打开 v5 库。
- 导出沿用 AppState.exportAllJson，输出 schema_version=3/database_version=5，完整 record_json 包含图谱及历史。取消/保存后的原图缓存清理仍由 N3 入口生命周期管理；N1 只保存无文件路径的来源摘要和资产 hash，不保存图像字节。

## N2 可执行边界（2026-09-07）

- `RecognitionAdapter.recognize` 是 N3 可直接调用的异步边界；显式 `MockRecognitionScenario` 固定支持 success、noFood、invalidStructure、timeout、cancelled、quotaExceeded。每个终态回显 draftId/requestId/draftRevision/assetIds；成功结果仍经过模型所有权及结构校验。
- `RecognitionCancellation` 可在等待中取消且幂等。取消、超时、错误响应都不含 result，`MealDraftV2.fromResponse` 只接受 review；迟到、版本或资产不匹配继续由 `response/canApply` 拒绝。Mock 的迟到 future 无写草稿或保存副作用。
- unconfigured/external 均直接返回 PROVIDER_UNAVAILABLE，`CredentialAccess` 不被调用；当前代码没有 HTTP 客户端或外部传输实现。requestTicket=null 继续合法。
- `RecognitionConfiguration` 复用 SharedPreferences，仅持久化 Provider 白名单内的 provider/endpoint/model/credentialRef/delivery/region/token limits 等无秘密配置。临时凭证只保留在对象生命周期，保存、取消/离开调用 `clearTemporaryCredential`，清除调用 `clear`；重启状态始终为 not_configured。不要传入真实密钥；Dart 字符串不能承诺内存零化。
