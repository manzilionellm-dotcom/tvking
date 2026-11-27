"""Pilote sur émulateur TV. Télémétrie visuelle indépendante des trois applications."""
import csv, io, json, os, statistics, subprocess, sys, time
from pathlib import Path
from PIL import Image
from read_display_capture import decode


out=Path(sys.argv[1])
adb=['adb','-s','emulator-5554']
def screenshot(name=None):
    start=time.monotonic()
    raw=subprocess.check_output(adb+['exec-out','screencap','-p'],timeout=15)
    if name: (out/(name+'.png')).write_bytes(raw)
    image=Image.open(io.BytesIO(raw)).convert('L')
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
result={'region':os.environ.get('REGION_OBS','unknown'),'kind':'Android TV emulator, 1536 MiB',
        'method':'host input dispatch to confirmation of two successive decoded screen markers; upper bound',
        'attempts':[],'probe':[]}
current,_,data=motion(12)
result['onboarding_motion']={'channel':current,'samples':data}
persist();screenshot('onboarding-result')
if not current: sys.exit('Aucune première image animée identifiée après import')
# Pendant la calibration, choisir l'action TV qui change effectivement de chaîne.
selected=None
for keycode in ['KEYCODE_CHANNEL_DOWN','KEYCODE_DPAD_DOWN','KEYCODE_CHANNEL_UP','KEYCODE_DPAD_UP']:
    target='B' if current=='A' else 'A'
    key(keycode);ch,end,raw=motion(8,target)
    result['probe'].append({'key':keycode,'expected':target,'seen':ch,'samples':raw})
    if ch: selected=keycode;current=ch;break
    key('KEYCODE_BACK')
    current,_,_=motion(4)
    if not current:break
persist();screenshot('tuning-result')
if not selected: sys.exit('Pas de commande de zap étalonnée sur les deux canaux')
result['key']=selected
for attempt in range(1,7):
    target='B' if current=='A' else 'A'
    start=time.monotonic();key(selected);ch,end,raw=motion(12,target)
    result['attempts'].append({'n':attempt,'expected':target,'seen':ch,
        'upper_bound_s':None if end is None else round(end-start,3),'samples':raw})
    persist()
    if not ch:break
    current=ch
print('PILOT',str([(r['n'],r['seen'],r['upper_bound_s']) for r in result['attempts']]),flush=True)
