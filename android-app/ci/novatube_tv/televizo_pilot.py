"""Exercise the normal free playlist and channel UI of the official Televizo APK."""
import io
import json
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image
from read_display_capture import decode
from pilot_observer import frame, verify_local_fixture

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
PKG = 'com.ottplay.ottplay'
URL = 'http://127.0.0.1:18471/channels.m3u'
NAME = 'Nova QA'
ADB = ['adb', '-s', 'emulator-5554']
history = []

def run(*args, check=True, binary=False):
    cmd = [*ADB, *args]
    for attempt in range(3):
        try:
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    timeout=50, text=not binary)
        except subprocess.TimeoutExpired:
            message = 'adb timeout'
            result = None
        else:
            if result.returncode == 0:
                return result.stdout
            err = result.stderr.decode(errors='replace') if binary else result.stderr
            message = err.strip()
        with (OUT/'televizo-adb-diagnostics.txt').open('a') as log_file:
            log_file.write(f'attempt={attempt+1} command={args[:2]} error={message[-350:]}\n')
        # A transport error can affect the transient shell, IME, or one
        # screenshot. Give adbd time to reconnect without relaunching the app.
        transient = result is None or re.search(
            r'offline|not found|closed|transport|protocol fault|broken pipe|device.*disconnect',
            message, re.I)
        if not transient or attempt == 2:
            if not check:
                return b'' if binary else ''
            raise RuntimeError(f'ADB {args[:2]} failed: {message[-250:]}')
        subprocess.run([*ADB,'get-state'],capture_output=True,timeout=7,check=False)
        try:
            subprocess.run([*ADB,'wait-for-device'],capture_output=True,timeout=20,check=False)
        except subprocess.TimeoutExpired:
            pass
        time.sleep(1)

def shell(*args, **kwargs):
    return run('shell', *args, **kwargs).strip()

def log(action):
    history.append({'time': time.monotonic(), 'action': action})
    (OUT / 'televizo-actions.json').write_text(json.dumps(history, indent=2))

def screenshot(label):
    for _ in range(2):
        image, raw = frame(ADB, OUT, time.monotonic())
        if image is not None:
            (OUT / ('televizo-' + label + '.png')).write_bytes(raw)
            return
    log('capture unavailable during setup: ' + label)


def snapshot(i):
    xml_path = '/sdcard/televizo-pilot-ui.xml'
    shell('rm', '-f', xml_path)
    shell('uiautomator', 'dump', xml_path, check=False)
    xml = shell('cat', xml_path, check=False)
    if not xml.startswith('<?xml') and '<hierarchy' not in xml:
        return []
    (OUT / f'televizo-{i:02}.xml').write_text(xml)
    root = ET.fromstring(xml)
    return list(root.iter('node'))

def desc(n):
    return ' '.join(filter(None, [n.get('text','').strip(),n.get('content-desc','').strip()]))

def point(n):
    x1,y1,x2,y2 = map(int,re.findall(r'\d+',n.get('bounds','')))
    return (x1+x2)//2,(y1+y2)//2

def tap(n,reason):
    x,y = point(n)
    log(reason)
    shell('input','tap',str(x),str(y))
    time.sleep(.65)

def find(nodes,pattern):
    for n in nodes:
        if n.get('enabled')!='false' and re.fullmatch(pattern,desc(n),flags=re.I):
            return n
    return None

def fill(n,value,reason):
    tap(n,reason)
    shell('input','keycombination','113','29',check=False)
    shell('input','text',value.replace(' ','%s'))
    ime = shell('dumpsys','input_method',check=False)
    if 'mInputShown=true' in ime or 'isInputViewShown=true' in ime:
        shell('input','keyevent','KEYCODE_BACK',check=False)

def save(nodes):
    for n in nodes:
        rid=n.get('resource-id','').rsplit('/',1)[-1]
        if n.get('enabled')!='false' and (
                re.fullmatch(r'save|done|apply|check',desc(n),re.I)
                or re.fullmatch(r'(?:action|menu|btn|button|iv|ib)?_?(?:save|apply|done|check|confirm)',rid,re.I)):
            tap(n,'save local fixture playlist')
            return True
    # The playlist screen also uses an unlabeled toolbar action. Select the
    # rightmost clickable toolbar control, constrained to this form only.
    rectangles=[point(n) for n in nodes if re.fullmatch(r'\[\d+,\d+\]\[\d+,\d+\]',n.get('bounds',''))]
    if not rectangles: return False
    right=max(int(re.findall(r'\d+',n.get('bounds',''))[2]) for n in nodes if n.get('bounds'))
    bottom=max(int(re.findall(r'\d+',n.get('bounds',''))[3]) for n in nodes if n.get('bounds'))
    candidates=[n for n in nodes if n.get('clickable')=='true' and n.get('enabled')!='false'
                and point(n)[0] >= right*.76 and point(n)[1] <= bottom*.145]
    if not candidates:return False
    tap(max(candidates,key=lambda n:point(n)[0]),'confirm using playlist toolbar')
    return True

