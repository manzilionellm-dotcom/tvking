"""TiviMate free TV UI, pre-launched, on the disposable Android 11 emulator."""
import csv
import io
import json
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

ADB = ['adb', '-s', 'emulator-5554']
URL = 'http://127.0.0.1:18471/channels.m3u'


def command(args, timeout=15):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)


def key(code):
    command(ADB + ['shell', 'input', 'keyevent', str(code)])


def normalized(s):
    return ' '.join(re.findall(r'[a-z0-9]+', s.lower()))


def snapshot(folder, step):
    prefix = folder / f'ui-{step:02d}'
    png = prefix.with_suffix('.png')
    png.write_bytes(command(ADB + ['exec-out', 'screencap', '-p']).stdout)
    nodes = []
    try:
        command(ADB + ['shell', 'uiautomator', 'dump', '/sdcard/tivimate-pilot.xml'], timeout=8)
        data = command(ADB + ['exec-out', 'cat', '/sdcard/tivimate-pilot.xml']).stdout
        prefix.with_suffix('.xml').write_bytes(data)
        for el in ET.fromstring(data).iter('node'):
            bounds = list(map(int, re.findall(r'\d+', el.get('bounds',''))))
            if len(bounds) != 4 or bounds[2] <= bounds[0] or bounds[3] <= bounds[1]:
                continue
            pos = ((bounds[0]+bounds[2])//2, (bounds[1]+bounds[3])//2)
            for label in [el.get('text',''), el.get('content-desc','')]:
                if label and el.get('enabled') != 'false':
                    nodes.append((normalized(label), pos, 'label'))
            if el.get('class','').endswith('EditText') and el.get('enabled') != 'false':
                nodes.append((normalized(el.get('text','')), pos, 'editor'))
    except (ET.ParseError, subprocess.TimeoutExpired):
        pass
    # Some Leanback views draw the label themselves.
    tsv = command(['tesseract',str(png),'stdout','--psm','11','tsv']).stdout.decode('utf8','replace')
    lines = {}
    for row in csv.DictReader(io.StringIO(tsv), delimiter='\t'):
        if not row.get('text','').strip(): continue
        group = tuple(row[k] for k in ['block_num','par_num','line_num'])
        x,y,w,h = (int(row[k]) for k in ['left','top','width','height'])
        lines.setdefault(group,[]).append((row['text'],x,y,x+w,y+h))
    for words in lines.values():
        x=(min(w[1] for w in words)+max(w[3] for w in words))//2
        y=(min(w[2] for w in words)+max(w[4] for w in words))//2
        nodes.append((normalized(' '.join(w[0] for w in words)),(x,y),'ocr'))
    return nodes


def onboard(folder):
    folder.mkdir(parents=True,exist_ok=True)
    history=[]
    repeats=Counter()
    submitted=False
    channel_attempts=0
    for step in range(36):
        nodes=snapshot(folder,step)
        labels={v for v,_,_ in nodes}
        def find(*wanted):
            for word in wanted:
                for value,pos,kind in nodes:
                    if value == normalized(word) and kind != 'editor':
                        return pos
            return None
        editor=next((pos for text,pos,kind in nodes if kind=='editor'),None)
        has_url=any('18471' in v for v in labels)
        action=None
        pos=None
        if channel_attempts and not find('Mire B','All channels','Add playlist','Playlist type','EPG URL'):
            # Parent verifies first moving video independently.
            (folder/'ui-actions.json').write_text(json.dumps(history,indent=2))
            return
        if find('Failed to add playlist','An error has occurred while processing the playlist'):
            raise RuntimeError('TiviMate reported playlist import failure')
        if find('Mire A'):
            action,pos='open Mire A',find('Mire A')
            channel_attempts+=1
        elif editor and not submitted:
            action='type synthetic playlist URL'
            command(ADB+['shell','input','tap',str(editor[0]),str(editor[1])])
            time.sleep(.25)
            command(ADB+['shell','input','text',URL])
            time.sleep(.25)
            key(66)
            submitted=True
        elif editor and submitted and has_url:
            pos=find('OK','Done','Next','Save','Enter')
            if pos: action='confirm URL'
            else: action='dismiss keyboard'; key(4)
        else:
            choices=(('dismiss tutorial',('Got it','Understood','Close')),
                     ('playlist type',('M3U playlist','M3U URL')),
                     ('add playlist',('Add playlist','Add your playlist')),
                     ('confirm wizard',('Done','Next','Continue','Finish')),
                     ('open channels',('All channels','TV guide','Channels','Live TV')))
            if not submitted:
                choices=(choices[0],('enter URL',('Enter URL','Playlist URL','Paste playlist URL')),choices[1],choices[2],choices[3],choices[4])
            else:
                choices=(choices[0],choices[3],('confirm entry',('OK','Save')),choices[4],choices[2])
            for action_name,words in choices:
                pos=find(*words)
                if pos:
                    action=action_name
                    break
        if action:
            signature=(action,tuple(sorted(v for v in labels if len(v)<56)))
            repeats[signature]+=1
            if repeats[signature]>4:
                raise RuntimeError('No UI progress at '+action)
            if pos:
                if repeats[signature]>=2 and action not in ('dismiss tutorial',):
                    key(23)
                else:
                    command(ADB+['shell','input','tap',str(pos[0]),str(pos[1])])
        else:
            action='wait for UI'
            signature=('wait',tuple(sorted(labels)))
            repeats[signature]+=1
            if repeats[signature]>5:
                raise RuntimeError('Unrecognized TiviMate screen: '+str(sorted(labels))[:160])
        history.append({'step':step,'action':action,'labels':sorted(labels),'point':pos})
        (folder/'ui-actions.json').write_text(json.dumps(history,indent=2))
        time.sleep(1.2 if channel_attempts else .75)
    raise RuntimeError('TiviMate onboarding did not reach a channel before the step limit')


if __name__=='__main__':
    onboard(Path(sys.argv[1]))
