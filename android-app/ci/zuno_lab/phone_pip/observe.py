"""Vérifier le mode de fenêtre PiP d'Android et le mouvement avant et après HOME."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from optical_witness import APK_PACKAGE, motion, key, open_fixture, read_marker, screen


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
    return dict(pinned=pinned,window_frames=bounds,package_notification_records=len(notices),
                pid=adb('shell','pidof','-s',APK_PACKAGE).strip())


def run(out):
    out.mkdir();rows=[];events=[]
    def record(action,**data):
        events.append(dict(action=action,host_monotonic=time.monotonic(),**data))
        (out/'telephonie.json').write_text(json.dumps(events,indent=2))
    os.environ['ZUNO_PRELOADED_BY_PANEL']='yes'
    open_fixture(out)
    if not motion(out,'lecture','A',18,rows,True):
        key('KEYCODE_DPAD_CENTER')
        if not motion(out,'confirmation','A',18,rows,True):
            record('lecture_initiale_non_confirmee',**state())
            raise RuntimeError('La mire doit être visible avant HOME')
    baseline=state();record('lecture_initiale',**baseline)
    key('KEYCODE_HOME')
    deadline=time.monotonic()+15
    guest=None
    while time.monotonic()<deadline:
        guest=state();record('apres_HOME',**guest)
        if guest['pinned']:break
        time.sleep(.4)
    counts=[]
    if guest['pinned']:
        for _ in range(12):
            im=screen()
            for x,y,r,b in guest['window_frames']:
                if not (0<=x<r<=im.width and 0<=y<b<=im.height):continue
                crop=im.crop((x,y,r,b))
                ch,n,box=read_marker(crop)
                if ch=='A':
                    counts.append(n)
                    if box:crop.crop(box).save(out/f'pip-mire-{n}.png')
                    break
            if len(counts)>1 and counts[-1]!=counts[-2]:break
            time.sleep(.22)
    record('compteurs_dans_fenetre_pip',values=counts)
    adb('shell','am','start','-a','android.intent.action.MAIN','-c','android.intent.category.LAUNCHER','-n',APK_PACKAGE+'/com.example.tv_king.MainActivity')
    seen=motion(out,'retour','A',25,rows,True)
    resumed=state();record('retour_activite',motion=bool(seen),same_pid=baseline['pid']==resumed['pid'],**resumed)
    (out/'compteurs.json').write_text(json.dumps(rows))
    if not guest['pinned'] or resumed['pinned'] or not seen:
        raise RuntimeError('Parcours PiP incomplet, conserver les états observés')
if __name__=='__main__':
    run(Path(sys.argv[1]))
