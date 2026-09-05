# P5 复跑工具

从源码仓库根目录运行，先设置新的证据目录标识，例如 PowerShell：

```powershell
$env:CANTING_P5_RUN_ID='review-20260906-01'
python scripts/p5/run.py analyze
python scripts/p5/run.py full
python scripts/p5/run.py kotlin
python scripts/p5/run.py universal
python scripts/p5/run.py split
python scripts/p5/run.py bundle
python scripts/p5/inspect_artifacts.py
python scripts/p5/validate_configuration.py
```

逐项确认退出码再运行下一项，不并行运行 Flutter、Gradle 和模拟器。工具适配当前 Windows 安装的 Flutter/Android SDK/JBR 路径；换机器需先核对路径、版本和缓存，不自动升级依赖。

构建使用生产入口 lib/main.dart、release模式、全部三个ABI、离线Gradle、单worker、2GB堆。full使用concurrency=1。run.py设置CANTING_TEST_EVIDENCE_DIR到本次test-output；直接跑测试时也可显式指定新的目录。Flutter默认build/test-evidence/latest，Kotlin默认模块build/test-evidence，不应将环境变量指向冻结证据。

日志与构建前源哈希位于dev-docs/p5-evidence/<run_id>/，后续工具产物位于build/p5-artifacts/<run_id>/；本次最初开发运行产物位于build/p5-artifacts/{baseline-offline,universal,split,bundle}/，以本次JSON中的路径为准。run.py保留重复命令的独立日志；存在validation.json的目录视为冻结，不再写入。不要再次使用run-20260905，也不要直接运行会覆盖P4目录的旧metrics/native_metrics脚本。

inspect_artifacts.py记录APK/AAB精确字节数、SHA-256、APK证书/Manifest、ZIP压缩与解压前20项、分类、按ABI统计及重复内容；AAB不是安装或下载大小。validate_configuration.py验证合并Manifest、源配置和P4冻结哈希，并不替代设备测试。

每轮交付还需人工生成本轮validation.json、交付报告和全路径p5-changes.json；不能把这些辅助脚本输出直接当成真机、真实图片或发布验收通过。本轮P4冻结输入仍只读使用，无新真实数据集。所有APK保持本地，不自动提交、安装或分发。
