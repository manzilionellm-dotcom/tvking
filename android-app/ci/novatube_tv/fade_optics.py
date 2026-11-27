"""Mesurer la première observation de la mire plein écran après un OK unique."""
import csv,io,json,re,subprocess,sys,tempfile,threading,time
from pathlib import Path
from PIL import Image
from read_display_capture import decode

serial,pkg,where,action=sys.argv[1:]
out=Path(where);out.mkdir(parents=True,exist_ok=True);adb=['adb','-s',serial]
def run(args,timeout=15):
 return subprocess.run(adb+args,capture_output=True,check=True,timeout=timeout).stdout
def source(im):
 im=im.convert('L');w,h=im.size
 for top,bottom in ((0,0),(0,24),(0,48),(24,0),(24,24),(48,0),(48,48)):
  hh=min(h-top-bottom,w*9/16);ww=hh*16/9;x=(w-ww)/2;y=top+(h-top-bottom-hh)/2
  ch,n=decode([im.getpixel((round(x+ww*(496+32*i)/1920),round(y+hh*650/1080))) for i in range(30)])
  if ch:return ch,n
 return '',None
def capture(method,folder):
 start=time.monotonic()
 try:
  if method=='console':
   for f in folder.glob('*.png'):f.unlink()
   run(['emu','screenrecord','screenshot',str(folder)],4)
   path=next(folder.glob('*.png'));raw=path.read_bytes()
  else:
   raw=run(['exec-out','screencap','-p'],4)
  end=time.monotonic()
  with Image.open(io.BytesIO(raw)) as im:ch,n=source(im)
  return {'ok':True,'start':start,'end':end,'ch':ch,'counter':n},raw
 except Exception as e:return {'ok':False,'start':start,'end':time.monotonic(),'error':type(e).__name__},None
with tempfile.TemporaryDirectory() as tmp:
 folder=Path(tmp)
 if action=='calibrate':
  winner=None
  for method in ('console','guest'):
   for i in range(13):
    row,blob=capture(method,folder)
    if row.get('ch')=='A':
     winner=method;(out/'plein-calibration.png').write_bytes(blob);break
    if not row['ok']:break
    time.sleep(.4)
   if winner:break
  assert winner,'Aucune mire lisible en plein écran'
  (out/'methode.txt').write_text(winner);print(winner);sys.exit(0)
 method=(out.parent/'methode.txt').read_text()
 before,blob=capture(method,folder);assert before['ok'] and not before.get('ch'),('La mire est déjà en plein écran',before)
 (out/'apercu.png').write_bytes(blob)
 run(['logcat','-c'])
 command={}
 def press():
  command['host_before']=time.monotonic()
  try:
   command['bracket']=run(['shell','read a rest < /proc/uptime; input keyevent KEYCODE_DPAD_CENTER; rc=$?; read b rest < /proc/uptime; echo "$a $b $rc"']).decode().strip()
  except (OSError,subprocess.SubprocessError) as e:command['error']=type(e).__name__
  command['host_after']=time.monotonic()
 worker=threading.Thread(target=press);worker.start();rows=[before];first=None;moving=None;deadline=time.monotonic()+18
 while time.monotonic()<deadline:
  row,blob=capture(method,folder);rows.append(row)
  if row.get('ch')=='A':
   if first is None:first=row;(out/'premiere-mire.png').write_bytes(blob)
   elif row['counter']!=first['counter']:
    moving=row;(out/'mouvement.png').write_bytes(blob);break
  time.sleep(.025)
 worker.join();pid=run(['shell','pidof',pkg]).decode().strip()
 from decimal import Decimal
 earliest=int(Decimal(command['bracket'].split()[0])*1000)
 actions=[]
 for i in range(28):
  logs=run(['logcat','-d','--pid='+pid,'-v','monotonic','-s','NovaTubeQA:I','flutter:I']).decode('utf8','replace')
  actions=[fields for fields in re.findall(r'action=preview_to_full outcome=first_frame elapsed_ms=(\d+) view=(\d+) epoch=(\d+) render_ms=(\d+)',logs) if int(fields[3])>=earliest]
  if actions:break
  time.sleep(.25)
 (out/'traces.txt').write_text(logs)
 result={'method':method,'input':command,'snapshots':rows,'moving':bool(moving),'native_correlation':False}
 if len(actions)==1:
  duration,v,e,t=map(int,actions[0]);core=rf'view={v} epoch={e} phase='
  frame=re.findall(core+r'first_render open_ms=(\d+) codec_to_render_ms=(\d+) dispatch_ms=(\d+)',logs)
  if len(frame)==1:
   result.update(native_correlation=True,listener_ms=duration,view=v,epoch=e,renderer_elapsed_ms=t,native_open_ms=int(frame[0][0]),dispatch_ms=int(frame[0][2]))
 if first and moving and 'host_after' in command:
  lows=[r['start'] for r in rows if r['ok'] and not r.get('ch') and r['start']<first['start']]
  lower=max(0,1000*(max(lows)-command['host_after']));upper=1000*(first['end']-command['host_before'])
  result.update(visual_lower_ms=round(lower),visual_upper_ms=round(upper),captured_first_frame=first['counter'],captured_later_frame=moving['counter'])
 (out/'mesure.json').write_text(json.dumps(result,indent=2));print({k:v for k,v in result.items() if k!='snapshots'})
