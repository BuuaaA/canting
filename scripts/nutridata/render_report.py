"""Render the audit report from statistics, validation and independent observation.

Never reads raw recipes/configs; safe for repository use. Run after acceptance.py.
"""
import json
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[2]
    folder = root / 'dev-docs' / 'nutridata-audit'
    s = json.loads((folder / 'statistics.json').read_text(encoding='utf-8'))
    observation_path = folder / 'completion-observation.json'
    obs = json.loads(observation_path.read_text(encoding='utf-8')) if observation_path.exists() else {}
    snap = s['snapshot']
    n = s['dishes']['accepted_unique_records']
    c = s['counts']
    p = s['parsed_coverage_counts']
    percent = lambda count: f'{count / n * 100:.2f}%' if n else 'unknown'
    observation_matches = all(
        entry['sha256'] == snap['inputs'].get(entry['name'], {}).get('sha256')
        for entry in obs.get('second', {}).get('files', []))
    stable = (snap['status'] == 'stable_terminal_snapshot'
              and obs.get('crawler_pid_exited') is True
              and obs.get('same_hashes_across_observations') is True
              and len(obs.get('second', {}).get('files', [])) == 3
              and observation_matches)
    intervals = []
    for source_id in s['missing_ids']:
        if intervals and intervals[-1][1] + 1 == source_id:
            intervals[-1][1] = source_id
        else:
            intervals.append([source_id, source_id])
    missing_ranges = '；'.join(str(lo) if lo == hi else f'{lo}–{hi}' for lo, hi in intervals)
    state = '完成原料验收与管线设计；等待产品复评。原料不具备直接导入资格。' if stable else '暂定验收：补爬或稳定性确认未结束，统计不可作为最终输入基线。'
    lines = [
        '# 餐盘 V1 P1：Nutradata 原料验收报告', '',
        f'**结论：{state}**', '',
        f'- 统计时间：`{snap["observed_at"]}`（含时区偏移）。',
        '- 冻结基线：功能 `2814db0`；文档及当前 HEAD `22952a9`。',
        '- 本阶段仅验收、脚本及设计；未替换 assets/data/dishes.json，未修改推荐引擎或用户数据库，未 commit/push。',
        '', '## 1. Git 与爬虫状态', '',
        '初检 `git status --short --branch` 为 `main...origin/main [ahead 5]`，无未提交文件；`git diff --stat`、`git diff --check` 均无内容。没有覆盖或回滚其他会话文件。', '',
        '初检发现 Python PID 197928（10:58:29 启动）仍在执行，failed.jsonl 持续增长。日志 10:56:07 首轮结束时累计有效24611条；10:58:30 重新排队1057个ID。验收期间未停止、重启、登录或操作其浏览器。首次进程查询受系统权限限制，随后经只读权限提升确认该PID对应 crawl_dishes.py；只输出PID/启动时间，不输出命令行或凭据，并与日志、文件增长交叉判断。', '',
        f'本次输入读取期间文件未变：**{snap["files_unchanged_during_read"]}**；最新一轮有结束标记：**{snap["latest_run_has_end_marker"]}**；独立退出/稳定证据：**{"已确认" if stable else "尚未确认"}**。', '',
        f'最新一轮终止日志的三个计数（成功/空白或不存在/失败计数器）：`{s["crawler_log_evidence"]["ends"][-1] if s["crawler_log_evidence"]["ends"] else "unknown"}`。稳定性观察时刻：`{obs.get("first", {}).get("observed_at", "pending")}` 与 `{obs.get("second", {}).get("observed_at", "pending")}`。', '',
        '具体PID退出、两次观察的时间和摘要比较见 `nutridata-audit/completion-observation.json`（尚未结束时该文件不存在或结论未完成）。单纯文件短暂停写或出现“累计完成”不能当作成功采集；终止标记也不证明没有抓取错误。', '',
        '## 2. 输入固定与 SHA-256', '',
        '| 文件 | 字节 | SHA-256 |', '|---|---:|---|',
    ]
    for key, value in snap['inputs'].items():
        lines.append(f'| {key} | {value["bytes"]:,} | `{value["sha256"]}` |')
    lines += [
        '', f'验收脚本摘要：`{snap["audit_script_sha256"]}`。统计语义摘要：`{s["semantic_sha256"]}`。', '',
        '原文件路径与mtime_ns写在 statistics.json；报告不复制原文件。源目标范围8456–34123（含首尾），共25668个ID；来源为本机配置中只提取的 start_id/end_id，与日志总数交叉一致。这是本次配置目标，不是权威站点全部菜品目录，不能把范围覆盖称为全站采集完整率。未输出其他配置项，未打开含凭据的交接文档。', '',
        '## 3. 全部目标ID去向', '',
        '| 互斥状态 | 数量 | 判据 |', '|---|---:|---|',
        f'| 有效记录 valid | {c["valid"]:,} | JSON对象、正整数菜品ID、非空名称且同ID无内容冲突；仅代表采集结构可读 |',
        f'| 确认不存在 confirmed_absent | {c["confirmed_absent"]:,} | 需要可信404/410、权威目录或明确业务不存在证据；目前爬虫未保存这些证据 |',
        f'| 抓取失败 fetch_failed | {c["fetch_failed"]:,} | 有明确错误记录/浏览器异常且无有效记录；0不证明所有请求成功 |',
        f'| 待核实 unverified | {c["unverified"]:,} | 页面空白/超时歧义、同ID冲突或无证据，不冒认为不存在 |',
        '', f'四类合计 {sum(c.values()):,}，目标总数 {s["target"]["count"]:,}；范围外ID {len(s["outside_target_ids"])}。', '',
        f'有效记录之外的缺失ID共 **{len(s["missing_ids"]):,}**。当前连续区间：**{missing_ranges}**。逐项列表及尝试次数见 `missing_id_disposition.jsonl`；全部目标逐项状态见 `all_id_disposition.jsonl`（{s["all_id_disposition_file"]["rows"]:,}行）。', '',
        f'failed.jsonl 当前 {s["failed"]["physical_lines"]:,} 行，{s["failed"]["unique_ids"]:,} 个唯一ID，重复尝试超额 {s["failed"]["duplicate_attempt_excess"]:,} 行；与有效记录交集 {len(s["failed"]["overlap_valid_ids"])}。重复失败不是新增缺失ID。', '',
        '**failed.jsonl 的实际含义**：parse_dish 只要未取得标题便返回 None；worker 随即记录“页面无内容/ID不存在”。等待超时后也会走这一分支，未检查权威不存在标记，因此重试两次空白依然不能升级成 confirmed_absent。`load_done_ids` 只读有效记录；重启会重排这些ID。`stats["failed"]` 初始化后从未递增；浏览器错误走重试/停止分支，线程异常也不完整落入失败台账。结束日志把成功与 missing 相加称“累计完成”，这里只能解释为处理计数。', '',
        '补查建议（未执行）：对1057项使用单独、可授权的核实流程，保存请求时间、HTTP/业务不存在证据、会话有效性、重试结果及来源链接；若无法区分，继续待核实。不得更改或抢占现有爬虫来实现。', '',
        '## 4. 唯一性、坏行与字段覆盖', '',
        f'- 原始 {s["dishes"]["physical_lines"]:,} 行；解析对象 {s["dishes"]["parsed_objects"]:,}；唯一有效ID {n:,}；重复ID {len(s["dishes"]["duplicate_id_ids"])}；同ID内容冲突 {len(s["dishes"]["conflicting_id_ids"])}。',
        f'- 唯一原文名称 {s["dishes"]["unique_names"]:,}；规范化名称 {s["dishes"]["unique_name_keys"]:,}；原文同名超额 {s["dishes"]["name_duplicate_excess"]}（{percent(s["dishes"]["name_duplicate_excess"])}），不能仅据名称删除。',
        f'- 排除ID、名称、采集时间后其余内容完全相同的超额记录 {s["dishes"]["body_duplicate_excess_excluding_id_name_time"]} 条；分组仅作为重复配方/别名审核线索，不自动合并来源。',
        f'- dishes 坏行 {s["dishes"]["bad_lines"]}；failed 坏行 {s["failed"]["bad_lines"]}；无效ID/名称对象 {len(s["dishes"]["invalid_records"])}。空白、UTF-8解码错误、非对象、重复JSON键和非有限数字都计入坏行。',
        '- 坏行隔离索引 quarantine.jsonl 保留文件名、行号、行哈希与错误类型；当前可为空文件。原字节仍留在原文件中，不写入仓库隔离数据。', '',
        '覆盖率分母为去重后结构可读的记录数，不代表内容真实、许可明确或可以推荐。', '',
        '| 原字段 | 非空条数 | 缺失/空 | 非空覆盖率 |', '|---|---:|---:|---:|',
    ]
    for field, v in s['field_coverage'].items():
        lines.append(f'| {field} | {v["nonempty"]:,} | {v["missing_or_empty"]:,} | {percent(v["nonempty"])} |')
    lines += ['', '| 语义/解析检查 | 条数 | 覆盖率 |', '|---|---:|---:|']
    for label, key in [('配料数值可解析', 'ingredients_parsed'), ('非自身占位成分', 'non_self_ingredients'),
                       ('有编号步骤（含占位）','has_numbered_steps'), ('去占位后的编号步骤','has_steps'),
                       ('单位选项可解析','units_parsed'), ('四项宏量全部可解析','complete_macros'),
                       ('钠可解析','sodium_parsed'), ('做法中含炸字（仅待审核线索）','frying_keyword'),
                       ('配料/基准/单位/步骤/宏量齐且无当前脚本异常','ingredient_basis_units_steps_macro_no_flag')]:
        lines.append(f'| {label} | {p[key]:,} | {percent(p[key])} |')
    lines += [
        '', f'能量/蛋白质/脂肪/碳水分别可解析 {p["parsed_能量"]:,}/{p["parsed_蛋白质"]:,}/{p["parsed_脂肪"]:,}/{p["parsed_碳水化合物"]:,} 条。缺项保持null；NRV百分比与含量分离。', '',
        '“非自身占位成分”的2273条排除量使用NFKC及标点归一化后的名称比较；初步原文精确比较为2247条，二者判据不同，最终统一以前者为准。真正完整配料仍需审核。', '',
        '## 5. 异常规则与人工解释', '',
        '| 规则 | 数量 | 解释 |', '|---|---:|---|',
    ]
    descriptions = {
        'placeholder_steps':'占位步骤，不能支持做法或非油炸事实。',
        'self_referential_ingredient':'成分只是自身名称+重量，不能当成配料表。',
        'all_zero_macros':'26条包含水；原站报告零不等于错误，也不能让普通菜未知贡献变成全零。',
        'energy_449_difference_gt30pct':'能量与4P+9F+4C差异超过max(20kcal,30%)；只是审查信号，未考虑纤维/糖醇等，不自动改值。',
        'macro_mass_gt_basis':'ID16306：蛋白8g+脂肪50g+碳水75g超过100g基准，且能量不相符，需隔离数值使用。',
        'html_residue':'ID29636的菜名含尖括号，可能是标点而非实际HTML残留；保留审查，不盲目strip tags丢菜名。',
    }
    for rule, ids in s['anomaly_ids'].items():
        lines.append(f'| {rule} | {len(ids):,} | {descriptions.get(rule,"待人工核实")} |')
    lines += [
        '', '所有异常ID均在 statistics.json，异常类别可重叠，不能把各行相加当坏记录总数。', '',
        f'每菜源基准克重范围 {s["ranges"]["basis_g"]}；单配料克重范围 {s["ranges"]["ingredient_g"]}；源基准能量范围 {s["ranges"]["macros_per_source_basis"]["能量"]} kcal。这是原配方基准的范围，不是外卖一餐合理区间。', '',
        '当前未命中负克重、>5000g基准/配料、非正单位量、未知单位语法、配料总量与基准差异>max(1g,10%)、负营养素、>950kcal/100g或UTF-8替换符规则。这些是宽松的数据工程警戒线，非医学阈值，不能据“未命中”宣称营养值已正确。', '',
        '14,448条使用同一组通用单位选项，另1,407条使用另一常见组。模板复用不提供外卖份量校准；缺单位量2817条也不补默认100g。', '',
        '## 6. 固定随机抽样与高频人工样本', '',
        '固定Random(20260905)抽20个唯一ID，ID/源行号见statistics.json。只做原文件文本核查，未登录源站逐页复验；不把本次核查标成curated审核通过。', '',
        '| 随机ID | 人工核查结论 |', '|---|---|',
        '| 9728 | 名称看似炖菜，步骤含先煎，不能只按名称标清淡。 |',
        '| 9800 | 有焯和炒，支持复合做法候选。 |',
        '| 10323 | 步骤明确有下锅炸，名称的“烧”不能掩盖风险。 |',
        '| 11197 | 有蛋白和蔬菜线索、做法可读；调味与真实份量仍待核实。 |',
        '| 11906 | 多阶段腌/炒/炖，文本配料与成分表并不完全一致。 |',
        '| 12617 | 汤配方后段出现成分表未列材料，需要一致性复核。 |',
        '| 15240 | 名称“烧”，步骤含煎，应保留过程事实。 |',
        '| 15813 | 多阶段蒸/煎，支持混合类别而非单主料替代。 |',
        '| 15929 | 做法出现成分表外调味与加工步骤，配方不宜自动视为完整。 |',
        '| 17309、18224 | 包装食品自身成分占位，无真实做法。 |',
        '| 18764 | 步骤用盐/油，定量成分未列盐/油，不能据定量表判低油盐。 |',
        '| 24052 | 有真实步骤，但仍需复核成分与步骤一致性。 |',
        '| 25271、26933、27451、27703、29815、31957、32498 | 做法是占位，不能用编号误报做法完整。25271配方基准694g也不能当单人一份。 |', '',
        '| 高频/边界样本ID | 发现及用途限制 |', '|---|---|',
        '| 8456 | 成分表未列步骤中的肉松；支持豆类/蔬菜候选，不能当完整配方。 |',
        '| 8457 | 菜名未写炸，做法明确炸；建议后续作为安全门反例。 |',
        '| 8522 | 番茄炒蛋可提供蛋白+蔬菜线索，不能泛化全部同名配方。 |',
        '| 9408 | 黄焖鸡米饭支持主食+蛋白；单位选项与配方基准不同，不能直接取“份”的克数。炸姜与炸主料需区分。 |',
        '| 9771、12415 | 鱼香肉丝/麻婆豆腐提供多类别及酱料线索，非天然合格推荐。 |',
        '| 13510、15147 | 三明治/汉堡能见主食+蛋白+蔬菜；酱料和做法条件需要确认，不能因名字一律排除或放行。 |',
        '| 15898、17374、18470、32839 | “奶茶”搜索4项分别涉及虾菜、包装饮料、糖果和菜谱饮品，不能当成4款外卖奶茶，更无法推糖型杯型。 |',
        '| 17506 | 宫保鸡丁关键词命中包装自热米饭，不能直接合并普通菜。 |',
        '| 16306、16901、29636 | 分别验证营养质量冲突、合理原站零值和尖括号误报边界。 |', '',
        '这组样本证明“非空”“有数字”“菜名关键词”都不能单独代表可用。完整高频搜索ID列表在机器统计；它是编辑检索集，不代表用户真实点单频率样本。', '',
        '## 7. 可用于下一阶段的范围与限制', '',
        f'- 结构可读原料：{n:,}条；仅在相应使用许可允许的前提下，作为后续规范化/人工审核输入。',
        f'- 非自身成分候选 {p["non_self_ingredients"]:,}条可辅助类别映射；非占位编号做法 {p["has_steps"]:,}条可辅助做法核查。两者都不是事实已验证数。',
        f'- 配料、基准、单位、步骤、宏量齐备且无已设异常的交集 {p["ingredient_basis_units_steps_macro_no_flag"]:,}条，仅是优先审核上界；抽样发现未被规则捕获的配方冲突，不可直接用于准入。',
        '- 份量：有原配方克重及单位选项，但缺真实外卖规格、生熟/损耗、食用人数和商家份量映射，不能生成精确食量。',
        '- 推荐：目前新增可直接发布/推荐条数为0。先补许可证据及人工一致性审核，再按安全政策派生。',
        '- 品牌别名/糖型/杯型：没有独立结构化证据，需许可明确的菜单/商品资料或P2本机用户确认。碳水不等于添加糖，商品名称不等于品牌别名映射。', '',
        '## 8. 许可核查与敏感材料', '',
        '本机参考采集仓库对应 [sunw80910/nutridata_data](https://github.com/sunw80910/nutridata_data)，README注明仅供学习参考、非商业用途；未找到LICENSE文件。公开访问 [nutridata.cn](https://nutridata.cn/) 未获得可核实的再分发条款；/home、/login公开抓取失败，不意味着不存在协议。当前没有权利方明确授权 App 离线内置/再分发的证据，license_status=unknown。', '',
        '访问权、爬虫代码可见与数据再分发权不同；自有schema或人工标签也不能自动消除来源限制。原始内容、账号配置、带凭据交接文档及真实派生数据集均不入库、不打包；本交付只含自编代码、合成测试、统计和ID审计索引。完整许可门与版本/迁移方案见 food-knowledge-distillation.md。', '',
        '## 9. 复现与测试', '',
        '在 D:\\dev\\canting 运行（Python3.12，标准库，无网络调用）：', '',
        '```powershell',
        'python scripts/nutridata/acceptance.py --input-dir D:/dev/nutridata_crawl/output --crawler-source D:/dev/nutridata_crawl/crawl_dishes.py --catalog D:/dev/canting/assets/data/dishes.json --start-id 8456 --end-id 34123 --out dev-docs/nutridata-audit --settle-seconds 10',
        'python -m unittest discover -s scripts/nutridata -p "test_*.py" -v',
        'python scripts/nutridata/render_report.py',
        'flutter analyze --no-pub',
        'flutter test --no-pub --reporter compact',
        'git diff --check',
        '```', '',
        '输入活跃时最终命令拒绝输出；临时探索必须显式 --provisional。同一输入两次验收除snapshot时间/观察元数据外语义相同；逐ID清单可字节比对。结果摘要与真实命令记录见 validation.json。', '',
        '本次静态分析：No issues found（55.1秒）；完整Flutter：343/343通过（23秒），包含当前种子迁移与用户数据保留测试。Python覆盖坏行隔离、中文ID、缺失未知、NRV解析、重复/冲突、占位、全零与风险契约；全部使用合成fixture，无原菜谱入测试。新schema迁移未实施，不能借旧迁移测试宣称未来迁移通过。', '',
        '体积当前1004道为639757字节、gzip50155字节；新库尚无许可且未生成，SQLite新旧导入耗时和Android冷启动对比留待获批实施/真机测量。本阶段不拿桌面脚本时间替代冷启动。设计预算与测试方法见管线文档。', '',
        '## 10. P3待办与复评', '',
        '1. 主食保底名额与首推排序分开处理。',
        '2. 推荐原因必须与实际输出一致。',
        '3. 油炸食品确定性排除优先于 recommendable 标记，所有模式适用。',
        '4. 用合格混合菜替换“炸鸡必须被推荐”的分类测试夹具，保留槽位与自身分类不同的断言。', '',
        '本阶段不修改推荐引擎。产品复评需确认原料质量边界、缺失ID归类、审核核心集范围及管线方案；授权未明确时不发布派生数据。交付后等待产品经理复评，再另行授权替换App菜库。回滚仅涉及新增报告和脚本，基线资产与用户数据未改变。', '',
        '交付文件：本报告、food-knowledge-distillation.md、scripts/nutridata/ 下验收/契约/测试/报告脚本、nutridata-audit/ 下统计/逐ID清单/隔离索引/验证记录。',
    ]
    (root / 'dev-docs' / 'nutridata-raw-acceptance.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
