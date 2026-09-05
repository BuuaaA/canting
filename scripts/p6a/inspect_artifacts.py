from pathlib import Path
import os,json,hashlib,zipfile,re,subprocess,datetime,io
from PIL import Image
r=Path(__file__).resolve().parents[2];run=os.environ['CANTING_P6A_RUN_ID'];e=r/'dev-docs/p6a-evidence'/run
assert not (e/'validation.json').exists(), 'Evidence is frozen'
bt=Path('C:/Users/gxy20/AppData/Local/Android/Sdk/build-tools/36.0.0')
env=os.environ.copy();env['JAVA_HOME']='C:/Program Files/Android/Android Studio/jbr'
rows=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def command(label,cmd):
 start=datetime.datetime.now(datetime.timezone.utc).isoformat();p=subprocess.run(list(map(str,cmd)),env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (e/f'{label}.txt').write_bytes(p.stdout)
 (e/f'{label}.command.json').write_text(json.dumps({'command':list(map(str,cmd)),'started_at':start,'ended_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exit_code':p.returncode},indent=2),encoding='utf-8')
 assert p.returncode==0,label
 return p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n')
paths=[r/'canting_v0.1.0-beta.apk',r/'build/p5-artifacts/split/app-arm64-v8a-release.apk',r/'build/p5-artifacts/universal/app-release.apk',r/f'build/p6a-artifacts/{run}/split/app-arm64-v8a-release.apk',r/f'build/p6a-artifacts/{run}/universal/app-release.apk']
for i,p in enumerate(paths):
 label=f'apk-{i}';cert=command(label+'-signature',[bt/'apksigner.bat','verify','--verbose','--print-certs',p]);badging=command(label+'-badging',[bt/'aapt2.exe','dump','badging',p]);manifest=command(label+'-manifest',[bt/'aapt2.exe','dump','xmltree',p,'--file','AndroidManifest.xml'])
 match=re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'",badging)
 row={'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p),'built_file_mtime':datetime.datetime.fromtimestamp(p.stat().st_mtime,datetime.timezone.utc).isoformat(),'application_id':match[1],'version_code':int(match[2]),'version_name':match[3],'certificate_sha256':re.search(r'certificate SHA-256 digest: ([a-f0-9]+)',cert)[1],'debug_signed':'CN=Android Debug' in cert}
 with zipfile.ZipFile(p) as z:
  row['abis']=sorted({n.split('/')[1] for n in z.namelist() if n.startswith('lib/')})
  if i>=3:
   resources=command(label+'-resources',[bt/'aapt2.exe','dump','resources',p])
   for attr,name in [('icon','ic_launcher'),('roundIcon','ic_launcher_round')]:
    resource_id=re.search(r'resource (0x[0-9a-f]+) mipmap/'+name+r'\n',resources)[1]
    assert re.search(r'android:'+attr+r'\([^)]*\)=@'+resource_id,manifest)
   entries=[]
   for name in ['ic_launcher','ic_launcher_foreground','ic_launcher_round']:
    block=re.search(r'mipmap/'+name+r'\n((?:\s+\([^\n]+\n)+)',resources)[1]
    variants=re.findall(r'\(([^)]+)\) \(file\) (\S+)',block)
    assert len(variants)==(5 if name.endswith('foreground') else 6)
    for density,entry in variants:
     entries.append(entry)
     if entry.endswith('.png'):
      source=r/f'android/app/src/main/res/mipmap-{density}/{name}.png'
      actual=Image.open(io.BytesIO(z.read(entry))).convert('RGBA');expected=Image.open(source).convert('RGBA')
      # AAPT may clear RGB under fully transparent pixels; visible RGBA must match.
      assert actual.size==expected.size and all(a==b or a[3]==b[3]==0 for a,b in zip(actual.get_flattened_data(),expected.get_flattened_data())),entry
     else:
      tree=command(label+'-'+name,[bt/'aapt2.exe','dump','xmltree',p,'--file',entry])
      assert 'adaptive-icon' in tree and 'foreground' in tree and 'background' in tree
   row['icon_entries']=entries
   row['icon_pixels_match_source']=True
   row['packaged_icon_hashes']={n:hashlib.sha256(z.read(n)).hexdigest() for n in row['icon_entries'] if n.endswith('.png')}
   assert row['icon_entries'], 'No launcher resources in APK'
   assert 'android.permission.INTERNET' not in badging and 'android.permission.ACCESS_NETWORK_STATE' not in badging
   assert 'roundIcon' in manifest
 rows.append(row)
assert len({x['certificate_sha256'] for x in rows})==1
assert all(x['application_id']=='com.canting.canting' for x in rows)
version=re.search(r'^version: ([^+]+)\+(\d+)', (r/'pubspec.yaml').read_text(encoding='utf-8'), re.M)
assert rows[3]['version_code']==rows[4]['version_code']==int(version[2])
assert rows[3]['version_name']==rows[4]['version_name']==version[1]
assert rows[3]['abis']==['arm64-v8a']
assert rows[4]['abis']==['arm64-v8a','armeabi-v7a','x86_64']
(e/'package-analysis.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
print(json.dumps([{k:x[k] for k in ['path','bytes','version_name','version_code','abis','sha256']} for x in rows],indent=2))
