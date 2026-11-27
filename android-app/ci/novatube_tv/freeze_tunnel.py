"""Independent resident Android probes of the adb reverse and emulator-NAT paths.

The guest writes both results to its own file, even when the host loses adb.
It checks the HLS manifest and an independent static root HTTP response, via
both routes. The origin witness separately verifies the TS payload and decode.
Only fixture port 18471 is addressed. Every request has a diagnostic query.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import uuid


GUEST = r'''#!/system/bin/sh
base="$1"
seconds="$2"
interval="$3"
channel="$4"
trap '' HUP
now() { cut -d' ' -f1 /proc/uptime; }
started=$(now)
born=${started%.*}
printf 'iteration\tutc_s\tguest_boot_start\tguest_boot_end\troute\tdocument\tnc_exit\thttp_status\tbytes\tmedia_sequence\tlatest_segment\n' > "$base/results.tsv"
printf '%s\n' "$$" > "$base/resident.pid"
# This shell and its file descriptor are independent of the host's ADB session.
request() {
    name="$1"; address="$2"; document="$3"; path="$4"; n="$5"
    a=$(now); epoch=$(date -u +%s)
    response="$base/$name-$document.http"
    printf 'GET %s?probe=guest-%s-%s HTTP/1.0\r\nHost: 127.0.0.1:18471\r\nUser-Agent: novatube-guest-witness/1\r\nConnection: close\r\n\r\n' "$path" "$name" "$document" |
        toybox timeout 4 toybox nc "$address" 18471 > "$response" 2>"$base/$name-$document.stderr"
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
    request reverse 127.0.0.1 playlist "/$channel/index.m3u8" "$index" &
    first_pid=$!
    request nat 10.0.2.2 playlist "/$channel/index.m3u8" "$index" &
    second_pid=$!
    wait "$first_pid"; wait "$second_pid"
    if [ "$((index % 6))" -eq 1 ]; then
        request reverse 127.0.0.1 static '/channels.m3u' "$index" & first_pid=$!
        request nat 10.0.2.2 static '/channels.m3u' "$index" & second_pid=$!
        wait "$first_pid"; wait "$second_pid"
    fi
    sleep "$interval"
done
printf 'done %s\n' "$(now)" > "$base/done"
'''


def run(args):
    args.out.mkdir(parents=True, exist_ok=True)
    adb = ['adb', '-s', args.serial]
    temp = '/data/local/tmp/nt-tunnel-' + uuid.uuid4().hex[:12]
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
        + str(args.seconds) + ' ' + str(args.interval) + ' ' + args.channel + ') '
        + ' </dev/null >' + temp + '/console 2>&1 & echo $!')
    with tempfile.TemporaryDirectory() as w:
        script = Path(w, 'probe.sh')
        script.write_text(GUEST)
        if call(['push', str(script), temp + '/probe.sh'])[0]:
            raise RuntimeError('guest probe installation failed')
        launched = call(['shell', cmd])
        if launched[0] != 0:
            raise RuntimeError('guest probe launch failed: ' + launched[2])
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

        record('start', guest_directory=temp, launcher=launched[1], duration_s=args.seconds,
               fixture_channel=args.channel)
        while not finished and time.monotonic()-start <= args.seconds+5:
            reverse = call(['reverse', '--list'])
            rows = call(['exec-out', 'tail', '-n', '50', temp+'/results.tsv'])
            append_rows(rows[1])
            record('poll', reverse_exit=reverse[0],
                   fixture_reverse_lines=[x for x in reverse[1].splitlines() if 'tcp:18471' in x],
                   reverse_error=reverse[2], read_exit=rows[0], read_error=rows[2],
                   unique_rows=len(pending))
            until=time.monotonic()+6
            while not finished and time.monotonic()<until:
                time.sleep(min(.4, max(0, until-time.monotonic())))
        stopped = call(['shell', 'touch', temp+'/stop'])
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
    p.add_argument('--channel',choices=('A','B'),default='A')
    args=p.parse_args()
    if args.interval<1 or args.seconds<1:p.error('positive durations required')
    run(args)
