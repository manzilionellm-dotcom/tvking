"""Petit fournisseur Xtream local à deux mires. Aucune connexion en amont."""
import datetime as dt
import http.server
import json
import re
import sys
import time
import urllib.parse
from pathlib import Path

root,events=map(Path,sys.argv[1:3]); now=int(time.time())//60*60
rows=[('ARCHIVE ALPHA',now-7200,now-3600,1),('LIVE STUDIO',now-300,now+1200,0),('FUTURE NOVA',now+1200,now+4800,0)]
base='http://127.0.0.1:8783'; source='/lab/lab/42.ts'
def wall(epoch):return dt.datetime.fromtimestamp(epoch,dt.timezone.utc)
def event(kind,**more):
    with events.open('a') as f:f.write(json.dumps({'t':round(time.monotonic(),3),'kind':kind,**more})+'\n')
class Server(http.server.ThreadingHTTPServer):daemon_threads=True
class Provider(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def payload(self,obj,kind='application/json'):
        body=json.dumps(obj).encode() if kind=='application/json' else obj.encode();self.send_response(200);self.send_header('Content-Type',kind);self.send_header('Content-Length',str(len(body)));self.end_headers()
        if self.command!='HEAD':self.wfile.write(body)
    def do_HEAD(self):self.do_GET()
    def do_GET(self):
        u=urllib.parse.urlsplit(self.path); path=u.path;query=urllib.parse.parse_qs(u.query); action=query.get('action',[''])[0]
        if path=='/player_api.php':
            event(action or 'auth')
            if not action: obj={'user_info':{'username':'lab','password':'lab','auth':1,'status':'Active','exp_date':str(now+86400),'active_cons':'0','max_connections':'1','allowed_output_formats':['ts','m3u8']},'server_info':{'url':'127.0.0.1','port':'8783','server_protocol':'http','timezone':'UTC','timestamp_now':int(time.time()),'time_now':wall(int(time.time())).strftime('%Y-%m-%d %H:%M:%S')}}
            elif action=='get_live_streams': obj=[{'num':1,'name':'AURORA QA','stream_id':42,'stream_type':'live','stream_icon':'','epg_channel_id':'aurora.demo','category_id':'1','tv_archive':1,'tv_archive_duration':2,'direct_source':''}]
            elif action=='get_live_categories':obj=[{'category_id':'1','category_name':'Laboratory','parent_id':0}]
            elif action in ('get_simple_data_table','get_short_epg'):
                obj={'epg_listings':[{'id':i+1,'channel_id':'aurora.demo','title':title,'description':'Programme de test local','lang':'en','start_timestamp':str(a),'stop_timestamp':str(b),'start':wall(a).strftime('%Y-%m-%d %H:%M:%S'),'end':wall(b).strftime('%Y-%m-%d %H:%M:%S'),'has_archive':arc,'now_playing':int(a<=time.time()<b)} for i,(title,a,b,arc) in enumerate(rows)]}
            else:obj=[]
            self.payload(obj);return
        if path in ('/list.m3u','/get.php'):
            event('m3u');self.payload(f'#EXTM3U x-tvg-url="{base}/xmltv.php"\n#EXTINF:-1 tvg-id="aurora.demo" group-title="Laboratory" catchup="default" catchup-days="2",AURORA QA\n{base}{source}\n','audio/x-mpegurl');return
        if path=='/xmltv.php':
            event('xmltv');date=lambda ep:wall(ep).strftime('%Y%m%d%H%M%S +0000');self.payload('<?xml version="1.0" encoding="UTF-8"?><tv><channel id="aurora.demo"><display-name>AURORA QA</display-name></channel>'+''.join(f'<programme start="{date(a)}" stop="{date(b)}" channel="aurora.demo"><title>{name}</title><desc>Programme de test local</desc></programme>' for name,a,b,_ in rows)+'</tv>','application/xml');return
        if path==source:
            event('short404'); self.send_error(404); return
        if path=='/live'+source or path.startswith('/timeshift/'):
            mode='replay' if path.startswith('/timeshift/') else 'live'
            if mode=='replay':
                expected='/timeshift/lab/lab/60/'+wall(rows[0][1]).strftime('%Y-%m-%d:%H-%M')+'/42.ts'
                if urllib.parse.unquote(path)!=expected:event('wrong_archive');self.send_error(404);return
            file=root/(mode+'.ts');total=file.stat().st_size;start=0;stop=total-1
            h=self.headers.get('Range','');m=re.fullmatch(r'bytes=(\d+)-(\d*)',h)
            if m:start=int(m[1]);stop=min(total-1,int(m[2]) if m[2] else total-1)
            if start>=total or stop<start:self.send_error(416);return
            event(mode,offset=start);self.send_response(206 if m else 200);self.send_header('Content-Type','video/mp2t');self.send_header('Accept-Ranges','bytes');self.send_header('Content-Length',str(stop-start+1));
            if m:self.send_header('Content-Range',f'bytes {start}-{stop}/{total}')
            self.end_headers()
            if self.command!='HEAD':
                with file.open('rb') as f:
                    f.seek(start);remain=stop-start+1
                    try:
                        while remain:
                            block=f.read(min(32768,remain));self.wfile.write(block);remain-=len(block)
                    except (BrokenPipeError, ConnectionResetError):pass
            return
        self.send_error(404)
Server(('127.0.0.1',8783),Provider).serve_forever()
