"""Génération continue de A avec temps du programme et cadence explicite."""
from pathlib import Path
import os
import sys
from regional_live_source import marker

def main():
    d=Path(sys.argv[1]);d.mkdir()
    label="drawbox=x=iw/4:y=ih*0.38:w=iw/2:h=ih*0.24:color=black:t=fill,drawtext=text='A %{n}':fontcolor=white:fontsize=94:x=(w-tw)/2:y=(h-th)/2"
    opts=['-nostdin','-hide_banner','-v','error','-re','-f','lavfi','-i','testsrc2=size=1920x1080:rate=25',
        '-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-vf',label+','+marker('A'),
        '-c:v','libx264','-pix_fmt','yuv420p','-threads','2','-preset','ultrafast','-g','50','-keyint_min','50',
        '-sc_threshold','0','-b:v','4M','-maxrate','4M','-bufsize','8M','-c:a','aac','-b:a','128k',
        '-f','hls','-hls_time','2','-hls_list_size','10','-hls_delete_threshold','4',
        '-hls_flags','delete_segments+temp_file+independent_segments+program_date_time',
        '-hls_segment_filename',str(d/'s%09d.ts'),str(d/'index.m3u8')]
    os.execvp('ffmpeg',['ffmpeg',*opts])
if __name__=='__main__':main()
