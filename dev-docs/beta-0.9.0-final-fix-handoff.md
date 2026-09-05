# 0.9.0-beta 终审最小修正交接（2026-09-06）

结论：完成。仅修改文档并新增测试，无生产代码、数据结构、规则或用户体验变化。现有未提交工作全部保留。写入权交回审核方；未 commit、push、发布或安装设备。

## 修改清单

- `test/state/p6a_widget_query_failure_test.dart`：新增一个完整故障恢复回归。真实临时 SQLite 数据库未初始化时快照日期为 null；正常加载有效；重命名 meal_records 表注入查询异常并显式断言 DatabaseException，7/28 天窗口均 error 且快照日期为 null；恢复表名后重新查询，日期与 UTC 偏移有效。
- `dev-docs/p5-device-checklist.md` 及随包副本：将旧日期/默认图标问题标记为 P5 历史观察，说明 P6-A 已修复、真机待验。
- `build/releases/0.9.0-beta/START-HERE.md`、`known-limitations.md`、`package-info.md`、`RELEASE-NOTES.md`：统一为已授权 beta 测试发布、非 V1 封版，更新回归数；正式发布决策与 beta 授权分开表述。
- `dev-docs/releases/0.9.0-beta/`：保存上述文档与 feedback-template.md、p5-device-checklist.md、SHA256SUMS.txt、package-analysis.json，共 8 个文件，无 APK。
- `dev-docs/p6a-evidence/review-fix-20260906/`：本次命令、完整日志、测试证据及 source-apk-verification.json。历史冻结报告未修改。

## 实际验证

- `dart format test/state/p6a_widget_query_failure_test.dart`：通过。
- `flutter test --no-pub --concurrency=1 test/state/p6a_widget_query_failure_test.dart`：1 项通过，日志中实际出现 no such table: meal_records。
- `CANTING_P6A_RUN_ID=review-fix-20260906 python scripts/p6a/run.py analyze`：No issues found，退出码 0。
- 同证据目录运行 `python scripts/p6a/run.py full`：501 项通过，退出码 0，含新增故障注入测试。
- 审核方先前独立 Kotlin clean/retest 38 项通过；本任务没有 Android 代码变更，未重复运行 Kotlin。
- split/universal 构建输入文件集合及每个文件 SHA-256 均与 beta-20260906 原始 manifest 一致，各 145 项；两 APK 与原 SHA256SUMS.txt 一致。详细值见 source-apk-verification.json。没有生产 bug 需要修复，无需重建 APK。

## 未验事项与边界

小米真机图标、Widget 跨日/缩放/重启、旧数据升级与完整恢复、原生首次离线/无 GMS OCR、系统备份、真实订单图与独立留出/完整危险场景仍 not_run。重要旧数据升级仍暂停。沿用 Android Debug 测试签名，非 V1 正式封版。

没有新增待产品决策项；下一步仅由审核方复核并按已有授权执行 beta 发布，本任务不开始下一阶段。若撤销本次补丁，仅撤销上述文档修正及新测试，不回滚原有未提交工作；历史验证证据应保留。
