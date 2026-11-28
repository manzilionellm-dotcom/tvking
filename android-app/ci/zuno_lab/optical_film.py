"""Capture continue Android ; export des seules valeurs de mire et PTS."""
import argparse
import bisect
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import secrets
import statistics
import struct
import subprocess
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from android_film_clock import ffprobe, marker_values, winscope

def dump(path, data):
    path.write_text(json.dumps(data,indent=2,ensure_ascii=False,allow_nan=False)+'\n')


def encoded_cells(ch, n):
    if ch not in ('A','B'):return bytes([128]*30)
    bits=[(n>>k)&1 for k in range(20)]
    return bytes(255*b for b in ([1,0,1,1,0,1,0,int(ch=='B')]+bits+[sum(bits)%2,1]))


def safe_movie(out, pts, markers):
    """Un film sans pixels de l'interface. Chaque case vient du compteur reconnu."""
    with tempfile.TemporaryDirectory(dir=out.parent) as d:
        root=Path(d); entries=['ffconcat version 1.0']
        for i,(stamp,(channel,n)) in enumerate(zip(pts,markers)):
            # PGM binaire de 30x1. FFmpeg l'agrandit sans interpolation.
            image=root/f'{i:05d}.pgm'
            image.write_bytes(b'P5\n30 1\n255\n'+encoded_cells(channel,n))
            entries+=['file '+image.name,'option framerate 1000']
            if i+1<len(pts):
                duration=(round((pts[i+1]-pts[0])*1000)-round((stamp-pts[0])*1000))/1000
                if duration<.001:raise ValueError('Deux PTS à moins de 1 ms')
                entries.append(f'duration {duration:.3f}')
        listing=root/'plan.ffconcat';listing.write_text('\n'.join(entries)+'\n')
        subprocess.run(['ffmpeg','-v','error','-nostdin','-safe','0','-f','concat','-i',str(listing),
            '-vf','scale=300:22:flags=neighbor,format=gray','-threads','1','-fps_mode','passthrough',
            '-enc_time_base','1:1000','-c:v','ffv1',str(out)],check=True,timeout=100)
    exported=ffprobe(out,'-select_streams','v:0','-show_frames','-show_entries','frame=best_effort_timestamp_time')['frames']
    shown=[float(r['best_effort_timestamp_time']) for r in exported]
    if len(pts)!=len(shown):raise ValueError('Images perdues à la création du film expurgé')
    error=max(abs((b-shown[0])-(a-pts[0])) for a,b in zip(pts,shown))
    if error>.0011:raise ValueError('PTS du film expurgé incohérents')
    return error


def export_clip(private,out,clip):
    parsed=ffprobe(private,'-select_streams','v:0','-show_frames','-show_entries','frame=best_effort_timestamp_time')['frames']
    pts=[float(frame['best_effort_timestamp_time']) for frame in parsed]
    if len(pts)<2 or any(b<=a for a,b in zip(pts,pts[1:])):raise ValueError('PTS source non croissants')
    markers,optical=marker_values(private)
    if len(markers)!=len(pts):raise ValueError('Décodage et PTS divergent')
    try:
        clock,met= winscope(private)
        met['aligned']=True
    except (ValueError,StopIteration,IndexError,KeyError,AssertionError,struct.error) as e:
        # Le film et ses PTS restent exploitables dans leur propre référentiel.
        clock=[None]*len(pts);met={'aligned':False,'reason':type(e).__name__}
    err=safe_movie(out/f'film-{clip:03d}.mkv',pts,markers)
    with (out/f'images-{clip:03d}.csv').open('w',newline='') as dest:
        writer=csv.writer(dest);writer.writerow(('clip','frame','capture_pts_s','android_elapsed_s','channel','counter'))
        for i,(t,c,(ch,n)) in enumerate(zip(pts,clock,markers)):
            writer.writerow((clip,i,t,c,ch,n))
    gaps=[b-a for a,b in zip(pts,pts[1:])]
    hist={'clip':clip,'frames':len(pts),'duration_s':pts[-1]-pts[0],'median_frame_interval_s':statistics.median(gaps),
          'max_gap_s':max(gaps),'unknown_frames':sum(not m[0] for m in markers),
          'clock':met,'optical':optical,'export_pts_max_error_s':err,'source_video_sha256':digest(private)}
    dump(out/f'clip-{clip:03d}.json',hist)


