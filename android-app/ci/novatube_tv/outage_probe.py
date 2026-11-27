"""Mesure sur la mire contrôlée du rétablissement jusqu'à l'image rendue.
La résolution dépend de la cadence des captures, conservées avec leur durée.
L'application et Atlas restent connectés. Seul le port de la mire est coupé."""
import argparse
import csv
import io
import json
from pathlib import Path
import subprocess
import time
from PIL import Image


def code(im):
    # L'écran Android 11 centré comporte parfois des barres système.
    # Deux lignes complémentaires limitent les faux positifs sur les menus.
    # Trouver le rectangle 16:9, avec ou sans barres de navigation.
    for top, bottom in ((.05, .91), (0, 1)):
        ratio_h = bottom - top
        width = min(im.width, im.height * ratio_h * 16 / 9)
        left = (im.width - width) / 2
        values = []
        for bit in range(6):
            x = round(left + width * (560 + 160 * bit) / 1920)
            y1 = round(im.height * (top + ratio_h * .405))
            y2 = round(im.height * (top + ratio_h * .598))
            a = im.getpixel((x, y1))[:3]
            b = im.getpixel((x, y2))[:3]
            if min(a) > 200 and max(b) < 60:
                values.append(1)
            elif max(a) < 60 and min(b) > 200:
                values.append(0)
            else:
                break
        if len(values) == 6:
            return sum(v << i for i, v in enumerate(values))
    return None


def run(serial, output, duration):
    adb = ['adb', '-s', serial]
    rule = ['OUTPUT', '-o', 'lo', '-p', 'tcp', '--dport', '8080', '-j', 'REJECT']
    def firewall(action):
        subprocess.run(adb + ['shell', 'iptables', '-w', action] + rule, check=True, timeout=12)

    points = []
    def screen(phase):
        t = time.monotonic()
        raw = subprocess.check_output(adb + ['exec-out', 'screencap', '-p'], timeout=12)
        value = code(Image.open(io.BytesIO(raw)).convert('RGB'))
        end = time.monotonic()
        points.append((phase, t, end, value))
        return value

    def sample(phase, seconds):
        stop = time.monotonic() + seconds
        while time.monotonic() < stop:
            screen(phase)
    sample('before', 4)
    closed_at = time.monotonic()
    firewall('-I')
    try:
        sample('down', duration)
    finally:
        subprocess.run(adb + ['shell', 'iptables', '-w', '-L', 'OUTPUT', '-n', '-v', '-x'],
            stdout=(output / f'cut-{duration}-rules.txt').open('w'), check=True, timeout=12)
        firewall('-D')
    restored = time.monotonic()
    sample('restored', 15)
    filename = output / f'cut-{duration}-screen.csv'
    with filename.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(('phase', 'capture_start_from_restore_s', 'capture_end_from_restore_s', 'video_code'))
        for phase, start, end, val in points:
            writer.writerow((phase, round(start-restored,4), round(end-restored,4), val))

    before = [p for p in points if p[0] == 'before' and p[3] is not None]
    down = [p for p in points if p[0] == 'down']
    after = [p for p in points if p[0] == 'restored']
    # Le premier changement après rétablissement est une borne supérieure.
    last = down[-1][3] if down else None
    changes = []
    for p in after:
        if p[3] is None:
            last = None
        elif last is not None and last != p[3]:
            changes.append(p[2] - restored)
            break
        else:
            last = p[3]
    late = [p[3] for p in down if p[1] >= restored-3 and p[3] is not None]
    result = {'requested_s': duration, 'observed_cut_s': round(restored-closed_at,3),
              'valid_moving_before': len({p[3] for p in before}) >= 2,
              'moving_final_3s_of_cut': len(set(late)) >= 2,
              'max_gap_s_after_restore': round(max((b[2]-a[2] for a,b in zip(after,after[1:])),default=0),3),
              'motion_seen_by_s': round(changes[0],3) if changes else None,
              'observation_after_restore_s': round(after[-1][2]-restored,3) if after else 0}
    (output / f'cut-{duration}-result.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('serial')
    p.add_argument('output', type=Path)
    p.add_argument('duration', type=int, choices=[5,15,60])
    a = p.parse_args()
    run(a.serial, a.output, a.duration)
