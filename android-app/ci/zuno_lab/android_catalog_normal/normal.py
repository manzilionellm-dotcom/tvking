"""Même import Xtream sur APK signé livrable, sans code de mesure dans l'application."""
import csv,hashlib,json,os,re,socket,sys,threading,time
from datetime import datetime,timezone
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlsplit,parse_qs
sys.path.insert(0,str(Path('android-app/ci/zuno_lab').resolve()))
from panel_device import observe as panel
from optical_witness import screen,words
from android_ui import visible_nodes
from zuno_ui_path import normalized,control
out=Path(sys.argv[1]);movie=Path('android-app/ci/zuno_lab/android_catalog_fixture/mire.ts').read_bytes()
pkg='com.sevenmotion.tv.seven_tv.lab'
srcs={}
req=lambda row:json.dumps(row,separators=(',',':')).encode()
cats=[{'category_id':str(i),'category_name':f'CAT {i:03d}'} for i in range(1,121)]
chs=[{'stream_id':i,'num':i,'name':'Mire A' if i==1 else 'Mire B' if i==2 else f'LAB {i:05d}','stream_type':'live','category_id':str((i-1)//250+1),'epg_channel_id':f'lab{i}'} for i in range(1,30001)]
all_streams=req(chs);groups=req(cats)
def note(event,**data):
 with (out/'parcours.jsonl').open('a') as f:f.write(json.dumps({'utc':datetime.now(timezone.utc).isoformat(),'monotonic':time.monotonic(),'event':event,**data})+'\n')
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_GET(self):
  p=urlsplit(self.path);q=parse_qs(p.query)
  if p.path.endswith('player_api.php'):
   act=q.get('action',['auth'])[0];cat=q.get('category_id',[''])[0]
   if act=='get_live_streams': buf=all_streams if not cat else req([x for x in chs if x['category_id']==cat])
   elif act=='get_live_categories':buf=groups
   elif act=='auth':buf=req({'user_info':{'auth':1,'status':'Active'},'server_info':{'url':'127.0.0.1','port':'18479','server_protocol':'http'}})
   else:buf=b'[]'
   ct='application/json'
  elif p.path.endswith('xmltv.php'):act='guide';buf=b'<tv/>';ct='application/xml'
  else:
   m=re.search(r'/([0-9]+)(?:\.ts)?$',p.path);act='media.'+(m[1] if m else 'unknown')
   srcs[act]=srcs.get(act,0)+1;note('media_requested',stream=act)
   self.send_response(200);self.send_header('Content-Type','video/mp2t');self.end_headers()
   try:
    while True:
     for i in range(0,len(movie),5264):
      v=movie[i:i+5264];self.wfile.write(v);self.wfile.flush();time.sleep(4*len(v)/len(movie))
   except OSError:return
  srcs[act]=srcs.get(act,0)+1
  self.send_response(200);self.send_header('Content-Type',ct);self.send_header('Content-Length',str(len(buf)));self.end_headers()
  try:self.wfile.write(buf)
  except OSError:pass
fixture=ThreadingHTTPServer(('127.0.0.1',18479),Handler);threading.Thread(target=fixture.serve_forever,daemon=True).start()
adb=panel.adb;api=panel.api
def labelshot():
 focus=[];ns=visible_nodes(pkg,focused=focus);im=screen()
 ts=words(im);labels={normalized(x[0]) for x in ns+ts}
 # N'écrire que ces mots génériques ou identifiants de fixture synthétiques.
 display=sorted(x for x in labels if x in {'live','direct','movies','films','server','serveur','settings','reglages','mire a','mire b','favorites','favoris'} or re.fullmatch(r'(cat|lab) \d+',x))
 for phrase in ('mire a','mire b','live','direct','cat 001','lab 00003'):
  if phrase not in display and control(ns,ts,im.size,(phrase,)) is not None:display.append(phrase)
 focused=sorted({normalized(x) for x in focus if normalized(x) in display})
 note('screen',known=display,focus=focused,sha256_rgb=hashlib.sha256(im.tobytes()).hexdigest(),size=im.size)
 return display,focused
def key(n):
 at=time.monotonic();adb('shell','input','keyevent',str(n));note('remote_key',code=n,adb_s=time.monotonic()-at)
def pid():return adb('shell','pidof',pkg,check=False).strip()
def exitinfo():
 s=adb('shell','dumpsys','activity','exit-info',pkg,check=False)
 return re.findall(r'(?:timestamp=[0-9T :.\-]+|\bpid=\d+|\breason=\d+ \([^)]*\)|\bsubreason=\d+ \([^)]*\)|\bprocess=com\.sevenmotion\.tv\.seven_tv\.lab)',s)
panel.token=api('POST','/api/v1/auth/login',{'email':'admin','password':os.environ['ZUNO_QA_PASS']})['token']
note('before',exit=exitinfo())
adb('shell','am','start','-n',pkg+'/com.example.tv_king.MainActivity')
start=time.monotonic()
while time.monotonic()-start<115:
 devices=api('GET','/api/v1/boxes/live')['items']
 if devices:break
 time.sleep(1)
if len(devices)!=1:raise RuntimeError('identité de la TV locale non vérifiée')
mac=devices[0]['mac'];api('POST','/api/v1/activate',{'mac':mac,'plan':'lifetime'})
begin=time.monotonic();prior=(devices[0].get('last_applied') or {}).get('id',0)
api('PUT','/api/v1/sources/'+mac,{'sources':[{'type':'xtream','server_url':'http://127.0.0.1:18479','username':'demo','password':'demo','label':'LAB 30000'}]})
note('submitted_xtream')
try:
 ack=False
 while time.monotonic()-begin<120:
  item=api('GET','/api/v1/boxes/live')['items'][0];applied=item.get('last_applied') or {}
  if applied.get('id',0)>prior and srcs.get('get_live_streams'):
   ack=True;note('ack',elapsed_s=time.monotonic()-begin);break
  time.sleep(.5)
 if not ack:raise RuntimeError('révision non acquittée avec lecture Xtream')
 counts=panel.read_sqlite();note('sqlite',counts=counts)
 if counts.get('available') and (counts.get('rows')!=30000 or counts.get('categories')!=120):raise RuntimeError('lignes non conformes après ACK')
 origin_pid=pid();note('before_keys',pid=origin_pid)
 labels,focused=labelshot()
 if not any(x in labels for x in ('mire a','mire b')) and not any(x.startswith('cat ') for x in labels):
  if not any(x in labels for x in ('live','direct')):raise RuntimeError('accueil Direct non reconnu')
  # Rangée horizontale du hub. La butée gauche correspond à Direct.
  for _ in range(6):key(21);time.sleep(.14)
  key(23);time.sleep(1)
 labels,focused=labelshot()
 if not any(x in labels for x in ('mire a','mire b')) and not any(x.startswith(('cat ','lab ')) for x in labels):
  raise RuntimeError('Direct non reconnu')
 for n in [22,20,23,166,167,4]*4:
  key(n);time.sleep(.8)
  if not pid() or pid()!=origin_pid:raise RuntimeError('processus disparu ou remplacé')
 note('after_inputs',keys=24,live_process=pid());labelshot()
finally:
 note('end',exit=exitinfo(),last_pid=pid(),requests=srcs)
