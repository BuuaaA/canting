"""Read-only Nutradata audit. Stdlib only; never exports recipe text or credentials.

Output contains aggregate metrics, source IDs, hashes and line references only.
Source bytes are held in memory; a changing snapshot is never called final.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import gzip
import hashlib
import json
import math
from pathlib import Path
import random
import re
import time
import unicodedata

VERSION = '1.0.0'
FIELDS = ['菜品ID', '菜品名称', '成分', '计量单位', '菜肴做法',
          '能量及宏量营养素', '维生素', '矿物质', '单位量', '爬取时间']
NUMBER = r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)'
MISSING = {'', '-', '--', '未知', '暂无', '暂无数据', '无数据', 'null', 'N/A'}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(',', ':'), allow_nan=False).encode('utf-8')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def present(value):
    return isinstance(value, str) and value.strip() not in MISSING


def name_key(value):
    # Retrieval key only. Keep region, preparation and sugar modifiers.
    return ''.join(c for c in unicodedata.normalize('NFKC', value).casefold()
                   if not c.isspace() and not unicodedata.category(c).startswith('P'))


def identifier(value):
    return value if type(value) is int and value > 0 else None


def reject_constant(value):
    raise ValueError('nonfinite JSON constant')


def finite_float(value):
    result = float(value)
    if not math.isfinite(result):
        raise ValueError('nonfinite JSON number')
    return result


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key')
        result[key] = value
    return result


def read_jsonl(data, source):
    records, issues = [], []
    for line, raw in enumerate(data.splitlines(), 1):
        try:
            value = json.loads(raw.decode('utf-8'), parse_constant=reject_constant,
                               object_pairs_hook=unique_object, parse_float=finite_float)
            if not isinstance(value, dict):
                raise ValueError('not an object')
            stack = [(value, 0)]
            while stack:
                node, depth = stack.pop()
                if depth > 64:
                    raise ValueError('JSON nesting exceeds audit limit 64')
                children = node.values() if isinstance(node, dict) else node if isinstance(node, list) else []
                stack.extend((child, depth + 1) for child in children)
            canonical(value)  # Reject lone Unicode surrogates before later hashing.
            records.append((line, value))
        except (ValueError, UnicodeError, RecursionError, OverflowError) as error:
            issues.append({'file': source, 'line': line, 'sha256': sha(raw),
                           'reason': type(error).__name__})
    return records, issues


def nutrient(text, label, unit):
    # Anchor after NRV: percentage is NOT the nutrient amount.
    matches = re.findall(r'^' + re.escape(label) + NUMBER + r'%\s*NRV\s*('
                         + NUMBER + r')\s*' + re.escape(unit) + r'\s*$',
                         text, re.M)
    value = float(matches[0]) if len(matches) == 1 else None
    return value if value is None or math.isfinite(value) else None


def features(record):
    text = {k: record.get(k) if isinstance(record.get(k), str) else '' for k in FIELDS}
    ingredients = text['成分'].splitlines()
    parsed = [re.fullmatch(r'(.+?)[:：]\s*(' + NUMBER + r')\s*(g|克|mg|毫克|kg|千克)',
                           line.strip()) for line in ingredients]
    factors = {'g': 1, '克': 1, 'mg': .001, '毫克': .001, 'kg': 1000, '千克': 1000}
    grams = [float(m[2]) * factors[m[3]] for m in parsed if m]
    basis_match = re.fullmatch(r'「?以每(' + NUMBER + r')克可食部分计」?', text['计量单位'])
    basis = float(basis_match[1]) if basis_match else None
    units = text['单位量'].splitlines()
    unit_matches = [re.fullmatch(r'(.+?)[（(](' + NUMBER + r')克[)）]', u) for u in units]
    unit_g = [float(m[2]) for m in unit_matches if m]
    macros = {label: nutrient(text['能量及宏量营养素'], label, unit)
              for label, unit in [('能量', 'kcal'), ('蛋白质', 'g'), ('脂肪', 'g'), ('碳水化合物', 'g')]}
    sodium = nutrient(text['矿物质'], '钠', 'mg')
    flags = []
    numeric_overflow = any(not math.isfinite(g) for g in grams + unit_g + ([basis] if basis is not None else []))
    if numeric_overflow: flags.append('numeric_text_nonfinite')
    grams = [g for g in grams if math.isfinite(g)]
    unit_g = [g for g in unit_g if math.isfinite(g)]
    if basis is not None and not math.isfinite(basis): basis = None
    placeholder_steps = bool(re.search(r'步骤更新中|敬请期待|做法更新中|暂无做法', text['菜肴做法']))
    self_ingredient = (len(parsed) == 1 and parsed[0] is not None
                       and name_key(parsed[0][1]) == name_key(text['菜品名称']))
    if placeholder_steps: flags.append('placeholder_steps')
    if self_ingredient: flags.append('self_referential_ingredient')
    if ingredients and not all(parsed): flags.append('ingredient_unparsed')
    if any(g < 0 or g > 5000 for g in grams): flags.append('ingredient_grams_outlier')
    if basis is None: flags.append('basis_unknown')
    elif basis <= 0 or basis > 5000: flags.append('basis_grams_outlier')
    if units and not all(unit_matches): flags.append('unit_unparsed')
    if any(g <= 0 or g > 5000 for g in unit_g): flags.append('unit_grams_outlier')
    if ingredients and all(parsed) and basis and abs(sum(grams) - basis) > max(1, basis * .1):
        flags.append('ingredient_basis_difference_gt10pct')
    if any(v is not None and v < 0 for v in [*macros.values(), sodium]): flags.append('negative_nutrient')
    if all(v is not None for v in macros.values()):
        if all(v == 0 for v in macros.values()): flags.append('all_zero_macros')
        energy = 4 * macros['蛋白质'] + 9 * macros['脂肪'] + 4 * macros['碳水化合物']
        if abs(energy - macros['能量']) > max(20, macros['能量'] * .3):
            flags.append('energy_449_difference_gt30pct')
        if basis and basis > 0:
            if sum(macros[k] for k in ['蛋白质', '脂肪', '碳水化合物']) > basis * 1.05:
                flags.append('macro_mass_gt_basis')
            if macros['能量'] / basis * 100 > 950: flags.append('energy_gt950kcal_per100g')
    if sodium is not None and basis and basis > 0 and sodium > basis * 1000:
        flags.append('sodium_mass_gt_basis')
    all_text = '\n'.join(text.values())
    if re.search(r'<[^>]+>|&(?:nbsp|amp|lt|gt|quot);|&#\d+;', all_text): flags.append('html_residue')
    if '\ufffd' in all_text or any(ord(c) < 32 and c not in '\n\r\t' for c in all_text):
        flags.append('encoding_or_control_character')
    if re.search(r'访问过于频繁|请先登录|验证码|页面不存在|系统异常', text['菜品名称']):
        flags.append('suspect_error_title')
    return {'ingredients_parsed': bool(ingredients) and all(parsed) and not numeric_overflow,
            'ingredient_count': len(ingredients), 'ingredient_grams': grams,
            'basis_g': basis, 'units_parsed': bool(units) and all(unit_matches) and not numeric_overflow,
            'unit_count': len(units), 'macros': macros, 'sodium_mg': sodium,
            'has_numbered_steps': bool(re.search(r'(?:^|\n)\s*\d+[、.．：:]', text['菜肴做法'])),
            'has_steps': bool(re.search(r'(?:^|\n)\s*\d+[、.．：:]', text['菜肴做法'])) and not placeholder_steps,
            'non_self_ingredients': bool(ingredients) and all(parsed) and not self_ingredient and not numeric_overflow,
            'preparation_keyword': bool(re.search(r'蒸|煮|炖|焯|炒|炸|烤|拌|煎', text['菜肴做法'])),
            'frying_keyword': '炸' in text['菜肴做法'], 'flags': flags}


def deduplicate(rows):
    """Same ID: collapse exact content excluding crawl time; conflicts quarantine.

    Same names across IDs are NOT merged. Sorting is independent of input order.
    """
    grouped = defaultdict(list)
    for line, rec in rows:
        if identifier(rec.get('菜品ID')) and present(rec.get('菜品名称')):
            grouped[rec['菜品ID']].append((line, rec))
    accepted, conflicts, duplicate_ids, exact_excess = [], [], [], 0
    for source_id, versions in sorted(grouped.items()):
        hashes = {sha(canonical({k: v for k, v in rec.items() if k != '爬取时间'}))
                  for _, rec in versions}
        if len(versions) > 1: duplicate_ids.append(source_id)
        exact_excess += len(versions) - len(hashes)
        if len(hashes) != 1:
            conflicts.append(source_id)
        else:
            # Lexical full-content order includes timestamp; never last-write-wins.
            accepted.append(min(versions, key=lambda item: canonical(item[1])))
    return accepted, conflicts, duplicate_ids, exact_excess


def audit(dishes, failed, start, end, log=''):
    rows, bad = read_jsonl(dishes, 'dishes.jsonl')
    failures, bad_failed = read_jsonl(failed, 'failed.jsonl')
    accepted, conflicts, duplicate_ids, exact_excess = deduplicate(rows)
    target = set(range(start, end + 1))
    valid = {r['菜品ID'] for _, r in accepted}
    structurally_invalid = []
    for line, r in rows:
        if not identifier(r.get('菜品ID')) or not present(r.get('菜品名称')):
            structurally_invalid.append({'file': 'dishes.jsonl', 'line': line,
                                         'reason': 'invalid_id_or_name'})
    failed_by_id = defaultdict(list)
    invalid_failure_lines = []
    for line, r in failures:
        if identifier(r.get('菜品ID')):
            failed_by_id[r['菜品ID']].append(r)
        else:
            invalid_failure_lines.append(line)
    # Existing crawler has no authoritative absence evidence. Ambiguous empty
    # DOM results always remain unverified, even after repeated attempts.
    fetch_failed = {i for i, rs in failed_by_id.items()
                    if any(present(r.get('错误')) and r['错误'] != '页面无内容/ID不存在' for r in rs)}
    browser_error_ids = {int(i) for i in re.findall(r'浏览器异常 id=(\d+)', log)}
    fetch_failed |= browser_error_ids
    fetch_failed = (fetch_failed & target) - valid - set(conflicts)
    missing = target - valid
    unverified = missing - fetch_failed
    statuses = []
    for i in sorted(target):
        state = 'valid' if i in valid else 'fetch_failed' if i in fetch_failed else 'unverified'
        reason = ('parsed_record' if state == 'valid' else 'conflicting_records' if i in conflicts
                  else 'logged_browser_error_without_valid_record' if state == 'fetch_failed' and i in browser_error_ids
                  else 'explicit_fetch_error' if state == 'fetch_failed'
                  else 'empty_page_not_authoritative_absence' if i in failed_by_id else 'no_evidence')
        statuses.append({'source_id': i, 'status': state, 'reason': reason,
                         'failure_attempts': len(failed_by_id[i])})
    counts = Counter(s['status'] for s in statuses)
    for state in ['valid', 'confirmed_absent', 'fetch_failed', 'unverified']:
        counts.setdefault(state, 0)
    count = len(accepted)
    coverage = {}
    for field in FIELDS:
        nonempty = sum(identifier(r.get(field)) is not None if field == '菜品ID'
                       else present(r.get(field)) for _, r in accepted)
        coverage[field] = {'nonempty': nonempty, 'missing_or_empty': count - nonempty,
                           'coverage': nonempty / count if count else None,
                           'wrong_type': sum(field in r and (type(r[field]) is not int if field == '菜品ID'
                                                          else not isinstance(r[field], str)) for _, r in accepted)}
    names, keys, bodies = defaultdict(list), defaultdict(list), defaultdict(list)
    anomalies, parsed_counts, samples = defaultdict(list), Counter(), {}
    unit_signatures = Counter()
    basis_values, ingredient_values = [], []
    macro_ranges = defaultdict(list)
    for line, record in accepted:
        i = record['菜品ID']
        names[record['菜品名称']].append(i)
        keys[name_key(record['菜品名称'])].append(i)
        bodies[sha(canonical({k: v for k, v in record.items()
                              if k not in {'菜品ID', '菜品名称', '爬取时间'}}))].append(i)
        f = features(record)
        for flag in f['flags']: anomalies[flag].append(i)
        for key in ['ingredients_parsed', 'non_self_ingredients', 'units_parsed', 'has_steps', 'has_numbered_steps', 'preparation_keyword', 'frying_keyword']:
            parsed_counts[key] += int(f[key])
        parsed_counts['positive_basis'] += int(f['basis_g'] is not None and f['basis_g'] > 0)
        complete = all(v is not None for v in f['macros'].values())
        parsed_counts['complete_macros'] += int(complete)
        parsed_counts['sodium_parsed'] += int(f['sodium_mg'] is not None)
        parsed_counts['ingredient_basis_units_steps_macro_no_flag'] += int(
            f['ingredients_parsed'] and f['units_parsed'] and f['has_steps']
            and f['basis_g'] is not None and f['basis_g'] > 0 and complete and not f['flags'])
        for key, value in f['macros'].items():
            parsed_counts['parsed_' + key] += int(value is not None)
            if value is not None: macro_ranges[key].append(value)
        if f['basis_g'] is not None: basis_values.append(f['basis_g'])
        ingredient_values.extend(f['ingredient_grams'])
        unit_text = record.get('单位量')
        unit_signatures[sha((unit_text if isinstance(unit_text, str) else '').encode('utf-8'))] += 1
        samples[i] = {'source_id': i, 'line': line, 'flags': f['flags']}
    rng = random.Random(20260905)
    random_ids = sorted(rng.sample(sorted(valid), min(20, len(valid))))
    high_frequency_terms = ['宫保鸡丁', '鱼香肉丝', '番茄炒蛋', '西红柿炒鸡蛋', '麻婆豆腐',
                            '黄焖鸡', '红烧肉', '炒饭', '汉堡', '三明治', '奶茶', '炸鸡', '沙拉']
    # Terms are editorial search inputs, not copied source content.
    high_frequency = {term: [r['菜品ID'] for _, r in accepted if term in r['菜品名称']]
                      for term in high_frequency_terms}
    return {'audit_version': VERSION, 'target': {'start': start, 'end': end, 'count': len(target)},
            'crawler_log_evidence': {'browser_error_ids': sorted(browser_error_ids),
                'session_expired_count': log.count('会话过期'),
                'login_failure_count': log.count('登录失败'),
                'starts': re.findall(r'总计 (\d+) 个 ID \| 已完成 (\d+) \| 本次待爬 (\d+)', log),
                'ends': re.findall(r'结束：本轮成功 (\d+) \| 不存在 (\d+) \| 失败 (\d+)', log)},
            'counts': dict(counts), 'dishes': {'physical_lines': len(dishes.splitlines()),
            'parsed_objects': len(rows), 'accepted_unique_records': count,
            'unique_ids_with_valid_name': len({r['菜品ID'] for _, r in rows if identifier(r.get('菜品ID')) and present(r.get('菜品名称'))}),
            'unique_names': len(names), 'unique_name_keys': len(keys),
            'duplicate_id_ids': duplicate_ids, 'conflicting_id_ids': conflicts,
            'exact_content_duplicate_excess': exact_excess,
            'name_duplicate_excess': count - len(names),
            'name_duplicate_rate': (count - len(names)) / count if count else None,
            'body_duplicate_excess_excluding_id_name_time': count - len(bodies),
            'body_duplicate_groups': sorted((v for v in bodies.values() if len(v) > 1), key=lambda v: v[0]),
            'name_collision_groups': sorted((v for v in names.values() if len(v) > 1), key=lambda v: v[0]),
            'normalized_name_collision_groups': sorted((v for v in keys.values() if len(v) > 1), key=lambda v: v[0]),
            'bad_lines': len(bad), 'bad_line_rate': len(bad) / len(dishes.splitlines()) if dishes else None,
            'invalid_records': structurally_invalid},
            'failed': {'physical_lines': len(failed.splitlines()), 'parsed_objects': len(failures),
            'unique_ids': len({r['菜品ID'] for _, r in failures if identifier(r.get('菜品ID'))}),
            'duplicate_attempt_excess': sum(max(0, len(rs) - 1) for rs in failed_by_id.values()),
            'bad_lines': len(bad_failed), 'invalid_id_lines': invalid_failure_lines,
            'overlap_valid_ids': sorted(valid & {r['菜品ID'] for _, r in failures if identifier(r.get('菜品ID'))})},
            'outside_target_ids': sorted((valid | {r['菜品ID'] for _, r in failures if identifier(r.get('菜品ID'))}) - target),
            'field_coverage': coverage, 'parsed_coverage_counts': dict(parsed_counts),
            'anomaly_ids': dict(sorted(anomalies.items())),
            'ranges': {'basis_g': [min(basis_values), max(basis_values)] if basis_values else None,
                       'ingredient_g': [min(ingredient_values), max(ingredient_values)] if ingredient_values else None,
                       'macros_per_source_basis': {k: [min(v), max(v)] for k, v in macro_ranges.items()}},
            'unit_option_signatures': dict(unit_signatures.most_common()),
            'missing_ids': sorted(missing), 'missing_id_disposition': [s for s in statuses if s['status'] != 'valid'],
            'all_id_disposition': statuses, 'quarantine': bad + bad_failed + structurally_invalid + [
                {'file': 'failed.jsonl', 'line': line, 'reason': 'invalid_id'} for line in invalid_failure_lines],
            'random_sample_seed': 20260905, 'random_samples': [samples[i] for i in random_ids],
            'high_frequency_search_ids': high_frequency}


def fingerprint(path):
    stat = path.stat()
    return {'bytes': stat.st_size, 'mtime_ns': stat.st_mtime_ns}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-dir', type=Path, required=True)
    parser.add_argument('--crawler-source', type=Path, required=True)
    parser.add_argument('--catalog', type=Path, required=True)
    parser.add_argument('--start-id', type=int, required=True)
    parser.add_argument('--end-id', type=int, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--settle-seconds', type=float, default=10)
    parser.add_argument('--provisional', action='store_true')
    args = parser.parse_args()
    if args.start_id < 1 or args.end_id < args.start_id or args.settle_seconds < 0:
        parser.error('invalid range or settle interval')
    paths = {name: args.input_dir / name for name in ['dishes.jsonl', 'failed.jsonl', 'progress.log']}
    paths['crawl_dishes.py'] = args.crawler_source
    paths['baseline_dishes.json'] = args.catalog
    if args.out.resolve() == args.input_dir.resolve() or args.input_dir.resolve() in args.out.resolve().parents:
        parser.error('output must be separate from raw input')
    before = {name: fingerprint(p) for name, p in paths.items()}
    data = {name: p.read_bytes() for name, p in paths.items()}
    time.sleep(args.settle_seconds)
    after = {name: fingerprint(p) for name, p in paths.items()}
    stable = before == after and all(sha(p.read_bytes()) == sha(data[name]) for name, p in paths.items())
    log = data['progress.log'].decode('utf-8', errors='replace')
    last_start = log.rfind('总计 ')
    terminal = log.rfind('结束：') > last_start or log.rfind('全部完成，无需继续') > last_start
    result = audit(data['dishes.jsonl'], data['failed.jsonl'], args.start_id, args.end_id, log)
    result['snapshot'] = {'status': 'stable_terminal_snapshot' if stable and terminal and not args.provisional else 'provisional',
        'files_unchanged_during_read': stable, 'latest_run_has_end_marker': terminal,
        'process_exit_verified': False, 'settle_seconds': args.settle_seconds,
        'observed_at': datetime.now(timezone.utc).isoformat(),
        'audit_script_sha256': sha(Path(__file__).read_bytes()),
        'inputs': {name: {**before[name], 'sha256': sha(value), 'path': str(paths[name].resolve())}
                   for name, value in data.items()}}
    baseline = json.loads(data['baseline_dishes.json'])
    catalog_rows = baseline['dishes'] if isinstance(baseline, dict) else baseline
    result['baseline_catalog'] = {'records': len(catalog_rows), 'json_bytes': len(data['baseline_dishes.json']),
        'gzip_bytes': len(gzip.compress(data['baseline_dishes.json'], mtime=0)),
        'new_catalog_bytes': None, 'sqlite_import_ms': None, 'android_cold_start_ms': None,
        'reason': 'design_only_no_licensed_new_catalog_or_device_benchmark'}
    if result['snapshot']['status'] == 'provisional' and not args.provisional:
        raise SystemExit('Input still active or latest crawl lacks end marker; use --provisional for non-final audit')
    # All data except observation metadata is deterministic for the same bytes.
    semantic = {k: v for k, v in result.items() if k != 'snapshot'}
    result['semantic_sha256'] = sha(canonical(semantic))
    args.out.mkdir(parents=True, exist_ok=True)
    for key in ['all_id_disposition', 'missing_id_disposition', 'quarantine']:
        (args.out / (key + '.jsonl')).write_bytes(b''.join(canonical(r) + b'\n' for r in result[key]))
    result['all_id_disposition_file'] = {'path': 'all_id_disposition.jsonl',
        'sha256': sha((args.out / 'all_id_disposition.jsonl').read_bytes()),
        'rows': len(result.pop('all_id_disposition'))}
    (args.out / 'statistics.json').write_text(json.dumps(result, ensure_ascii=False, sort_keys=True,
                                                       indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({'snapshot': result['snapshot']['status'], 'counts': result['counts'],
                      'semantic_sha256': result['semantic_sha256']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
