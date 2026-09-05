"""Collect already completed P2 checks; does not run tests or touch user databases."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'dev-docs/p2-evidence'
OUT.mkdir(parents=True, exist_ok=True)

def git(*args):
    return subprocess.check_output(['git', '-c', 'core.quotepath=false', *args], cwd=ROOT).decode('utf-8').strip()

checks = []
for name, marker, command in [
    ('format', '0 changed', 'dart format --output=none --set-exit-if-changed <P2 changed Dart files>'),
    ('analyze', 'No issues found!', 'flutter analyze --no-pub'),
    ('regression', 'All tests passed!', 'flutter test --no-pub --reporter expanded'),
    ('kotlin', 'BUILD SUCCESSFUL', 'gradlew.bat :app:testDebugUnitTest --offline'),
    ('emulator-build', 'app-debug.apk', 'flutter build apk --debug --no-pub -t tool/p2_emulator_smoke.dart'),
]:
    source = ROOT / f'p2-{name}.log'
    data = source.read_bytes()
    content = data.decode('utf-8', errors='replace')
    assert marker in content, f'{name} has no successful completion marker'
    destination = OUT / f'{name}.txt'
    destination.write_bytes(data)
    checks.append({'name': name, 'command': command, 'result': 'pass',
                   'verification': 'success marker in preserved command log',
                   'log': str(destination.relative_to(ROOT)),
                   'log_sha256': hashlib.sha256(data).hexdigest(),
                   'log_updated_at': datetime.fromtimestamp(source.stat().st_mtime, timezone.utc).isoformat()})

diff = subprocess.run(['git', 'diff', '--check'], cwd=ROOT, capture_output=True)
assert diff.returncode == 0, diff.stdout.decode(errors='replace')
checks.append({'name': 'diff-check', 'command': 'git diff --check', 'exit_code': diff.returncode})
junit = []
for file in (ROOT / 'build/app/test-results/testDebugUnitTest').glob('*.xml'):
    suite = ET.parse(file).getroot()
    assert suite.attrib.get('failures') == '0' and suite.attrib.get('errors') == '0'
    junit.append(suite.attrib)
    shutil.copyfile(file, OUT / file.name)

asset = hashlib.sha256((ROOT / 'assets/data/dishes.json').read_bytes()).hexdigest()
assert asset == '7cdef0bd03f4df72270020b0b42a67be4aa119049ebdfb3b88eec5acc368079a'
regression = (ROOT / 'p2-regression.log').read_text(encoding='utf-8', errors='replace')
count = re.search(r'\+(\d+): All tests passed!', regression)
assert count
report = {'recorded_at': datetime.now(timezone.utc).isoformat(), 'p1_commit': git('rev-parse', 'HEAD'),
          'flutter_tests_passed': int(count[1]), 'checks': checks, 'kotlin_junit': junit,
          'unchanged_catalog_sha256': asset, 'p2_committed': False,
          'emulator': json.loads((OUT / 'emulator-verification.json').read_text(encoding='utf-8'))}
(OUT / 'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')

files = set(git('diff', '--name-only').splitlines()) | set(git('ls-files', '--others', '--exclude-standard').splitlines())
manifest = []
for name in sorted(files):
    if name == 'dev-docs/p2-local-food-profile-changes.json':
        continue
    file = ROOT / name
    if file.is_file():
        manifest.append({'path': name, 'sha256': hashlib.sha256(file.read_bytes()).hexdigest(), 'bytes': file.stat().st_size})
(ROOT / 'dev-docs/p2-local-food-profile-changes.json').write_text(json.dumps({
    'p1_commit': report['p1_commit'], 'note': 'P2 worktree only; excludes this manifest own hash; no raw source, accounts or build artifacts',
    'files': manifest}, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'flutter_tests_passed': report['flutter_tests_passed'], 'kotlin_tests': sum(int(s['tests']) for s in junit),
                  'files': len(manifest), 'git_head': report['p1_commit']}, indent=2))
