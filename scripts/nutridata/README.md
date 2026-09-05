# P1 后半段：schema 2 与离线适配

当前有效记录契约为 FoodKnowledge schema 2（31 个必需字段），不是正式 assets 的旧种子 schema v2。
contract.py 与 Dart FoodKnowledge 校验同一组 33 个合成正反例；不读取或生成真实派生菜库。
糖型是所选甜度选项，none 不代表总糖 0；份量为 consumed 的 g/ml 区间；未知保持 null。
规则、字段映射、来源/审核、包摘要及同步边界见 dev-docs/food-knowledge-distillation.md 第 11 节。

在仓库根目录执行：

```powershell
python -m unittest discover -s scripts/nutridata -p "test_*.py" -v
python scripts/nutridata/verify_adapter.py
```

verify_adapter.py 顺序运行 Python、Dart 格式、相关测试、静态检查和完整 Flutter 回归，
写入 dev-docs/food-knowledge-adapter-validation.json。使用已安装 Flutter/Dart 与缓存依赖，
不会联网安装；必要时先执行 flutter pub get --offline。数据库仅为测试临时库。
需要重建共享 fixture 时执行 python scripts/nutridata/build_synthetic_fixtures.py。

本轮最终结果：Python 30 项（内含 33 个共享子例），相关 Dart 50 项，Flutter 完整 386 项，analyze 无问题。
真实原料 acceptance.py 与前半段统计保持不变。以下是前半段原始操作说明与当时结果；
draft 1、全零拒绝、尚无 Dart 适配的旧描述已由上述 schema 2 取代。
render_report.py 只用于前半段原料报告，不用于本轮适配交付，不应为更新本轮报告而执行它。

---

# P1 原料验收（标准库，不连接 App）

`acceptance.py` 只读读取指定文件，不启动爬虫、不联网、不读取账号配置、不输出原菜谱。`contract.py` 是 FoodKnowledge draft schema 1 的可执行契约；与当前 App seed schema v2 不兼容，禁止直接导入。`render_report.py` 根据当前统计和本次人工抽样结论输出验收报告；更换 dishes.jsonl 摘要时，需重新进行报告中人工抽样核查。

`food-knowledge-draft.schema.json` 是对应的JSON Schema 2020-12设计文件，可供编辑器检查；区间上下界顺序、全零贡献、估算标记及安全事实一致性还须运行 `contract.validate`。本机未安装通用jsonschema校验器，本次对声明文件做JSON语法/字段集合检查，运行时语义以可执行契约测试为准；未为此安装依赖。

仓库根目录执行：

```powershell
python scripts/nutridata/acceptance.py --input-dir D:/dev/nutridata_crawl/output --crawler-source D:/dev/nutridata_crawl/crawl_dishes.py --catalog D:/dev/canting/assets/data/dishes.json --start-id 8456 --end-id 34123 --out dev-docs/nutridata-audit --settle-seconds 10
python -m unittest discover -s scripts/nutridata -p "test_*.py" -v
python scripts/nutridata/render_report.py
```

输入仍有写入或最新一轮没有结束标记时，默认命令非零退出，不输出最终统计。探索阶段可加 `--provisional`，输出明确标为暂定；不能拿来冻结输入。观察字段包含原始时区偏移，不把源记录无时区采集时间推断为UTC。

结束标记只证明程序打印了末尾日志：必须另核实具体爬虫PID已退出、没有新的同爬虫进程、相隔至少60秒的两次文件大小/mtime/SHA-256完全相同。将实际观察记录写入 `completion-observation.json`，不要手填未经验证的true。命令行不会自行查询系统进程，所以 snapshot.process_exit_verified 始终为false，独立进程证据以观察文件为准。

`statistics.json` 为主统计；`all_id_disposition.jsonl` 覆盖目标范围内每一个ID；`missing_id_disposition.jsonl` 是有效记录之外的ID；`quarantine.jsonl` 为坏行/无效对象位置索引。坏行原字节留在原文件，可按一基行号重取；不得把原字节导出到仓库。原料许可不明时，同样不生成真实 normalized/distilled/curated 数据文件。

解析拒绝非法UTF-8、孤立Unicode代理字符、重复键、非有限数字、非对象根及超过64层的JSON嵌套；这些属于验收格式限制，逐行隔离，不使整批中断。

确定性：同样的输入字节、脚本版本和参数产生相同的 semantic_sha256 与逐ID清单。统计时间/输入观察元数据允许不同。语义摘要涵盖 `audit()` 的全部结果（含完整ID清单）及 baseline_catalog；保存 statistics.json 时为减小体积，把完整ID清单替换成清单路径、哈希和行数。

状态含义：valid只表示对象ID/名称可读且同ID内容无冲突；confirmed_absent需要权威证据，本爬虫没有保存，故不从空白页面推导；fetch_failed从明确错误及浏览器异常汇总；其余unverified。统计为0不代表从未发生网络故障。

规则阈值为宽松质量审查信号：基准/单位非正或>5000g、配料负值或>5000g、成分总量差>max(1g,10%)、宏量质量>基准105%、能量449差>max(20kcal,30%)、每100g>950kcal。它们不是健康准入阈值，也不用于自动改数值。自指成分、占位步骤、全零宏量、HTML样式字符单独列示；人工复核可能确认合理零值或标点误报。

本次合成测试覆盖27个案例；不使用真实菜谱作为fixture。完整App回归仍使用原有菜库/临时测试数据库，本目录无用户数据库写操作。新schema迁移/Android性能待下一阶段获批后验证。
