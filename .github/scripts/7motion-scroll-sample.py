"""Test de deux APK livrés avec la même source M3U et des logos synthétiques."""
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import math
from pathlib import Path
import re
import shlex
import struct
import subprocess
import sys
import time
from xml.etree import ElementTree
import zlib

HOST = 'http://127.0.0.1:18089'


def serve():
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))

    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 1024, 512, 8, 2, 0, 0, 0))
    row = b'\x00' + bytes(range(256)) * 12
    png += chunk(b'IDAT', zlib.compress(row * 512)) + chunk(b'IEND', b'')
    lines = ['#EXTM3U']
    for i in range(8000):
        group = 0 if i < 800 else 1 + (i - 800) % 799
        lines.extend([f'#EXTINF:-1 tvg-logo="{HOST}/logo/{i}.png" group-title="Group {group:03d}",Station {i:04d}', f'{HOST}/live/{i}.ts'])
    playlist = '\n'.join(lines).encode()

    class Fixture(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/liste.m3u':
                body, mime = playlist, 'application/x-mpegURL'
            elif self.path.startswith('/logo/'):
                body, mime = png, 'image/png'
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', mime)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            if self.path == '/liste.m3u':
                super().log_message(fmt, *args)

    ThreadingHTTPServer(('127.0.0.1', 18089), Fixture).serve_forever()


def adb(*args, check=True):
    return subprocess.run(['adb', *args], capture_output=True, text=True, check=check, timeout=35).stdout.strip()


def probe(apk, tag):
    out = Path('diagnostic') / tag
    out.mkdir(exist_ok=True)
    package = 'com.manzilionellm.tvking.qa.' + tag

    def labels(node):
        return ' '.join(filter(None, (node.get('content-desc'), node.get('text'))))

    def tree():
        adb('shell', 'uiautomator dump /sdcard/scroll-ui.xml >/dev/null', check=False)
        doc = adb('shell', 'cat /sdcard/scroll-ui.xml', check=False)
        if '<hierarchy' not in doc:
            return []
        (out / 'last-ui.xml').write_text(doc)
        return list(ElementTree.fromstring(doc).iter('node'))

    def wait_for(predicate, timeout=70, seek=False):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            nodes = tree()
            for node in nodes:
                if predicate(node):
                    return node
            if seek:
                adb('shell', 'input swipe 345 1050 345 770 480')
            time.sleep(.5)
        raise RuntimeError('Contrôle absent. Voir last-ui.xml : ' + str([labels(n) for n in nodes if labels(n)][:18]))

    def tap(node):
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
        adb('shell', f'input tap {(x1+x2)//2} {(y1+y2)//2}')
        time.sleep(.45)

    def capture(name):
        with (out / (name + '.png')).open('wb') as stream:
            subprocess.run(['adb', 'exec-out', 'screencap', '-p'], stdout=stream, check=True)

    def measure(name, expected):
        visible_before = [labels(n) for n in tree() if expected in labels(n)]
        adb('shell', 'dumpsys SurfaceFlinger --timestats -clear -enable')
        frame_ns = set()
        layer = None
        for swipe in range(8):
            if layer is None:
                listing = adb('shell', 'dumpsys SurfaceFlinger --list').splitlines()
                layers = [s for s in listing if package in s and 'SurfaceView' in s]
                (out / (name + '-layers.txt')).write_text('\n'.join(layers))
                candidates = sorted(layers, key=lambda s: ('BLAST' not in s, s.startswith('Background'), len(s)))
            else:
                candidates = [layer]
            adb('shell', 'input swipe 360 1160 360 500 440')
            time.sleep(.15)
            for candidate in candidates:
                raw = adb('shell', 'dumpsys SurfaceFlinger --latency ' + shlex.quote(candidate))
                stamps = {int(a[1]) for line in raw.splitlines() if len(a := line.split()) == 3 and all(v.isdigit() for v in a) and 0 < int(a[1]) < 2**62}
                if stamps:
                    layer = candidate
                    frame_ns.update(stamps)
                    break
        stats = adb('shell', 'dumpsys SurfaceFlinger --timestats -dump -maxlayers 250')
        adb('shell', 'dumpsys SurfaceFlinger --timestats -disable')
        (out / (name + '-timestats.txt')).write_text(stats)
        visible_after = [labels(n) for n in tree() if expected in labels(n)]
        capture(name)
        if not visible_after or visible_before == visible_after:
            raise RuntimeError('Défilement non confirmé : ' + name)
        stamps = sorted(frame_ns)
        intervals = sorted((b-a)/1e6 for a,b in zip(stamps,stamps[1:]) if 0 < b-a <= 300_000_000)
        summary = {'before': visible_before, 'after': visible_after, 'layer': layer, 'intervals': len(intervals)}
        if intervals:
            summary.update(p50_ms=intervals[len(intervals)//2], p95_ms=intervals[math.ceil(.95*len(intervals))-1])
        (out / (name + '.json')).write_text(json.dumps(summary, indent=2))
        print(name, json.dumps(summary), flush=True)

    try:
        print('APK SHA256', hashlib.file_digest(open(apk, 'rb'), 'sha256').hexdigest(), flush=True)
        adb('install', '-r', apk)
        adb('shell', 'pm grant ' + package + ' android.permission.POST_NOTIFICATIONS', check=False)
        adb('shell', 'monkey -p ' + package + ' -c android.intent.category.LAUNCHER 1')
        add = wait_for(lambda n: 'Add an M3U list' in labels(n))
        capture('home')
        tap(add)
        field = wait_for(lambda n: n.get('class') == 'android.widget.EditText')
        tap(field)
        adb('shell', 'input text ' + HOST + '/liste.m3u')
        time.sleep(.6)
        adb('shell', 'input keyevent 4')
        tap(wait_for(lambda n: 'Load my channels' in labels(n)))
        wait_for(lambda n: 'Group 000' in labels(n), timeout=100, seek=True)
        measure('groups', 'Group ')
        for _ in range(35):
            first = next((n for n in tree() if 'Group 000' in labels(n)), None)
            if first is not None:
                break
            adb('shell', 'input swipe 345 450 345 1200 170')
        first = wait_for(lambda n: 'Group 000' in labels(n), seek=True)
        tap(first)
        wait_for(lambda n: 'Station ' in labels(n))
        measure('channels', 'Station ')
    finally:
        capture('final')
        adb('shell', 'am force-stop ' + package)


if __name__ == '__main__':
    if sys.argv[1] == 'serve':
        serve()
    else:
        probe(sys.argv[2], sys.argv[3])
