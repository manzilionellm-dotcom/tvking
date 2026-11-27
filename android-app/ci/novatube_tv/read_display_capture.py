"""Convertit une capture HDMI 16:9 des mires régionales en observations CSV.

Usage : python3 read_display_capture.py capture.mkv mesures.csv
Travailler sur une acquisition sans recadrage/overscan. La capture doit suivre
la sortie vidéo du téléviseur. Une image indécodable est marquée unknown.
Les temps sont les PTS de la capture ; les événements télécommande/réseau
doivent être relevés dans ce même référentiel pour calculer un délai.
"""
import argparse
import csv
import re
import subprocess
import tempfile
from pathlib import Path

from regional_live_source import CELLS, COUNTER_BITS, SIGNATURE


def decode(row):
    if any(60 < value < 190 for value in row):
        return '', ''
    bits = [int(value >= 190) for value in row]
    if tuple(bits[:7]) != SIGNATURE or bits[-1] != 1:
        return '', ''
    counter = bits[8:8 + COUNTER_BITS]
    if sum(counter) % 2 != bits[-2]:
        return '', ''
    return ('B' if bits[7] else 'A'), sum(bit << i for i, bit in enumerate(counter))


def extract(capture, target):
    # Chaque échantillon représente le centre d'une case de la bande vidéo.
    # showinfo associe chaque ligne décodée à son PTS réel, même en cadence variable.
    filters = f'crop=iw/2:4:iw/4:ih*0.6,scale={CELLS}:1:flags=area,format=gray,showinfo'
    timestamp = re.compile(r'\bn:\s*(\d+).*?\bpts_time:\s*([-+.0-9eE]+)')
    with tempfile.TemporaryDirectory(prefix='nova-capture-') as tmp:
        markers = Path(tmp) / 'markers.raw'
        traces = Path(tmp) / 'timestamps.log'
        with traces.open('w') as log:
            subprocess.run(['ffmpeg', '-nostdin', '-hide_banner', '-nostats',
                            '-i', str(capture), '-map', '0:v:0', '-an', '-vf', filters,
                            '-fps_mode', 'passthrough', '-f', 'rawvideo', '-pix_fmt', 'gray',
                            str(markers)], stderr=log, check=True)
        rows = 0
        valid = 0
        with markers.open('rb') as raw, traces.open() as log, target.open('x', newline='') as dest:
            writer = csv.writer(dest)
            writer.writerow(['capture_frame', 'capture_pts_s', 'channel', 'source_frame', 'status'])
            for line in log:
                match = timestamp.search(line)
                if not match:
                    continue
                row = raw.read(CELLS)
                if len(row) != CELLS or int(match[1]) != rows:
                    raise ValueError('Désalignement entre les horodatages et les images.')
                channel, frame = decode(row)
                valid += bool(channel)
                writer.writerow([rows, match[2], channel, frame, 'ok' if channel else 'unknown'])
                rows += 1
            if raw.read(1) or not rows:
                raise ValueError('Horodatages ou trames manquants dans la capture.')
        if not valid:
            raise ValueError('Aucune mire reconnue. Vérifier le cadrage et la piste vidéo.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('output_csv', type=Path)
    args = parser.parse_args()
    extract(args.capture, args.output_csv)
