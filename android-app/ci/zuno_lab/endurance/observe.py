"""Observation optique des pixels émulés, indépendante du serveur et du lecteur."""
from collections import deque
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import threading
import time
from urllib.request import urlopen

from PIL import Image
from read_display_capture import decode
from origin import append, utc

PKG='com.sevenmotion.tv.seven_tv.lab.diagnostic'
CYCLE=1<<20

def adb(*args,timeout=6):
    return subprocess.check_output(['adb',*args],stderr=subprocess.DEVNULL,timeout=timeout)


def region(image):
    im=image.convert('L'); w,h=im.size
    for top,bottom in [(0,0),(0,24),(0,48),(24,0),(24,24),(48,0),(48,48)]:
        vh=min(h-top-bottom,w*9/16); vw=vh*16/9
        x=(w-vw)/2; y=top+(h-top-bottom-vh)/2
        row=[im.getpixel((round(x+vw*(496+32*i)/1920),round(y+vh*650/1080))) for i in range(30)]
        ch,n=decode(row)
        if ch:
            # Partager uniquement la bande de compteur vérifiée.
            band=Image.new('L',(30,1));band.putdata(row)
            return ch,n,band.resize((300,30),Image.Resampling.NEAREST)
    return None,None,None


def run_shell(out,label,args,rx):
    try:
        raw=adb(*args,timeout=8).decode(errors='replace')
        out[label]=re.findall(rx,raw,re.M)[:180]
    except (OSError, subprocess.SubprocessError) as e:
        out[label]={'inaccessible':type(e).__name__}


def forensic(out,pid):
    if not pid or not pid.isdigit(): return
    state={'utc':utc(),'pid':pid}
    for label,cmd,pattern in [
        ('mem',['shell','dumpsys','meminfo',pid],r'(TOTAL (?:PSS|RSS)|Native Heap|Dalvik Heap)\s*:?\s*(\d+)'),
        ('threads',['shell','cat','/proc/'+pid+'/status'],r'^(Threads|VmRSS|FDSize):\s*(\d+)'),
        ('exit',['shell','dumpsys','activity','exit-info',PKG],r'\b(reason|status|pss|rss)=(\d+)'),
        ('media',['logcat','-d','--pid='+pid,'-v','epoch','-t','1200'],r'^(\d+\.\d+).*?\b(MediaCodec|renderedFirstFrame|droppedFrames|ExoPlaybackException|Source error|ANR|OutOfMemoryError)\b'),
        ('native_frames',['shell','debuggerd','-b',pid],r'(?m)^\s*#(\d+)\s+pc\s+([0-9a-fA-F]+)\s+.*?/(lib[A-Za-z0-9_.-]+\.so)\b'),
        ('codec_counters',['shell','dumpsys','media.metrics'],r'(?i)\b(frames[-_.]?(?:rendered|dropped|decoded)|buffer[-_.]?(?:duration|size)|framesRendered|framesDropped)[=: ]+(\d+)'),
        ('sqlite',['shell','dumpsys','dbinfo',PKG],r'(PAGECACHE_OVERFLOW|MEMORY_USED|PAGECACHE_USED|PAGESIZE)\s*[:=]?\s*(\d+)')]:
        run_shell(state,label,cmd,pattern)
    (out/'forensic.json').write_text(json.dumps(state,indent=2))


