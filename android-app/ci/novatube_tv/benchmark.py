"""Pilote sur émulateur TV. Télémétrie visuelle indépendante des trois applications."""
import argparse, csv, io, json, math, os, statistics, subprocess, sys, time
from pathlib import Path
from PIL import Image
from read_display_capture import decode
from pilot_observer import frame, sparse_hour


parser = argparse.ArgumentParser()
parser.add_argument('output', type=Path)
parser.add_argument('--physical-serial')
args = parser.parse_args()
out = args.output
physical = bool(args.physical_serial)
adb = ['adb', '-s', args.physical_serial or 'emulator-5554']
planned = 100 if physical else 50
def screenshot(name=None):
    start=time.monotonic()
    image,raw=frame(adb,out,start,console_fallback=not physical)
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
result={'region':os.environ.get('REGION_OBS','unknown'),'kind':'Android TV physique' if physical else 'Android TV emulator, 1536 MiB',
        'method':'host input dispatch to confirmation of two successive decoded screen markers; upper bound',
        'attempts':[],'probe':[]}
current,_,data=motion(12)
result['onboarding_motion']={'channel':current,'samples':data}
persist();screenshot('onboarding-result')
if not current: sys.exit('Aucune première image animée identifiée après import')
if physical and current != 'A':
    sys.exit('Ouvrir Mire A en plein écran avant de commencer la calibration.')
if not physical and os.environ.get('BENCH_SKIP_VERIFIED_ZAPS') == '1':
    result['zap_status']='déjà mesuré par la campagne référencée'
    result['zap_source_run']=os.environ.get('BENCH_PRIOR_ZAPS_RUN','')
else:
    # Pendant la calibration, choisir l'action TV qui change effectivement de chaîne.
    selected=None
    for keycode in ['KEYCODE_CHANNEL_DOWN','KEYCODE_DPAD_DOWN','KEYCODE_CHANNEL_UP','KEYCODE_DPAD_UP']:
        target='B' if current=='A' else 'A'
        key(keycode);ch,end,raw=motion(8,target)
        result['probe'].append({'key':keycode,'expected':target,'seen':ch,'samples':raw})
        if ch: selected=keycode;current=ch;break
        current,_,_=motion(4)
        if not current:
            key('KEYCODE_BACK')
            current,_,_=motion(4)
        if not current:break
    persist();screenshot('tuning-result')
    # Essais complets lorsque le pilote visuel a identifié le canal.
    end_keys = {'KEYCODE_CHANNEL_DOWN': 'KEYCODE_CHANNEL_UP', 'KEYCODE_CHANNEL_UP':'KEYCODE_CHANNEL_DOWN',
                'KEYCODE_DPAD_DOWN':'KEYCODE_DPAD_UP','KEYCODE_DPAD_UP':'KEYCODE_DPAD_DOWN'}
    result['key']=selected
    if selected:
        backwards=end_keys[selected]
        target='B' if current=='A' else 'A'
        key(backwards)
        returned,end,raw=motion(10,target)
        result['probe'].append({'key':backwards,'expected':target,'seen':returned,'samples':raw})
        if returned:
            current=returned
        else:
            current,_,_=motion(4)
            backwards=selected
        commands=(selected,backwards)
        fail_streak=0
        for attempt in range(1,planned+1):
            if not current or fail_streak >= 3:break
            target='B' if current=='A' else 'A'
            start=time.monotonic();key(commands[(attempt-1)%2]);ch,end,raw=motion(12,target)
            result['attempts'].append({'n':attempt,'expected':target,'seen':ch,
                'input_s':round(start-zero,6),'upper_bound_s':None if end is None else round(end-start,3),'samples':raw})
            persist()
            if not ch:
                fail_streak+=1
                current,_,_=motion(4)
            else:
                current=ch
                fail_streak=0
        print('ZAPS',len(result['attempts']),flush=True)
persist()
if physical:
    # Les tentatives sans mouvement confirmé restent dans le dénominateur.
    attempts = result['attempts']
    measured = sorted(row['upper_bound_s'] for row in attempts if row['upper_bound_s'] is not None)
    rank = math.ceil(0.95 * planned)
    result['zap_summary'] = {
        'planned': planned, 'attempted': len(attempts), 'confirmed': len(measured),
        'under_3_s': sum(delay < 3 for delay in measured),
        'p95_s': measured[rank - 1] if len(attempts) == planned and len(measured) >= rank else None,
    }
    persist()
    if len(attempts) != planned:
        sys.exit('Série interrompue, tentatives brutes conservées.')
    current, _, _ = motion(12)
    if not current:
        sys.exit('Mire en mouvement absente avant la lecture continue.')
    result['reading'] = sparse_hour(out, adb, screenshot, current, duration=4800)
    # Vérifier le sens du compteur et conserver toute capture illisible.
    rows = [json.loads(line) for line in (out / 'hour-samples.jsonl').read_text().splitlines()]
    forward = sum(a['channel'] == b['channel'] == current
                  and 0 < (b['frame'] - a['frame']) % (1 << 20) < (1 << 19)
                  for a, b in zip(rows, rows[1:]))
    result['forward_pairs'] = forward
    result['all_sampled_pairs_moved'] = len(rows) > 1 and forward == len(rows) - 1
    persist()
    sys.exit(0)
if os.environ.get('BENCH_ZAPS_ONLY') == '1':
    attempts=result['attempts']
    result['complete_zap_campaign']=len(attempts)==50
    persist()
    if len(attempts)!=50:
        sys.exit('Campagne de zaps incomplète, observations conservées')
    sys.exit(0)
current,_,raw=motion(8)
if not current: sys.exit('Aucun mouvement vérifié avant la lecture continue')
from extended import hour,recover
result['hour_channel']=current;persist()
result['cuts']=[]
for seconds in (5,15,60):
    channel,_,_=motion(6)
    if not channel:
        result['cuts'].append({'cut_s':seconds,'status':'bloqué avant coupure'});persist();continue
    result['cuts'].append(recover(out,seconds,channel,screenshot))
    persist()
# Une reprise après coupure peut échouer. Avant le test long, rétablir
# une lecture sur l'autre mire via un zap explicite si nécessaire.
current,_,_=motion(10)
if not current:
    key('KEYCODE_CHANNEL_DOWN')
    current,_,_=motion(15)
if not current:
    sys.exit('Aucun mouvement vérifié après les coupures')
result['hour_channel']=current;persist()
if os.environ.get('BENCH_HOUR_MODE','sampled')=='sampled':
    sparse_hour(out,adb,screenshot,current)
else:
    hour(out,adb,screenshot,current)
print('Fin des essais exécutables',flush=True)
