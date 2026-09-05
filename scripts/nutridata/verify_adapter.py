"""Offline P1 verification. Only synthetic/temporary DB tests; no data import."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone


def main():
    root = Path(__file__).resolve().parents[2]
    flutter = shutil.which('flutter')
    dart = shutil.which('dart')
    if not flutter or not dart:
        raise SystemExit('Flutter and Dart must already be installed/on PATH')
    dart_files = ['lib/core/models/food_knowledge.dart', 'lib/core/models/food_data.dart',
                  'lib/core/models/portions.dart', 'lib/data/food_database.dart',
                  'lib/data/database_helper.dart', 'test/data/food_knowledge_test.dart',
                  'test/data/food_knowledge_sync_test.dart']
    commands = [
        [sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts/nutridata', '-p', 'test_*.py', '-v'],
        [dart, 'format', '--output=none', '--set-exit-if-changed', *dart_files],
        [flutter, 'test', '--no-pub', 'test/data/food_knowledge_test.dart',
         'test/data/food_knowledge_sync_test.dart', 'test/data/seed_migration_test.dart',
         'test/data/database_migration_test.dart'],
        [flutter, 'analyze', '--no-pub'],
        [flutter, 'test', '--no-pub'],
    ]
    result = {'started_at': datetime.now(timezone.utc).isoformat(), 'commands': [],
              'scope': 'synthetic contract and temporary SQLite fixtures; original 1004 asset unchanged'}
    for command in commands:
        print('Running: ' + ' '.join(command), flush=True)
        start = datetime.now(timezone.utc)
        process = subprocess.run(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        output = process.stdout.decode('utf-8', errors='replace')
        tests = re.findall(r'\+(\d+): All tests passed!', output)
        python_tests = re.findall(r'Ran (\d+) tests', output)
        row = {'argv': command, 'started_at': start.isoformat(),
               'finished_at': datetime.now(timezone.utc).isoformat(),
               'exit_code': process.returncode, 'stdout_sha256': hashlib.sha256(process.stdout).hexdigest(),
               'tail': output.splitlines()[-8:]}
        if tests or python_tests: row['tests_passed'] = int((tests or python_tests)[-1])
        result['commands'].append(row)
        print('\n'.join(row['tail']), flush=True)
    paths = dart_files + ['pubspec.yaml', 'pubspec.lock', 'scripts/nutridata/contract.py',
        'scripts/nutridata/test_contract.py', 'scripts/nutridata/test_adapter_contract.py',
        'scripts/nutridata/food-knowledge-draft.schema.json', 'scripts/nutridata/build_synthetic_fixtures.py',
        'scripts/nutridata/verify_adapter.py', 'test/fixtures/food_knowledge_contract_cases.json',
        'assets/data/dishes.json']
    result['sha256'] = {p: hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths}
    result['finished_at'] = datetime.now(timezone.utc).isoformat()
    result['passed'] = all(c['exit_code'] == 0 for c in result['commands'])
    (root/'dev-docs/food-knowledge-adapter-validation.json').write_text(
        json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
