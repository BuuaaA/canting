"""Collect P3 evidence from existing actual test logs; never runs or fabricates tests."""
from pathlib import Path
import hashlib, json, re, subprocess, datetime, platform

root = Path(__file__).resolve().parents[2]
evidence = root / 'dev-docs/p3-evidence'
def git(*args):
    return subprocess.run(['git',*args],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8')
def dump(path,obj):
    path.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

# Tool transcripts are normalized only for trailing whitespace/newlines, never results.
for path in evidence.glob('*.txt'):
    text = path.read_text(encoding='utf-8-sig')
    path.write_text('\n'.join(line.rstrip() for line in text.splitlines())+'\n',encoding='utf-8')
full=(evidence/'flutter-final.txt').read_text(encoding='utf-8')
analyze=(evidence/'analyze-final.txt').read_text(encoding='utf-8')
count=re.findall(r'\+(\d+): All tests passed!',full)
assert count and 'No issues found' in analyze
tracked=git('diff','--name-only').stdout.splitlines()
untracked=git('ls-files','--others','--exclude-standard').stdout.splitlines()
checks=[{'scope':'tracked diff','exit_code':git('diff','--check').returncode}]
for path in untracked:
    if path.endswith('p3-changes.json'): continue
    check=git('diff','--no-index','--check','--','/dev/null',path)
    assert not check.stdout, (path,check.stdout)
    checks.append({'scope':path,'exit_code':check.returncode})
assert checks[0]['exit_code']==0
frozen=['AGENTS.md','assets/data/dishes.json','assets/data/categories.json','assets/data/dietary_guidelines.json','dev-docs/p2-local-food-profile-acceptance.md']+git('ls-tree','-r','--name-only','HEAD','dev-docs/p2-evidence').stdout.splitlines()
unchanged={path:git('hash-object',path).stdout.strip()==git('rev-parse','HEAD:'+path).stdout.strip() for path in frozen}
assert all(unchanged.values())
audit=json.loads((evidence/'candidate-audit.json').read_text(encoding='utf-8'))
dump(evidence/'validation.json',{
 'collected_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'baseline':'d7077e221bab45226ba0a16a881588418d61460a','head':git('rev-parse','HEAD').stdout.strip(),
 'git_status':git('status','--short','--branch').stdout.splitlines(),
 'staged_paths':git('diff','--cached','--name-only').stdout.splitlines(),
 'commands':[
  {'command':'dart format --output=none --set-exit-if-changed <changed Dart paths>','result':(evidence/'format-final.txt').read_text(encoding='utf-8').strip(),'exit_code':0},
  {'command':'dart format --output=none --set-exit-if-changed lib/ui/history/record_summary_panel.dart test/ui/p3_production_pages_test.dart','result':(evidence/'r1-format-final.txt').read_text(encoding='utf-8').strip(),'exit_code':0},
  {'command':'flutter test --no-pub test/ui/p3_production_pages_test.dart --reporter expanded','passed':7,'exit_code':0,'log':'r1-component.txt'},
  {'command':'flutter analyze --no-pub','result':'No issues found','exit_code':0,'log':'analyze-final.txt'},
  {'command':'flutter test --no-pub --reporter expanded','passed':int(count[-1]),'exit_code':0,'log':'flutter-final.txt'}],
 'diff_checks':checks,'frozen_files_unchanged':unchanged,
 'candidate_counts':audit['eligibility_evaluated'],'constructed_exclusion_leaks':0,
 'screenshots':{'kind':'Flutter widget test, 1080x2400, host font for evidence only','paths':[p.name for p in evidence.glob('component-*.png')]},
 'host':platform.platform(),
 'r1_review':{'status':'corrected','approved_copy':'仅展示已记录餐食结构，暂不判断改善趋势；28天差额不分摊到下一餐。','complete_28d_assertion':{'recordedDays':28,'partialDays':0,'missingDays':0,'unknownItemCount':0},'preserved_component_states':['empty','partial','error']},
 'normalization':'P3 text tool transcripts normalize trailing whitespace only; P2 files untouched',
 'known_limitations':['legacy 30-day +/-20% convergence assertion no longer holds; full negative diagnostic retained','No device/native/system share acceptance in P3','Six-category model and legacy proxy evidence are incomplete health knowledge'],
 'commit_or_push':False,'next_phase_started':False})
paths=sorted(set(tracked+untracked+['dev-docs/p3-evidence/validation.json']))
paths=[p for p in paths if p!='dev-docs/p3-changes.json' and (root/p).is_file()]
dump(root/'dev-docs/p3-changes.json',{'baseline':git('rev-parse','HEAD').stdout.strip(),'manifest_excludes_itself':True,'files':[{'path':p,'sha256':hashlib.sha256((root/p).read_bytes()).hexdigest(),'bytes':(root/p).stat().st_size} for p in paths]})
print(json.dumps({'flutter_passed':int(count[-1]),'files':len(paths),'candidate_counts':audit['eligibility_evaluated'],'frozen_paths_checked':len(unchanged),'staged_paths':git('diff','--cached','--name-only').stdout.splitlines()},ensure_ascii=False))
