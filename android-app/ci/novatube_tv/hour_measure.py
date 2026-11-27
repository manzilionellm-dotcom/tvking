"""Horloge Android commune aux événements, suivi du processus et contrôles d'écran ponctuels."""
import csv,io,json,statistics,subprocess,sys,time
from pathlib import Path
from PIL import Image
from read_display_capture import decode

serial,pkg,where=sys.argv[1:];out=Path(where);adb=['adb','-s',serial]
def run(args,timeout=15):return subprocess.run(adb+args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout,check=True).stdout
def mark(text):run(['shell','log','-t','NovaDriver',text])
def proc():
 try:
  p=run(['shell','pidof',pkg]).decode().strip();stat=run(['shell','cat',f'/proc/{p}/stat']).decode().split(')',1)[1].split()
  return p+':'+stat[19]
 except (subprocess.SubprocessError,IndexError):return ''
def visual(save):
 raw=run(['exec-out','screencap','-p'],35)
 if save:(out/f'capture-{save}.png').write_bytes(raw)
 im=Image.open(io.BytesIO(raw)).convert('L');w,h=im.size
 for top,bot in ((0,0),(0,24),(0,48),(24,0),(24,24),(48,0),(48,48)):
  vh=min(h-top-bot,w*9/16);vw=vh*16/9;x=(w-vw)/2;y=top+(h-top-bot-vh)/2
  b=[im.getpixel((round(x+vw*(496+32*i)/1920),round(y+vh*650/1080))) for i in range(30)]
  ch,n=decode(b)
  if ch:return ch,n
 return None,None

pid=proc();assert pid
(out/'fixed-process.txt').write_text(pid)
with (out/'zaps-dispatch.csv').open('w') as file:
 w=csv.writer(file);w.writerow(['trial','host_monotonic_s','process','command_ok'])
 for i in range(1,101):
  at=time.monotonic()
  try:run(['shell',f'log -t NovaDriver ZAP_{i}; input keyevent KEYCODE_CHANNEL_DOWN']);ok=True
  except subprocess.SubprocessError:ok=False
  w.writerow([i,at,proc(),ok]);file.flush();time.sleep(4)
time.sleep(8)
mark('HOUR_START');start=time.monotonic()
with (out/'heure.csv').open('w') as f:
 w=csv.writer(f);w.writerow(['minute','elapsed_s','process','channel','counter','error'])
 for minute in range(61):
  time.sleep(max(0,start+minute*60-time.monotonic()))
  if minute==60:mark('HOUR_END')
  elapsed=time.monotonic()-start;p=proc();ch=n=None;err=''
  try:ch,n=visual(str(minute) if minute in (0,15,30,45,60) else None)
  except Exception as e:err=type(e).__name__
  w.writerow([minute,round(elapsed,3),p,ch,n,err]);f.flush()
  if minute%5==0 or p!=pid:print('minute',minute,'process stable',p==pid,'channel',ch,flush=True)
