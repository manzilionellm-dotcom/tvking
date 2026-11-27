"""Prépare les deux mires avant le démarrage de la box puis les sert par remuxage.

L'image numérotée se répète au bout de 120 s. Le remuxage en lecture continue
conserve des horodatages MPEG-TS croissants et laisse le processeur au client.
"""
import argparse, http.server, functools, tempfile, time, subprocess, signal
from pathlib import Path
from regional_live_source import marker
import sys, os

parser=argparse.ArgumentParser()
parser.add_argument('mode', choices=['prepare','serve'])
parser.add_argument('directory',type=Path)
parser.add_argument('--duration',type=int,default=6600)
args=parser.parse_args();root=args.directory.resolve();root.mkdir(parents=True,exist_ok=True)
def encode(ch):
    filt=('hflip,' if ch=='B' else '')+"drawbox=x=iw/4:y=ih*0.38:w=iw/2:h=ih*0.24:color=black:t=fill,"+f"drawtext=text='{ch}  %{{n}}':fontcolor=white:fontsize=94:x=(w-tw)/2:y=(h-th)/2,"+marker(ch)
    subprocess.run(['ffmpeg','-nostdin','-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=1920x1080:rate=25','-f','lavfi','-i',f"sine=frequency={440 if ch=='A' else 660}:sample_rate=48000",'-t','120','-vf',filt,'-c:v','libx264','-threads','2','-preset','ultrafast','-pix_fmt','yuv420p','-g','50','-keyint_min','50','-sc_threshold','0','-b:v','4M','-maxrate','4M','-bufsize','8M','-c:a','aac','-ac','2','-b:a','128k',str(root/(ch+'.mkv'))],check=True)
if args.mode=='prepare':
    for ch in ('A','B'):encode(ch)
    sys.exit(0)
with tempfile.TemporaryDirectory() as directory:
    public=Path(directory);jobs=[]
    server=http.server.ThreadingHTTPServer(('127.0.0.1',18471),functools.partial(http.server.SimpleHTTPRequestHandler,directory=directory))
    server.timeout=.5
    try:
        lines=['#EXTM3U']
        for ch in ('A','B'):
            p=public/ch;p.mkdir()
            jobs.append(subprocess.Popen(['ffmpeg','-nostdin','-v','error','-re','-stream_loop','-1','-i',str(root/(ch+'.mkv')),'-map','0:v:0','-map','0:a:0','-c','copy','-f','hls','-hls_time','2','-hls_list_size','8','-hls_delete_threshold','2','-hls_flags','delete_segments+temp_file+independent_segments','-hls_segment_filename',str(p/'seg%08d.ts'),str(p/'index.m3u8')]))
            lines += [f'#EXTINF:-1,Mire {ch}',f'http://{os.environ.get("FREEZE_ROUTE", "127.0.0.1")}:18471/{ch}/index.m3u8']
        (public/'channels.m3u').write_text('\n'.join(lines)+'\n')
        end=time.monotonic()+args.duration
        while time.monotonic()<end:
            if any(j.poll() is not None for j in jobs):raise RuntimeError('Le remuxage de la mire a quitté.')
            server.handle_request()
    finally:
        server.server_close()
        for j in jobs:j.terminate()
        for j in jobs:j.wait()
