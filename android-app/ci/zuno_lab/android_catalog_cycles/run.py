"""AVD de test vierge, SQLite natif et vraie vue Direct; sans compte ni flux privé."""
import csv
from datetime import datetime, timezone
import hashlib
import json
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import re
import subprocess
import sys
import threading
import time
from urllib.parse import urlsplit, parse_qs

out, apk, movie = map(Path,sys.argv[1:])
pkg = 'com.sevenmotion.tv.seven_tv.lab.catalog'
out.mkdir(exist_ok=True, parents=True)
categories = [{'category_id':str(i),'category_name':f'CAT {i:03d}'} for i in range(1,121)]
channels = [{'stream_id':i,'num':i,'name':f'LAB {i:05d}','stream_type':'live',
             'category_id':str((i-1)//250+1),'epg_channel_id':f'lab{i}',
             'stream_icon':'','tv_archive':0} for i in range(1,30001)]
def enc(x): return json.dumps(x,separators=(',',':')).encode()
all_channels = enc(channels)
auth = enc({'user_info':{'auth':1,'status':'Active'},'server_info':{'server_protocol':'http','url':'127.0.0.1','port':'18479'}})
xml = ('<?xml version="1.0"?><tv>'+''.join(f'<channel id="lab{i}"><display-name>LAB {i:05d}</display-name></channel>' for i in range(1,30001))+'</tv>').encode()
media = movie.read_bytes()
counters = {}
lock = threading.Lock()
class Source(BaseHTTPRequestHandler):
    def log_message(self,*args):
        pass
    def do_GET(self):
        u = urlsplit(self.path)
        q = parse_qs(u.query)
        action = q.get('action',['auth'])[0]
        key = action if u.path.endswith('player_api.php') else 'xmltv' if u.path.endswith('xmltv.php') else 'mpegts'
        with lock: counters[key]=counters.get(key,0)+1
        if key == 'mpegts':
            self.send_response(200)
            self.send_header('Content-Type','video/mp2t')
            self.end_headers()
            try:
                while True:
                    for i in range(0,len(media),188*28):
                        chunk=media[i:i+188*28]
                        self.wfile.write(chunk)
                        self.wfile.flush()
                        time.sleep(4 * len(chunk) / len(media))
            except (BrokenPipeError, ConnectionResetError):
                return
        elif key == 'get_live_categories': b=enc(categories)
        elif key == 'get_live_streams':
            cat = q.get('category_id',[''])[0]
            b = all_channels if not cat else enc([x for x in channels if x['category_id']==cat])
        elif key == 'auth': b=auth
        elif key == 'xmltv': b=xml
        else: b=b'[]'
        self.send_response(200)
        self.send_header('Content-Type', 'application/xml' if key=='xmltv' else 'application/json')
        self.send_header('Content-Length',str(len(b)))
        self.end_headers()
        try: self.wfile.write(b)
        except (BrokenPipeError,ConnectionResetError): pass
def adb(*args, check=True):
    return subprocess.run(['adb',*args],capture_output=True,text=True,check=check,timeout=60).stdout.strip()
def launch():
    activity=adb('shell','cmd','package','resolve-activity','--brief','-a','android.intent.action.MAIN','-c','android.intent.category.LEANBACK_LAUNCHER',pkg).splitlines()[-1]
    if '/' not in activity: raise RuntimeError('activité TV introuvable')
    adb('shell','am','start','-W','-n',activity)
def identity(name):
    paths=adb('shell','pm','path',pkg).replace('package:','').splitlines()
    (out/f'installed-{name}.sha256').write_text('\n'.join(adb('shell','sha256sum',p) for p in paths)+'\n')
    if len(paths)!=1 or adb('shell','sha256sum',paths[0]).split()[0] != hashlib.sha256(apk.read_bytes()).hexdigest(): raise RuntimeError('empreinte installée')
def sampleresources():
    with (out/'process.csv').open('w',buffering=1) as f:
        writer=csv.writer(f);writer.writerow(['utc','host_monotonic','pid','pss_kb','rss_kb','cpu_ps_pct'])
        while True:
            pid=adb('shell','pidof',pkg,check=False)
            if pid:
                dump=adb('shell','dumpsys','meminfo',pid,check=False)
                vals=[re.search(p,dump) for p in [r'TOTAL PSS:\s*(\d+)',r'TOTAL RSS:\s*(\d+)']]
                cpu=adb('shell','ps','-o','%CPU','-p',pid,check=False).splitlines()
                writer.writerow([datetime.now(timezone.utc).isoformat(),time.monotonic(),pid,*[m[1] if m else '' for m in vals],cpu[-1] if len(cpu)>1 else ''])
            time.sleep(2)
events=[]
def loglistener():
    process=subprocess.Popen(['adb','logcat','-v','raw','flutter:I','*:S'],stdout=subprocess.PIPE,text=True,errors='replace')
    with (out/'events.jsonl').open('w',buffering=1) as f:
        for line in process.stdout:
            if 'ZUNO_CAT ' not in line: continue
            raw=line.split('ZUNO_CAT ',1)[1].strip()
            try: row=json.loads(raw)
            except ValueError:continue
            row.update(utc=datetime.now(timezone.utc).isoformat(),host_monotonic=time.monotonic())
            f.write(json.dumps(row)+'\n');events.append(row)
def wait(kind,start,seconds):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        for r in events[start:]:
            if r['event']=='failed': raise RuntimeError('échec diagnostic, consulter events.jsonl')
            if r['event']==kind:return r
        time.sleep(.25)
    raise TimeoutError(kind)
server=ThreadingHTTPServer(('127.0.0.1',18479),Source)
threading.Thread(target=server.serve_forever,daemon=True).start()
state={'required_cycles':30,'required_rest_s':900,'samples':[],'cycles':[],
       'fixture_rows':30000,'fixture_categories':120,
       'dart_heap_bytes':None,'retained_objects':None,
       'heap_limitation':'Release sans VM Service; Dalvik reflète les objets Android, pas le tas Dart.'}
def sample(kind,number):
    pid=adb('shell','pidof',pkg,check=False)
    if not pid or ('pid' in state and pid!=state['pid']):
        raise RuntimeError('processus remplacé ou absent')
    state['pid']=pid
    mem=adb('shell','dumpsys','meminfo',pid)
    proc=adb('shell','cat',f'/proc/{pid}/status',check=False)
    def match(pattern,buf):
        term=re.search(pattern,buf)
        return int(term[1]) if term else None
    # Ne pas enregistrer les noms de sockets, de descripteurs ou de clients.
    fd=adb('shell',f'ls -1 /proc/{pid}/fd 2>/dev/null | wc -l',check=False)
    native_line=next((line.strip().split() for line in mem.splitlines()
                      if line.lstrip().startswith('Native Heap ') and ':' not in line),[])
    codec=adb('shell','dumpsys','media.resource_manager',check=False)
    codec_mentions=sum(bool(re.search(rf'\b{pid}\b',line)) for line in codec.splitlines()) if 'Permission Denial' not in codec and codec else None
    row={'phase':kind,'n':number,'utc':datetime.now(timezone.utc).isoformat(),
         't_monotonic':time.monotonic(),'pid':pid,
         'pss_kb':match(r'TOTAL PSS:\s*(\d+)',mem),'rss_kb':match(r'TOTAL RSS:\s*(\d+)',mem),
         'native_heap_alloc_kb':int(native_line[-2]) if len(native_line)>5 and native_line[-2].isdigit() else None,
         'threads':match(r'Threads:\s*(\d+)',proc),
         'fd':int(fd) if fd.isdigit() and int(fd)>0 else None,
         'media_resource_manager_pid_mentions':codec_mentions}
    state['samples'].append(row)
    with (out/'checkpoints.jsonl').open('a') as f: f.write(json.dumps(row)+'\n')
def nav():
    return next((r for r in reversed(events) if r.get('event')=='sample' and r.get('phase')=='navigation'),{})
def button(key):
    adb('shell','input','keyevent',str(key))
def until(field,n,seconds):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        row=nav()
        if row.get(field,0)>=n: return row
        time.sleep(.2)
    return None
try:
    # AVD jetable. Si adbd refuse root, l'APK reste un APK release normal;
    # les métriques /proc alors inaccessibles sont nulles.
    adb('root',check=False)
    subprocess.run(['adb','wait-for-device'],check=True,timeout=40)
    adb('reverse','tcp:18479','tcp:18479')
    adb('install','-r','-g',str(apk))
    identity('before')
    info=adb('shell','cat','/proc/meminfo')
    state['actual_memtotal_kib']=int(re.search(r'MemTotal:\s*(\d+)',info)[1])
    adb('logcat','-c')
    threading.Thread(target=loglistener,daemon=True).start()
    threading.Thread(target=sampleresources,daemon=True).start()
    launch()
    state['import']=wait('imported',0,275)
    deadline=time.monotonic()+30
    while not nav() and time.monotonic()<deadline: time.sleep(.25)
    if not nav(): raise RuntimeError('Direct non identifié')
    sample('avant',0)
    for i in range(1,31):
        previous=nav()
        base_open,base_close=previous.get('opens',0),previous.get('closes',0)
        if base_open!=base_close: raise RuntimeError('lecteur encore ouvert avant le cycle')
        t0=time.monotonic()
        # Le premier focus peut être sur une catégorie. La flèche de droite
        # entre dans la grille et les lignes suivantes sont des chaînes test.
        opened=None
        for attempt in range(3):
            if i==1 or attempt:
                button(22); time.sleep(.45)
            button(20 if i%2 else 19); time.sleep(.6);button(23)
            opened=until('opens',base_open+1,8)
            if opened:break
        if not opened or opened['opens']!=base_open+1: raise RuntimeError(f'ouverture non confirmée, cycle {i}')
        t1=time.monotonic()
        time.sleep(2)
        button(4)
        closed=until('closes',base_close+1,10)
        if not closed or closed['closes']!=base_close+1 or closed['opens']!=base_open+1:
            raise RuntimeError(f'fermeture non confirmée, cycle {i}')
        t2=time.monotonic()
        state['cycles'].append({'cycle':i,'opens':closed['opens'],'closes':closed['closes'],
                                'unique_preview_focus':closed['unique_selected'],
                                'enter_seen_s':round(t1-t0,3),'exit_seen_s':round(t2-t1,3)})
        sample('fermeture',i)
    start=time.monotonic()
    while time.monotonic()-start<900:
        time.sleep(min(30,max(0,900-(time.monotonic()-start))))
        sample('repos',int(time.monotonic()-start))
    state['rest_s']=time.monotonic()-start
    identity('after')
    assert state['cycles'][-1]['opens']==30 and state['cycles'][-1]['closes']==30
finally:
    state['fixture_requests']=counters.copy()
    (out/'summary.json').write_text(json.dumps(state,indent=2))
