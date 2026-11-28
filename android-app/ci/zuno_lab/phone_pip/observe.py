"""Vérifier le mode de fenêtre PiP d'Android et le mouvement avant et après HOME."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from optical_witness import APK_PACKAGE, key, observe_ui, tap
from hub_remote import live_row_visible
from zuno_ui_path import control
from mobile_marker import find_marker
from PIL import Image
import io


def adb(*args):
    return subprocess.run(['adb',*args],capture_output=True,text=True,timeout=18).stdout


def state():
    scenes=adb('shell','dumpsys','activity','activities')
    # Android 30 nomme Stack le parent : exiger l'activité exacte dans son bloc PINNED.
    chunks=re.split(r'(?m)(?=^\s*(?:RootTask|Stack) #\d+)',scenes)
    pinned=False
    for block in chunks:
        for line in block.splitlines():
            if ('mode=pinned' in line.lower() or 'windowingmode=pinned' in line.lower()) and (APK_PACKAGE in line or ('RootTask #' in line or 'Stack #' in line) and APK_PACKAGE+'/' in block[:6000]):
                pinned=True
    wm=adb('shell','dumpsys','window','windows')
    bounds=[]
    for section in re.split(r'(?m)^\s*Window #\d+ ',wm):
        if APK_PACKAGE+'/' not in section.split('\n',1)[0]:continue
        for label in ('mFrame=','frame='):
            m=re.search(r'(?<![a-zA-Z])'+label+r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]',section)
            if m:bounds.append(tuple(map(int,m.groups())))
    notification=adb('shell','dumpsys','notification')
    notices=[line for line in notification.splitlines() if 'NotificationRecord(' in line and 'pkg='+APK_PACKAGE in line]
    tops=[l for l in scenes.splitlines() if re.search(r'topResumedActivity|mResumedActivity|ResumedActivity:',l)]
    return dict(pinned=pinned,foreground=any(APK_PACKAGE+'/' in l for l in tops),window_frames=bounds,package_notification_records=len(notices),
                pid=adb('shell','pidof','-s',APK_PACKAGE).strip())


def fixture_requests():
    path=Path(os.environ['RUNNER_TEMP'])/'fixture.log'
    counts={}
    if not path.exists():return counts
    for ch,file,status in re.findall(r'"GET /([AB])/(index\.m3u8|seg\d+\.ts) HTTP/[^"]+" (\d{3})',path.read_text(errors='replace')):
        group='manifeste' if file.startswith('index') else 'segment'
        name=f'{ch}_{group}_{status}';counts[name]=counts.get(name,0)+1
    return counts


def diagnostics(guest):
    pid=guest.get('pid','')
    if not pid.isdigit():return {'source':fixture_requests()}
    lines=adb('logcat','--pid='+pid,'-d','-t','1000')
    layers=adb('shell','dumpsys','SurfaceFlinger','--list')
    return dict(source=fixture_requests(),surface_application=any(APK_PACKAGE in l for l in layers.splitlines()),
                surface_video_nommee=any(APK_PACKAGE in l and ('SurfaceView' in l or 'TextureView' in l) for l in layers.splitlines()),
                mimes_media_observes=sorted(set(re.findall(r'(?i)\b(?:audio/(?:mp4a-latm|aac|mpeg)|video/(?:avc|hevc))\b',lines))),
                trace_codec=bool(re.search(r'MediaCodec|ACodec|CCodec',lines)))


def screen_android():
    # Sur 46095766298 la console donne 1080×1920 lorsque l'activité et les
    # entrées utilisent 1920×1080. Le screencap Android suit sa rotation.
    p=subprocess.run(['adb','exec-out','screencap','-p'],capture_output=True,timeout=9,check=True)
    return Image.open(io.BytesIO(p.stdout)).convert('RGB')


def grid_or_hub(out):
    ns,ts,size,image,focus=observe_ui(out,'mobile-configuration',retry=True)
    if image is None:return 'attendre',None
    def point(nodes,words,label):return control(nodes,words,size,[label])
    # Chaque contrôle doit provenir d'un seul capteur et appartenir à la bonne colonne.
    for nodes,words in ((ns,[]),([],ts)):
        n=[v for v in nodes if .22*size[0]<v[1]<.62*size[0]]
        w=[v for v in words if .22*size[0]<v[1]<.62*size[0]]
        a,b=point(n,w,'mire a'),point(n,w,'mire b')
        if a and b and b[1]-a[1]>.025*size[1]:return 'grille',a
        if live_row_visible(nodes,words,size):
            a=control(nodes,words,size,['live','direct'])
            if a and 0<a[0]<size[0] and 0<a[1]<size[1]:return 'hub',a
    return 'attendre',None


def run(out):
    out.mkdir(); events=[]
    def record(action,**fields):
        events.append(dict(action=action,host_monotonic=time.monotonic(),**fields))
        (out/'telephonie.json').write_text(json.dumps(events,indent=2))
    def telemetry(stage):
        s=state();record(stage,**s,**diagnostics(s));return s
    def moving(stage,limit,mode):
        deadline=time.monotonic()+limit;previous=None
        while time.monotonic()<deadline:
            guest=state()
            if mode=='pip' and (not guest['pinned'] or not guest['window_frames']):
                record(stage,etat='fenetre_pip_non_confirmee',**guest);previous=None;time.sleep(.3);continue
            if mode=='plein' and (guest['pinned'] or not guest['foreground']):
                record(stage,etat='activite_hors_premier_plan',**guest);previous=None;time.sleep(.3);continue
            try:im=screen_android()
            except (OSError,ValueError,subprocess.SubprocessError) as exc:
                record(stage,etat='capture_indisponible',classe=type(exc).__name__);previous=None;continue
            bounds=guest['window_frames']
            if not bounds and mode=='plein':bounds=[[0,0,im.width,im.height]]
            now=time.monotonic();candidates=[]
            for box in bounds:
                x,y,r,b=box
                if not (0<=x<r<=im.width and 0<=y<b<=im.height):continue
                # Une prétendue fenêtre PiP pratiquement pleine ne qualifie aucune petite fenêtre.
                if mode=='pip' and (r-x)*(b-y)>.55*im.width*im.height:continue
                if mode=='plein' and (r-x)*(b-y)<.55*im.width*im.height:continue
                v=find_marker(im.crop(box))
                if v:candidates.append((v,box))
            if candidates:
                (ch,n,geometry),box=candidates[0]
                record(stage,sortie=im.size,rectangle=box,chaine=ch,compteur=n,centre_pas=geometry)
                if ch=='A' and previous:
                    prev,tm=previous
                    if 0<(n-prev)%3000<300 and now-tm<12:return True
                previous=(n,now) if ch=='A' else None
            else:
                record(stage,sortie=im.size,rectangles=bounds,etat='aucun_grand_code')
                previous=None
        return False
    telemetry('avant_navigation')
    limit=time.monotonic()+100; entered=False;last_hub=0
    while time.monotonic()<limit:
        s=state()
        if not s['foreground']:
            adb('shell','am','start','-n',APK_PACKAGE+'/com.example.tv_king.MainActivity');time.sleep(1);continue
        where,point=grid_or_hub(out)
        if where=='grille':
            tap(*point);record('toucher_ligne_mire_A',point=point);entered=True;break
        if where=='hub' and time.monotonic()-last_hub>10:
            tap(*point);record('toucher_direct',point=point);last_hub=time.monotonic()
        time.sleep(.7)
    if not entered:raise RuntimeError('Grille A/B non identifiée')
    if not moving('avant_HOME',15,'plein'):
        where,point=grid_or_hub(out)
        if where=='grille':
            # Réessayer par la ligne identifiée, aucune touche envoyée à un lecteur inconnu.
            tap(*point);record('seconde_selection_ligne_A',point=point)
        if not moving('confirmation_avant_HOME',16,'plein'):
            telemetry('lecture_initiale_non_confirmee');raise RuntimeError('Mire mobile absente avant HOME')
    baseline=telemetry('lecture_initiale')
    key('KEYCODE_HOME')
    pip_motion=moving('apres_HOME',22,'pip')
    telemetry('fin_fenetre_pip')
    adb('shell','am','start','-a','android.intent.action.MAIN','-c','android.intent.category.LAUNCHER','-n',APK_PACKAGE+'/com.example.tv_king.MainActivity')
    resumed=moving('retour_activite',25,'plein')
    final=telemetry('etat_final')
    same=bool(baseline['pid']) and baseline['pid']==final['pid']
    record('synthese',mouvement_avant=True,mouvement_dans_fenetre_pip=pip_motion,mouvement_au_retour=resumed,meme_processus=same)
    if not (pip_motion and resumed and same and not final['pinned']):
        raise RuntimeError('Parcours PiP incomplet, consulter les relevés')
if __name__=='__main__':
    run(Path(sys.argv[1]))
