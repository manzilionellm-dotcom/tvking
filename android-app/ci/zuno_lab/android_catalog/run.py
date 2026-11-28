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
state={'fixture_rows':30000,'fixture_categories':120,'guide_programmes':0,'navigation_seconds_planned':1800,'sample_period_ms':100}
try:
    adb('reverse','tcp:18479','tcp:18479')
    adb('install','-r','-g',str(apk))
    identity('before')
    info=adb('shell','cat','/proc/meminfo')
    (out/'android-meminfo.txt').write_text(info)
    state['actual_memtotal_kib']=int(re.search(r'MemTotal:\s*(\d+)',info)[1])
    adb('logcat','-c')
    threading.Thread(target=loglistener,daemon=True).start()
    threading.Thread(target=sampleresources,daemon=True).start()
    launch()
    imp=wait('imported',0,275)
    state['import']=imp
    adb('shell','dumpsys','gfxinfo',pkg,'reset')
    pid_initial=adb('shell','pidof',pkg)
    start=time.monotonic()
    i=0
    pattern=[22]+[20]*10+[23]+[166,167,20,19]*2+[4,22]+[20]*6+[21,20,22]+[19]*3
    with (out/'commands.csv').open('w',buffering=1) as f:
        w=csv.writer(f);w.writerow(['utc','seconds','keycode','send_ms'])
        while time.monotonic()-start<1800:
            at=time.monotonic(); key=pattern[i%len(pattern)]
            if key==4:
                recent=next((e for e in reversed(events) if e['event']=='sample'),{})
                if recent.get('opens',0)<=recent.get('closes',0): key=22
            adb('shell','input','keyevent',str(key))
            w.writerow([datetime.now(timezone.utc).isoformat(),round(at-start,3),key,round((time.monotonic()-at)*1000,1)])
            i+=1
            if i%20==0 and adb('shell','pidof',pkg,check=False)!=pid_initial: raise RuntimeError('processus perdu ou remplacé')
            time.sleep(max(0,1.2-(time.monotonic()-at)))
    state.update(n_commands=i,duration_s=time.monotonic()-start,same_pid=adb('shell','pidof',pkg)==pid_initial)
    (out/'gfx-end.txt').write_text(adb('shell','dumpsys','gfxinfo',pkg).split('View hierarchy:')[0])
    state['last_navigation']=next((s for s in reversed(events) if s['event']=='sample' and s['phase']=='navigation'),None)
    identity('after-navigation')
    n=len(events)
    adb('shell','am','force-stop',pkg)
    launch()
    state['restored']=wait('restored',n,150)
    identity('after-restart')
    assert state['restored']['rows']==30000 and state['restored']['visible_cache']==30000
    if not state['last_navigation'] or state['last_navigation']['unique_selected']<2 or not state['last_navigation']['opens'] or not state['last_navigation']['zap_intents']:
        raise RuntimeError('parcours insuffisant pour qualifier navigation/zapping, importer preuves partielles')
finally:
    state['fixture_requests']=counters.copy()
    (out/'summary.json').write_text(json.dumps(state,indent=2))
