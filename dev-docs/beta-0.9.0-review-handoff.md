# 0.9.0-beta 最终审核交接

状态：开发准备完成，等待独立产品经理审核；尚未commit/push/创建Release。用户已明确授权最终审核通过后提交并发布GitHub beta。

## 审核入口

实际源码：D:/dev/canting。读取AGENTS.md、dev-docs/p6a-test-package-report.md、dev-docs/ponytail-simplification-report.md、dev-docs/p5-device-checklist.md。
任务书：C:/Users/gxy20/Documents/ChatGPT/代码审核/餐盘_P6-A_执行交接包/餐盘_P6-A_执行任务书.md。
后续用户指令覆盖原任务书的“不提交/不分发”：用户要求加载Ponytail精简、版本0.9.0-beta、在餐盘APP项目经理/代码审核新建对话加载PM Master审核；若需修改，在餐盘APP开发项目新建对话加载Ponytail修正；产品经理复核后发布GitHub。工作树创建失败必须重试。

## 本轮结果

P6-A先完成并冻结在build/p6a-delivery/run-20260905；其证据dev-docs/p6a-evidence/run-20260905。随后做精简，beta独立证据dev-docs/p6a-evidence/beta-20260906。
最新Flutter静态零问题、完整500通过；Kotlin第二次命令显式cleanTestDebugUnitTest后重新执行38通过（第一次UP-TO-DATE日志保留）。universal与split均重新release构建，源文件哈希相同且与当前文件一致。
Ponytail聚焦重复实现，6个生产文件合计-45行（含About版本/文案与格式化）；没有删功能、迁移、校验或插件，也没有新增依赖。三入口搜索对照、元数据校验和Map独立性有专门测试。
宠物代码和资源哈希保持P6前原状。旧P5改动按原manifest核实并保留；首次源码基线P4 6f1286d、P3 ef1613c。当前main相对origin/main领先9提交，未重写历史。

## 成品

路径：D:/dev/canting/build/releases/0.9.0-beta。
versionName=0.9.0-beta，versionCode=5003（主备相同），包名com.canting.canting。
证书SHA-256：336e3f94c188e3a5452475abaf0db1c2bd56a0d1986b5cf36cbdb3cbb6b2bd03，与旧beta和P5相同的Android Debug测试签名。

| 构建来源 | 字节 | SHA-256 |
|---|---:|---|
| app-arm64-v8a-release.apk | 35,839,129 | 1fb4a88e9331e45939c6abc46e8a318466688f77f242c00f6fa8ee223fe0e807 |
| app-release.apk | 93,335,900 | ed16e84934aabb6b7caef418c9ed3d2995d512aca03c5882aab8318fe3ae9c2f |

包内各密度可见RGBA像素与指定母稿派生资源一致（Android会清除完全透明像素的RGB，这部分不影响显示）；实际Manifest的icon/roundIcon资源ID已核对。adaptive配置已确认。release无网络权限，保留备份排除和私有Provider。
随包有START-HERE、SHA256SUMS、package-info、feedback-template、known-limitations、RELEASE-NOTES、P5矩阵、图标预览和package-analysis。

## 审核重点与限制

重点核查：跨日/时区/旧快照是否失效、旧布局日期标记、保存编辑删除/前台恢复同步、未初始化/加载失败不误称空记录；精简三搜索入口语义、排序、空输入；普通/元数据写入无schema变化；原有安全推荐、未知识别、事务、隐私和宠物奖励边界。
重要数据升级仍暂停：当前导出无完整恢复入口，不能声称真实升级通过。小米、真实原生OCR、无GMS、系统备份、P6-B多人试用均not_run；beta上传不表示V1封版。不得虚填证据或替用户安装/清数据。
工具首次检查失败已修正：新测试不存在的copyWith；备份pubspec被分析；APK资源混淆文件名/CRLF/透明RGB差异；split合并Manifest路径。失败不是产品运行故障，构建和核验最终成功。原始P5/P4证据只读保留。

## 复跑和发布

每次复跑设新的CANTING_P6A_RUN_ID，按scripts/p6a/run.py顺序analyze/full/kotlin/universal/split；inspect_artifacts.py需要Pillow，可用已安装Codex Python运行时。不得覆盖冻结validation.json目录。
GitHub仓库 https://github.com/BuuaaA/canting ，origin HTTPS；gh已登录BuuaaA（读配置/网络需相应执行权限），目标v0.9.0-beta在核查时不存在。
发布前核对最终工作树、源码哈希与APK；有代码修改必须新运行目录回归、重建并更新交接资料/哈希。审查通过后提交本轮P5/P6/精简和相应证据，push非强制到main，创建v0.9.0-beta标记和GitHub prerelease；上传最终主/备APK及SHA256SUMS、安装指南等资料。APK放Release资产，不加入Git历史。不要上传密钥/密码/真实数据库/个人截图。
最终报告给出审核结论、修正任务ID（若有）、commit、tag、Release链接及上传资产哈希。
