"""Observateur tolérant à une perte ADB. La mire et l'application continuent.
Les périodes sans capture restent des lacunes dans le rapport."""
import io
import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

from PIL import Image


def command(args,timeout):
    try:
        p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
        return p.returncode,p.stdout,p.stderr.decode(errors='replace')[:160]
    except (subprocess.TimeoutExpired,OSError) as err:
        return -1,b'',type(err).__name__


def frame(adb,out,start,console_fallback=True):
    def validate(data):
        if not data.startswith(b'\x89PNG\r\n\x1a\n'):raise ValueError('Image PNG absente')
        im=Image.open(io.BytesIO(data))
        im.load()
        return im, data

    code,data,err=command(adb+['exec-out','screencap','-p'],4)
    if code==0:
        try:
            return validate(data)
        except (OSError,ValueError) as e:
            err=type(e).__name__
    note={'host_monotonic':start,'guest_rc':code,'guest_error':err}
    if console_fallback:
        with tempfile.TemporaryDirectory(prefix='novatube-screen-') as folder:
            rc,_,msg=command(adb+['emu','screenrecord','screenshot',folder],5)
            note.update(console_rc=rc,console_error=msg)
            for f in Path(folder).glob('*.png'):
                try:
                    image,raw=validate(f.read_bytes())
                    note['result']='console'
                    with (out/'capture-events.jsonl').open('a') as log:
                        log.write(json.dumps(note)+'\n')
                    return image,raw
                except (OSError,ValueError):
                    continue
    note['result']='missing'
    with (out/'capture-events.jsonl').open('a') as log:
        log.write(json.dumps(note)+'\n')
    return None,b''


def sparse_hour(out,adb,screenshot,channel,duration=3600):
    """Une heure murale et deux observateurs indépendants, sans encodeur dans le guest."""
    start=time.monotonic()
    deadline=start+duration
    package=os.getenv('BENCH_PACKAGE','com.sevenmotion.novatube.tv')
    samples=out/'hour-samples.jsonl'
    states=out/'hour-process.jsonl'
    events=out/'hour-cadence.jsonl'
    samples.touch();states.touch();events.touch()
    next_health=start
    seen=set()
    known_pid=None
    def health(initial=False):
        nonlocal known_pid,seen
        rc,raw,err=command(adb+['shell','pidof',package],3)
        pid=raw.decode(errors='replace').strip().split()
        pid=pid[0] if pid and pid[0].isdigit() else None
        if (pid and known_pid and pid!=known_pid):
            seen.clear()
        if pid:known_pid=pid
        record={'elapsed_s':round(time.monotonic()-start,3),'pid':pid,'query_rc':rc}
        if rc:record['error']=err
        if pid:
            rc,raw,err=command(adb+['logcat','-d','-t','6000','-v','epoch','--pid='+pid,'-s','flutter:I','NovaTubeQA:I','AndroidRuntime:E'],5)
            record['logcat_rc']=rc
            lines=raw.decode(errors='replace').splitlines()
            for line in lines:
                m=re.search(r'window_ms=(\d+) rendered=(\d+) dropped=(\d+)',line)
                fatal='FATAL EXCEPTION' in line
                if not m and not fatal:continue
                if line in seen:continue
                seen.add(line)
                if initial:continue
                item={'elapsed_sample_s':record['elapsed_s'],'pid':pid,'device_epoch':line.strip().split()[0]}
                if m:
                    item.update(window_ms=int(m[1]),rendered=int(m[2]),dropped=int(m[3]))
                if fatal:item['event']='fatal_exception'
                with events.open('a') as f:f.write(json.dumps(item)+'\n')
        with states.open('a') as f:f.write(json.dumps(record)+'\n')
    health(initial=True)
    next_health=start+20
    while time.monotonic()<deadline:
        if time.monotonic()>=next_health:
            health()
            next_health=time.monotonic()+20
        ch,n,b,e=screenshot()
        with samples.open('a') as f:
            f.write(json.dumps({'start_s':round(b-start,3),'end_s':round(e-start,3),'channel':ch,'frame':n})+'\n')
        time.sleep(max(0,min(2,deadline-time.monotonic())))
    health()
    rows=[json.loads(l) for l in samples.read_text().splitlines()]
    good=[r for r in rows if r['channel']==channel]
    pids=[json.loads(l).get('pid') for l in states.read_text().splitlines()]
    wins=[j for l in events.read_text().splitlines() if 'window_ms' in (j:=json.loads(l))]
    transitions=sum(1 for a,b in zip(rows,rows[1:]) if a['channel']==b['channel']==channel and a['frame']!=b['frame'])
    output={'method':'sampled_composited_video_and_native_cadence','wall_s':round(time.monotonic()-start,3),
            'target':channel,'screens':len(rows),'identified':len(good),'unobserved_or_wrong_channel':len(rows)-len(good),
            'moving_pairs':transitions,'max_gap_between_identified_s':round(max([rows[-1]['end_s']-good[-1]['end_s'],good[0]['start_s']]+[b['end_s']-a['end_s'] for a,b in zip(good,good[1:])]),3) if good else None,
            'pids':sorted(set(p for p in pids if p)),'pid_checks':len(pids),'pid_unavailable':pids.count(None),
            'native_windows':len(wins),'native_window_ms':sum(w['window_ms'] for w in wins),'native_rendered':sum(w['rendered'] for w in wins) if wins else None,
            'native_dropped':sum(w['dropped'] for w in wins) if wins else None}
    (out/'hour-sampled.json').write_text(json.dumps(output,indent=2))
    return output
