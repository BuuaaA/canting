from pathlib import Path
import subprocess,sys,os,json,datetime
import hashlib
sys.stdout.reconfigure(encoding="utf-8")
r=Path(__file__).resolve().parents[2]; out=r/'dev-docs/p4-evidence/run-20260905'; out.mkdir(parents=True,exist_ok=True)
env=os.environ.copy(); env['JAVA_HOME']='C:/Program Files/Android/Android Studio/jbr'; env['ANDROID_USER_HOME']='C:/Users/gxy20/.android'
jobs={
 'spec':('flutter test --no-pub test/core/p4_specs_test.dart --reporter expanded',r),
 'semantic':('flutter test --no-pub test/state/p4_semantic_replay_test.dart --reporter expanded',r),
 'related':('flutter test --no-pub test/ui/ocr/in_app_ocr_launcher_test.dart test/state/p4_race_test.dart --reporter expanded',r),
 'build':('flutter build apk --debug --no-pub --target tool/p4_native_smoke.dart',r),
 'install':('adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk',r),
 'launch':('adb -s emulator-5554 shell am start -S -n com.canting.canting/.MainActivity',r),
 'race':('flutter test --no-pub test/state/p4_race_test.dart --reporter expanded',r),
 'kotlin':('gradlew.bat :app:testDebugUnitTest --offline',r/'android'),
 'full':('flutter test --no-pub --reporter expanded',r),
 'analyze':('flutter analyze --no-pub',r),
 'devices':('adb devices -l',r),
 'version':('flutter --version',r),
 'format':('dart format lib/services/ocr_pipeline.dart lib/state/app_state.dart lib/ui/record/record_detail_page.dart lib/main.dart lib/ui/ocr/in_app_ocr_launcher.dart lib/platform/android_native_bridge.dart test/state/p4_race_test.dart',r),
}
name=sys.argv[1]; command,cwd=jobs[name]; label=sys.argv[2] if len(sys.argv)>2 else name
start=datetime.datetime.now(datetime.timezone.utc).isoformat()
if name=='build':
 sources=[*r.glob('lib/**/*.dart'),*r.glob('android/app/src/main/**/*.kt'),r/'tool/p4_native_smoke.dart',r/'pubspec.lock']
 (out/f'{label}-sources.json').write_text(json.dumps({'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip(),'files':{str(p.relative_to(r)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}},indent=2)+'\n')
p=subprocess.run(command,cwd=cwd,env=env,shell=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
(out/f'{label}.log').write_bytes(p.stdout)
entry={'command':command,'cwd':str(cwd),'started_at':start,'ended_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exit_code':p.returncode,'log':f'{label}.log'}
(out/f'{label}.command.json').write_text(json.dumps(entry,indent=2)+'\n')
print(p.stdout.decode('utf-8',errors='replace')[-3500:]); print(json.dumps(entry))
