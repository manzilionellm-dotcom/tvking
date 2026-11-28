"""Deux MPEG-TS marqués réellement décodables, multiplexés à l'horloge pendant chaque lecture."""
from pathlib import Path
import subprocess,sys
from regional_live_source import marker
def make(directory):
 directory.mkdir(parents=True,exist_ok=True)
 for ch,freq,col in [('A',440,'0x173951'),('B',880,'0x852444')]:
  target=directory/(ch+'.ts')
  vf="drawbox=x=iw/4:y=ih*0.38:w=iw/2:h=ih*0.24:color=black:t=fill,drawtext=text='"+ch+" %{n}':fontcolor=white:fontsize=94:x=(w-tw)/2:y=(h-th)/2,"+marker(ch)
  subprocess.run(['ffmpeg','-nostdin','-v','error','-f','lavfi','-i',f'color=c={col}:size=1920x1080:rate=25',
                  '-f','lavfi','-i',f'sine=frequency={freq}:sample_rate=48000','-t','8','-vf',vf,
                  '-threads','1','-c:v','libx264','-preset','ultrafast','-g','25','-sc_threshold','0',
                  '-c:a','aac','-b:a','96k','-f','mpegts','-y',str(target)],check=True)
def write_stream(handler,target,on_write):
 proc=subprocess.Popen(['ffmpeg','-nostdin','-v','error','-re','-stream_loop','-1','-i',str(target),
                        '-map','0:v:0','-map','0:a:0','-c','copy','-muxdelay','0','-f','mpegts','pipe:1'],
                        stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
 try:
  while True:
   data=proc.stdout.read(1316)
   if not data:return
   handler.wfile.write(data);handler.wfile.flush();on_write()
 except OSError:return
 finally:
  proc.terminate()
  try:proc.wait(timeout=3)
  except subprocess.TimeoutExpired:proc.kill();proc.wait()
if __name__=='__main__':make(Path(sys.argv[1]))
