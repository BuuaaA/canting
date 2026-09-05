"""Collect R1/R2 completed command logs; never runs tests or opens user DBs."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'dev-docs/p2-evidence/review-20260905'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def git(*args):
    return subprocess.check_output(['git', '-c', 'core.quotepath=false', *args], cwd=ROOT).decode('utf8').strip()

baseline = json.loads((OUT / 'baseline-changes.json').read_text(encoding='utf8'))
old = {f['path']: f for f in baseline['files']}
source_files = [
    'lib/core/models/local_food.dart', 'lib/core/local_food_matcher.dart',
    'lib/ui/record/record_detail_page.dart', 'lib/ui/record/food_confirmation_sheet.dart',
    'lib/core/models/meal_record.dart', 'lib/state/app_state.dart',
    'test/ui/record/brand_context_review_test.dart', 'test/state/meal_reward_review_test.dart',
    'test/state/app_state_pet_test.dart',
]
expected = set(source_files + ['dev-docs/p2-local-food-profile-acceptance.md'])
unexpected = [n for n, f in old.items() if sha(ROOT / n) != f['sha256'] and n not in expected]
assert not unexpected, f'Unexpected overlapping modifications: {unexpected}'
checks = []
for name, marker, command in [
    ('format', '0 changed', 'dart format --output=none --set-exit-if-changed ' + ' '.join(source_files)),
    ('analyze', 'No issues found!', 'flutter analyze --no-pub'),
    ('related', '+47: All tests passed!', 'flutter test --no-pub test/state/meal_reward_review_test.dart test/state/app_state_pet_test.dart test/ui/record/brand_context_review_test.dart test/data/local_food_flow_test.dart test/core/local_food_knowledge_match_test.dart test/ui/food_confirmation_test.dart --reporter expanded'),
    ('regression', '+425: All tests passed!', 'flutter test --no-pub --reporter expanded'),
    ('independent', 'before=60 after=60', 'flutter test --no-pub C:/Users/gxy20/Documents/ChatGPT/代码审核/p2_review_probe_test.dart --plain-name "deleting an uncredited complete meal must not change vitality" --reporter expanded'),
]:
    p = ROOT / f'p2-review-{name}.log'
    text = p.read_text(encoding='utf8')
    assert marker in text, name
    dest = OUT / f'{name}.txt'
    dest.write_bytes(p.read_bytes())
    checks.append({'command': command, 'result': 'pass', 'log': str(dest.relative_to(ROOT)), 'sha256': sha(dest)})
for name in ['r1-before', 'r2-before']:
    p = ROOT / f'p2-{name}.log'
    assert 'Some tests failed' in p.read_text(encoding='utf8')
    (OUT / f'{name}.txt').write_bytes(p.read_bytes())
result = subprocess.run(['git', 'diff', '--check'], cwd=ROOT, capture_output=True)
assert result.returncode == 0, result.stdout
assert git('rev-parse', 'HEAD') == baseline['p1_commit']
assert not git('diff', '--cached', '--name-only')
assert not git('diff', '--name-only', '--', 'AGENTS.md', 'assets/data/dishes.json')
report = {
    'recorded_at': datetime.now(timezone.utc).isoformat(),
    'head': git('rev-parse', 'HEAD'), 'branch': git('branch', '--show-current'),
    'flutter_tests': 425, 'related_tests': 47, 'new_tests': 21, 'independent_r2_tests': 1,
    'r1_before': {'passed': 1, 'failed': 5}, 'r2_initial_before': {'passed': 5, 'failed': 7},
    'checks': checks, 'diff_check_exit': result.returncode,
    'r1_evidence_type': 'Production RecordDetailPage widget interaction, not emulator or physical device',
    'native_changed_this_review': False, 'kotlin_rerun': False,
    'original_probe_sha256': sha(Path('C:/Users/gxy20/Documents/ChatGPT/代码审核/p2_review_probe_test.dart')),
    'unchanged_catalog_sha256': sha(ROOT / 'assets/data/dishes.json'),
    'unexpected_baseline_changes': unexpected,
    'git_status': git('status', '--short', '--branch'), 'staged_files': [], 'committed': False,
}
(OUT / 'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
changed = []
for n in source_files + ['dev-docs/p2-local-food-profile-acceptance.md', 'scripts/p2/collect_review_evidence.py']:
    before = old.get(n, {}).get('sha256')
    if before is None:
        previous = subprocess.run(['git','show',f'HEAD:{n}'],cwd=ROOT,capture_output=True)
        if previous.returncode == 0:
            before = hashlib.sha256(previous.stdout).hexdigest()
    changed.append({'path': n, 'before_sha256': before, 'after_sha256': sha(ROOT/n), 'bytes': (ROOT/n).stat().st_size})
(OUT/'changes.json').write_text(json.dumps({'head':report['head'],'note':'R1/R2 only; baseline copied before edits; source/acceptance/collector files below, evidence logs separately hashed in validation.json','files':changed},ensure_ascii=False,indent=2),encoding='utf8')
files = set(git('diff','--name-only').splitlines()) | set(git('ls-files','--others','--exclude-standard').splitlines())
manifest = []
for n in sorted(files):
    if n == 'dev-docs/p2-local-food-profile-changes.json':
        continue
    p = ROOT/n
    if p.is_file():
        manifest.append({'path':n,'sha256':sha(p),'bytes':p.stat().st_size})
(ROOT/'dev-docs/p2-local-food-profile-changes.json').write_text(json.dumps({'p1_commit':report['head'],'note':'P2 including R1/R2 remains uncommitted; own hash excluded; initial evidence retained separately','files':manifest},ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'flutter_tests':425,'related_tests':47,'p2_files':len(manifest),'head':report['head'],'staged':False,'unexpected_changes':unexpected},ensure_ascii=False))
