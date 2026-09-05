from pathlib import Path
from PIL import Image, ImageDraw
import hashlib,json,shutil
import os
r=Path(__file__).resolve().parents[2]
run_id=os.environ['CANTING_P6A_RUN_ID']
assert run_id and all(c.isalnum() or c in '-_' for c in run_id)
e=r/'dev-docs/p6a-evidence'/run_id
assert not (e/'validation.json').exists(), 'Evidence is frozen'
e.mkdir(parents=True,exist_ok=True)
dest=r/'branding/canting-icon-v1.png'
im=Image.open(dest).convert('RGBA'); bg=im.getpixel((0,0)); res=r/'android/app/src/main/res'
files=[]
def save(img,p):
 p.parent.mkdir(parents=True,exist_ok=True); img.save(p); files.append(str(p.relative_to(r)))
def legacy(size,rounded=False):
 canvas=im.resize((size,size),Image.Resampling.LANCZOS)
 if rounded:
  mask=Image.new('L',(size,size)); ImageDraw.Draw(mask).ellipse((0,0,size-1,size-1),fill=255);canvas.putalpha(mask)
 return canvas
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
 save(legacy(size),res/f'mipmap-{density}/ic_launcher.png')
 save(legacy(size,True),res/f'mipmap-{density}/ic_launcher_round.png')
 # The original is opaque: retain the entire painting as a padded tile,
 # over a matching solid background, never treat its cream pixels as alpha.
 full=round(size*108/48); tile=round(full*76/108)
 fg=Image.new('RGBA',(full,full));fg.alpha_composite(im.resize((tile,tile),Image.Resampling.LANCZOS),((full-tile)//2,(full-tile)//2))
 save(fg,res/f'mipmap-{density}/ic_launcher_foreground.png')
for name in ['ic_launcher','ic_launcher_round']:
 p=res/f'mipmap-anydpi-v26/{name}.xml';p.parent.mkdir(exist_ok=True)
 p.write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/canting_icon_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''',encoding='utf-8');files.append(str(p.relative_to(r)))
p=res/'values/canting_icon_colors.xml';p.write_text(f'<resources><color name="canting_icon_background">#{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}</color></resources>\n',encoding='utf-8');files.append(str(p.relative_to(r)))
sheet=Image.new('RGB',(720,620),'#dedede');draw=ImageDraw.Draw(sheet)
for col,size in enumerate([48,72,96]):
 draw.text((col*240+15,10),f'{size}px: legacy / circle / rounded',fill='black')
 previews=[legacy(size)]
 for circle in [True,False]:
  full=432; tile=304; base=Image.new('RGBA',(full,full),bg);base.alpha_composite(im.resize((tile,tile),Image.Resampling.LANCZOS),(64,64));base=base.crop((72,72,360,360)).resize((size,size),Image.Resampling.LANCZOS)
  mask=Image.new('L',(size,size));md=ImageDraw.Draw(mask)
  if circle: md.ellipse((0,0,size-1,size-1),fill=255)
  else: md.rounded_rectangle((0,0,size-1,size-1),radius=size*.24,fill=255)
  base.putalpha(mask); previews.append(base)
 for row,preview in enumerate(previews):
  x=col*240+15;y=45+row*185;sheet.paste(preview,(x,y),preview)
  zoom=preview.resize((128,128),Image.Resampling.NEAREST);sheet.paste(zoom,(col*240+100,y+40),zoom)
sheet.save(e/'icon-previews.png')
report={'master':str(dest),'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'size':im.size,'alpha_extrema':im.getchannel('A').getextrema(),'background_pixel':bg,'foreground_tile_dp':76,'adaptive_canvas_dp':108,'subject_bounds_approx_pixels':[257,189,1000,1081],'resources':{p:hashlib.sha256((r/p).read_bytes()).hexdigest() for p in files}}
(e/'icon-resources.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