def digest(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()


def run_adb(*args,timeout=10):
    return subprocess.check_output(['adb',*args],timeout=timeout,stderr=subprocess.DEVNULL)


def clocked_key(code):
    if code not in ('KEYCODE_CHANNEL_DOWN','KEYCODE_CHANNEL_UP'):raise ValueError('Touche non prévue')
    # Les deux lectures sont dans le même processus shell que la touche.
    cmd='read b rest < /proc/uptime; input keyevent '+code+' || exit 1; read a rest < /proc/uptime; echo "$b $a"'
    raw=run_adb('shell',cmd,timeout=25).decode().strip()
    if not re.fullmatch(r'\d+\.\d{2}\s+\d+\.\d{2}',raw):raise ValueError('Horloge de touche non vérifiable')
    b,a=map(float,raw.split())
    if a<b:raise ValueError('Horloge régressive')
    return b,a+.010


class Recorder:
    """Un encodeur dans le guest ; export asynchrone de chaque segment sur l’hôte."""
    def __init__(self,out):
        self.out=out
        self.base='/data/local/tmp/zuno-diag-film-'+secrets.token_hex(6)
        self.stop=threading.Event();self.ready=threading.Event()
        self.worker=None;self.failure=None

    def start(self):
        self.out.mkdir()
        self.worker=threading.Thread(target=self.capture,daemon=True);self.worker.start()
        if not self.ready.wait(12) or self.failure:raise RuntimeError('Enregistreur Android indisponible avant la série')
        # Le film vérifiera lui-même présence et horloge d'une trame avant l'appui.
        time.sleep(1)

    def capture(self):
        tasks=[]
        try:
            with ThreadPoolExecutor(max_workers=1) as export:
                index=0
                while not self.stop.is_set():
                    index+=1
                    basename=f'{self.base}-{index:03d}'
                    remote=basename+'.mp4'
                    # Un PID spécifique au processus enfant ; fichiers du seul AVD jetable.
                    script=f'screenrecord --size 960x540 --bit-rate 2400000 --time-limit 90 {remote} >/dev/null 2>&1 & p=$!; echo "$p" > {self.base}.pid; wait "$p"; code=$?; rm -f {self.base}.pid; exit "$code"'
                    proc=subprocess.Popen(['adb','shell',script],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                    try:
                        for _ in range(30):
                            if proc.poll() is not None:break
                            try:
                                if run_adb('shell','cat',self.base+'.pid',timeout=2).strip().isdigit():
                                    self.ready.set();break
                            except subprocess.SubprocessError:pass
                            time.sleep(.1)
                        rc=proc.wait(timeout=110)
                        if rc not in (0,130):raise RuntimeError('Enregistrement Android interrompu, code '+str(rc))
                        tasks.append(export.submit(self.pull_and_export,remote,index))
                    finally:
                        if proc.poll() is None:proc.kill();proc.wait()
                for job in tasks: job.result()
        except Exception as exc:
            self.failure=type(exc).__name__
            dump(self.out/'collecte-incomplete.json',{'reason':self.failure})
        finally:
            self.ready.set()

    def pull_and_export(self,remote,i):
        with tempfile.TemporaryDirectory() as d:
            private=Path(d)/'prive.mp4'
            try:
                run_adb('pull',remote,str(private),timeout=65)
                export_clip(private,self.out,i)
            finally:
                run_adb('shell','rm','-f',remote)

    def finish(self):
        self.stop.set()
        if self.worker is None:return
        try:
            run_adb('shell',f'if read p < {self.base}.pid; then kill -INT "$p"; fi')
        except subprocess.SubprocessError:pass
        self.worker.join(timeout=200)
        if self.worker.is_alive() or self.failure:
            dump(self.out/'collecte-incomplete.json',{'reason':self.failure or 'export_timeout'})
            return False
        return True


def score(out,trials):
    frames=[]
    for f in sorted(out.glob('images-*.csv')):
        with f.open() as stream:
            for r in csv.DictReader(stream):
                if r['android_elapsed_s']:
                    frames.append((float(r['android_elapsed_s']),int(r['clip']),r['channel'],
                                   int(r['counter']) if r['counter'] else None))
    frames.sort();times=[r[0] for r in frames];result=[]
    for i,t in enumerate(trials):
        lower=t.get('key_elapsed_min'); upper=t.get('key_elapsed_max')
        r={'number':t.get('number'),'phase':t.get('phase'),'target':t.get('target'),'input':t.get('status'),
           'key_lo_s':lower,'key_hi_s':upper,'outcome':'horloge_touche_absente'}
        result.append(r)
        if lower is None or upper is None:continue
        next_lower=trials[i+1].get('key_elapsed_min') if i+1<len(trials) else None
        # Stopper au prochain appui ; la coupure de capture ne redevient jamais un succès.
        end=min(upper+9,next_lower if next_lower is not None else upper+9)
        ix=bisect.bisect_left(times,upper); hi=bisect.bisect_left(times,end)
        pre=bisect.bisect_right(times,lower)-1
        r['outcome']='captation_non_couvrante'
        if pre<0 or hi<=ix or ix>=len(frames) or frames[ix][1]!=frames[pre][1]:continue
        r['clip']=frames[ix][1]; target=t['target'];last=None;old=False;obscured=False
        final='';last_t=times[pre]; gaps=0;largest=0.; returns=0; wrong=unknown=0
        final_moving=False
        for j in range(ix,hi):
            stamp,clip,ch,n=frames[j]
            gap=stamp-last_t;largest=max(largest,gap);last_t=stamp
            if gap>.250 or clip!=r['clip']:gaps+=1;last=None;final_moving=False
            final=ch
            if not ch:
                unknown+=1;obscured|=old;last=None;final_moving=False;continue
            if ch!=target:
                wrong+=1;returns+=int(obscured);old=True;obscured=False;last=None;final_moving=False;continue
            old=obscured=False
            # Les bords de la touche et de l'image sont indépendants.
            prev_t=times[j-1]
            def mark(label):
                r.setdefault(label+'_lo_ms',max(0,1000*(prev_t-upper)))
                r.setdefault(label+'_hi_ms',max(0,1000*(stamp-lower)))
            mark('first')
            if last is not None and 0<(n-last)%3000<1500:
                mark('movement');final_moving=True
            last=n
        # L'absence d'une image postérieure à l'échéance rend une expiration
        # incertaine. Les résultats observés restent disponibles individuellement.
        no_end=times[-1]+.25<end
        r.update(unknown_frames=unknown,other_frames=wrong,old_after_unknown=returns,gaps_over_250ms=gaps,
                 largest_gap_ms=round(largest*1000,3),end_censored=no_end)
        if gaps:r['outcome']='trou_de_capture'
        elif final and final!=target:r['outcome']='mauvaise_destination_finale'
        elif 'movement_hi_ms' in r and final==target and final_moving:r['outcome']='mouvement_observe'
        elif no_end:r['outcome']='fin_non_couverte'
        else:r['outcome']='mouvement_non_confirme'
    dump(out/'verdicts-film.json',result)
    summary=[]
    for phase in sorted({r['phase'] or '' for r in result}):
        group=[r for r in result if r['phase']==phase]
        good=[r for r in group if r['outcome']=='mouvement_observe']
        stat={'phase':phase,'commandes':len(group),'reussies':len(good),
              'sous_3s_mouvement':sum(r['movement_hi_ms']<3000 for r in good),
              'resurgences_candidates':sum(r.get('old_after_unknown',0) for r in group)}
        for label in ['first','movement']:
            values=sorted(r[label+'_hi_ms'] for r in good)
            if values:
                stat[label+'_mediane_ms']=statistics.median(values)
                stat[label+'_p95_succes_ms']=values[math.ceil(.95*len(values))-1]
                stat[label+'_pire_succes_ms']=values[-1]
        summary.append(stat)
    dump(out/'bilan-film.json',summary)
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('video',type=Path);p.add_argument('sortie',type=Path)
    a=p.parse_args();a.sortie.mkdir();export_clip(a.video,a.sortie,1)
