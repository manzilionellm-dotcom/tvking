"""Capturer la sortie une fois, à l’extérieur du lecteur. Aucune compression vidéo pendant le test."""
import csv
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
from threading import Condition, Event, Thread
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from optical_witness import key, motion, open_fixture, read_marker, screen
from android_film_clock import decode
from optical_film import clocked_key


def follows(previous, current):
    return previous is not None and current is not None and 0 < (current-previous)%3000 < 300


def first_pair(frames, target, start, stop):
    previous=None
    for before,end,channel,count in frames:
        if before<start or end>stop:continue
        if channel!=target:
            previous=None
        else:
            if follows(previous,count):return end
            previous=count
    return None


class ScreenSamples:
    def __init__(self, directory):
        self.directory=directory
        self.frames=[]
        self.changed=Condition()
        self.stop=Event()
        self.worker=Thread(target=self.capture,daemon=True)

    def capture(self):
        with (self.directory/'luminance.csv').open('w', newline='') as output:
            wr=csv.writer(output);wr.writerow(['start_s','end_s','luma_hex','status'])
            while not self.stop.is_set():
                before=time.monotonic(); status='inconnue'; ch=n=None; vals=bytes(30)
                try:
                    im=screen(); ch,n,box=read_marker(im)
                    if box:
                        x,y,r,b=box
                        # Centres des trente cellules déjà identifiées. Toute image non vérifiable est occultée.
                        gray=im.convert('L');vals=bytes(gray.getpixel((round(x+(r-x)*(k+.5)/30),round((y+b)/2))) for k in range(30))
                        if decode(vals)==(ch,n):status='mire'
                        else: ch=n=None;vals=bytes(30)
                except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):status='collecte-manquante'
                end=time.monotonic();wr.writerow([before,end,vals.hex(),status]);output.flush()
                with self.changed:
                    self.frames.append((before,end,ch,n));self.changed.notify_all()

    def wait_motion(self, target, since, deadline):
        with self.changed:
            previous=None;idx=max(0,len(self.frames)-12)
            while True:
                while idx<len(self.frames):
                    before,end,ch,n=self.frames[idx];idx+=1
                    if before<since:continue
                    if end>deadline:return None
                    if ch!=target:previous=None;continue
                    if follows(previous,n):return end
                    previous=n
                delay=deadline-time.monotonic()
                if delay<=0:return None
                self.changed.wait(min(delay,1))


def run(out,count):
    out.mkdir(parents=True,exist_ok=True)
    open_fixture(out);rows=[]
    if not motion(out,'avant','A',16,rows):
        key('KEYCODE_DPAD_CENTER')
        if not motion(out,'avant-avec-OK','A',28,rows):raise RuntimeError('Deux compteurs A requis avant la première touche')
    samples=ScreenSamples(out);samples.worker.start();cases=[]
    def save():
        (out/'trials.json').write_text(json.dumps(cases,indent=2))
    def emit(i,phase):
        target='B' if i%2==0 else 'A'
        code='KEYCODE_CHANNEL_DOWN' if target=='B' else 'KEYCODE_CHANNEL_UP'
        when=time.monotonic(); row=dict(number=i+1,phase=phase,key=code,target=target,dispatch_s=when,movement_upper_ms=None,status='dispatch-requested');row['from']='A' if target=='B' else 'B'
        row['origine_planifiee']=row['from'];row['origine_observee']=samples.frames[-1][2] if samples.frames else None
        cases.append(row);low,high=clocked_key(code);row.update(key_elapsed_min=low,key_elapsed_max=high,status='command-returned');save();return row
    try:
        (out/'horloge.json').write_text(json.dumps(dict(utc=datetime.now(timezone.utc).isoformat(),monotonic_s=time.monotonic(),method='pilotage hôte, bornes monotones Android pour chaque appui, un seul observateur externe')))
        time.sleep(1); planned=time.monotonic()
        for i in range(count):
            time.sleep(max(0,planned+5*i-time.monotonic()));emit(i,'spaced')
        time.sleep(max(0,planned+5*count-time.monotonic())); closed=time.monotonic()
        for i,row in enumerate(cases):
            until=cases[i+1]['dispatch_s'] if i+1<count else closed;row['window_end_s']=until
            end=first_pair(samples.frames,row['target'],row['dispatch_s'],until)
            row.update(status='verified-motion' if end else 'target-timeout',movement_upper_ms=round((end-row['dispatch_s'])*1000,3) if end else None)
        save()
        if not samples.wait_motion('A',closed,closed+35):raise RuntimeError('La base de départ de la rafale n’est pas confirmée')
        for i in range(count,count*2):
            row=emit(i,'burst');start=row['dispatch_s'];bound=start+9
            end=samples.wait_motion(row['target'],start,bound)
            if end:
                row.update(status='verified-motion',movement_upper_ms=round((end-start)*1000,3),window_end_s=end)
            else:
                row.update(status='target-timeout',window_end_s=bound)
                # Le timeout reste une erreur, même si la bonne chaîne avance ensuite.
                regained=samples.wait_motion(row['target'],bound,bound+30)
                row['mouvement_hors_delai_s']=regained
                if not regained:save();raise RuntimeError('Rafale interrompue : mauvaise destination ou reprise absente')
            save()
    finally:
        samples.stop.set();samples.worker.join(timeout=10);save()
        with (out/'samples.csv').open('w',newline='') as fd:
            wr=csv.writer(fd);wr.writerow(['trial','host_before_s','host_after_s','channel','counter']); index=0
            for before,end,ch,n in samples.frames:
                while index+1<len(cases) and before>=cases[index+1]['dispatch_s']:index+=1
                if cases and before>=cases[index]['dispatch_s'] and end<=cases[index].get('window_end_s',float('inf')):
                    wr.writerow([cases[index]['number'],before,end,ch,n])
        (out/'couverture.json').write_text(json.dumps(dict(commandes_planifiees=2*count,commandes_emises=len(cases),captures=len(samples.frames),seuil_expiration_rafale_s=9,intervalle_impose_s=5,fin=time.monotonic()),indent=2))


if __name__=='__main__':run(Path(sys.argv[1]),int(sys.argv[2]))
