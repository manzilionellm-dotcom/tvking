"""Contre-épreuve avec ou sans encodeur invité, sur le même APK diagnostic."""
import argparse
import csv
import json
import os
from pathlib import Path
import sys
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from optical_witness import clocked_key,motion
from optical_film import Recorder,score


def run(folder,encode):
    folder.mkdir()
    shots=[];cases=[]
    def persist():
        (folder/'trials.json').write_text(json.dumps(cases,indent=2))
        with (folder/'samples.csv').open('w',newline='') as dest:
            writer=csv.writer(dest);writer.writerow(['trial','host_before_s','host_after_s','channel','counter']);writer.writerows(shots)
    rec=Recorder(folder/'films-android') if encode else None
    try:
        if not motion(folder,'initial','A',35,shots,True):
            raise RuntimeError('Le diagnostic doit ouvrir directement la mire A en mouvement')
        if rec:rec.start()
        for i in range(12):
            old,target,button=('A','B','KEYCODE_CHANNEL_DOWN') if i%2==0 else ('B','A','KEYCODE_CHANNEL_UP')
            mark=time.monotonic()
            trial=dict(number=i+1,phase='spaced' if i<6 else 'burst',key=button,target=target,dispatch_s=mark,status='requested')
            trial['from']=old
            cases.append(trial);persist()
            before,after=clocked_key(button);trial.update(key_elapsed_min=before,key_elapsed_max=after)
            end=motion(folder,str(i+1),target,30,shots,i<2)
            if end is None:
                trial['status']='target-timeout'
                raise RuntimeError('Cible absente pendant la fenêtre indépendante de 30 s')
            trial.update(status='verified-motion',movement_upper_ms=round((end-mark)*1000,3))
            persist()
            if i<6:time.sleep(max(0,mark+5-time.monotonic()))
    finally:
        persist()
        if rec:
            complete=rec.finish()
            if complete:score(rec.out,cases)
if __name__=='__main__':
    a=argparse.ArgumentParser();a.add_argument('folder',type=Path);a.add_argument('mode',choices=['film','sans-encodeur']);p=a.parse_args()
    run(p.folder,p.mode=='film')
