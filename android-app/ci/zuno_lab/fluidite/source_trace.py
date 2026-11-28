"""Compte les octets effectivement écrits vers le client pour les deux mires locales."""
import http.server,json,os,re,runpy,sys,time
from pathlib import Path
Base=http.server.SimpleHTTPRequestHandler
class Observed(Base):
    def copyfile(self,source,out):
        path=re.fullmatch('/([AB])/(seg[0-9]+[.]ts|index[.]m3u8)',self.path)
        if not path:return super().copyfile(source,out)
        start=time.monotonic();n=0;done=False
        try:
            while data:=source.read(65536):
                n+=out.write(data)
            done=True
        finally:
            with open(os.environ['TRACE_SOURCE'],'a') as f:
                f.write(json.dumps(dict(start=start,end=time.monotonic(),ch=path[1],name=path[2],body_bytes=n,completed=done))+'\n')
http.server.SimpleHTTPRequestHandler=Observed
original=Path(sys.argv[1]).resolve();sys.argv=sys.argv[1:];sys.path.insert(0,str(original.parent))
runpy.run_path(str(original),run_name='__main__')
