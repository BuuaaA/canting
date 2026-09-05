import os
run_id=os.environ.get('CANTING_P6A_RUN_ID', '')
if not run_id or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_' for c in run_id):
 raise SystemExit('Set CANTING_P6A_RUN_ID to a new run id (letters/digits/hyphen/underscore).')
from pathlib import Path
import json,hashlib,subprocess,xml.etree.ElementTree as ET
r=Path(__file__).resolve().parents[2];e=r/'dev-docs/p6a-evidence'/run_id
if (e/'validation.json').exists():
 raise SystemExit('This evidence run is frozen; choose a new run id.')
checks=[]
def check(name,ok,detail=''):
 checks.append({'name':name,'passed':bool(ok),'detail':detail})
m=json.loads((r/'dev-docs/p4-changes.json').read_text(encoding='utf-8'))
frozen=[f for f in m['files'] if f['path'].startswith(('dev-docs/p4-evidence/','test/fixtures/recognition_acceptance/'))]
bad=[f['path'] for f in frozen if hashlib.sha256((r/f['path']).read_bytes()).hexdigest()!=f['sha256']]
check('P4 frozen raw bytes unchanged',not bad,{'count':len(frozen),'mismatches':bad})
p3=subprocess.check_output(['git','diff','--name-only','HEAD','--','dev-docs/p2-evidence','dev-docs/p3-evidence'],cwd=r,text=True)
check('P2/P3 tracked evidence unchanged',not p3,p3)
ns='{http://schemas.android.com/apk/res/android}'
merged=r/'build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml'
tree=ET.parse(merged);root=tree.getroot();app=root.find('application')
permissions=[x.get(ns+'name') for x in root.findall('uses-permission')]
check('Production no INTERNET or ACCESS_NETWORK_STATE',not set(permissions)&{'android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE'},permissions)
check('Package identity preserved',root.get('package')=='com.canting.canting',root.get('package'))
check('Backup explicitly disabled',app.get(ns+'allowBackup')=='false')
check('Both backup formats declared',app.get(ns+'fullBackupContent')=='@xml/backup_rules' and app.get(ns+'dataExtractionRules')=='@xml/data_extraction_rules')
for n in ['.PetWidgetProvider','.SharedDataProvider','androidx.core.content.FileProvider']:
 found=[x for x in app if x.get(ns+'name','').endswith(n)]
 check(n+' is private',bool(found) and all(x.get(ns+'exported')=='false' for x in found))
for file in ['backup_rules.xml','data_extraction_rules.xml']:
 t=ET.parse(r/'android/app/src/main/res/xml'/file)
 domains={'root','file','database','sharedpref','external','device_root','device_file','device_database','device_sharedpref'}
 sections=[t.getroot()] if file=='backup_rules.xml' else [t.getroot().find('cloud-backup'),t.getroot().find('device-transfer')]
 check(file+' covers all data domains',all({x.get('domain') for x in s.findall('exclude') if x.get('path')=='.'}==domains for s in sections))
views=(r/'android/app/src/main/kotlin/com/canting/canting/PetWidgetViews.kt').read_text(encoding='utf-8')
check('Widget binds tested unknown model and hides unknown progress',all(s in views for s in ['PetWidgetCompletion.percent(','PetWidgetCompletion.label(','status.todayCompletionPercent == null) View.GONE']))
for file in ['lib/main.dart','lib/state/app_state.dart','lib/ui/settings/settings_page.dart']:
 lines=(r/file).read_text(encoding='utf-8').splitlines();bad=[]
 for i,line in enumerate(lines):
  if 'debugPrint(' in line and 'if (kDebugMode)' not in line and not any('if (kDebugMode)' in x for x in lines[max(0,i-2):i]):bad.append(i+1)
 check(file+' diagnostic calls guarded',not bad,bad)
result={'checks':checks,'passed':all(c['passed'] for c in checks)}
(e/'configuration-validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))
raise SystemExit(0 if result['passed'] else 1)
