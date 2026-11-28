"""Mesure des coupures réelles du chemin HTTP du LAB, avec sa sonde d'origine séparée."""
import csv
from datetime import datetime,timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import threading
import time
from urllib.request import urlopen

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from optical_witness import motion, read_marker, screen, key, open_fixture


def save(path,obj):
    t=path.with_suffix('.tmp');t.write_text(json.dumps(obj,indent=2));t.replace(path)


def canary(out, stop):
    while not stop.is_set():
        now=time.monotonic();valid=False;n=0
        try:
            with urlopen('http://127.0.0.1:18472/A/index.m3u8',timeout=4) as response:
                seg=re.findall(rb'(?m)^seg[0-9]+\.ts$',response.read())[-1].decode()
            with urlopen('http://127.0.0.1:18472/A/'+seg,timeout=4) as response:
                packet=response.read(8192)
            n=len(packet);valid=n==8192 and packet[0]==0x47
        except (OSError,IndexError,ValueError):
            pass
        with (out/'source.jsonl').open('a') as f:
            print(json.dumps(dict(at_s=now,end_s=time.monotonic(),valid=valid,bytes=n)),file=f)
        stop.wait(3)


def run(folder,arm):
    folder.mkdir();os.environ['ZUNO_PRELOADED_BY_PANEL']='yes'
    stop=threading.Event()
    probe=threading.Thread(target=canary,args=(folder,stop),daemon=True);probe.start()
    try:
        open_fixture(folder)
        samples=[]
        if not motion(folder,'ouverture','A',12,samples,True):
            key('KEYCODE_DPAD_CENTER')
            if not motion(folder,'confirmation','A',18,samples,True):
                raise RuntimeError("Mouvement initial non confirmé")
        events=[]
        for i,length in enumerate((5,15,60,60,15,5),1):
            if not motion(folder,'avant-'+str(i),'A',30,[],True):
                raise RuntimeError('Origine visuelle absente avant la prochaine coupure')
            begin=time.monotonic();resume=begin+length
            save(arm,dict(start_s=begin,resume_s=resume))
            row=dict(index=i,seconds=length,start_s=begin,resume_s=resume,utc=datetime.now(timezone.utc).isoformat())
            events.append(row);save(folder/'essais.json',events)
            prev=None;last_change=None;longest=0;longest_upper_gap=0;after=0;end_last=None
            limit=resume+80
            with (folder/f'pixels-{i}.csv').open('w',newline='') as raw:
                writer=csv.writer(raw);writer.writerow(['start_s','end_s','channel','counter','received'])
                while time.monotonic()<limit:
                    before=time.monotonic()
                    try:
                        im=screen();ch,n,box=read_marker(im);ok=True
                    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError):
                        ch=n=None;ok=False
                    end=time.monotonic()
                    writer.writerow([before,end,ch,n,ok]);raw.flush()
                    if end_last:longest_upper_gap=max(longest_upper_gap,end-end_last)
                    end_last=before
                    if ch=='A':
                        if n!=prev:
                            step=prev is not None and 0<(n-prev)%3000<500
                            if before>=resume and step:
                                after+=1
                                if 'movement_after_s' not in row:
                                    row['movement_after_s']=end-resume
                            last_change=end
                        elif last_change:
                            longest=max(longest,before-last_change)
                        prev=n
                    else:
                        prev=None;last_change=None
                    if after>=2 and end>=resume+8:break
                    time.sleep(.12)
            row.update(longest_equal_sample_span_s=longest,max_two_sample_bound_s=longest_upper_gap,
                       recovery_movement_observed=after>=2)
            http=folder.parent/'reseau'/'http.jsonl'
            rows=[json.loads(line) for line in http.read_text().splitlines() if line.endswith('}')]
            client=[x for x in rows if x['path'].startswith('/A/') and begin<=x['request_s']]
            row['fault_responses']=sum(x['blocked'] for x in client)
            req=[x for x in client if x['request_s']>=resume]
            ts=[x for x in req if x['path'].endswith('.ts') and x['valid'] and x['wrote_response']]
            row['first_request_after_s']=min((x['request_s']-resume for x in req),default=None)
            row['first_ts_write_after_s']=min((x['write_end_s']-resume for x in ts),default=None)
            save(folder/'essais.json',events)
        if not all(x['recovery_movement_observed'] for x in events):
            raise RuntimeError('Des reprises ne sont pas confirmées dans le délai')
    finally:
        stop.set();probe.join(timeout=10)
if __name__=='__main__':
    run(Path(sys.argv[1]),Path(sys.argv[2]))
