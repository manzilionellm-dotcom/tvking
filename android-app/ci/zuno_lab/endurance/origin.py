"""Origine HLS synthétique et deux chemins testables vers les mêmes octets."""
import argparse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import threading
import time

PORTS = {"bootstrap":18470, "canary":18471, "media":18472}
SEG = re.compile(r"/A/s(\d{9})\.ts")


def utc():
    return datetime.now(timezone.utc).isoformat()


def append(path, obj):
    with path.open('a') as out:
        print(json.dumps(obj,separators=(',',':')),file=out)


class Source(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        role, state = self.server.role, self.server.state
        path=self.path.partition('?')[0]
        host='10.0.2.2' if state['route']=='direct' else '127.0.0.1'
        start=time.monotonic()
        segment=SEG.fullmatch(path)
        if role=='bootstrap' and path=='/start.m3u8':
            # Même URL compilée, même binaire. La playlist de sélection indique
            # explicitement le trajet invité→hôte du manifeste ET des segments.
            body=f'#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=4500000\nhttp://{host}:18472/A/index.m3u8\n'.encode()
            status,mime=200,'application/vnd.apple.mpegurl'
        elif role!='bootstrap' and (path=='/A/index.m3u8' or segment):
            requested=state['media']/Path(path).name
            try:
                body=requested.read_bytes()
                status=200
            except FileNotFoundError:
                body=b''
                status=404
            mime='video/mp2t' if segment else 'application/vnd.apple.mpegurl'
            # Incident injecté sur le trafic lecteur uniquement. Le canari
            # continue à lire la même origine sans traverser cette condition.
            if role=='media' and state['scenario']=='degraded':
                time.sleep(.12)
                if segment and int(segment[1])>0 and int(segment[1])%37==0:
                    with state['lock']:
                        if path not in state['failed']:
                            state['failed'].add(path)
                            body,status=b'',503
        else:
            body,status,mime=b'',404,'text/plain'
        try:
            self.send_response(status)
            self.send_header('Content-Type',mime)
            self.send_header('Content-Length',str(len(body)))
            self.send_header('Cache-Control','no-store')
            self.end_headers()
            self.wfile.write(body)
        except (ConnectionError,OSError):
            pass
        with state['lock']:
            append(state['trace'],dict(utc=utc(),start_monotonic_s=start,finish_monotonic_s=time.monotonic(),
                role=role,path=(path if segment or path in ('/start.m3u8','/A/index.m3u8') else '/unknown'),
                host_role='direct' if self.headers.get('Host','').split(':')[0]=='10.0.2.2' else 'loopback',
                http=status,bytes=len(body)))


def serve(media,trace,route,scenario):
    state=dict(media=media,trace=trace,route=route,scenario=scenario,lock=threading.Lock(),failed=set())
    servers=[]
    try:
        for role,port in PORTS.items():
            server=ThreadingHTTPServer(('127.0.0.1',port),Source)
            server.role,server.state=role,state
            servers.append(server)
            threading.Thread(target=server.serve_forever,daemon=True).start()
        threading.Event().wait()
    finally:
        for s in servers:
            s.server_close()


if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('media',type=Path)
    p.add_argument('trace',type=Path)
    p.add_argument('route',choices=['direct','tunnel'])
    p.add_argument('scenario',choices=['stable','degraded','lowram'])
    a=p.parse_args()
    serve(a.media,a.trace,a.route,a.scenario)
