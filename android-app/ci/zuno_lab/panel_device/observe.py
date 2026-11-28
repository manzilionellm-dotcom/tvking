"""Suivi externe du seul AVD, du vrai Worker et de sa base jetable."""
import argparse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile
from threading import Thread
import time
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from visible_launch import LABELS, screen_evidence

PACKAGE = 'com.sevenmotion.tv.seven_tv.lab'
ROOT = 'http://127.0.0.1:18787'
token = None


def api(method, path, body=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = Request(ROOT + path, data=json.dumps(body).encode() if body else None, headers=headers, method=method)
    with urlopen(req, timeout=8) as res:
        return json.load(res)


def adb(*args, timeout=25, check=True):
    return subprocess.run(['adb', *args], check=check, capture_output=True, text=True, timeout=timeout).stdout.strip()


def read_sqlite():
    # AVD vierge contrôlé par le banc. Seuls des comptes sortent de la copie privée.
    path = '/data/user/0/' + PACKAGE + '/app_flutter/tv_king.db'
    with tempfile.TemporaryDirectory() as tmp:
        for suffix in ['', '-wal', '-shm']:
            dest = Path(tmp) / ('guide.db' + suffix)
            p = subprocess.run(['adb','pull',path+suffix,str(dest)],capture_output=True,timeout=15)
            if not suffix and p.returncode != 0:
                return {'available':False,'adb_uid':adb('shell','id','-u',check=False),'pull_denied':b'Permission denied' in p.stderr or b'Permission denied' in p.stdout}
        with sqlite3.connect(str(Path(tmp)/'guide.db')) as db:
            counts = db.execute('SELECT COUNT(*),COUNT(DISTINCT stream_url),COUNT(DISTINCT category) FROM channels').fetchone()
            valid = db.execute('PRAGMA quick_check').fetchone()[0]=='ok'
        return dict(available=True,valid=valid,rows=counts[0],unique_streams=counts[1],categories=counts[2])


def main(args):
    global token
    events = args.out/'transactions.jsonl'
    def note(name,**data):
        with events.open('a') as f:
            print(json.dumps(dict(event=name,utc=datetime.now(timezone.utc).isoformat(),host_monotonic=time.monotonic(),**data)),file=f)
    def capture_timeout(stage):
        try:
            LABELS['fallback_mode'] = {'safe','mode','secours','récupération'}
            evidence = screen_evidence(args.out, 'timeout-'+stage)
            note('timeout_screen',stage=stage,**evidence)
        except (ValueError, OSError, subprocess.SubprocessError) as exc:
            note('timeout_capture_failed',stage=stage,error=type(exc).__name__)
    seen = {}
    class Fixture(BaseHTTPRequestHandler):
        def log_message(self,*args): pass
        def do_GET(self):
            m=re.fullmatch(r'/(5000|20000|2|0)\.m3u',self.path)
            if not m:
                self.send_error(404);return
            size=int(m[1]);seen[size]=seen.get(size,0)+1
            if not size:
                self.send_error(404);return
            if size==2:
                with urlopen('http://127.0.0.1:18471/channels.m3u',timeout=8) as r: body=r.read()
            else:
                body=('#EXTM3U\n'+''.join(f'#EXTINF:-1 tvg-id="qa{i}" group-title="Test-{i%8}",Mire {i}\nhttp://127.0.0.1:18471/A/index.m3u8?test={i}\n' for i in range(size))).encode()
            self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    fixture=ThreadingHTTPServer(('127.0.0.1',18475),Fixture);Thread(target=fixture.serve_forever,daemon=True).start()
    token=api('POST','/api/v1/auth/login',{'email':'admin','password':os.environ['ZUNO_QA_PASS']})['token']
    adb('shell','am','start','-n',PACKAGE+'/com.example.tv_king.MainActivity')
    until=time.monotonic()+110;mac=None
    initial_screen = False
    while time.monotonic()<until:
        if not initial_screen and until-time.monotonic()<=10:
            initial_screen=True;Thread(target=capture_timeout,args=('initial',),daemon=True).start()
        devices=api('GET','/api/v1/boxes/live')['items']
        if len(devices)>1: raise RuntimeError('Ce D1 doit contenir une seule TV synthétique')
        if devices:
            mac=devices[0]['mac'];break
        time.sleep(1)
    if not mac: raise RuntimeError('Aucune TV inscrite dans le Worker local')
    note('tv_identified',adb_uid=adb('shell','id','-u',check=False))
    api('POST','/api/v1/activate',{'mac':mac,'plan':'lifetime'})
    sizes = [[2]] if args.mode=='pixels' else [[5000],[20000],[20000,0],[20000]]
    for rev,spec in enumerate(sizes,1):
        prior=(api('GET','/api/v1/boxes/live')['items'][0].get('last_applied') or {}).get('id',0)
        start=time.monotonic()
        res=api('PUT','/api/v1/sources/'+mac,{'sources':[{'type':'m3u','m3u_url':f'http://127.0.0.1:18475/{s}.m3u','label':f'LAB {s}'} for s in spec]})
        note('revision_posted',step=rev,sizes=spec,write_count=res.get('count'))
        if args.mode=='catalogue' and rev==1 and os.environ.get('ZUNO_ACK_ARM'):
            current=api('GET','/api/v1/boxes/live')['items'][0]
            orders=[o['id'] for o in current['pending'] if o.get('kind')=='source']
            if orders:
                target=max(orders);flag=Path(os.environ['ZUNO_ACK_ARM']);atomic=flag.with_suffix('.tmp')
                atomic.write_text(str(target));atomic.replace(flag);note('ack_fault_armed',order=target)
        refused = 0 in spec
        limit=125
        ok=False;pending=set();timed_screen=False
        while time.monotonic()-start<limit:
            if not timed_screen and time.monotonic()-start>=100:
                timed_screen=True;Thread(target=capture_timeout,args=(str(rev),),daemon=True).start()
            item=api('GET','/api/v1/boxes/live')['items'][0]
            applied=item.get('last_applied') or {}
            pending.update(o['id'] for o in item['pending'] if o.get('kind')=='source')
            if applied.get('kind')=='source' and applied.get('id',0)>prior:
                note('applied',step=rev,order=applied['id'],applied_at=applied['applied_at'],ms=round((time.monotonic()-start)*1000))
                ok=True;break
            if refused and seen.get(0,0)>=2 and pending:
                break
            time.sleep(.5)
        note('order_observed',step=rev,pending=sorted(pending),success_ack=ok,fixture_reads=seen)
        if refused:
            if ok or not seen.get(0) or not pending: raise RuntimeError('Le refus de la révision doit rester en attente')
        elif not ok or not all(seen.get(s) for s in spec): raise RuntimeError('Révision non attestée par origine et ACK')
        if rev==len(sizes):
            adb('shell','am','force-stop',PACKAGE)
            db=read_sqlite();note('sqlite_after_stop',step=rev,**db)
            if db['available'] and (not db['valid'] or db['rows']!=spec[0] or db['unique_streams']!=spec[0]):
                raise RuntimeError('Volume ou unicité SQLite inattendu')
            adb('shell','am','start','-n',PACKAGE+'/com.example.tv_king.MainActivity')
            time.sleep(3)
    fixture.shutdown()

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('out',type=Path);p.add_argument('mode',choices=['catalogue','pixels'])
    main(p.parse_args())
