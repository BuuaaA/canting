# P4 冻结文字验收集
人工构造文字，不是平台截图或原生 OCR。所有案例为修复集，无独立留出集。标注在修复前冻结，尚未独立复核。
商品按顺序匹配；同名同规格允许合并数量，不同规格不可合并。仅删除空白和价格、数量后缀；错字不纠正。quantity 案例的购买数量超出既有 1–99 范围，应原文保留并要求确认，不得变为 10。
真实平台、布局和 S01 全部缺失；S02–S08 仅部分人工文字覆盖，不证明图像识别能力。文字集首次冻结时尚无图像；当前另有1张合成图，见 native-manifest.json，真实图仍为0。超过 20 项仍以全部 22 项作为召回分母。

## 复跑与补充标注

原始文字 manifest 另存 manifest.text-v1.frozen.json。当前 manifest 引用新增字段标注和 native-manifest.json。后者是合成文字图，图像哈希在原生处理前计算；路径基准为仓库。所有原始输入/标签哈希未改变。

数量标注 v2 修正了分母：只有输入明确出现的数量参与正确率；缺数量的默认 1 不视作图片事实；×100 按 100 标注，生产降级为待确认仍算抽取未正确。原始标签和修正理由均保留，两阶段采用同一更正口径。

在仓库 android 运行 `gradlew.bat :app:testDebugUnitTest --offline`，P4ReplayTest 对十份冻结输入分别运行两次，并写 parser-actual.tsv。然后在仓库运行 `flutter test --no-pub test/state/p4_semantic_replay_test.dart`、`python scripts/p4/metrics.py`、`python scripts/p4/native_metrics.py`。复跑前复制整个 run-20260905 目录或修改统一输出 run_id，避免覆盖已交付 P4 证据。baseline-parser.tsv 和 baseline-semantic.json 是修复前冻结输出，不重新生成。

语义基线重测使用 P3 的 local_food.dart 和 baseline-parser.tsv；请求隔离不参与语义评分。首次评估入口遗漏 guidelines，匹配器未初始化，该输出单独标 invalid，不参与最终成绩。

运行阶段严格区分：文本 Kotlin parser_unit、生产 AppState text_replay、widget/SQLite、合成图 native_ocr；没有真实平台图。原生实际输出及坐标见 native-result.json。仅同一作者标注、修复、测试，无盲测或统计代表性。


## R1–R3整改后的复跑目录

当前Dart回归输出到dev-docs/p4-evidence/repair-20260905，评分器默认也使用该目录，可通过P4_EVIDENCE_DIR指定新的目录。运行python scripts/p4/test_metrics.py执行5项评分故障注入；运行metrics.py重算文字结果。baseline-parser.tsv与baseline-semantic.json来自只读的上轮冻结输入，parser-actual.tsv复用未变的Kotlin输出。新一次复跑请选择新目录并配套重定向Dart采集路径，勿覆盖已交付证据。上文native_metrics.py与Kotlin命令是原生历史复跑说明，本次整改未执行原生，也不应直接运行它们覆盖原run-20260905。
