import copy
import unittest
import hashlib
import json
from pathlib import Path
from contract import validate, validate_package, CONTRIBUTION_KEYS
from test_contract import synthetic


def reviewed():
    r = synthetic()
    r.update(eligibility='eligible', preparation='boiled', facts_complete=True,
             review_status='reviewed', review_evidence='synthetic:review',
             license_status='approved', license_evidence='synthetic:own',
             semantic_category='beverage', beverage_type='coffee', recipe_known=True, sugar_level='none', risk_tags=[],
             category_contributions={k: [0, 0] for k in CONTRIBUTION_KEYS})
    r['category_contributions']['protein'] = [0.5, 1]
    for k in r['field_provenance']:
        r['field_provenance'][k] = {'kind': 'source', 'evidence': 'synthetic:fact'}
    return r


class AdapterContractTests(unittest.TestCase):
    def test_shared_dart_cases(self):
        path = Path(__file__).resolve().parents[2] / 'test/fixtures/food_knowledge_contract_cases.json'
        for c in json.loads(path.read_text(encoding='utf-8')):
            with self.subTest(name=c['name']):
                if c['valid']:
                    validate(c['record'])
                else:
                    with self.assertRaises(ValueError): validate(c['record'])

    def test_package_integrity(self):
        r = synthetic()
        content = json.dumps({'records':[r]}, ensure_ascii=False)
        p = dict(schema_version=2, content_version='test-only', content_json=content,
                 content_sha256=hashlib.sha256(content.encode()).hexdigest())
        validate_package(p)
        for change in [{'schema_version':1}, {'content_version':'different'}, {'content_json':'{}'}]:
            with self.assertRaises(ValueError): validate_package(dict(p, **change))
        p['content_json'] = json.dumps({'records':[r,r]})
        p['content_sha256'] = hashlib.sha256(p['content_json'].encode()).hexdigest()
        with self.assertRaises(ValueError): validate_package(p)

    def test_sweetness_fact_beats_missing_tags(self):
        for sugar in ('low', 'regular', 'high'):
            with self.subTest(sugar=sugar):
                r = reviewed()
                r['sugar_level'] = sugar
                with self.assertRaises(ValueError):
                    validate(r)


if __name__ == '__main__':
    unittest.main()
