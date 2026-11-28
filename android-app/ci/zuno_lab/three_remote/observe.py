"""Suite télécommande sur A/B/C avec observation pixels et collecte des requêtes de mire."""
import csv
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from threading import Event,Thread
import time

sys.path.insert(1,str(Path(__file__).resolve().parents[1]))
from android_ui import visible_nodes
from optical_witness import key,open_fixture,motion,screen,read_marker
from optical_film import Recorder
from panel_device import observe as panel


def setup_playlist(out):
    panel.token=panel.api('POST','/api/v1/auth/login',{'email':'admin','password':os.environ['ZUNO_QA_PASS']})['token']
    panel.adb('shell','am','start','-n',panel.PACKAGE+'/com.example.tv_king.MainActivity')
    limit=time.monotonic()+95
    while not (items:=panel.api('GET','/api/v1/boxes/live')['items']) and time.monotonic()<limit:
        time.sleep(.5)
    if len(items)!=1:raise RuntimeError('Une seule box de laboratoire attendue')
    address=items[0]['mac']
    panel.api('POST','/api/v1/activate',{'mac':address,'plan':'lifetime'})
    panel.api('PUT','/api/v1/sources/'+address,{'sources':[{'type':'m3u','m3u_url':'http://127.0.0.1:18471/channels.m3u','label':'LAB ABC'}]})
    while time.monotonic()<limit:
        item=panel.api('GET','/api/v1/boxes/live')['items'][0]
        ack=item.get('last_applied') or {}
        if ack.get('kind')=='source':break
        time.sleep(.5)
    else: raise RuntimeError('Accusé des trois chaînes absent')
    (out/'source.json').write_text(json.dumps({'synthetic_channels':3,'order':ack['id']}))
    panel.adb('shell','am','force-stop',panel.PACKAGE)
    panel.adb('shell','am','start','-n',panel.PACKAGE+'/com.example.tv_king.MainActivity')
    time.sleep(4)


def run(out):
    out.mkdir();os.environ['ZUNO_PRELOADED_BY_PANEL']='yes';setup_playlist(out)
    open_fixture(out)
    origin=[]
    if not motion(out,'open','A',15,origin,True):
        key('KEYCODE_DPAD_CENTER')
        if not motion(out,'resume','A',30,origin,True):raise RuntimeError('Pas de mire A initiale')
    (out/'initial.json').write_text(json.dumps(origin))
    stop=Event()
    def capture():
        with (out/'observations.csv').open('w',newline='') as f:
            w=csv.writer(f);w.writerow(['start_s','end_s','ch','counter','ok'])
            while not stop.is_set():
                stamp=time.monotonic()
                try:ch,n,_=read_marker(screen());ok=True
                except (OSError,ValueError,RuntimeError,subprocess.SubprocessError):ch=n=None;ok=False
                w.writerow([stamp,time.monotonic(),ch,n,ok]);f.flush();stop.wait(.13)
    def rec(name,cmd):
        start=time.monotonic();ret=subprocess.run(['adb','shell',cmd],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=23)
        with (out/'touches.jsonl').open('a') as f:
            print(json.dumps(dict(scenario=name,start_s=start,end_s=time.monotonic(),code=ret.returncode,utc=datetime.now(timezone.utc).isoformat())),file=f)
    t=Thread(target=capture,daemon=True);t.start()
    filmer=Recorder(out/'films')
    try:
        try:filmer.start()
        except (OSError,RuntimeError,ValueError,subprocess.SubprocessError):pass
        for name,cmd,wait in [
            ('bref-relache','input keyevent KEYCODE_CHANNEL_DOWN',16),  # A vers B
            ('retablir-A','input keyevent KEYCODE_CHANNEL_UP',16),
            ('rafale-A-B-C','input keyevent KEYCODE_CHANNEL_DOWN KEYCODE_CHANNEL_DOWN',19),
            ('numerique-invalide','input keyevent KEYCODE_9 KEYCODE_9 KEYCODE_9 KEYCODE_9',12),
            ('appui-maintenu','input keyevent --longpress KEYCODE_CHANNEL_UP',18),
            ('retour','input keyevent KEYCODE_BACK',5),
            ('double-OK-grille','input keyevent KEYCODE_DPAD_CENTER KEYCODE_DPAD_CENTER',14),
            ('retour-apres-double-OK','input keyevent KEYCODE_BACK',6)
        ]:
            rec(name,cmd);time.sleep(wait)
            try:
                nodes=visible_nodes(panel.PACKAGE)
                labels=set()
                for label,*_ in nodes:
                    labels.update(re.findall(r'\bmire [abc]\b|\b(?:guide|channels|settings|live)\b',label.lower()))
                with (out/'ecrans.jsonl').open('a') as f:
                    print(json.dumps({'scenario':name,'time_s':time.monotonic(),'labels':sorted(labels)}),file=f)
            except (OSError,subprocess.SubprocessError):pass
    finally:
        stop.set();t.join(18);complete=filmer.finish()
        (out/'capture.json').write_text(json.dumps({'film_complete':complete}))
if __name__=='__main__':run(Path(sys.argv[1]))
