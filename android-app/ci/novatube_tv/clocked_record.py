"""On an isolated QA emulator, record presentation timestamps and injected keys on the device clock."""
from pathlib import Path
import json
import subprocess
import sys
import time
from pilot_observer import frame
from read_display_capture import decode

out = Path(sys.argv[1])
out.mkdir(parents=True,exist_ok=True)
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
# The key clock log and MP4 must survive an ADB transport interruption.
# Each invocation has a unique per-clip device path and belongs only to the test AVD.
fixture_id=out.name
assert fixture_id.startswith('clip-') and int(fixture_id.split('-')[1]) in range(1,6)
guestroot=root+'-'+out.parent.name+'-'+fixture_id
guest=guest.replace(root,guestroot)
script=out/'private-guest.sh'
script.write_text('(' + guest + ') > ' + guestroot+'.keys 2> '+guestroot+'.errors\n'
                  + 'echo $? > '+guestroot+'.done\n')
subprocess.run(adb+['shell','rm','-f',guestroot+'.done',guestroot+'.keys',guestroot+'.errors'],check=True,timeout=15)
subprocess.run(adb+['push',str(script),guestroot+'.sh'],check=True,capture_output=True,timeout=22)
subprocess.run(adb+['shell','nohup sh '+guestroot+'.sh </dev/null >/dev/null 2>&1 &'],check=True,timeout=10)
deadline=time.monotonic()+160
while time.monotonic()<deadline:
    try:
        state=subprocess.run(adb+['shell','cat',guestroot+'.done'],capture_output=True,timeout=5)
        if state.returncode==0 and state.stdout.strip().isdigit():
            break
        if state.returncode and b'offline' in state.stderr:
            subprocess.run(['adb','reconnect','offline'],capture_output=True,timeout=6)
    except subprocess.TimeoutExpired:
        pass
    time.sleep(4)
else:
    raise ValueError('Guest completion not readable, clip cannot be scored')
for ext,filename in [('.keys','device-keys.txt'),('.record-log','recording-status.txt'),('.mp4','clocked-video.mp4')]:
    target=out/filename; fetched=False
    for attempt in range(4):
        try:
            subprocess.run(adb+['pull',guestroot+ext,str(target)],check=True,timeout=70,capture_output=True)
            fetched=True;break
        except (subprocess.SubprocessError,OSError):
            time.sleep(2)
    if not fetched: raise ValueError('Missing device evidence '+filename)
if int(state.stdout.strip())!=0 or len((out/'device-keys.txt').read_text().strip().splitlines())!=10:
    raise ValueError('Incomplete guest clock series')
# Check timing tracks and ALL 10 optically verified channel transitions before committing this clip.
from clocked_analyze import analyse
scored,_,_=analyse(out/'clocked-video.mp4',out/'device-keys.txt')
(out/'clock-results.json').write_text(json.dumps(scored,indent=2))
# Retain every timed-out or unobserved action in the planned denominator.
(out/'valid.txt').write_text(f'10 time-bracketed commands; {sum(t.get("valid",False) for t in scored["trials"])}/10 target transitions identified\\n')
