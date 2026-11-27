"""Remove only the fixture's adb reverse twice while recording route and app state.

Both arms run this identical schedule. The guest connects either through that
reverse or through the virtual router's host alias. No key presses, player
restart, adb reset or Atlas intervention take place.
"""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import sys
import time

ADB = ['adb', '-s', 'emulator-5554']
MEDIA = 'tcp:18471'
ATLAS = 'tcp:8788'
PKG = 'com.sevenmotion.novatube.tv'


def adb(*args, timeout=8, binary=False):
    return subprocess.run(ADB + list(args), capture_output=True, timeout=timeout,
                          text=not binary, check=False)


def reverse_table():
    r = adb('reverse', '--list')
    if r.returncode:
        raise RuntimeError('adb reverse --list failed: ' + r.stderr.strip())
    # The adb executable can prefix mappings with a transport or serial.
    return [line.split()[-2:] for line in r.stdout.splitlines() if line.strip()]


def fixture_state(table):
    if [ATLAS, ATLAS] not in table:
        raise RuntimeError('Atlas reverse is unavailable; paired condition invalid')
    return [MEDIA, MEDIA] in table


def snapshot(out, label):
    target = out / 'interventions' / label
    target.mkdir(parents=True, exist_ok=True)
    for name, cmd in (
        ('screen.png', ['exec-out', 'screencap', '-p']),
        ('pid.txt', ['shell','pidof',PKG]),
        ('activity.txt', ['shell','dumpsys','activity','top']),
        ('codec.txt', ['shell','dumpsys','media.codec']),
        ('routes.txt', ['reverse','--list']),
    ):
        try:
            r = adb(*cmd, timeout=12, binary=True)
            (target/name).write_bytes(r.stdout)
            if r.returncode:
                (target/(name+'.stderr')).write_bytes(r.stderr)
        except (OSError, subprocess.TimeoutExpired) as exc:
            (target/(name+'.error')).write_text(str(exc))
    (target/'completed-unix.txt').write_text(str(time.time()))


def main():
    out = Path(sys.argv[1])
    zero = json.loads((out/'observation-start.json').read_text())['monotonic']
    table = reverse_table()
    if not fixture_state(table):
        raise RuntimeError('Expected initial fixture reverse is absent')
    active = False
    with (out/'reverse-interventions.jsonl').open('w', buffering=1) as log, ThreadPoolExecutor(max_workers=2) as pool:
        def record(kind, **fields):
            now = time.monotonic()
            log.write(json.dumps({'kind':kind,'unix':time.time(),'monotonic':now,
                                  'elapsed_s':round(now-zero,3),**fields})+'\n')

        def until(offset):
            time.sleep(max(0, zero+offset-time.monotonic()))

        record('plan', offsets_s=[120,600], hold_s=110, passive=True,
               initial_mappings=table, scheduled_end_s=4800)
        try:
            for index, offset in enumerate((120,600),1):
                until(offset-12)
                pool.submit(snapshot, out, f'{index}-baseline')
                until(offset)
                before = reverse_table()
                if not fixture_state(before):
                    raise RuntimeError('reverse already absent before injection')
                started = time.monotonic()
                remove = adb('reverse','--remove',MEDIA)
                active = remove.returncode == 0
                after = reverse_table()
                record('removed', index=index, rc=remove.returncode,
                       before=before, after=after, host_started=started)
                if not active or fixture_state(after):
                    raise RuntimeError('removal did not isolate fixture reverse')
                until(offset+65)
                pool.submit(snapshot, out, f'{index}-during')
                until(offset+110)
                restore = adb('reverse',MEDIA,MEDIA)
                restored = reverse_table()
                record('restored', index=index, rc=restore.returncode,
                       mappings=restored, actual_s=round(time.monotonic()-started,3))
                if restore.returncode or not fixture_state(restored):
                    raise RuntimeError('fixture reverse not restored')
                active = False
                until(offset+125)
                pool.submit(snapshot, out, f'{index}-restored-15s')
                until(offset+170)
                pool.submit(snapshot, out, f'{index}-restored-60s')
            record('done', final_mappings=reverse_table(), user_input_count=0)
        finally:
            if active:
                r = adb('reverse',MEDIA,MEDIA)
                record('cleanup_restore', rc=r.returncode, mappings=reverse_table())
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
