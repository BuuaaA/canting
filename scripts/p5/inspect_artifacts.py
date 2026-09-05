import os
run_id=os.environ.get('CANTING_P5_RUN_ID', '')
if not run_id or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_' for c in run_id):
 raise SystemExit('Set CANTING_P5_RUN_ID to a new run id (letters/digits/hyphen/underscore).')
from pathlib import Path
import json,subprocess,os,hashlib,zipfile,collections,re
r=Path(__file__).resolve().parents[2];e=r/'dev-docs/p5-evidence'/run_id;e.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();env.update(JAVA_HOME='C:/Program Files/Android/Android Studio/jbr',ANDROID_USER_HOME='C:/Users/gxy20/.android')
sdk=Path('C:/Users/gxy20/AppData/Local/Android/Sdk');bt=sdk/'build-tools/36.0.0'
if (e/'validation.json').exists():
 raise SystemExit('This evidence run is frozen; choose a new run id.')
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def run(label,cmd):
 p=subprocess.run([str(c) for c in cmd],cwd=r,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (e/f'{label}.txt').write_bytes(p.stdout)
 write(e/f'{label}.command.json',{'command':[str(c) for c in cmd],'exit_code':p.returncode,'log':f'{label}.txt'})
 return p.stdout.decode('utf-8',errors='replace')
def category(n):
 if n.startswith('BUNDLE-METADATA/') and ('debugsymbols/' in n or n.endswith('.map')):return 'Debug symbols and mapping'
 if n.endswith('/libapp.so'):return 'Dart AOT'
 if n.endswith('/libflutter.so'):return 'Flutter engine'
 if n.startswith(('lib/','base/lib/')):
  return 'OCR native libraries' if 'ocr' in n.lower() or 'mlkit' in n.lower() else 'Other native libraries'
 if 'ocr' in n.lower() or 'mlkit' in n.lower() or 'tflite' in n.lower():return 'OCR models/resources'
 if n.endswith(('.ttf','.otf')):return 'Fonts'
 if 'flutter_assets' in n:return 'Flutter assets/data'
 if n.endswith('.dex'):return 'DEX'
 return 'Android resources/metadata'
allrows=[]
for path in [r/'canting_v0.1.0-beta.apk',*sorted((r/'build/p5-artifacts'/run_id).rglob('*.apk')),*sorted((r/'build/p5-artifacts'/run_id).rglob('*.aab'))]:
 label='old-beta' if path.parent==r else path.parent.name+'-'+path.stem
 row={'path':str(path),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
 with zipfile.ZipFile(path) as z:
  entries=[{'path':i.filename,'compressed_bytes':i.compress_size,'uncompressed_bytes':i.file_size,'category':category(i.filename)} for i in z.infolist() if not i.is_dir()]
  totals={};abi={};duplicates=collections.defaultdict(list)
  for item in entries:
   c=item['category'];totals.setdefault(c,{'compressed_bytes':0,'uncompressed_bytes':0})
   for field in ['compressed_bytes','uncompressed_bytes']:totals[c][field]+=item[field]
   if '/lib/' in '/'+item['path']:
    parts=item['path'].split('/');arch=parts[parts.index('lib')+1];abi[arch]=abi.get(arch,0)+item['uncompressed_bytes']
   if item['uncompressed_bytes']>1024:duplicates[hashlib.sha256(z.read(item['path'])).hexdigest()].append(item['path'])
  row.update(top20_by_uncompressed=sorted(entries,key=lambda x:x['uncompressed_bytes'],reverse=True)[:20],top20_by_compressed=sorted(entries,key=lambda x:x['compressed_bytes'],reverse=True)[:20],categories=totals,native_uncompressed_by_abi=abi,duplicate_entries=[v for v in duplicates.values() if len(v)>1])
 if path.suffix=='.apk':
  cert=run(label+'-signature',[bt/'apksigner.bat','verify','--verbose','--print-certs',path]);row['signature_log']=label+'-signature.txt';row['debug_signed']='CN=Android Debug' in cert
  digest=re.search(r'certificate SHA-256 digest: ([a-f0-9]+)',cert)
  row['certificate_sha256']=digest.group(1) if digest else None
  badging=run(label+'-badging',[bt/'aapt2.exe','dump','badging',path])
  identity=re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'",badging)
  row['package_identity']=dict(zip(['application_id','version_code','version_name'],identity.groups())) if identity else None
  row['network_permission_present']=any(x in badging for x in ['android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE'])
  run(label+'-manifest',[bt/'aapt2.exe','dump','xmltree',path,'--file','AndroidManifest.xml'])
 else:
  run(label+'-signature',['C:/Program Files/Android/Android Studio/jbr/bin/jarsigner.exe','-verify','-verbose','-certs',path])
 allrows.append(row)
write(e/'artifact-analysis.json',allrows)
run('devices',[sdk/'platform-tools/adb.exe','devices','-l'])
run('flutter-version',['C:/flutter/bin/cache/dart-sdk/bin/dart.exe','C:/flutter/bin/cache/flutter_tools.snapshot','--no-version-check','--version','--machine'])
run('java-version',['C:/Program Files/Android/Android Studio/jbr/bin/java.exe','-version'])
print(json.dumps([{'path':x['path'],'bytes':x['bytes']} for x in allrows],indent=2))
