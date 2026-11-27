"""On an isolated QA emulator, record presentation timestamps and injected keys on the device clock."""
from pathlib import Path
import json
import subprocess
import sys
import time
from pilot_observer import frame
from read_display_capture import decode

out = Path(sys.argv[1])
adb = ['adb', '-s', 'emulator-5554']


def visible(target, timeout=13):
    limit = time.monotonic() + timeout
    last = None
    while time.monotonic() < limit:
        im, _ = frame(adb, out, time.monotonic())
        if im is None:
            last = None
            continue
        im = im.convert('L')
        w, h = im.size
        for t,b in ((0,0),(0,24),(0,48),(24,0),(24,24),(48,0),(48,48)):
            vh = min(h-t-b,w*9/16); vw=vh*16/9
            x=(w-vw)/2; y=t+(h-t-b-vh)/2
            ch,n = decode([im.getpixel((round(x+vw*(496+32*i)/1920),round(y+vh*650/1080))) for i in range(30)])
            if ch:
                break
        if ch == target and last is not None and 0<(n-last)%(1<<20)<(1<<19):
            return True
        last = n if ch == target else None
    return False


def key(k):
    subprocess.run(adb+['shell','input','keyevent',k],check=True,timeout=6)


def calibrate():
    if not visible('A'):
        raise ValueError('Expected animated fixture A in foreground')
    for down,up in [('KEYCODE_CHANNEL_DOWN','KEYCODE_CHANNEL_UP'),('KEYCODE_CHANNEL_UP','KEYCODE_CHANNEL_DOWN'),
                    ('KEYCODE_DPAD_DOWN','KEYCODE_DPAD_UP'),('KEYCODE_DPAD_UP','KEYCODE_DPAD_DOWN')]:
        key(down)
        if visible('B',8):
            key(up)
            if visible('A',8): return down,up
            if visible('B',4):
                key(down)
                if visible('A',8): return down,down
            break
        if not visible('A',4): break
    raise ValueError('Unverified A to B to A calibration')


keys=calibrate()
(out/'device-clock-calibration.json').write_text(json.dumps({'keys':keys,'sequence':'A->B->A confirmed in motion'}))
root='/data/local/tmp/nova-pts'
# Time of the input is bracketed in the Android shell, not by host communication.
guest = r'''
set -eu
mp4=ROOT.mp4
rm -f "$mp4"
screenrecord --size 640x360 --bit-rate 2500000 --time-limit 72 "$mp4" >ROOT.record-log 2>&1 &
pid=$!
sleep 5
i=1
while [ "$i" -le 10 ]; do
  kill -0 "$pid" || exit 71
  case $((i % 2)) in 1) k=KEY1; ch=B;; 0) k=KEY2; ch=A;; esac
  read before rest </proc/uptime
  input keyevent "$k"
  read after rest </proc/uptime
  echo "$i $ch $k $before $after"
  i=$((i+1))
  sleep 5
done
kill -INT "$pid" || true
wait "$pid"
'''.replace('ROOT',root).replace('KEY1',keys[0]).replace('KEY2',keys[1])
with (out/'device-keys.txt').open('w') as clocks:
    p=subprocess.run(adb+['shell',guest],stdout=clocks,stderr=subprocess.DEVNULL,timeout=100)
subprocess.run(adb+['pull',root+'.record-log',str(out/'recording-status.txt')],capture_output=True,timeout=10)
subprocess.run(adb+['pull',root+'.mp4',str(out/'clocked-video.mp4')],check=True,timeout=60)
if p.returncode or len((out/'device-keys.txt').read_text().strip().splitlines())!=10:
    raise ValueError('Incomplete guest clock series')
