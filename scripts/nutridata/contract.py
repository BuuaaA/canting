"""FoodKnowledge schema 2 contract; synthetic fixtures only in this repository.

This validates synthetic candidate records only in tests. No real distilled
dataset is emitted. Numerical confidence requires separate calibration evidence.
"""
import math
import hashlib
import json

REQUIRED = {'canonical_id', 'canonical_name', 'aliases', 'source_type', 'source_id', 'source_sha256',
            'schema_version', 'data_version', 'transform_version', 'policy_version',
            'estimated', 'confidence', 'confidence_evidence', 'review_status',
            'license_status', 'license_evidence', 'review_evidence',
            'semantic_category', 'beverage_type', 'recipe_known', 'preparation', 'sugar_level', 'cup_size', 'size_bucket',
            'portion_range', 'category_contributions', 'risk_tags', 'eligibility',
            'eligibility_reasons', 'facts_complete', 'field_provenance'}
HARD_RISKS = {'fried', 'alcohol', 'sugary_drink', 'high_sugar', 'high_sodium', 'high_oil'}
CATEGORIES = {'grains', 'vegetables', 'fruits', 'protein', 'protein_soy', 'dairy',
              'nuts', 'mixed', 'burger', 'beverage', 'dessert', 'condiment', 'water', 'unknown'}
CONTRIBUTION_KEYS = {'grains', 'vegetables', 'fruits', 'protein', 'protein_soy', 'oil'}


def numeric(v):
    return type(v) in (int, float) and math.isfinite(v)


def validate_range(value, allow_zero=False):
    if value is None:
        return
    if not isinstance(value, list) or len(value) != 2 or not all(numeric(v) for v in value):
        raise ValueError('range must be null or two finite numbers')
    lo, hi = value
    if lo < 0 or (not allow_zero and lo == 0) or hi < lo:
        raise ValueError('invalid interval')


