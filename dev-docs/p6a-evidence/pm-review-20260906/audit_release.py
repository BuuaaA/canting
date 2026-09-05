from pathlib import Path
import hashlib,json,subprocess,re,os,zipfile,io
from PIL import Image
r=Path('D:/dev/canting')
out=Path(__file__).parent/'review-evidence'
out.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
checks={}
for kind in ['split','universal']:
    source=json.loads((r/f'dev-docs/p6a-evidence/beta-20260906/{kind}-sources.json').read_text())['files']
    bad=[p for p,h in source.items() if sha(r/p)!=h]
    checks[kind+'_sources']={'count':len(source),'mismatches':bad}
    assert not bad,bad
env=os.environ.copy();env['JAVA_HOME']='C:/Program Files/Android/Android Studio/jbr'
bt=Path('C:/Users/gxy20/AppData/Local/Android/Sdk/build-tools/36.0.0')
def cmd(label,args):
    p=subprocess.run([str(x) for x in args],env=env,capture_output=True)
    (out/(label+'.txt')).write_bytes(p.stdout+p.stderr)
    assert p.returncode==0,label
    return p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n')
rows=[]
for kind,expected in [('arm64','1fb4a88e9331e45939c6abc46e8a318466688f77f242c00f6fa8ee223fe0e807'),('universal','ed16e84934aabb6b7caef418c9ed3d2995d512aca03c5882aab8318fe3ae9c2f')]:
    p=r/f'build/releases/0.9.0-beta/canting-0.9.0-beta-{kind}.apk'
    digest=sha(p);assert digest==expected
    cert=cmd(kind+'-signature',[bt/'apksigner.bat','verify','--verbose','--print-certs',p])
    assert '336e3f94c188e3a5452475abaf0db1c2bd56a0d1986b5cf36cbdb3cbb6b2bd03' in cert
    badging=cmd(kind+'-badging',[bt/'aapt2.exe','dump','badging',p])
    assert "name='com.canting.canting' versionCode='5003' versionName='0.9.0-beta'" in badging
    assert 'android.permission.INTERNET' not in badging and 'android.permission.ACCESS_NETWORK_STATE' not in badging
    manifest=cmd(kind+'-manifest',[bt/'aapt2.exe','dump','xmltree',p,'--file','AndroidManifest.xml'])
    resources=cmd(kind+'-resources',[bt/'aapt2.exe','dump','resources',p])
    with zipfile.ZipFile(p) as z:
        abis=sorted({n.split('/')[1] for n in z.namelist() if n.startswith('lib/')})
        assert abis==(['arm64-v8a'] if kind=='arm64' else ['arm64-v8a','armeabi-v7a','x86_64'])
        nicons=0
        for name in ['ic_launcher','ic_launcher_foreground','ic_launcher_round']:
            block=re.search(r'mipmap/'+name+r'\n((?:\s+\([^\n]+\n)+)',resources)[1]
            for density,entry in re.findall(r'\(([^)]+)\) \(file\) (\S+)',block):
                if not entry.endswith('.png'):continue
                actual=Image.open(io.BytesIO(z.read(entry))).convert('RGBA')
                source=Image.open(r/f'android/app/src/main/res/mipmap-{density}/{name}.png').convert('RGBA')
                assert actual.size==source.size
                assert all(a==b or a[3]==b[3]==0 for a,b in zip(actual.get_flattened_data(),source.get_flattened_data()))
                nicons+=1
        assert nicons==15
    rows.append({'name':p.name,'bytes':p.stat().st_size,'sha256':digest,'abis':abis,'icon_variants_verified':nicons})
checks['artifacts']=rows
checks['icon_master_matches_supplied']=sha(r/'branding/canting-icon-v1.png')==sha(Path('C:/Users/gxy20/Documents/ChatGPT/代码审核/餐盘_P6-A_执行交接包/assets/canting-icon-v1.png'))
assert checks['icon_master_matches_supplied']
(out/'independent-artifact-audit.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(checks,ensure_ascii=False,indent=2))
