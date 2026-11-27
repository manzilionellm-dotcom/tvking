"""Pilote sur émulateur TV. Télémétrie visuelle indépendante des trois applications."""
import csv, io, json, os, statistics, subprocess, sys, time
from pathlib import Path
from PIL import Image
from read_display_capture import decode
from pilot_observer import frame, sparse_hour


out=Path(sys.argv[1])
adb=['adb','-s','emulator-5554']
def screenshot(name=None):
    start=time.monotonic()
    image,raw=frame(adb,out,start)
    if image is None:return None,None,start,time.monotonic()
    if name: (out/(name+'.png')).write_bytes(raw)
    image=image.convert('L')
    w,h=image.size
    # Le marqueur couvre la moitié centrale d'une image 16:9.
    # Les variantes couvrent plein écran et une barre Android de 24–48 pixels.
    for top, bottom in ((0,0),(0,24),(0,48),(24,0),(24,24),(48,0),(48,48)):
        vh=min(h-top-bottom,w*9/16);vw=vh*16/9
        x=(w-vw)/2;y=top+(h-top-bottom-vh)/2
        values=[image.getpixel((round(x+vw*(496+32*i)/1920),round(y+vh*650/1080))) for i in range(30)]
        ch,n=decode(values)
        if ch:return ch,n,start,time.monotonic()
    return None,None,start,time.monotonic()
def motion(seconds, target=None):
    deadline=time.monotonic()+seconds;prev=None;raw=[]
    while time.monotonic()<deadline:
        ch,n,t,e=screenshot()
        raw.append([ch,n,round(t-zero,3),round(e-zero,3)])
        if ch and (target is None or target==ch) and prev and prev[0]==ch and 0<(n-prev[1])%(1<<20)<(1<<19):
            return ch,e,raw
        prev=(ch,n) if ch else None
    return None,None,raw
def key(code):
    subprocess.run(adb+['shell','input','keyevent',code],check=True,timeout=5)
def persist():
    (out/'pilot.json').write_text(json.dumps(result,indent=2))
zero=time.monotonic()
result={'region':os.environ.get('REGION_OBS','unknown'), 'kind':f"Android TV emulator, {os.environ['RAM_MIB']} MiB",
        'method':'host input dispatch to confirmation of two successive decoded screen markers; upper bound',
        'attempts':[],'probe':[]}
current,_,data = motion(18, target="A")
result['onboarding_motion'] = {'channel':current,'samples':data}
result['hour_channel'] = current
result['cuts'] = []
persist()
screenshot('onboarding-result')
if current != 'A':
    sys.exit("La mire A animée n'a pas été vérifiée en plein écran")
from freeze_long import observe
observe(out,screenshot,current,int(os.environ["FREEZE_DURATION"]))