def validate(record):
    if not isinstance(record, dict) or set(record) != REQUIRED:
        raise ValueError('required fields or unexpected fields')
    enums = {
        'source_type': {'nutridata', 'editorial', 'user_confirmed'},
        'review_status': {'unreviewed', 'needs_review', 'reviewed', 'rejected'},
        'license_status': {'unknown', 'restricted', 'approved'},
        'semantic_category': CATEGORIES,
        'beverage_type': {'milk_tea', 'coffee', 'tea', 'milk', 'water', 'other', 'unknown', 'notApplicable'},
        'preparation': {'steamed', 'boiled', 'stewed', 'stir_fried', 'fried',
                        'pan_fried', 'grilled', 'raw', 'mixed', 'unknown'},
        'sugar_level': {'none', 'low', 'regular', 'high', 'unknown', 'notApplicable'},
        'cup_size': {'small', 'regular', 'large', 'unknown', 'notApplicable'},
        'size_bucket': {'small', 'regular', 'large', 'unknown'},
        'eligibility': {'eligible', 'conditional', 'ineligible'},
    }
    for key, options in enums.items():
        if not isinstance(record[key], str) or record[key] not in options:
            raise ValueError('invalid enum: ' + key)
    for key in ['canonical_id', 'canonical_name', 'source_id', 'source_sha256', 'data_version',
                'transform_version', 'policy_version']:
        if not isinstance(record[key], str) or not record[key].strip():
            raise ValueError('missing provenance/version: ' + key)
    if len(record['source_sha256']) != 64 or any(c not in '0123456789abcdef' for c in record['source_sha256']):
        raise ValueError('invalid source digest')
    if type(record['schema_version']) is not int or record['schema_version'] != 2:
        raise ValueError('unsupported knowledge schema')
    for key in ['estimated', 'facts_complete']:
        if type(record[key]) is not bool: raise ValueError('expected boolean: ' + key)
    confidence = record['confidence']
    for key in ['confidence_evidence', 'license_evidence', 'review_evidence']:
        if record[key] is not None and (not isinstance(record[key], str) or not record[key].strip()):
            raise ValueError('invalid evidence: ' + key)
    if confidence is not None and (not numeric(confidence) or not 0 <= confidence <= 1 or not record['confidence_evidence']):
        raise ValueError('uncalibrated or invalid confidence')
    for key in ['risk_tags', 'eligibility_reasons', 'aliases']:
        if not isinstance(record[key], list) or any(not isinstance(v, str) for v in record[key]):
            raise ValueError('expected string list: ' + key)
        if len(record[key]) != len(set(record[key])): raise ValueError('duplicate tags')
    if not set(record['risk_tags']) <= HARD_RISKS | {'unknown_preparation', 'unknown_ingredients', 'source_conflict'}:
        raise ValueError('invalid risk tag')
    if record['recipe_known'] is not None and type(record['recipe_known']) is not bool:
        raise ValueError('recipe_known must be null or boolean')
    if record['semantic_category'] == 'beverage':
        if record['beverage_type'] == 'notApplicable' or record['sugar_level'] == 'notApplicable':
            raise ValueError('beverage facts cannot be notApplicable')
    elif record['beverage_type'] not in {'unknown', 'notApplicable'}:
        raise ValueError('beverage subtype requires beverage category')
    portion = record['portion_range']
    if portion is not None:
        if (not isinstance(portion, dict) or set(portion) != {'min', 'max', 'unit', 'scope'}
                or portion['unit'] not in {'g', 'ml'} or portion['scope'] != 'consumed'):
            raise ValueError('portion must describe consumed g or ml')
        validate_range([portion['min'], portion['max']], allow_zero=True)
    contributions = record['category_contributions']
    if contributions is not None:
        if not isinstance(contributions, dict) or set(contributions) != CONTRIBUTION_KEYS:
            raise ValueError('invalid contributions')
        for value in contributions.values(): validate_range(value, allow_zero=True)
    provenance = record['field_provenance']
    if not isinstance(provenance, dict) or not provenance:
        raise ValueError('field provenance required')
    for field in ['semantic_category', 'beverage_type', 'recipe_known', 'preparation', 'sugar_level', 'cup_size', 'size_bucket', 'portion_range', 'category_contributions']:
        p = provenance.get(field)
        if not isinstance(p, dict) or p.get('kind') not in {'source', 'calculated', 'inferred', 'estimated', 'user_confirmed', 'unknown'}:
            raise ValueError('missing field origin: ' + field)
        if p['kind'] != 'unknown' and (not isinstance(p.get('evidence'), str) or not p['evidence'].strip()):
            raise ValueError('field evidence required')
        if p['kind'] in {'estimated', 'inferred'} and not record['estimated']:
            raise ValueError('estimated fact cannot be upgraded to verified')
    for field in ['portion_range', 'category_contributions']:
        if record[field] is not None and provenance[field]['kind'] == 'unknown':
            raise ValueError('known numerical fact needs evidence; unknown is null')
    if record['recipe_known'] is True and provenance['recipe_known']['kind'] == 'unknown':
        raise ValueError('known recipe needs evidence')
    if record['review_status'] == 'reviewed' and not record['review_evidence']:
        raise ValueError('review evidence required')
    if record['license_status'] == 'approved' and not record['license_evidence']:
        raise ValueError('license evidence required')
    if record['eligibility'] == 'eligible':
        if (record['preparation'] in {'fried', 'unknown'} or record['risk_tags']
                or not record['facts_complete'] or record['review_status'] != 'reviewed'
                or record['license_status'] != 'approved' or not record['eligibility_reasons']
                or record['semantic_category'] == 'unknown' or contributions is None
                or any(v is None for v in contributions.values())
                or record['sugar_level'] in {'low', 'regular', 'high'}
                or record['recipe_known'] is not True
                or (record['semantic_category'] == 'beverage' and (
                    record['sugar_level'] != 'none' or record['beverage_type'] == 'unknown'
                    or any(provenance[k]['kind'] == 'unknown' for k in ['sugar_level', 'beverage_type'])))
                or any(provenance[k]['kind'] == 'unknown' for k in
                       ['semantic_category', 'preparation', 'category_contributions'])):
            raise ValueError('candidate cannot bypass deterministic eligibility gate')
    return record


def validate_package(package):
    if not isinstance(package, dict) or set(package) != {'schema_version', 'content_version', 'content_sha256', 'content_json'}:
        raise ValueError('invalid package envelope')
    if type(package['schema_version']) is not int or package['schema_version'] != 2:
        raise ValueError('unsupported package schema')
    if not isinstance(package['content_version'], str) or not package['content_version'].strip():
        raise ValueError('missing content version')
    if not isinstance(package['content_json'], str):
        raise ValueError('content_json must be exact JSON text')
    if hashlib.sha256(package['content_json'].encode('utf-8')).hexdigest() != package['content_sha256']:
        raise ValueError('content digest mismatch')
    body = json.loads(package['content_json'])
    if not isinstance(body, dict) or set(body) != {'records'} or not isinstance(body['records'], list):
        raise ValueError('invalid content body')
    seen = set()
    for record in body['records']:
        validate(record)
        if record['canonical_id'] in seen or record['data_version'] != package['content_version']:
            raise ValueError('duplicate ID or content version mismatch')
        seen.add(record['canonical_id'])
    return package
