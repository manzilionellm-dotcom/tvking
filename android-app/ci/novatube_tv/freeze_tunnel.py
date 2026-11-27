"""Independent resident Android probes of the adb reverse and emulator-NAT paths.

The guest writes both results to its own file, even when the host loses adb.
It checks the HLS manifest and an independent static root HTTP response, via
both routes. The origin witness separately verifies the TS payload and decode.
With --passive-reverse, only NAT is addressed before a freeze or observation end.
Only fixture port 18471 is addressed. Every request has a diagnostic query.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import signal
import subprocess
import tempfile
import threading
import time
import uuid


GUEST = r'''#!/system/bin/sh
base="$1"
seconds="$2"
interval="$3"
channel="$4"
passive="$5"
token="$6"
trap '' HUP
now() { cut -d' ' -f1 /proc/uptime; }
{
    date -u
    id
    command -v toybox
    command -v mkfifo
    toybox nc --help 2>&1 | head -3
    toybox timeout --help 2>&1 | head -3
    toybox readlink /proc/self/exe
} > "$base/runtime.txt" 2>&1
started=$(now)
born=${started%.*}
printf 'iteration\tutc_s\tguest_boot_start\tguest_boot_end\troute\tdocument\tnc_exit\thttp_status\tbytes\tmedia_sequence\tlatest_segment\n' > "$base/results.tsv"
printf '%s\n' "$$" > "$base/resident.pid"
# This shell and its file descriptor are independent of the host's ADB session.
request() {
    name="$1"; address="$2"; document="$3"; path="$4"; n="$5"
    a=$(now); epoch=$(date -u +%s)
    response="$base/$name-$document.http"
    # Retain stdin while the HTTP/1.0 server responds through adbd. Do not
    # create a FIFO: Android SELinux policy and available applets vary by image.
    # elapsed_seconds includes up to one second of local pipe linger.
    {
        printf 'GET %s?probe=guest-%s-%s HTTP/1.0\r\nHost: 127.0.0.1:18471\r\nUser-Agent: novatube-guest-witness/1\r\nConnection: close\r\n\r\n' "$path" "$name" "$document"
        sleep 1
    } | toybox timeout 4 toybox nc "$address" 18471 > "$response" 2>"$base/$name-$document.stderr"
    rc=$?; b=$(now)
    code=$(head -n 1 "$response" | awk '{ print $2 }')
    seq=$(tr -d '\r' < "$response" | sed -n 's/^#EXT-X-MEDIA-SEQUENCE://p' | head -n 1)
    last=$(tr -d '\r' < "$response" | sed -n '/^seg[0-9]*\.ts$/p' | tail -n 1)
    bytes=$(wc -c < "$response" | tr -d ' ')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$epoch" "$a" "$b" "$name" "$document" "$rc" "${code:--}" "$bytes" "${seq:--}" "${last:--}" >> "$base/results.tsv"
}
index=0
while [ ! -e "$base/stop" ]; do
    clock=$(now)
    if [ "$(( ${clock%.*} - born ))" -ge "$seconds" ]; then break; fi
    index=$((index+1))
    reverse_allowed=1
    if [ "$passive" = 1 ] && [ ! -e "$base/arm-reverse" ]; then
        reverse_allowed=0
        # Read the gate through emulator NAT only. The host can still arm this
        # resident after a loss of the ADB control transport.
        request nat 10.0.2.2 control '/qa-reverse-gate.txt' "$index"
        if grep -Fxq "ARM $token" "$base/nat-control.http"; then
            touch "$base/arm-reverse"
            reverse_allowed=1
        fi
    fi
    if [ "$passive" = 1 ] && [ -e "$base/arm-reverse" ]; then
        reverse_allowed=1
        if [ ! -f "$base/armed-guest.txt" ]; then
            printf '%s %s %s\n' "$index" "$(now)" "$(date -u +%s)" > "$base/armed-guest.txt"
        fi
    fi
    if [ "$reverse_allowed" = 1 ]; then
        request reverse 127.0.0.1 playlist "/$channel/index.m3u8" "$index" &
        first_pid=$!
    fi
    request nat 10.0.2.2 playlist "/$channel/index.m3u8" "$index" &
    second_pid=$!
    if [ "$reverse_allowed" = 1 ]; then wait "$first_pid"; fi
    wait "$second_pid"
    if [ "$((index % 6))" -eq 1 ] || { [ "$passive" = 1 ] && [ "$reverse_allowed" = 1 ] && [ ! -f "$base/first-reverse-static" ]; }; then
        if [ "$reverse_allowed" = 1 ]; then
            request reverse 127.0.0.1 static '/channels.m3u' "$index" &
            first_pid=$!
            touch "$base/first-reverse-static"
        fi
        request nat 10.0.2.2 static '/channels.m3u' "$index" &
        second_pid=$!
        if [ "$reverse_allowed" = 1 ]; then wait "$first_pid"; fi
        wait "$second_pid"
    fi
    sleep "$interval"
done
printf 'done %s\n' "$(now)" > "$base/done"
'''


def run(args):
    args.out.mkdir(parents=True, exist_ok=True)
    adb = ['adb', '-s', args.serial]
    token = uuid.uuid4().hex[:12]
    temp = '/data/local/tmp/nt-tunnel-' + token
    gate = args.out / 'tunnel-arm-gate.txt'
    def publish_gate(state):
        tmp = gate.with_suffix('.new')
        tmp.write_text(state+' '+token+'\n')
        tmp.replace(gate)
    if args.passive_reverse:
        publish_gate('HOLD')
    finished = False

    def stop(_n, _frame):
        nonlocal finished
        finished = True

    def call(command, timeout=5):
        try:
            p = subprocess.run(adb + command, capture_output=True, text=True,
                               timeout=timeout, errors='replace')
            return p.returncode, p.stdout.strip(), p.stderr.strip()[-200:]
        except subprocess.TimeoutExpired:
            return 124, '', 'ADB command timeout'

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    if call(['shell', 'mkdir', temp])[0]:
        raise RuntimeError('guest probe directory unavailable')
    cmd = (
        "(trap '' HUP; exec sh " + temp + '/probe.sh ' + temp + ' '
        + str(args.seconds) + ' ' + str(args.interval) + ' ' + args.channel + ' '
        + str(int(args.passive_reverse)) + ' ' + token + ') '
        + ' </dev/null >' + temp + '/console 2>&1 & echo $!')
    with tempfile.TemporaryDirectory() as w:
        script = Path(w, 'probe.sh')
        script.write_text(GUEST)
        if call(['push', str(script), temp + '/probe.sh'])[0]:
            raise RuntimeError('guest probe installation failed')
        launched = call(['shell', cmd])
        if launched[0] != 0:
            raise RuntimeError('guest probe launch failed: ' + launched[2])
    gate_stop = threading.Event()

    def monitor_arm():
        arm_origin = args.out / 'observation-start.json'
        visual_dir = args.out / 'freeze-events'
        source = None
        with (args.out/'guest-reverse-arming.jsonl').open('a',buffering=1) as report:
            def write(state, **fields):
                now = time.monotonic()
                report.write(json.dumps(dict(state=state, host_monotonic=now, unix=time.time(), **fields))+'\n')
            write('HOLD')
            observed = None
            while not gate_stop.is_set():
                if observed is None and arm_origin.exists():
                    try:
                        observed = json.loads(arm_origin.read_text())
                    except (ValueError,OSError):
                        pass
                if observed is not None:
                    requests=sorted(visual_dir.glob('event-*/request.json'))
                    optical=None
                    for request in requests:
                        try:
                            event=json.loads(request.read_text())
                        except (OSError,ValueError):
                            continue
                        if (event.get('threshold_s',0)>=6 and
                            event.get('detection_s',-1)-event.get('last_motion_s',0)>=5.999 and
                            event.get('monotonic',0)>=observed['monotonic']):
                            optical=event['id']
                            break
                    if optical:
                        source='optical:'+optical
                    elif time.monotonic() >= observed['monotonic'] + observed['seconds']:
                        source = 'observation-deadline'
                if source:
                    break
                gate_stop.wait(.12)
            if source is None:
                write('ended-without-arm')
                return
            publish_gate('ARM')
            write('ARM',reason=source)
            while not gate_stop.is_set():
                result_code,_,err=call(['shell','touch',temp+'/arm-reverse'])
                write('notify-guest-without-changing-mappings',code=result_code,error=err)
                if result_code==0:break
                gate_stop.wait(2)
    armer = None
    if args.passive_reverse:
        armer = threading.Thread(target=monitor_arm, name='independent-NAT-gate', daemon=True)
        armer.start()
    header = 'iteration\tutc_s\tguest_boot_start\tguest_boot_end\troute\tdocument\tnc_exit\thttp_status\tbytes\tmedia_sequence\tlatest_segment'
    pending = set()
    start = time.monotonic()
    with (args.out/'guest-path-status.jsonl').open('a', buffering=1) as status, (args.out/'guest-path-live.tsv').open('w', buffering=1) as live:
        live.write(header+'\n')

        def record(phase, **fields):
            status.write(json.dumps({'phase': phase, 'host_monotonic': time.monotonic(),
                                     'utc': datetime.now(timezone.utc).isoformat(timespec='milliseconds'),
                                     **fields}, separators=(',', ':'))+'\n')

        def append_rows(rows):
            for line in rows.splitlines():
                cells = line.split('\t')
                if len(cells) != 11 or not cells[0].isdigit():
                    continue
                key = (cells[0], cells[4], cells[5])
                if key not in pending:
                    live.write(line+'\n')
                    pending.add(key)
                    # The launch controller may wait for a verified, production-guest
                    # sample; no probe writes through the reverse path in passive mode.
                    if cells[4:6]==['nat','playlist'] and cells[7]=='200' and cells[9].isdigit():
                        ready=args.out/'guest-tunnel-ready.json'
                        if not ready.exists():
                            obj={'host_monotonic':time.monotonic(),'utc':datetime.now(timezone.utc).isoformat(),
                                 'route':cells[4],'data':'manifest','http':200,'latest_segment':cells[10]}
                            tn=ready.with_suffix('.tmp')
                            tn.write_text(json.dumps(obj)+'\n')
                            tn.replace(ready)

        record('start', guest_directory=temp, launcher=launched[1], duration_s=args.seconds,
               fixture_channel=args.channel, passive_reverse=args.passive_reverse)
        while not finished and time.monotonic()-start <= args.seconds+5:
            reverse = call(['reverse', '--list'])
            rows = call(['exec-out', 'tail', '-n', '50', temp+'/results.tsv'])
            append_rows(rows[1])
            record('poll', reverse_exit=reverse[0],
                   fixture_reverse_lines=[x for x in reverse[1].splitlines() if 'tcp:18471' in x],
                   reverse_error=reverse[2], read_exit=rows[0], read_error=rows[2],
                   unique_rows=len(pending))
            if not pending:
                runtime=call(['exec-out','cat',temp+'/runtime.txt'],timeout=3)
                console=call(['exec-out','tail','-20',temp+'/console'],timeout=3)
                (args.out/'guest-preflight.txt').write_text(str(runtime)+'\n'+str(console)+'\n')
            until=time.monotonic()+6
            while not finished and time.monotonic()<until:
                time.sleep(min(.4, max(0, until-time.monotonic())))
        gate_stop.set()
        if armer:
            armer.join(6)
        stopped = call(['shell', 'touch', temp+'/stop'])
        # Pull targeted diagnostics even if the first request or resident failed.
        for local, remote in [
                ('guest-runtime.txt','runtime.txt'), ('guest-resident-console.txt','console'),
                ('guest-reverse-playlist.stderr','reverse-playlist.stderr'),
                ('guest-reverse-static.stderr','reverse-static.stderr'),
                ('guest-nat-control.stderr','nat-control.stderr'),
                ('guest-nat-playlist.stderr','nat-playlist.stderr'),
                ('guest-nat-static.stderr','nat-static.stderr')]:
            _rc, data, err = call(['exec-out','cat',temp+'/'+remote],timeout=3)
            if data or err:(args.out/local).write_text(data+'\n'+err+'\n')
        if args.passive_reverse:
            rc, armed_at, _ = call(['exec-out', 'cat', temp+'/armed-guest.txt'])
            record('guest-arm-record', rc=rc, guest_times=armed_at)
        all_rows = call(['exec-out', 'cat', temp+'/results.tsv'],timeout=10)
        if all_rows[0]==0 and all_rows[1].startswith(header):
            (args.out/'guest-path-final.tsv').write_text(all_rows[1]+'\n')
            append_rows(all_rows[1])
        # On a transport failure the resident keeps collecting and self-expires.
        # Preserve its files in case the caller can reconnect and pull them later.
        record('finish', stop_exit=stopped[0], full_read_exit=all_rows[0],
               unique_rows=len(pending), error=all_rows[2])


if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('out',type=Path)
    p.add_argument('--serial',default='emulator-5554')
    p.add_argument('--seconds',type=int,default=7200)
    p.add_argument('--interval',type=int,default=6)
    p.add_argument('--passive-reverse',action='store_true',help='arm reverse only at measured incident/deadline')
    p.add_argument('--channel',choices=('A','B'),default='A')
    args=p.parse_args()
    if args.interval<1 or args.seconds<1:p.error('positive durations required')
    run(args)
