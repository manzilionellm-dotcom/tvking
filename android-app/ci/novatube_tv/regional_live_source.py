"""Mires HLS en direct pour comparer trois lecteurs TV sur la même entrée.

Exemple sur le réseau de test :
  python3 regional_live_source.py --bind 192.0.2.10 --port 8080
Charger /channels.m3u dans chaque lecteur. Filmer la télécommande et l'écran
sur la même base de temps. Le numéro de trame incrusté permet de distinguer
une image figée, une première image animée et des trames source non affichées.
Le direct continue côté serveur pendant chaque coupure du réseau de la box.
"""
import argparse
import functools
import http.server
import signal
import subprocess
import tempfile
import time
from pathlib import Path


# Bande centrale de 30 cases, décodable sur une capture 16:9 plein écran.
# La signature et la parité écartent les images de menu ou masquées par un OSD.
SIGNATURE = (1, 0, 1, 1, 0, 1, 0)
COUNTER_BITS = 20
CELLS = 30


def marker(channel):
    digits = [f'mod(floor(n/{1 << bit}),2)' for bit in range(COUNTER_BITS)]
    bits = [str(i) for i in SIGNATURE] + [str(int(channel == 'B'))] + digits
    bits.extend(['mod(' + '+'.join(digits) + ',2)', '1'])
    return ','.join(
        f"drawbox=x={480 + 32 * index}:y=640:w=32:h=20:color=white:t=fill:enable='{value}'"
        for index, value in enumerate(bits) if value != '0'
    )


def encode(channel, output):
    # Deux canaux aux mêmes GOP, cadence et profil. La lettre et la tonalité
    # distinguent le nouveau canal de la dernière image du canal précédent.
    stamp = (
        "drawbox=x=iw/4:y=ih*0.38:w=iw/2:h=ih*0.24:color=black:t=fill,"
        f"drawtext=text='{channel}  %{{n}}':fontcolor=white:fontsize=94:"
        "x=(w-tw)/2:y=(h-th)/2"
    )
    source = "testsrc2=size=1920x1080:rate=25"
    if channel == 'B':
        stamp = 'hflip,' + stamp
    return subprocess.Popen([
        'ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error',
        '-re', '-f', 'lavfi', '-i', source, '-f', 'lavfi', '-i',
        f"sine=frequency={440 if channel == 'A' else 660}:sample_rate=48000",
        '-vf', stamp + ',' + marker(channel), '-c:v', 'libx264', '-preset', 'ultrafast', '-threads', '2',
        '-pix_fmt', 'yuv420p', '-g', '50', '-keyint_min', '50', '-sc_threshold', '0',
        '-b:v', '4M', '-maxrate', '4M', '-bufsize', '8M',
        '-c:a', 'aac', '-ac', '2', '-b:a', '128k', '-f', 'hls', '-hls_time', '2',
        '-hls_list_size', '8', '-hls_delete_threshold', '2',
        '-hls_flags', 'delete_segments+temp_file+independent_segments',
        '-hls_segment_filename', str(output / 'segment%08d.ts'), str(output / 'index.m3u8')
    ])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bind', default='127.0.0.1',
                        help='Adresse IPv4 du banc accessible aux box')
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--duration', type=int, help='Durée de service en secondes, après préparation')
    args = parser.parse_args()
    if args.duration is not None and args.duration < 1:
        parser.error('La durée doit être positive.')
    if args.bind in ('0.0.0.0', ''):
        parser.error('Utiliser une adresse précise, joignable depuis la box.')
    with tempfile.TemporaryDirectory(prefix='novatube-live-') as root:
        folder = Path(root)
        channels = ('A', 'B')
        procs = []
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
        server = http.server.ThreadingHTTPServer((args.bind, args.port), handler)
        server.timeout = 0.5
        origin = f'http://{args.bind}:{server.server_port}'
        lines = ['#EXTM3U']
        stop = False

        def on_stop(_signal, _frame):
            nonlocal stop
            stop = True

        signal.signal(signal.SIGINT, on_stop)
        signal.signal(signal.SIGTERM, on_stop)
        try:
            for channel in channels:
                dest = folder / channel
                dest.mkdir()
                procs.append(encode(channel, dest))
                lines.extend([f'#EXTINF:-1,Mire {channel}', f'{origin}/{channel}/index.m3u8'])
            # Les mêmes fichiers sont distribués à tous les clients connectés.
            # Trois segments publiés laissent aux lecteurs une fenêtre de départ.
            deadline = time.monotonic() + 60
            while not stop:
                if any(proc.poll() is not None for proc in procs):
                    raise RuntimeError('Un encodeur a quitté le banc de test.')
                ready = all(len(list((folder / ch).glob('segment*.ts'))) >= 3 for ch in channels)
                if ready:
                    break
                if time.monotonic() > deadline:
                    raise TimeoutError('Les mires ne sont pas prêtes après 60 s.')
                time.sleep(0.2)
            if stop:
                return
            (folder / 'channels.m3u').write_text('\n'.join(lines) + '\n', encoding='utf-8')
            print(f'{origin}/channels.m3u', flush=True)
            end = time.monotonic() + args.duration if args.duration else None
            while not stop and (end is None or time.monotonic() < end):
                if any(proc.poll() is not None for proc in procs):
                    raise RuntimeError('Un encodeur a quitté le banc de test.')
                server.handle_request()
        finally:
            server.server_close()
            for proc in procs:
                if proc.poll() is None:
                    proc.terminate()
            for proc in procs:
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()


if __name__ == '__main__':
    main()
