import os
run_id=os.environ.get('CANTING_P5_RUN_ID', '')
if not run_id or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_' for c in run_id):
 raise SystemExit('Set CANTING_P5_RUN_ID to a new run id (letters/digits/hyphen/underscore).')
from pathlib import Path
import subprocess, json, datetime, sys, os, hashlib, shutil
sys.stdout.reconfigure(encoding='utf-8')
r=Path(__file__).resolve().parents[2]; e=r/'dev-docs/p5-evidence'/run_id
e.mkdir(parents=True,exist_ok=True)
flutter=['C:/flutter/bin/cache/dart-sdk/bin/dart.exe','C:/flutter/bin/cache/flutter_tools.snapshot','--no-version-check']
env=os.environ.copy();env.update(JAVA_HOME='C:/Program Files/Android/Android Studio/jbr',ANDROID_USER_HOME='C:/Users/gxy20/.android',PYTHONIOENCODING='utf-8',GRADLE_OPTS='-Dorg.gradle.workers.max=1 -Dorg.gradle.parallel=false',CANTING_TEST_EVIDENCE_DIR=str(e/'test-output'))
jobs={
 'baseline':flutter+['build','apk','--release','--no-pub','--target','lib/main.dart'],
 'universal':flutter+['build','apk','--release','--no-pub','--target','lib/main.dart'],
 'split':flutter+['build','apk','--release','--no-pub','--target','lib/main.dart','--split-per-abi'],
 'bundle':flutter+['build','appbundle','--release','--no-pub','--target','lib/main.dart'],
 'full':flutter+['test','--no-pub','--concurrency=1','--reporter','expanded'],
 'analyze':flutter+['analyze','--no-pub'],
 'kotlin':[str(r/'android/gradlew.bat'),':app:testDebugUnitTest','--offline','--no-daemon','--max-workers=1','-Dorg.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=1G'],
}
name=sys.argv[1]
build_names=['baseline-offline','universal','split','bundle']
if name in build_names:
 jobs[name]=[str(r/'android/gradlew.bat'), ':app:bundleRelease' if name=='bundle' else ':app:assembleRelease', '--offline','--no-daemon','--max-workers=1','-Dorg.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=1G','-Ptarget=lib/main.dart','-Ptarget-platform=android-arm,android-arm64,android-x64','-Ptree-shake-icons=true']+(['-Psplit-per-abi=true'] if name=='split' else [])
command=jobs[name];cwd=r/'android' if name=='kotlin' or name in build_names else r
label=name
attempt=1
while (e/f'{label}.command.json').exists():
 attempt+=1;label=f'{name}-{attempt}'
if (e/'validation.json').exists():
 raise SystemExit('This evidence run is frozen; choose a new run id.')
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if name in ['baseline',*build_names]:
 files=[p for folder in ['lib','android/app/src/main','assets'] for p in (r/folder).rglob('*') if p.is_file()]+[r/p for p in ['pubspec.yaml','pubspec.lock','android/app/build.gradle.kts','android/settings.gradle.kts','android/gradle.properties']]
 write(e/f'{label}-sources.json',{'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip(),'dirty':subprocess.check_output(['git','status','--porcelain'],cwd=r,text=True),'files':{p.relative_to(r).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}})
start=datetime.datetime.now(datetime.timezone.utc).isoformat()
with (e/f'{label}.txt').open('wb') as log:
 p=subprocess.run(command,cwd=cwd,env=env,stdout=log,stderr=subprocess.STDOUT)
write(e/f'{label}.command.json',{'command':command,'cwd':str(cwd),'started_at':start,'ended_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exit_code':p.returncode,'log':f'{label}.txt'})
if p.returncode==0 and name in ['baseline',*build_names]:
 dest=r/'build/p5-artifacts'/run_id/name;dest.mkdir(parents=True,exist_ok=True)
 sources=list((r/'build/app/outputs/flutter-apk').glob('app-*-release.apk')) if name=='split' else [r/('build/app/outputs/bundle/release/app-release.aab' if name=='bundle' else 'build/app/outputs/flutter-apk/app-release.apk')]
 artifacts=[]
 for src in sources:
  target=dest/src.name;shutil.copy2(src,target);artifacts.append({'path':str(target),'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
 write(e/f'{name}-artifacts.json',artifacts)
print((e/f'{label}.txt').read_text(encoding='utf-8',errors='replace')[-1800:]);print('exit_code',p.returncode)
sys.exit(p.returncode)
