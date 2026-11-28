"""Horloges de l'origine HLS de test et sonde active séparée du lecteur."""
import argparse
from datetime import datetime, timezone
import http.client
import http.server
import json
from pathlib import Path
import re
import runpy
import sys
import threading
import time

RESOURCE = re.compile(r'^/(?:channels\.m3u|[AB]/(?:index\.m3u8|seg[0-9]+\.ts))$')
VALID_SEG = re.compile(rb'(?m)^seg[0-9]+\.ts\s*$')
BASE = http.server.SimpleHTTPRequestHandler


def append(file, row):
    with file.open('a') as dest:
        row['utc'] = datetime.now(timezone.utc).isoformat()
        print(json.dumps(row,separators=(',',':')),file=dest)


def handler(file):
    class Observed(BASE):
        def do_GET(self):
            start = time.monotonic()
            self.response_status = None
            self.bytes_header = None
            self.headers_finished = None
            try:
                super().do_GET()
            finally:
                path = self.path.split('?')[0]
                if RESOURCE.fullmatch(path):
                    append(file,dict(start_s=start,headers_sent_s=self.headers_finished,end_s=time.monotonic(),
                                     resource=path,role='canary' if '?canary' in self.path else 'client_or_setup',
                                     status=self.response_status,content_length=self.bytes_header))
        def send_response(self, code, message=None):
            self.response_status = code
            super().send_response(code,message)
        def send_header(self, keyword, value):
            if keyword.lower()=='content-length': self.bytes_header=int(value)
            super().send_header(keyword,value)
        def end_headers(self):
            super().end_headers()
            self.headers_finished=time.monotonic()
        def log_message(self, *_args):
            pass
    return Observed


def canary(directory):
    while True:
        for ch in ['A','B']:
            playlist=None
            for kind in ['manifest','segment']:
                started=time.monotonic()
                if kind=='segment' and not playlist: continue
                path=f'/{ch}/'+('index.m3u8' if kind=='manifest' else playlist)
                conn=http.client.HTTPConnection('127.0.0.1',18471,timeout=5)
                try:
                    conn.request('GET',path+'?canary')
                    response=conn.getresponse()
                    first=response.read(1)
                    ttfb=time.monotonic()
                    data=first+response.read() if kind=='manifest' else first+response.read(8191)
                    done=time.monotonic()
                    if kind=='manifest':
                        matches=VALID_SEG.findall(data)
                        if matches: playlist=matches[-1].strip().decode('ascii')
                    append(directory/'canary.jsonl',dict(channel=ch,kind=kind,status=response.status,
                           bytes=len(data),host_start_s=started,first_body_byte_s=ttfb,end_s=done,
                           valid=bool(playlist) if kind=='manifest' else data[:1]==b'\x47'))
                except OSError as exc:
                    append(directory/'canary.jsonl',dict(channel=ch,kind=kind,error=type(exc).__name__))
                finally: conn.close()
        time.sleep(12)


def main():
    p=argparse.ArgumentParser()
    p.add_argument('original',type=Path)
    p.add_argument('fixtures',type=Path)
    p.add_argument('output',type=Path)
    args=p.parse_args()
    args.output.mkdir(exist_ok=True,parents=True)
    threading.Thread(target=canary,args=(args.output,),daemon=True).start()
    http.server.SimpleHTTPRequestHandler = handler(args.output/'http.jsonl')
    sys.argv=[str(args.original),'serve',str(args.fixtures),'--duration','3300']
    runpy.run_path(str(args.original),run_name='__main__')
if __name__=='__main__': main()