def canary(out,stop):
    while not stop.is_set():
        row={'utc':utc(),'monotonic_s':time.monotonic()}
        try:
            with urlopen('http://127.0.0.1:18471/A/index.m3u8',timeout=3) as r:
                names=re.findall(rb'(?m)^s\d{9}\.ts$',r.read())
            if len(names)<2: raise ValueError('deux segments requis')
            fragments=[]
            for name in names[-2:]:
                with urlopen('http://127.0.0.1:18471/A/'+name.decode(),timeout=4) as r:
                    data=r.read()
                if len(data)<188 or data[0]!=0x47: raise ValueError('segment TS invalide')
                fragments.append(dict(name=name.decode(),bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
            row['segments']=fragments
        except Exception as e: row['failure']=type(e).__name__
        append(out/'canary.jsonl',row)
        stop.wait(10)


def observe(out,duration):
    stop=threading.Event()
    can=threading.Thread(target=canary,args=(out,stop),daemon=True)
    can.start()
    ring=deque(maxlen=16)
    boot=time.monotonic();deadline=boot+110
    t0=last_t=repeated_from=last_counter=None
    longest=maxgap=0.; total=valid=missed=gaps=0
    first_fault=None
    unreadable_from=None
    last_pid=None
    worker=None
    period=1.
    next_due=boot
    while True:
        if t0 is None and time.monotonic()>deadline: break
        time.sleep(max(0,next_due-time.monotonic()))
        start=time.monotonic(); ch=n=band=None
        capture='ok'
        try:
            raw=adb('exec-out','screencap','-p',timeout=3)
            with Image.open(io.BytesIO(raw)) as im: ch,n,band=region(im)
        except (ValueError,subprocess.SubprocessError,OSError):
            capture='failed'
        t=time.monotonic()
        if total%10==0:
            try:
                pid=adb('shell','pidof',PKG).decode().strip()
                last_pid=pid if pid.isdigit() else None
            except (OSError,subprocess.SubprocessError): last_pid=None
        gap=t-last_t if last_t is not None else 0.
        if t0 is not None:
            maxgap=max(gap,maxgap)
            if gap>2.5: gaps+=1
        prev=last_counter
        if gap>2.5 or ch!='A' or n!=prev: repeated_from=t
        repeat=t-repeated_from if ch=='A' and repeated_from is not None else 0.
        if t0 is None and ch=='A' and prev is not None and gap<=2.5 and 0<(n-prev)%CYCLE<CYCLE//2:
            t0=t; deadline=t+duration
        state=dict(sample=total,utc=utc(),start_s=start,end_s=t,relative_s=(t-t0 if t0 is not None else None),
                   ch=ch,counter=n,capture=capture,pid=last_pid)
        append(out/'observations.jsonl',state)
        ring.append((total,t,band))
        if t0 is not None:
            valid+=int(ch=='A')
            missed+=int(capture=='failed')
            longest=max(longest,repeat)
            if ch=='A': unreadable_from=None
            elif unreadable_from is None: unreadable_from=t
            unreadable=(t-unreadable_from) if ch!='A' and unreadable_from is not None else 0.
            if first_fault is None and (repeat>=4 or unreadable>=4):
                first_fault=dict(**state,kind='repetition' if repeat>=4 else ('panne_collecte' if capture=='failed' else 'image_non_identifiee'))
                (out/'premier-incident.json').write_text(json.dumps(first_fault,indent=2))
                images=[]
                elapsed_ms=[]
                previous_time=None
                for index,when,b in ring:
                    images.append(b if b is not None else Image.new('L',(300,30),128))
                    if previous_time is not None:
                        elapsed_ms.append(max(10,round((when-previous_time)*1000)))
                    previous_time=when
                    if b is not None: b.save(out/f'marqueur-{index:05d}.png')
                if images:
                    images[0].save(out/'film-marqueurs.gif',save_all=True,append_images=images[1:],
                                   duration=elapsed_ms+[1000],loop=0)
                worker=threading.Thread(target=forensic,args=(out,last_pid),daemon=True);worker.start()
        last_counter=n if ch=='A' else None
        if total%15==0:
            state_net={}
            # Chiffres agrégés de l'interface virtuelle Android, aucune adresse du réseau.
            run_shell(state_net,'network',['shell','cat','/proc/net/dev'],
                      r'^\s*(eth0|wlan0|wlan1|lo):\s*(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)')
            append(out/'process-network.jsonl',dict(utc=utc(),pid=last_pid,**state_net))
        total+=1; last_t=t
        if t0 is not None and t>=deadline: break
        next_due=max(start+period,t)
    stop.set();can.join(12)
    if worker: worker.join(58)
    completed=t0 is not None and (last_t-t0)>=duration
    summary=dict(utc_end=utc(),timed=completed,requested_s=duration,
                 wall_observed_after_motion_s=last_t-t0 if t0 is not None else 0.,
                 samples=total,correct_after_motion=valid,capture_failures_after_motion=missed,
                 longest_readable_sampled_repetition_lower_s=longest,max_gap_s=maxgap,
                 gaps_over_2_5_s=gaps,first_incident=first_fault)
    (out/'summary.json').write_text(json.dumps(summary,indent=2))
    if not completed: raise SystemExit('Durée non atteinte ou deux compteurs croissants non reconnus.')


if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('out',type=Path)
    p.add_argument('--seconds',type=int,required=True)
    a=p.parse_args()
    if not 1<=a.seconds<=86400: p.error('Durée invalide')
    observe(a.out,a.seconds)
