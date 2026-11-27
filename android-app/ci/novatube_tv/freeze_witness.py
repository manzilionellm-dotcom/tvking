"""Independent loopback HTTP witness for the controlled NovaTube HLS fixture.

The witness requests the same origin, playlist and newly published segments as
the Android player. Its source address allows fault injection to affect only
the player. Each JSON line is independently durable if the test is interrupted.
"""
import argparse
from collections import deque
from datetime import datetime, timezone
import hashlib
import http.client
import json
from pathlib import Path
import re
import signal
import subprocess
import time


HOST = '127.0.0.1'
WITNESS = '127.0.0.2'
SEGMENT = re.compile(r'seg(\d{8})\.ts')
MAX_BODY = 12 * 1024 * 1024


def utc():
    return datetime.now(timezone.utc).isoformat(timespec='milliseconds')


def request(port, path, limit):
    start = time.monotonic()
    connection = http.client.HTTPConnection(
        HOST, port, timeout=2.0, source_address=(WITNESS, 0))
    try:
        connection.request('GET', path + '?probe=origin',
                           headers={'User-Agent': 'novatube-origin-witness/1'})
        response = connection.getresponse()
        data = response.read(limit + 1)
        if response.status != 200 or len(data) > limit:
            raise ValueError(f'HTTP {response.status}, {len(data)} bytes')
        size = response.getheader('Content-Length')
        if size is not None and int(size) != len(data):
            raise ValueError(f'Content-Length {size}, received {len(data)}')
        return data, round((time.monotonic() - start) * 1000)
    finally:
        connection.close()


def playlist(text):
    lines = text.decode('ascii').splitlines()
    if not lines or lines[0] != '#EXTM3U':
        raise ValueError('invalid fixture playlist')
    header = next((x for x in lines if x.startswith('#EXT-X-MEDIA-SEQUENCE:')), '')
    if not header:
        raise ValueError('missing media sequence')
    first = int(header.split(':', 1)[1])
    names = [x for x in lines if x and not x.startswith('#')]
    if not names or not all(SEGMENT.fullmatch(x) for x in names):
        raise ValueError('unexpected segment name')
    numbers = [int(SEGMENT.fullmatch(x)[1]) for x in names]
    if numbers != list(range(first, first + len(numbers))):
        raise ValueError('non-contiguous fixture playlist')
    return first, names


def inspect_ts(data):
    packets, partial = divmod(len(data), 188)
    if not packets or partial or any(data[i] != 0x47 for i in range(0, len(data), 188)):
        raise ValueError('invalid MPEG-TS packet sync')
    return {'bytes': len(data), 'ts_packets': packets,
            'sha256': hashlib.sha256(data).hexdigest()}


def decode(data):
    # An independent software decode, limited to one complete two-second segment.
    cmd = ['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-xerror',
           '-threads', '1', '-i', 'pipe:0', '-map', '0:v:0', '-an', '-threads', '1',
           '-progress', 'pipe:1', '-f', 'null', '-']
    proc = subprocess.run(cmd, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          check=False, timeout=12)
    frames = re.findall(rb'^frame=(\d+)$', proc.stdout, re.MULTILINE)
    return {'exit': proc.returncode,
            'frames': int(frames[-1]) if frames else None,
            'error': proc.stderr[-300:].decode(errors='replace') or None}


def save_incident(directory, channel, ring, token):
    dst = directory / f'origin-evidence-{channel}-{token}'
    dst.mkdir(exist_ok=True)
    for entry in ring:
        stamp, name, index, segment = entry
        (dst / (str(stamp) + '.m3u8')).write_bytes(index)
        (dst / name).write_bytes(segment)


def poll(args):
    finished = False

    def stop(_n, _frame):
        nonlocal finished
        finished = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    args.out.mkdir(parents=True, exist_ok=True)
    zero = time.monotonic()
    seen = {ch: -1 for ch in args.channels}
    changed = {ch: zero for ch in args.channels}
    decoded = {ch: float('-inf') for ch in args.channels}
    rings = {ch: deque(maxlen=3) for ch in args.channels}
    incident = {ch: None for ch in args.channels}
    with (args.out / 'origin-witness.jsonl').open('a', buffering=1) as log:
        while not finished and time.monotonic() - zero < args.seconds:
            start = time.monotonic()
            for ch in args.channels:
                now = time.monotonic()
                event = {'host_monotonic': now, 'utc': utc(), 'channel': ch}
                try:
                    idx, event['playlist_ms'] = request(args.port, f'/{ch}/index.m3u8', 65536)
                    first, names = playlist(idx)
                    number = int(SEGMENT.fullmatch(names[-1])[1])
                    event.update(first=first, last=number, playlist_entries=len(names))
                    if number != seen[ch]:
                        event['advanced_by'] = number - seen[ch] if seen[ch] >= 0 else None
                        changed[ch] = time.monotonic()
                    data, event['segment_ms'] = request(args.port, f'/{ch}/{names[-1]}', MAX_BODY)
                    event.update(inspect_ts(data))
                    if number != seen[ch]:
                        rings[ch].append((number, names[-1], idx, data))
                    seen[ch] = number
                    if now - decoded[ch] >= args.decode_every:
                        try:
                            event['software_decode'] = decode(data)
                        except (OSError, subprocess.TimeoutExpired) as exc:
                            event['decode_error'] = type(exc).__name__ + ': ' + str(exc)
                        decoded[ch] = now
                    event['ok'] = True
                except (ValueError, UnicodeError, OSError, http.client.HTTPException) as exc:
                    event.update(ok=False, error=type(exc).__name__ + ': ' + str(exc))
                event['seconds_since_last_sequence_change'] = round(time.monotonic() - changed[ch], 3)
                event['end_monotonic'] = time.monotonic()
                log.write(json.dumps(event, separators=(',', ':')) + '\n')
                # A trigger can be touched by the out-of-band Android watchdog.
                flag = args.out / 'freeze-trigger'
                stamp = flag.stat().st_mtime_ns if flag.exists() else None
                if stamp is not None and stamp != incident[ch]:
                    save_incident(args.out, ch, rings[ch], stamp)
                    incident[ch] = stamp
            remaining = start + args.interval - time.monotonic()
            if remaining > 0 and not finished:
                time.sleep(remaining)
        for ch in args.channels:
            save_incident(args.out, ch, rings[ch], 'final')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('out', type=Path)
    p.add_argument('--port', type=int, default=18471)
    p.add_argument('--channels', default='A', choices=('A', 'B', 'AB'))
    p.add_argument('--interval', type=float, default=2.)
    p.add_argument('--decode-every', type=float, default=30.)
    p.add_argument('--seconds', type=float, default=7200.)
    settings = p.parse_args()
    if min(settings.interval, settings.decode_every, settings.seconds) <= 0:
        p.error('durations must be positive')
    poll(settings)
