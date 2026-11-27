"""Campagne supplémentaire sur émulateur lorsque le pilote valide le lecteur.

Exécuté par benchmark.py après calibration sur la chaîne courante. Le serveur
continue de publier ses segments pendant la coupure du seul chemin média.
"""
import csv
import json
import statistics
import subprocess
import time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor


def hour(out, adb, screenshot, channel):
    """Capture par fenêtres successives ; la couverture et les trous sont publiés."""
    from read_display_capture import extract
    outfile = out/'hour.json'
    spans = []
    start = time.monotonic()

    def analyse(local, index, span):
        path = out/f'display-{index:02d}.csv'
        try:
            extract(local, path)
            with path.open() as f:
                rows = list(csv.DictReader(f))
            valid = [r for r in rows if r['status']=='ok' and r['channel']==channel]
            times = [float(r['capture_pts_s']) for r in rows]
            intervals = [b-a for a,b in zip(times,times[1:]) if b>a]
            observed_hz = 1/statistics.median(intervals) if intervals else 0
            unknown = len(rows)-len(valid)
            missing = 0; prev = None; prevt = None; gaps=0
            for r,t in zip(rows,times):
                if prevt is not None and t-prevt>0.041:
                    gaps+=1
                    prev=None
                if r['status']=='ok' and r['channel']==channel:
                    n=int(r['source_frame'])
                    if prev is not None and n!=prev:
                        jump=(n-prev)%(1<<20)
                        if jump<(1<<19): missing+=jump-1
                        else: unknown+=1
                    prev=n
                else:
                    prev=None
                prevt=t
            span.update({'capture_frames':len(rows),'identified':len(valid),'unknown':unknown,
                         'typical_capture_hz':round(observed_hz,2),'capture_gaps_gt41ms':gaps,
                         'source_missing_in_contiguous_visible_intervals':missing,
                         'last_source_frame':valid[-1]['source_frame'] if valid else None,
                         'moving_confirmed':len({r['source_frame'] for r in valid})>1,
                         'start_pts_s':times[0],'end_pts_s':times[-1]})
            if path.exists():
                subprocess.run(['gzip','-f',str(path)],check=True)
        except (ValueError,subprocess.SubprocessError,OSError) as e:
            span['capture_error']=str(e)[-220:]
        finally:
            local.unlink(missing_ok=True)

    analyses=[]
    with ThreadPoolExecutor(max_workers=1) as pool:
        i=0
        while time.monotonic()-start<3600:
            i+=1
            secs=min(120,max(1,int(3600-(time.monotonic()-start))))
            part=f'/sdcard/novatube-bench-{i}.mp4'
            local=out.parent/f'screen-{i}.mp4'
            a=time.monotonic()
            result=subprocess.run(adb+['shell','screenrecord','--size','960x540','--bit-rate','2000000',
                                       '--time-limit',str(secs),part],capture_output=True,timeout=secs+22)
            e=time.monotonic()
            span={'index':i,'start_elapsed_s':round(a-start,3),'end_elapsed_s':round(e-start,3)}
            spans.append(span)
            if result.returncode==0:
                p=subprocess.run(adb+['pull',part,str(local)],capture_output=True,timeout=30)
                subprocess.run(adb+['shell','rm','-f',part],check=False)
                if p.returncode==0:analyses.append(pool.submit(analyse,local,i,span))
                else:span['capture_error']='capture file unavailable'
            else:
                span['capture_error']=result.stderr.decode('utf8','replace')[-200:]
            if e-a<min(3,secs):
                # Un codeur indisponible ne doit pas créer des milliers de coquilles.
                # Recueillir à cadence réduite une preuve de mouvement au fil de l'heure.
                observations=[]
                while time.monotonic()-start<3600:
                    ch,n,_,t=screenshot()
                    observations.append([round(t-start,3),ch,n])
                    (out/'hour-samples.json').write_text(json.dumps(observations))
                    time.sleep(min(5,max(0,3600-(time.monotonic()-start))))
                break
            outfile.write_text(json.dumps(spans,indent=2))
        for f in analyses:f.result()
    outfile.write_text(json.dumps(spans,indent=2))
    return spans


def recover(out,seconds,channel,screenshot):
    entries=[]
    rule=['OUTPUT','-o','lo','-p','tcp','--dport','18471','-j','REJECT']
    def sample(label,duration):
        deadline=time.monotonic()+duration
        while time.monotonic()<deadline:
            ch,n,b,e=screenshot()
            entries.append([label,ch,n,b,e])
    sample('before',4)
    subprocess.run(['sudo','iptables','-w','-I']+rule,check=True)
    begin=time.monotonic()
    try:
        sample('cut',seconds)
        with (out/f'cut-{seconds}-counter.txt').open('w') as f:
            subprocess.run(['sudo','iptables','-w','-L','OUTPUT','-n','-v','-x'],stdout=f,check=True)
    finally:
        subprocess.run(['sudo','iptables','-w','-D']+rule,check=True)
    restored=time.monotonic()
    sample('restored',32)
    with (out/f'cut-{seconds}.csv').open('w',newline='') as f:
        w=csv.writer(f);w.writerow(['phase','channel','source_frame','start_from_restore_s','end_from_restore_s'])
        w.writerows((phase,ch,n,b-restored,e-restored) for phase,ch,n,b,e in entries)
    out_rows=[r for r in entries if r[0]=='restored']
    upper=next((q[4]-restored for p,q in zip(out_rows,out_rows[1:]) if p[1]==q[1]==channel and
                0<(q[2]-p[2])%(1<<20)<(1<<19)),None)
    tail=[r for r in entries if r[0]=='cut' and r[1]==channel and r[4]>=restored-2]
    return {'cut_s':seconds,'observed_s':round(restored-begin,3),'motion_in_final_2s_of_cut':len({r[2] for r in tail})>1,
            'motion_after_restoration_upper_s':upper,'post_window_s':32}
