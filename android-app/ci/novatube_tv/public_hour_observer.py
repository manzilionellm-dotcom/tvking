"""Observe playback independently of either Android application's instrumentation."""
import datetime
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import threading
import time

from pilot_observer import frame
from read_display_capture import decode

OUT = Path(sys.argv[1])
PACKAGE = os.environ['BENCH_PACKAGE']
ADB = ['adb', '-s', 'emulator-5554']
DURATION = int(os.environ.get('PUBLIC_OBSERVATION_SECONDS', '3600'))
CLOCK = time.monotonic
PERIOD = 5
CYCLE = 3000  # The encoded 120-second test clip restarts at 25 fps.


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def append(name, payload):
    with (OUT / name).open('a') as f:
        f.write(json.dumps(payload, separators=(',', ':')) + '\n')


def save(name, payload):
    tmp = OUT / (name + '.tmp')
    tmp.write_text(json.dumps(payload, indent=2))
    tmp.replace(OUT / name)


def shell(*args):
    try:
        p = subprocess.run(ADB + list(args), stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=5, check=False)
        return p.stdout.decode(errors='replace').strip() if p.returncode == 0 else ''
    except (subprocess.TimeoutExpired, OSError):
        return ''


def read_screen():
    image, _ = frame(ADB, OUT, CLOCK())
    if image is None:
        return None, None
    image = image.convert('L')
    w, h = image.size
    for top, bottom in ((0,0), (0,24), (0,48), (24,0), (24,24), (48,0), (48,48)):
        vh = min(h-top-bottom, w*9/16)
        vw = vh*16/9
        x, y = (w-vw)/2, top+(h-top-bottom-vh)/2
        row = [image.getpixel((round(x+vw*(496+32*i)/1920), round(y+vh*650/1080))) for i in range(30)]
        channel, number = decode(row)
        if channel:
            return channel, number
    return None, None


def canary(stop, start):
    while not stop.is_set():
        row = {'s': round(CLOCK()-start, 3)}
        conn = http.client.HTTPConnection('127.0.0.1', 18471, timeout=3)
        try:
            conn.request('GET', '/A/index.m3u8?observer=host')
            res = conn.getresponse()
            playlist = res.read().decode()
            segments = re.findall(r'(?m)^([A-Za-z0-9_-]+\.ts)\s*$', playlist)
            row['playlist'] = res.status
            if res.status == 200 and segments:
                last = segments[-1]
                conn.request('GET', '/A/'+last+'?observer=host')
                res = conn.getresponse()
                data = res.read()
                row.update(segment_http=res.status, segment=last, bytes=len(data),
                           sync_byte=data[:1] == b'\x47', digest=hashlib.sha256(data).hexdigest())
        except (OSError, ValueError, http.client.HTTPException) as exc:
            row['error'] = type(exc).__name__
        finally:
            conn.close()
        append('canary.jsonl',row)
        stop.wait(15)


def main():
    deadline = CLOCK()+50
    previous = None
    while CLOCK()<deadline:
        ch, n = read_screen()
        if ch=='A' and previous is not None and n!=previous:
            break
        previous = n if ch=='A' else None
        time.sleep(.5)
    else:
        raise SystemExit('Correct moving channel A was not visible before timing.')
    start = CLOCK()
    started = stamp()
    stop = threading.Event()
    probe = threading.Thread(target=canary,args=(stop,start),daemon=True)
    probe.start()
    save('start.json',{'utc':started,'duration_s':DURATION,'fixture':'direct 10.0.2.2:18471, HLS 1080p25','sample_period_s':PERIOD,'public_package':PACKAGE})
    i=0
    while True:
        target = min(i*PERIOD,DURATION)
        time.sleep(max(0, start+target-CLOCK()))
        sample_start = CLOCK()
        ch, n = read_screen()
        t = CLOCK()-start
        rec = {'i':i, 's':round(t,3), 'screen_capture_s':round(CLOCK()-sample_start,3),'channel':ch,'frame':n}
        if i%6==0:
            pid=shell('shell','pidof',PACKAGE)
            rec['pid'] = pid if re.fullmatch(r'[0-9]+',pid) else None
            if not pid:
                shell('reconnect','offline')
        append('optical.jsonl',rec)
        if i>=6 and not (OUT/'early.json').exists():
            save('early.json',{'elapsed_s':round(t,3),'last_channel':ch,'last_frame':n})
        if i%60==0:
            print(f'observation {i}, {t:.1f} s, channel {ch}, frame {n}',flush=True)
        if target>=DURATION:
            break
        i=max(i+1,int((CLOCK()-start)//PERIOD)+1)
    stop.set()
    probe.join(timeout=12)
    rows=[json.loads(line) for line in (OUT/'optical.jsonl').read_text().splitlines()]
    canaries=[json.loads(line) for line in (OUT/'canary.jsonl').read_text().splitlines()]
    valid=lambda r:r['channel']=='A' and r['frame'] is not None
    pairs=[(a,b) for a,b in zip(rows,rows[1:]) if valid(a) and valid(b)]
    moved=sum(0 < (b['frame']-a['frame'])%CYCLE < CYCLE//2 for a,b in pairs)
    between=[b['s']-a['s'] for a,b in zip(rows,rows[1:])]
    pids=[r['pid'] for r in rows if 'pid' in r]
    save('summary.json',{'utc_start':started,'utc_end':stamp(),'wall_s':round(CLOCK()-start,3),
         'screen_observations':len(rows),'scheduled_samples':DURATION//PERIOD+1,'correct_optical_samples':sum(map(valid,rows)),
         'comparable_neighbor_pairs':len(pairs),'forward_moving_pairs':moved,
         'equal_frame_pairs':sum(a['frame']==b['frame'] for a,b in pairs),
         'largest_sample_gap_s':round(max(between,default=0),3),'pid_queries':len(pids),
         'pid_query_failures':pids.count(None),'distinct_observed_processes':len(set(pids)-{None}),
         'independent_source_samples':len(canaries),'host_verified_segments':sum(r.get('segment_http')==200 and r.get('sync_byte') is True for r in canaries),
         'distinct_source_segments':len(set(r['segment'] for r in canaries if 'segment' in r))})

if __name__=='__main__':
    main()
