"""Origine de mire indépendante du chemin HTTP dégradé, tous deux locaux."""
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import sys
from threading import Lock
import time

out=Path(sys.argv[1]);out.mkdir(exist_ok=True)
arm=Path(sys.argv[2])
link=sys.argv[3]
if link not in ('direct','tunnel'):
    raise ValueError('Tracé réseau imprévu')
lock=Lock()
allowed=re.compile(r'/(?:channels\.m3u|[AB]/(?:index\.m3u8|seg\d+\.ts))')


class Bridge(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_GET(self):
        path=self.path.split('?')[0]
        if not allowed.fullmatch(path):
            self.send_error(404);return
        started=time.monotonic()
        blocked=False
        if arm.is_file():
            state=json.loads(arm.read_text())
            blocked=state['start_s']<=started<state['resume_s']
        conn=None;status=None;first=None;valid=False;n=0;sent=False
        try:
            if blocked:
                status=503;self.send_error(503);return
            conn=HTTPConnection('127.0.0.1',18472,timeout=8)
            conn.request('GET',path)
            r=conn.getresponse()
            status=r.status
            data=r.read();first=time.monotonic()
            if path=='/channels.m3u' and link=='direct':
                data=data.replace(b'http://127.0.0.1:18471/', b'http://10.0.2.2:18471/')
            valid=(data[:1]==b'\x47' and len(data)>=188) if path.endswith('.ts') else data.startswith(b'#EXTM3U')
            n=len(data);self.send_response(status)
            self.send_header('Content-Length',str(n))
            self.send_header('Content-Type',r.getheader('Content-Type','application/octet-stream'));self.end_headers()
            self.wfile.write(data);sent=True
        except (OSError,TimeoutError):
            pass
        finally:
            if conn:conn.close()
            with lock,(out/'http.jsonl').open('a') as ledger:
                print(json.dumps(dict(request_s=started,source_read_complete_s=first,write_end_s=time.monotonic(),path=path,
                                      blocked=blocked,status=status,valid=valid,bytes=n,wrote_response=sent)),file=ledger)

ThreadingHTTPServer(('127.0.0.1',18471),Bridge).serve_forever()
