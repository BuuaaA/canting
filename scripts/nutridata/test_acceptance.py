"""Synthetic-only regression fixtures: no source recipe text."""
import unittest
from acceptance import audit, canonical, deduplicate, features, name_key, nutrient, read_jsonl


def dish(i=1, name='测试菜', **changes):
    return {'菜品ID': i, '菜品名称': name, '成分': '测试原料：100g',
            '计量单位': '「以每100克可食部分计」', '菜肴做法': '1、煮熟。',
            '能量及宏量营养素': '能量5% NRV100 kcal\n蛋白质10% NRV6 g\n脂肪10% NRV4 g\n碳水化合物10% NRV10 g',
            '矿物质': '钠10% NRV200 mg', '单位量': '份(100克)', **changes}


class AcceptanceTests(unittest.TestCase):
    def test_nrv_is_not_amount(self):
        self.assertEqual(nutrient('蛋白质11% NRV6.50 g', '蛋白质', 'g'), 6.5)

    def test_missing_is_none_and_zero_is_reported_zero(self):
        self.assertIsNone(nutrient('', '脂肪', 'g'))
        self.assertEqual(nutrient('脂肪0% NRV0.00 g', '脂肪', 'g'), 0)

    def test_bad_lines_are_isolated_without_source_text(self):
        rows, errors = read_jsonl(b'broken\n[]\n\xff\n{"a":1,"a":2}\n{"a":NaN}\n{}\n', 'test')
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(errors), 5)
        self.assertTrue(all(set(e) == {'file', 'line', 'sha256', 'reason'} for e in errors))

    def test_failed_is_not_confirmed_absent_and_retries_count(self):
        failure = canonical({'菜品ID': 2, '错误': '页面无内容/ID不存在'}) + b'\n'
        result = audit(canonical(dish()) + b'\n', failure * 2, 1, 3)
        self.assertEqual(result['counts'], {'valid': 1, 'confirmed_absent': 0, 'fetch_failed': 0, 'unverified': 2})
        self.assertEqual(result['failed']['duplicate_attempt_excess'], 1)
        self.assertEqual(result['missing_ids'], [2, 3])

    def test_success_after_failure_wins_but_history_retained(self):
        result = audit(canonical(dish()), canonical({'菜品ID': 1, '错误': 'timeout'}), 1, 1)
        self.assertEqual(result['counts']['valid'], 1)
        self.assertEqual(result['failed']['overlap_valid_ids'], [1])

    def test_conflicting_id_is_quarantined(self):
        rows = [(1, dish()), (2, dish(name='另一测试菜'))]
        accepted, conflicts, duplicates, _ = deduplicate(rows)
        self.assertEqual(accepted, [])
        self.assertEqual(conflicts, [1])
        result = audit(b'\n'.join(canonical(r) for _, r in rows), b'', 1, 1)
        self.assertEqual(result['counts']['unverified'], 1)

    def test_dedup_is_order_independent(self):
        rows = [(1, dish(爬取时间='later')), (2, dish(爬取时间='earlier'))]
        a = deduplicate(rows)
        b = deduplicate(list(reversed(rows)))
        self.assertEqual(a, b)
        self.assertEqual(a[3], 1)

    def test_same_name_different_ids_stay_separate(self):
        self.assertEqual(len(deduplicate([(1, dish(1)), (2, dish(2))])[0]), 2)
        self.assertEqual(name_key(' 测试（甲） '), name_key('测试(甲)'))
        self.assertNotEqual(name_key('测试菜(四川)'), name_key('测试菜'))
        self.assertNotEqual(name_key('炸测试菜'), name_key('蒸测试菜'))

    def test_placeholder_and_self_ingredient_not_usable(self):
        f = features(dish(菜肴做法='1.步骤更新中，敬请期待', 成分='测试菜：100g'))
        self.assertFalse(f['has_steps'])
        self.assertTrue(f['has_numbered_steps'])
        self.assertFalse(f['non_self_ingredients'])

    def test_anomaly_boundary_and_units(self):
        f = features(dish(成分='测试原料：-1g', 计量单位='「以每0克可食部分计」', 单位量='份(0克)'))
        self.assertIn('ingredient_grams_outlier', f['flags'])
        self.assertIn('basis_grams_outlier', f['flags'])
        self.assertIn('unit_grams_outlier', f['flags'])
        self.assertIn('unit_unparsed', features(dish(单位量='份(一碗)'))['flags'])

    def test_bool_id_not_integer(self):
        result = audit(canonical(dish(True)), b'', 1, 1)
        self.assertEqual(result['counts']['valid'], 0)

    def test_all_zero_and_html(self):
        macro = '\n'.join(f'{k}0% NRV0 {u}' for k, u in [('能量','kcal'), ('蛋白质','g'), ('脂肪','g'), ('碳水化合物','g')])
        f = features(dish(能量及宏量营养素=macro, 菜肴做法='<p>1、煮</p>'))
        self.assertIn('all_zero_macros', f['flags'])
        self.assertIn('html_residue', f['flags'])

    def test_logged_failure_has_separate_destination(self):
        result = audit(b'', b'', 1, 2, '[00:00:00] [w1] 浏览器异常 id=1: unavailable')
        self.assertEqual(result['counts']['fetch_failed'], 1)
        self.assertEqual(result['counts']['unverified'], 1)

    def test_failed_bad_id_is_quarantined(self):
        result = audit(b'', canonical({'id': 1, '错误': 'timeout'}), 1, 1)
        self.assertEqual(result['quarantine'][0]['file'], 'failed.jsonl')
        self.assertEqual(result['counts']['unverified'], 1)

    def test_wrong_field_type_does_not_crash_audit(self):
        result = audit(canonical(dish(单位量=None, 菜肴做法=42)), b'', 1, 1)
        self.assertEqual(result['field_coverage']['单位量']['wrong_type'], 1)
        self.assertEqual(result['parsed_coverage_counts']['units_parsed'], 0)

    def test_overflow_number_is_bad_json(self):
        rows, bad = read_jsonl(b'{"number":1e999}', 'test')
        self.assertEqual(rows, [])
        self.assertEqual(len(bad), 1)

    def test_lone_surrogate_and_deep_nesting_are_quarantined(self):
        nested = b'{"nested":' + b'[' * 2000 + b'0' + b']' * 2000 + b'}'
        rows, bad = read_jsonl(b'{"name":"\\ud800"}\n' + nested, 'test')
        self.assertEqual(rows, [])
        self.assertEqual(len(bad), 2)

    def test_huge_text_number_does_not_break_output(self):
        r = dish(成分='测试原料：' + '9' * 400 + 'g')
        result = audit(canonical(r), b'', 1, 1)
        self.assertIn('numeric_text_nonfinite', result['anomaly_ids'])
        canonical(result)

    def test_repeated_audit_semantically_identical(self):
        raw = canonical(dish())
        self.assertEqual(canonical(audit(raw, b'', 1, 1)), canonical(audit(raw, b'', 1, 1)))


if __name__ == '__main__':
    unittest.main()
