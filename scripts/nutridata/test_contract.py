import copy
import json
from pathlib import Path
import unittest
from contract import CONTRIBUTION_KEYS, REQUIRED, validate


def synthetic():
    return dict(canonical_id='synthetic:1', canonical_name='测试混合菜', aliases=[], source_type='editorial', source_id='1',
        source_sha256='0'*64, schema_version=2, data_version='test-only',
        transform_version='1.0.0', policy_version='draft', estimated=True,
        confidence=None, confidence_evidence=None, review_status='unreviewed',
        license_status='unknown', license_evidence=None, review_evidence=None,
        semantic_category='unknown', beverage_type='unknown', recipe_known=None, preparation='unknown', sugar_level='unknown',
        cup_size='unknown', size_bucket='unknown', portion_range=None, category_contributions=None,
        risk_tags=['unknown_preparation'], eligibility='conditional',
        eligibility_reasons=['unknown_preparation'], facts_complete=False,
        field_provenance={k:{'kind':'unknown','evidence':None} for k in
            ['semantic_category','beverage_type','recipe_known','preparation','sugar_level','cup_size','size_bucket','portion_range','category_contributions']})


class ContractTests(unittest.TestCase):
    def test_declarative_schema_matches_contract_fields(self):
        schema=json.loads(Path(__file__).with_name('food-knowledge-draft.schema.json').read_text(encoding='utf-8'))
        self.assertEqual(set(schema['required']),REQUIRED)
        self.assertEqual(set(schema['properties']),REQUIRED)

    def test_unknown_is_valid_and_explicit(self):
        validate(synthetic())

    def test_illegal_enum_and_schema(self):
        for key, value in [('preparation','magic'),('schema_version',True),('confidence',float('nan'))]:
            r = synthetic(); r[key] = value
            with self.assertRaises(ValueError): validate(r)

    def test_zero_not_unknown(self):
        r = synthetic(); r['category_contributions'] = {key:[0,0] for key in CONTRIBUTION_KEYS}
        with self.assertRaises(ValueError): validate(r)

    def test_intervals(self):
        for value in [[200,100], [-1,0], [True,100], [1,float('inf')]]:
            r = synthetic(); r['portion_range'] = dict(min=value[0], max=value[1], unit='g', scope='consumed')
            with self.assertRaises(ValueError): validate(r)

    def test_risk_wins_even_reviewed(self):
        r = synthetic()
        r.update(eligibility='eligible', preparation='boiled', facts_complete=True,
                 recipe_known=True, review_status='reviewed', review_evidence='synthetic:test', license_status='approved',
                 license_evidence='synthetic:test', semantic_category='mixed',
                 category_contributions={key:[0,0] for key in CONTRIBUTION_KEYS}, risk_tags=[])
        r['category_contributions']['protein'] = [.5,1]
        for field in ['semantic_category', 'recipe_known', 'preparation', 'category_contributions']:
            r['field_provenance'][field] = {'kind':'estimated', 'evidence':'synthetic:test'}
        validate(r)
        for risk in ['fried','high_sodium','sugary_drink']:
            unsafe = copy.deepcopy(r); unsafe['risk_tags'] = [risk]
            with self.assertRaises(ValueError): validate(unsafe)
        r['preparation'] = 'fried'
        with self.assertRaises(ValueError): validate(r)

    def test_estimation_cannot_be_upgraded(self):
        r = synthetic(); r['estimated'] = False
        r['field_provenance']['preparation'] = {'kind':'inferred','evidence':'synthetic:test'}
        with self.assertRaises(ValueError): validate(r)

    def test_licence_and_review_need_evidence(self):
        for key, value in [('review_status','reviewed'),('license_status','approved')]:
            r=synthetic(); r[key]=value
            with self.assertRaises(ValueError): validate(r)


if __name__ == '__main__':
    unittest.main()
