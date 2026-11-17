"""Relais HTTPS limité au vrai Worker local, exclusivement sur la boucle locale de test."""
from http import server, client
from pathlib import Path
import ssl, sys, json, time
root,events=map(Path,sys.argv[1:3])
class Handler(server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_HEAD(self):self.relay()
    def do_GET(self):self.relay()
    def do_POST(self):self.relay()
    def relay(self):
        conn=client.HTTPConnection('127.0.0.1',8788,timeout=8)
        try:
            body=self.rfile.read(min(int(self.headers.get('Content-Length','0')),1048576))
            forward = {k: self.headers[k] for k in ('Content-Type','Accept','X-Device-Key','Authorization') if k in self.headers}
            conn.request(self.command,self.path,body=body,headers=forward)
            r=conn.getresponse();b=r.read();self.send_response(r.status)
            self.send_header('Content-Type',r.getheader('Content-Type','application/json'));self.send_header('Content-Length',str(len(b)));self.end_headers()
            with events.open('a') as f:f.write(json.dumps({'name':self.path.split('?',1)[0].split('/')[-1][:25],'status':r.status})+'\n') if self.path.startswith('/api/novatube4k/') else None
            if self.command!='HEAD':self.wfile.write(b)
        finally:conn.close()
s=server.ThreadingHTTPServer(('127.0.0.1',8743),Handler);c=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);c.load_cert_chain(root/'server.pem',root/'server.key');s.socket=c.wrap_socket(s.socket,server_side=True);s.serve_forever()