def open_fullscreen():
    # This free version opens in a split-screen preview. Android's accessibility
    # dump can wait forever for an idle view while a live video is rendering.
    # The official player's expand button was measured on the recorded preview
    # UI. Only press it once the exact channel marker is visible in that pane.
    deadline=time.monotonic()+45
    last_tap=0
    while time.monotonic()<deadline:
        # Un screencap PNG incomplet peut avoir un statut ADB nul. Le même
        # observateur vérifié que pour les zaps relit l’image via la console.
        picture,raw=frame(ADB,OUT,time.monotonic())
        if picture is None:
            time.sleep(.3)
            continue
        image=picture.convert('L')
        w,h=image.size
        for t,b in ((0,0),(0,24),(0,48),(24,0),(24,24),(48,0),(48,48)):
            vh=min(h-t-b,w*9/16);vw=vh*16/9
            x=(w-vw)/2;y=t+(h-t-b-vh)/2
            ch,num=decode([image.getpixel((round(x+vw*(496+32*i)/1920),
                        round(y+vh*650/1080))) for i in range(30)])
            if ch=='A':
                (OUT/'televizo-player-fullscreen.png').write_bytes(raw)
                log(f'full-screen marker verified A {num}')
                return
        xs=[round(w*.5*(496+32*i)/1920) for i in range(30)]
        for y in range(round(h*.40),round(h*.57),2):
            ch,num=decode([image.getpixel((x,y)) for x in xs])
            if ch=='A':
                (OUT/'televizo-player-preview.png').write_bytes(raw)
                if time.monotonic()-last_tap>5:
                    log(f'expand left preview with confirmed marker A {num}')
                    shell('input','tap',str(round(w*765/1920)),str(round(h*1062/1080)))
                    last_tap=time.monotonic()
                break
        time.sleep(.5)
    screenshot('player-unconfirmed')
    raise SystemExit('Mire A sélectionnée, passage en plein écran non vérifié.')

verify_local_fixture(ADB, OUT)
component=shell('cmd','package','resolve-activity','--brief','-a','android.intent.action.MAIN',
                '-c','android.intent.category.LEANBACK_LAUNCHER',PKG).splitlines()[-1]
if not component.startswith(PKG+'/'):
    component=PKG+'/.MainActivity'
shell('am','start','-W','-n',component)
log('launch official Televizo')
imported=False
refreshes=0
for i in range(46):
    time.sleep(.45)
    nodes=snapshot(i)
    if not nodes: continue
    if i<3 or i%3==0:screenshot(f'{i:02}')
    texts=[desc(n) for n in nodes if desc(n)]
    (OUT / f'televizo-{i:02}-labels.txt').write_text('\n'.join(texts))
    # Respect optional choices: no trial, subscription, account, or ad opt-in.
    button=find(nodes,r'do not consent|do not allow|don.t allow|reject all|not now|skip')
    if button is not None:
        tap(button,'dismiss optional prompt')
        continue
    if any(re.search(r'terms (?:and conditions|of (?:service|use))|end.user licen[sc]e|licen[sc]e agreement|by (?:continuing|using).+agree', text, re.I) for text in texts):
        screenshot('conditions-inattendues')
        raise SystemExit("Une nouvelle acceptation est demandée. Essai arrêté.")
    warning = find(nodes,r'warning')
    confirm_save = find(nodes,r'save')
    if warning is not None and confirm_save is not None and any(
            'not responsible for your playlists' in item.lower() for item in texts):
        tap(confirm_save,'confirm saving the supplied fixture playlist')
        imported=True
        continue
    if imported and any('playlist not found' in item.lower() for item in texts):
        refresh = find(nodes, r'update playlist')
        if refresh is not None and refreshes < 3:
            verify_local_fixture(ADB, OUT)
            tap(refresh, 'retry fixture import after verifying the local route')
            refreshes += 1
            time.sleep(2)
            continue
    chan=find(nodes,r'Mire A(?:\s.*)?')
    if chan is not None:
        tap(chan,'play Mire A')
        open_fullscreen()
        sys.exit(0)
    button=find(nodes,r'all channels|all broadcasts|all videos|all groups')
    if button is not None:
        tap(button,'open all channels')
        continue
    fields=[n for n in nodes if n.get('class','').endswith('EditText') and n.get('enabled')!='false']
    form=any(re.search(r'playlist name|link to the playlist|new m3u playlist',item,re.I) for item in texts)
    if not fields:
        for pattern in (r'new M3U playlist',r'M3U playlist',r'create playlist'):
            button = find(nodes,pattern)
            if button is not None:
                tap(button,'create M3U playlist')
                break
        if button is not None:continue
    if fields and (form or len(fields)>=2):
        if len(fields)>=2:
            if fields[0].get('text','')!=NAME:
                fill(fields[0],NAME,'type fixture name')
                continue
            if fields[1].get('text','')!=URL:
                fill(fields[1],URL,'type fixture URL')
                continue
        elif 'playlist name' in ' '.join(texts).lower() and fields[0].get('text','')!=NAME:
            fill(fields[0],NAME,'type playlist name')
            continue
        if save(nodes):
            imported=True
            time.sleep(1)
            continue
    if imported:
        for pattern in [r'Nova QA',r'QA',r'Unsorted|Ungrouped|General|Other|Live']:
            button=find(nodes,pattern)
            if button is not None:
                tap(button,'open fixture list or group')
                break
        else: button=None
        if button is not None: continue
    screenshot('stopped')
    log('waiting for a recognized standard UI action')
screenshot('blocked')
raise SystemExit('Televizo onboarding did not reach the controlled channel. See saved UI evidence.')
