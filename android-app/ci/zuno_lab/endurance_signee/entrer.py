"""Entrer sur A dans le candidat normal exclusivement par son panel et son écran."""
import hashlib,json,os,sys,time
from pathlib import Path
from panel_device import observe as panel
from optical_witness import key, tap, screen, read_marker, words
from android_ui import visible_nodes
from zuno_ui_path import next_step
from visible_launch import screen_evidence

out=Path(sys.argv[1]);out.mkdir(exist_ok=True)
pkg=os.environ['BENCH_PACKAGE']
def note(event,**info):
 with (out/'entree.jsonl').open('a') as f:print(json.dumps(dict(monotonic=time.monotonic(),event=event,**info)),file=f)
def press(name):key('KEYCODE_'+name);note('dpad',code=name)
def monitor(s):
 end=time.monotonic()+s;previous={};rows=[]
 while time.monotonic()<end:
  try:
   frame=screen();ch,n,box=read_marker(frame)
  except Exception as e:
   note('capture-error',type=type(e).__name__);time.sleep(.5);continue
  if ch in ('A','B'):
   rows.append([ch,n,time.monotonic()])
   if ch in previous and 0<(n-previous[ch])%(1<<20)<(1<<19):
    frame.crop(box).save(out/f'initial-{ch}.png');note('moving-full-frame',values=rows[-4:]);return ch
   previous[ch]=n
  else:previous.clear()
  time.sleep(.2)
 return None
panel.token=panel.api('POST','/api/v1/auth/login',{'email':'admin','password':os.environ['ZUNO_QA_PASS']})['token']
panel.adb('shell','am','start','-n',pkg+'/com.example.tv_king.MainActivity')
deadline=time.monotonic()+125
while time.monotonic()<deadline:
 devices=panel.api('GET','/api/v1/boxes/live')['items']
 if devices:break
 time.sleep(.5)
if len(devices)!=1:raise RuntimeError('Box LAB unique absente')
mac=devices[0]['mac']
panel.api('POST','/api/v1/activate',{'mac':mac,'plan':'lifetime'})
panel.api('PUT','/api/v1/sources/'+mac,{'sources':[{'type':'m3u','m3u_url':'http://127.0.0.1:18471/channels.m3u','label':'LAB ENDURANCE'}]})
deadline=time.monotonic()+125
while time.monotonic()<deadline:
 status=panel.api('GET','/api/v1/boxes/live')['items'][0].get('last_applied') or {}
 if status.get('kind')=='source':
  note('source-ack',order=status['id'],channels=['Mire A','Mire B']);break
 time.sleep(.5)
else:raise RuntimeError('Accusé précisément typé source absent')
deadline=time.monotonic()+235;hub_time=None;row_attempt=0;step=0;grid_seen=False
while time.monotonic()<deadline:
 seen=monitor(2)
 if seen=='A':break
 if seen=='B':press('CHANNEL_UP');time.sleep(2);continue
 step+=1
 focus=[]
 try:
  ns=visible_nodes(pkg,focused=focus);im=screen();ws=words(im);action,point=next_step(ns,ws,im.size,'after-submit',False,False)
 except Exception as e:
  note('setup-capture-error',type=type(e).__name__);time.sleep(1);continue
 fg=panel.adb('shell','dumpsys','activity','activities',check=False)
 app=any(pkg+'/' in l for l in fg.splitlines() if 'topResumedActivity' in l or 'mResumedActivity' in l)
 note('scene',screen_hash=hashlib.sha256(im.tobytes()).hexdigest(),action=action,foreground=app)
 if not app:
  panel.adb('shell','am','start','-n',pkg+'/com.example.tv_king.MainActivity');time.sleep(2);continue
 if step==1 or step%6==0:screen_evidence(out,'scene-'+str(step))
 if action=='channel-a':
  grid_seen=True;row_attempt+=1
  if row_attempt==1:
   press('DPAD_RIGHT');time.sleep(.4);press('DPAD_UP');time.sleep(.4);press('DPAD_CENTER')
  elif point:
   tap(*point);note('row-A-pointer-fallback')
  seen=monitor(10)
  if seen=='A':break
  if seen=='B':press('CHANNEL_UP')
 elif action in ('english','notifications') and point:tap(*point)
 elif action=='live':
  if hub_time is None:
   for _ in range(5):press('DPAD_LEFT');time.sleep(.16)
   press('DPAD_CENTER');hub_time=time.monotonic()
  elif time.monotonic()-hub_time>10 and point:tap(*point);note('live-pointer-fallback');hub_time=time.monotonic()
 elif action in ('return-to-hub','return-from-settings') and step<=3:press('BACK')
 elif grid_seen and step%3==0:
  # Un premier OK peut simplement ouvrir la vue native en pause.
  press('DPAD_CENTER')
 elif step in (3,6):press('DPAD_DOWN')
 time.sleep(.8)
else:raise RuntimeError('Deux compteurs A consécutifs en plein écran manquants')
note('started-normal-player',package=pkg)
