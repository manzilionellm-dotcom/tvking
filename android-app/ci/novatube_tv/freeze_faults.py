"""Scheduled, counted loss on the test Android connection to TCP port 18471."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

PORT = 18471


def main():
    p = argparse.ArgumentParser()
    p.add_argument('out', type=Path)
    p.add_argument('--every', type=int, default=30)
    p.add_argument('--seconds', type=float, default=4200.)
    p.add_argument('--windows', default='600,1800,3300',
                   help='comma-separated offsets in seconds from invocation')
    p.add_argument('--window-seconds', type=float, default=60.)
    args = p.parse_args()
    try:
        offsets = [float(x) for x in args.windows.split(',')]
    except ValueError:
        p.error('windows must be numeric seconds')
    if (args.every < 2 or args.window_seconds <= 0 or offsets != sorted(offsets)
            or offsets[0] < 0 or offsets[-1] + args.window_seconds > args.seconds
            or any(b - a < args.window_seconds for a, b in zip(offsets, offsets[1:]))):
        p.error('non-overlapping windows must fit inside the scenario duration; every >= 2')
    args.out.mkdir(parents=True, exist_ok=True)
    comment = 'novatube_fixture_loss_' + str(os.getpid())
    rule = ['-o', 'lo', '-p', 'tcp', '-s', '127.0.0.1/32', '--sport', str(PORT),
            '-d', '127.0.0.1/32', '-m', 'length', '--length', '100:65535',
            '-m', 'statistic', '--mode', 'nth', '--every', str(args.every), '--packet', '0',
            '-m', 'comment', '--comment', comment, '-j', 'DROP']
    prefix = ['sudo', '-n', 'iptables', '-w', '5']
    finished = False

    def stop(_n, _frame):
        nonlocal finished
        finished = True

    def wait_until(target):
        while not finished:
            left = target - time.monotonic()
            if left <= 0:
                break
            time.sleep(min(.5, left))

    def counters():
        raw = subprocess.check_output(['sudo', '-n', 'iptables-save', '-c', '-t', 'filter'],
                                      text=True, timeout=7)
        matches = [l for l in raw.splitlines() if comment in l]
        count = re.match(r'^\[(\d+):(\d+)\]', matches[0]) if len(matches) == 1 else None
        if not count:
            raise RuntimeError('fixture loss rule or its packet/byte counts unavailable')
        return {'packets_dropped': int(count[1]), 'bytes_dropped': int(count[2])}

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    zero = time.monotonic()
    with (args.out / 'network-loss.jsonl').open('a', buffering=1) as log:
        def record(phase, **fields):
            now=time.monotonic()
            event={'phase':phase,'host_monotonic':now,'elapsed_s':round(now-zero,3),
                   'utc':datetime.now(timezone.utc).isoformat(timespec='milliseconds'),**fields}
            log.write(json.dumps(event,separators=(',', ':'))+'\n')

        record('plan', offsets=offsets, window_s=args.window_seconds, every=args.every,
               duration_s=args.seconds, source_port=PORT, source='127.0.0.1', dest='127.0.0.1',
               exempt_witness='127.0.0.2')
        total = 0
        for index, offset in enumerate(offsets, 1):
            wait_until(zero + offset)
            if finished: break
            subprocess.run(prefix + ['-I', 'OUTPUT', '1'] + rule, check=True, timeout=10)
            began=time.monotonic()
            try:
                record('installed', window=index, **counters())
                while not finished and time.monotonic()-began < args.window_seconds:
                    wait_until(min(began + args.window_seconds, time.monotonic()+2))
                    record('active', window=index, **counters())
                last=counters()
            finally:
                subprocess.run(prefix + ['-D', 'OUTPUT'] + rule, check=True, timeout=10)
            total += last['packets_dropped']
            record('removed',window=index,duration_s=round(time.monotonic()-began,3),**last)
        wait_until(zero+args.seconds)
        record('end',interrupted=finished,total_packets_dropped=total)


if __name__ == '__main__':
    main()
