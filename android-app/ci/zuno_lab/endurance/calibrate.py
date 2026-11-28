"""Calibrer la lecture de pixels utilisée par observe.py, sur 225 trames réelles."""
from pathlib import Path
from tempfile import TemporaryDirectory
import argparse
import json
import subprocess
from PIL import Image
from regional_live_source import marker
from observe import region

def run(out):
    with TemporaryDirectory() as tmp:
        film=Path(tmp)/'calibration.mkv'
        vf="drawbox=x=iw/4:y=ih*0.38:w=iw/2:h=ih*0.24:color=black:t=fill,"+marker('A')+",scale=320:180,tpad=stop_mode=clone:stop_duration=8"
        subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','color=gray:size=1920x1080:rate=25:duration=1',
                        '-filter_threads','1','-vf',vf,'-frames:v','225','-c:v','ffv1','-threads','1',str(film)],check=True)
        raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(film),'-threads','1','-pix_fmt','gray','-f','rawvideo','-'])
        size=320*180
        rows=[]
        for i in range(len(raw)//size):
            ch,n,_=region(Image.frombytes('L',(320,180),raw[i*size:(i+1)*size]))
            rows.append((ch,n))
        assert rows[:25]==[('A',i) for i in range(25)]
        assert rows[25:]==[('A',24)]*200
        summary=dict(samples=len(rows),fps=25,injected_s=8.,last_moving_pts_s=.96,last_pts_s=8.96,
                     contiguous_repeat_lower_s=(len(rows)-25)/25,camera_or_android=False)
        out.write_text(json.dumps(summary,indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('out',type=Path);run(p.parse_args().out)
