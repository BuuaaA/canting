"""Rebuild shared test-only contract cases; never reads or emits real recipes."""
import copy
import json
from pathlib import Path
from test_contract import synthetic


def build():
    unknown = synthetic()
    good = synthetic()
    good.update(semantic_category='burger', beverage_type='notApplicable', recipe_known=True,
                preparation='grilled', sugar_level='notApplicable', eligibility='eligible',
                risk_tags=[], facts_complete=True, review_status='reviewed',
                review_evidence='synthetic:review', license_status='approved',
                license_evidence='synthetic:authored', eligibility_reasons=['synthetic:qualified'],
                category_contributions={k: [0, 0] for k in
                    ['grains', 'vegetables', 'fruits', 'protein', 'protein_soy', 'oil']})
    good['category_contributions'].update(grains=[1, 1], vegetables=[.5, 1], protein=[1, 1])
    for k in good['field_provenance']:
        good['field_provenance'][k] = {'kind': 'source', 'evidence': 'synthetic:fact'}
    cases = []
    def case(name, base, changes, valid):
        r = copy.deepcopy(base); r.update(changes)
        cases.append({'name': name, 'valid': valid, 'record': r})
        return r
    case('unknown remains null', unknown, {}, True)
    case('burger separate mixed contributions', good, {}, True)
    drink = copy.deepcopy(good)
    drink.update(semantic_category='beverage', beverage_type='milk_tea', sugar_level='none')
    for sugar in ['low', 'regular', 'high', 'unknown', 'notApplicable']:
        case('drink rejects '+sugar, drink, {'sugar_level': sugar}, False)
    for recipe in [None, False]:
        case('unsweetened unknown recipe '+str(recipe), drink, {'recipe_known': recipe}, False)
    case('known unsweetened coffee still requires all gates', drink, {'beverage_type': 'coffee'}, True)
    case('unsweetened unreviewed milk tea', drink, {'review_status': 'unreviewed'}, False)
    case('unknown drink subtype', drink, {'beverage_type': 'unknown'}, False)
    case('fried fact empty tags', good, {'preparation': 'fried'}, False)
    case('fried tag grilled fact', good, {'risk_tags': ['fried']}, False)
    case('unknown preparation', good, {'preparation': 'unknown'}, False)
    for unit in ['g', 'ml']:
        case('portion '+unit, good, {'portion_range': {'min': 120, 'max': 240, 'unit': unit, 'scope': 'consumed'}}, True)
    case('large cup no volume', drink, {'cup_size': 'large', 'portion_range': None}, True)
    case('cake size no portion', good, {'semantic_category': 'dessert', 'size_bucket': 'large', 'portion_range': None}, True)
    for lo, hi, unit, scope in [(240, 120, 'g', 'consumed'), (-1, 1, 'g', 'consumed'), (True, 1, 'g', 'consumed'), (1, 2, 'cm', 'consumed'), (1, 2, 'g', 'whole_product')]:
        case('invalid portion '+str((lo,hi,unit,scope)), good, {'portion_range': {'min':lo,'max':hi,'unit':unit,'scope':scope}}, False)
    case('explicit zero consumed', good, {'portion_range': {'min':0,'max':0,'unit':'g','scope':'consumed'}}, True)
    zeros = {k:[0,0] for k in good['category_contributions']}
    case('real zero contributions', good, {'category_contributions':zeros}, True)
    case('unknown is not zero', unknown, {'category_contributions':zeros}, False)
    partial = copy.deepcopy(good['category_contributions']); partial['oil'] = None
    case('partial unknown conditional', good, {'category_contributions':partial, 'eligibility':'conditional'}, True)
    case('partial unknown eligible', good, {'category_contributions':partial}, False)
    case('missing contribution key', good, {'category_contributions':{'grains':[1,1]}}, False)
    case('numeric confidence without evidence', good, {'confidence':.9}, False)
    case('wrong schema', good, {'schema_version':1}, False)
    case('license unknown eligible', good, {'license_status':'unknown'}, False)
    return cases


if __name__ == '__main__':
    out = Path(__file__).resolve().parents[2] / 'test/fixtures/food_knowledge_contract_cases.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(build(), ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
