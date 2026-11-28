"""Réglages et carnet d'arrêt du vrai paquet LAB, sur les seuls identifiants de test."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from android_ui import visible_nodes
from optical_witness import key, tap, open_fixture, motion, APK_PACKAGE
from visible_launch import LABELS, screen_evidence
from zuno_ui_path import normalized


def adb(*cmd):
    return subprocess.run(['adb',*cmd],capture_output=True,text=True,timeout=18).stdout.strip()


def evidence(out,step,**data):
    with (out/'actions.jsonl').open('a') as file:
        print(json.dumps(dict(step=step,time_s=time.monotonic(),utc=datetime.now(timezone.utc).isoformat(),**data)),file=file)


def native_exit(pid):
    system=adb('shell','dumpsys','activity','exit-info',APK_PACKAGE)
    entries=[]
    for record in system.split('ApplicationExitInfo #')[1:]:
        process=re.search(r'\bpid=(\d+)',record)
        reason=re.search(r'\breason=(\d+) \(([^)]+)\)',record)
        if reason and process and process[1]==pid:
            entries.append({'reason':int(reason[1]),'reason_name':reason[2][:60]})
    return entries


def read_screen():
    focus=[]
    try:
        nodes=visible_nodes(APK_PACKAGE,focus)
    except (OSError,subprocess.SubprocessError):
        nodes=[]
    return nodes,[normalized(x) for x in focus]


def observe(out):
    out.mkdir()
    os.environ['ZUNO_PRELOADED_BY_PANEL']='yes'
    try:
        open_fixture(out)
        confirmed=bool(motion(out,'avant-fermeture','A',15,[],True))
        evidence(out,'avant-fermeture',moving_a=confirmed)
    except (RuntimeError,OSError,ValueError,subprocess.SubprocessError) as exc:
        evidence(out,'avant-fermeture',moving_a=False,error=type(exc).__name__)
    pid=adb('shell','pidof','-s',APK_PACKAGE)
    if not pid.isdigit():
        raise RuntimeError('Aucun processus avant le redémarrage de test')
    adb('shell','am','force-stop',APK_PACKAGE)
    time.sleep(1)
    if adb('shell','pidof','-s',APK_PACKAGE):
        raise RuntimeError('Arrêt explicite non confirmé')
    evidence(out,'arret-demande',pid=pid,exit_info=native_exit(pid))
    adb('shell','am','start','-n',APK_PACKAGE+'/com.example.tv_king.MainActivity')
    time.sleep(5)
    current=adb('shell','pidof','-s',APK_PACKAGE)
    evidence(out,'nouveau-processus',previous_pid=pid,pid=current,native_previous=native_exit(pid))
    if not current.isdigit() or current==pid:
        raise RuntimeError('Nouvel identifiant de processus non confirmé')
    settings={'settings','reglages'}
    black={'black box','boite noire'}
    entered=False
    for i in range(8):
        nodes,_=read_screen()
        if any('parental' in normalized(t) or 'ambient' in normalized(t) for t,*_ in nodes):
            entered=True;break
        point=next(((x,y) for t,x,y,k in nodes if any(normalized(l) in settings for l in t.splitlines())),None)
        if point:
            tap(*point);evidence(out,'reglages',access='controle visible');time.sleep(1);continue
        key('KEYCODE_BACK' if i in (1,4) else 'KEYCODE_DPAD_RIGHT')
        time.sleep(.7)
    if not entered:
        nodes,_=read_screen()
        entered=any('settings' in normalized(t) or 'reglages' in normalized(t) for t,*_ in nodes)
        evidence(out,'reglages-non-identifie-par-rubriques',presence_libelle=entered)
    LABELS['journal']={'black','box','technical','journal','refresh','copy','boîte','noire','actualiser','copier'}
    for i in range(27):
        nodes,focus=read_screen()
        targets=[(x,y) for t,x,y,k in nodes if any(normalized(l) in black for l in t.splitlines())]
        focused=any(any(t in lab for t in black) for lab in focus)
        if targets and (focused or len(targets)>=2):
            # Exiger ensuite l'écran de lecture. Une carte latérale ne prouve pas la sélection.
            key('KEYCODE_DPAD_CENTER');time.sleep(1)
            nodes,_=read_screen()
            body='\n'.join(t for t,*_ in nodes)
            page=any(word in body for word in ('technical log','dernière action','last action','journal technique','previous session','refresh','actualiser'))
            evidence(out,'OK-sur-rubrique',rank=i,visible_detail=page)
            if page:
                summary={
                    'last_action_label':bool(re.search(r'last action|dernière action',body)),
                    'version_119_lab':'119-lab' in body,
                    'time_label':bool(re.search(r'when:|le :|date :|quand',body)),
                    'memory_label':bool(re.search(r'memory|mémoire|pss|rss',body)),
                    'android_exit_words':sorted(set(re.findall(r'user_requested|user_stopped|exit_self|unknown|low_memory|anr|crash_native',body))),
                    'unredacted_fixture_urls':bool(re.search(r'https?://(?:127\.0\.0\.1|10\.0\.2\.2):18[0-9]{3}/',body)),
                    'previous_pid_reason':native_exit(pid)}
                evidence(out,'journal-apres-redemarrage',**summary)
                try:screen_evidence(out,'journal')
                except (OSError,ValueError,RuntimeError,subprocess.SubprocessError):pass
                key('KEYCODE_DPAD_DOWN');key('KEYCODE_PAGE_DOWN')
                return
        key('KEYCODE_DPAD_RIGHT')
        time.sleep(.35)
    raise RuntimeError('Le journal redémarré n’a pas été reconnu après navigation')
if __name__=='__main__':
    observe(Path(sys.argv[1]))
