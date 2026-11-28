"""Faute unique sur l'ACK numérique destiné au Worker de test en boucle locale."""
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
from threading import Lock
import time

out=Path(sys.argv[1]);arm=Path(sys.argv[2]);lock=Lock()


def record(name,**fields):
    with lock, (out/'wire.jsonl').open('a') as f:
        print(json.dumps(dict(event=name,monotonic=time.monotonic(),**fields)),file=f)


class Gateway(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def forward(self):
        if self.headers.get('Upgrade','').lower()=='websocket':
            self.send_error(503);record('websocket_unavailable');return
        body=self.rfile.read(int(self.headers.get('Content-Length','0') or 0))
        ack=self.path.startswith('/api/box/ack/')
        ids=[]
        if ack:
            try: ids=[v for v in json.loads(body).get('box',[]) if type(v) is int]
            except (ValueError,TypeError): pass
        drop=None
        if ids:
            with lock:
                if arm.exists():
                    target=int(arm.read_text())
                    if target in ids:
                        arm.unlink();drop=target
        if drop is not None:
            record('ack_answer_lost_before_worker',order=drop)
            self.send_error(503);return
        connection=http.client.HTTPConnection('127.0.0.1',18787,timeout=45)
        try:
            headers={k:v for k,v in self.headers.items() if k.lower() not in
                     ('host','connection','transfer-encoding','accept-encoding','upgrade')}
            headers['Accept-Encoding']='identity'
            connection.request(self.command,self.path,body=body if body else None,headers=headers)
            r=connection.getresponse(); data=r.read()
            if self.path.startswith('/api/device-source/') and r.status==200:
                try:
                    rev=json.loads(data).get('source_rev')
                    if type(rev) is int:record('source_received',source_rev=rev)
                except (ValueError,TypeError):pass
            if ack:record('ack_reached_worker',orders=ids,http=r.status)
            self.send_response(r.status)
            for k,v in r.getheaders():
                if k.lower() not in ('connection','transfer-encoding','content-length','server','date'):
                    self.send_header(k,v)
            self.send_header('Content-Length',str(len(data)))
            self.end_headers();self.wfile.write(data)
        except (OSError,http.client.HTTPException):
            try:self.send_error(502)
            except OSError:pass
        finally:connection.close()
    do_GET=do_POST=do_PUT=do_DELETE=do_PATCH=forward


ThreadingHTTPServer(('127.0.0.1',18789),Gateway).serve_forever()
