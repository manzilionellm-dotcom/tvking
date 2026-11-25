"""Run the delivered APK with generated local video and measure the swipe."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from xml.etree import ElementTree
from PIL import Image
from io import BytesIO
import json, os, re, runpy, shlex, subprocess, sys, time

ADB=runpy.run_path(str(Path(__file__).with_name('7motion-scroll-sample.py')))['adb']
HOST='http://127.0.0.1:18089'
ROOT=Path(os.environ['RUNNER_TEMP'])/'feed-media'
CLIPS=[('Red','red'),('Blue','blue'),('Green','lime'),('Yellow','yellow'),('Cyan','cyan'),('Magenta','magenta')]

def generate():
    ROOT.mkdir(exist_ok=True)
    for i,(_,color) in enumerate(CLIPS):
        folder=ROOT/str(i);folder.mkdir(exist_ok=True)
        codec=['-c:v','libx264','-preset','ultrafast','-profile:v','baseline','-pix_fmt','yuv420p','-g','15','-sc_threshold','0','-c:a','aac']
        out=(['-muxrate','1800000','-f','mpegts',str(folder/'live.ts')] if i<3 else
             ['-f','hls','-hls_time','1','-hls_list_size','0','-hls_segment_filename',str(folder/'s%02d.ts'),str(folder/'index.m3u8')])
        subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','lavfi','-i',
           f'color=c={color}:s=480x270:r=30','-f','lavfi','-i','anullsrc=r=48000:cl=stereo',
           '-t','10',*codec,*out],check=True)

def serve():
    data=['#EXTM3U']
    for i,(name,_) in enumerate(CLIPS):
        path='live.ts' if i<3 else 'index.m3u8'
        data.extend([f'#EXTINF:-1 group-title="Motion Lab",Station {name}',f'{HOST}/media/{i}/{path}'])
    playlist='\n'.join(data).encode()
    class Fixture(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path=='/liste.m3u':
                self.send_response(200);self.send_header('Content-Length',str(len(playlist)));self.end_headers();self.wfile.write(playlist);return
            mat=re.fullmatch(r'/media/(\d)/(live\.ts|index\.m3u8|s\d+\.ts)',self.path)
            if not mat:self.send_error(404);return
            idx,part=mat.groups();path=ROOT/idx/part
            if not path.is_file():self.send_error(404);return
            self.send_response(200)
            self.send_header('Content-Type','application/vnd.apple.mpegurl' if part.endswith('m3u8') else 'video/mp2t')
            if part!='live.ts':self.send_header('Content-Length',str(path.stat().st_size))
            self.end_headers()
            print(f'{time.monotonic():.3f} {self.path}',flush=True)
            try:
                if part!='live.ts':self.wfile.write(path.read_bytes());return
                with path.open('rb') as stream:
                    while True:
                        chunk=stream.read(6016)
                        if chunk:self.wfile.write(chunk);time.sleep(.025)
                        else:stream.seek(0)
            except (BrokenPipeError,ConnectionResetError):pass
        def log_message(self,*args): pass
    ThreadingHTTPServer(('127.0.0.1',18089),Fixture).serve_forever()

def run(apk,tag):
    pkg='com.manzilionellm.tvking.qa.'+tag
    out=Path('diagnostic')/tag;out.mkdir(exist_ok=True)
    adb=ADB
    def doc():
        adb('shell','uiautomator dump /sdcard/feed-ui.xml >/dev/null',check=False)
        data=adb('shell','cat /sdcard/feed-ui.xml',check=False)
        if '<hierarchy' not in data:return []
        (out/'last.xml').write_text(data)
        return list(ElementTree.fromstring(data).iter('node'))
    def label(n): return n.get('content-desc','')+' '+n.get('text','')
    def tap(match,seek=False):
        polls=0
        deadline=time.monotonic()+65
        while time.monotonic()<deadline:
            nodes=doc()
            for n in nodes:
                if match(n):
                    x,y,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')))
                    adb('shell',f'input tap {(x+x2)//2} {(y+y2)//2}');time.sleep(.3);return
            polls+=1
            if seek and polls>=2:
                adb('shell', 'input swipe 340 1060 340 690 320')
            time.sleep(.4)
        raise ValueError('Contrôle absent : '+str([label(n) for n in nodes if label(n).strip()][:18]))
    def snap():return subprocess.check_output(['adb','exec-out','screencap','-p'])
    def wait_color(name,deadline):
        rgb={'Red':(1,0,0),'Blue':(0,0,1),'Green':(0,1,0),'Yellow':(1,1,0),'Cyan':(0,1,1),'Magenta':(1,0,1)}[name]
        while time.monotonic()<deadline:
            raw=snap();im=Image.open(BytesIO(raw)).convert('RGB');w,h=im.size
            matches=0
            for x,y in ((.26,.47),(.31,.55),(.45,.45),(.67,.52),(.59,.56)):
                pix=im.getpixel((int(x*w),int(y*h)))
                if all((v>110 if wanted else v<90) for v,wanted in zip(pix,rgb)):matches+=1
            if matches>=3:
                (out/(name+'.png')).write_bytes(raw);return time.monotonic()
            time.sleep(.10)
        (out/('failed-'+name+'.png')).write_bytes(snap())
        raise ValueError('Première image de '+name+' absente')
    results=[]
    try:
        print('INSTALL',tag,flush=True)
        adb('install','-r',apk)
        adb('shell','pm grant '+pkg+' android.permission.POST_NOTIFICATIONS',check=False)
        adb('shell','monkey -p '+pkg+' -c android.intent.category.LAUNCHER 1')
        tap(lambda n:'Add an M3U list' in label(n));tap(lambda n:n.get('class')=='android.widget.EditText')
        adb('shell','input text '+HOST+'/liste.m3u');time.sleep(.5);adb('shell','input keyevent 4')
        tap(lambda n:'Load my channels' in label(n));tap(lambda n:'Motion Lab' in label(n),seek=True);tap(lambda n:'Station Red' in label(n),seek=True)
        # Android can identify adb reverse as cellular when both radios are off.
        for _ in range(3):
            nodes=doc()
            if any('Cellular data' in label(n) for n in nodes):
                tap(lambda n:'Continue' in label(n))
                break
            time.sleep(.35)
        print('Chaîne sélectionnée',flush=True)
        wait_color('Red',time.monotonic()+32)
        size=adb('shell','wm size')
        sw,sh=map(int,re.findall(r'(\d+)x(\d+)',size)[-1])
        # Match logical input coordinates to the actual display rotation.
        sw,sh=Image.open(BytesIO(snap())).size
        for name,_ in CLIPS[1:]:
            time.sleep(2.1)
            adb('shell','dumpsys SurfaceFlinger --timestats -clear -enable')
            listing=adb('shell','dumpsys SurfaceFlinger --list').splitlines()
            layers=[n for n in listing if pkg in n and 'SurfaceView' in n and not n.startswith('Background')]
            start=time.monotonic()
            timing=adb('shell',f'cat /proc/uptime; input swipe {sw//2} {int(.77*sh)} {sw//2} {int(.26*sh)} 300; cat /proc/uptime')
            bounds=[float(l.split()[0])*1e9 for l in timing.splitlines() if re.fullmatch(r'[0-9.]+ [0-9.]+',l)]
            shown=wait_color(name,start+25)
            adb('shell','dumpsys SurfaceFlinger --timestats -disable')
            ts=adb('shell','dumpsys SurfaceFlinger --timestats -dump -maxlayers 180')
            (out/(name+'-frames.txt')).write_text(ts)
            stats={'station':name,'gesture_to_observed_image_ms':round((shown-start)*1000)}
            render=[]
            for layer in layers:
                raw=adb('shell','dumpsys SurfaceFlinger --latency '+shlex.quote(layer))
                stamps=sorted({int(a[1]) for line in raw.splitlines() if len(a:=line.split())==3 and all(v.isdigit() for v in a) and len(bounds)==2 and bounds[0]<=int(a[1])<=bounds[1]})
                if len(stamps)<2:continue
                delta=sorted((y-x)/1e6 for x,y in zip(stamps,stamps[1:]))
                render.append({'layer':layer,'frames':len(stamps),'elapsed_ms':round((stamps[-1]-stamps[0])/1e6,1),'median_interval_ms':round(delta[len(delta)//2],2),'fps_during_drag':round(1e9*(len(stamps)-1)/(stamps[-1]-stamps[0]),1)})
            stats['compositor']=render
            results.append(stats);(out/'swipes.json').write_text(json.dumps(results,indent=2));print(stats,flush=True)
        print('Toutes les couleurs atteintes',flush=True)
    finally:
        (out/'logcat.txt').write_text(adb('logcat','-d','-t','9000',check=False))
        (out/'memory.txt').write_text(adb('shell','dumpsys meminfo '+pkg,check=False))
        (out/'final.png').write_bytes(snap())
        adb('shell','am force-stop '+pkg)
if __name__=='__main__':
    if sys.argv[1]=='generate':generate()
    elif sys.argv[1]=='serve':serve()
    else:run(sys.argv[2],sys.argv[3])
