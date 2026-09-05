from pathlib import Path
import subprocess,re,json
r=Path('D:/dev/canting')
def git(*args):return subprocess.check_output(['git',*args],cwd=r).decode('utf-8').strip('\0').split('\0')
files=set(git('ls-files','-z'))|set(git('ls-files','--others','--exclude-standard','-z'))
patterns={'private_key':r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----','github_token':r'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}','aws_access':r'AKIA[0-9A-Z]{16}','secret_assignment':r'(?i)(?:password|api_key|apiKey|access_token|client_secret)\s*[:=]\s*[\x22\x27][^\x22\x27\s]{8,}[\x22\x27]'}
hits=[];binary=[];large=[]
for f in sorted(files):
 p=r/f
 if not p.is_file():continue
 if p.suffix.lower() in {'.db','.sqlite','.sqlite3','.jks','.keystore','.p12','.apk','.aab','.env'}:binary.append(f)
 if p.stat().st_size>20_000_000:large.append([f,p.stat().st_size])
 try:s=p.read_text(encoding='utf-8')
 except (UnicodeError,OSError):continue
 for label,pattern in patterns.items():
  for m in re.finditer(pattern,s):hits.append({'file':f,'line':s[:m.start()].count('\n')+1,'rule':label})
result={'files_scanned':len(files),'suspect_paths':binary,'large_files':large,'pattern_hits':hits}
Path('review-evidence/security-scan.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))
