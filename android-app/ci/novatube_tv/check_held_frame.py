"""Contrôle le cadrage avant, pendant et après une coupure de la mire HLS A.

Usage : python3 check_held_frame.py reprise-directe-60s.zip
Code 0 si les quatre captures conservent les six barres et le compteur central.
La mire arrêtée peut présenter le même numéro de trame sur plusieurs captures.
"""
import argparse
import io
import json
from pathlib import Path
from statistics import median
import zipfile

from PIL import Image

from read_display_capture import decode


EXPECTED = ['R', 'G', 'RG', 'B', 'RB', 'GB']
CAPTURES = ['before.png', 'during.png', 'first-post.png', 'two-advances.png']


def inspect(data):
    with Image.open(io.BytesIO(data)) as bitmap:
        image = bitmap.convert('RGB')
    w, h = image.size
    bars = []
    for i in range(6):
        # La mire testsrc2 anime des formes par-dessus les barres. Échantillonner
        # la moitié centrale de chaque barre sur cinq lignes distinctes.
        patch = [image.getpixel((round((i + x) * w / 6), round(y * h)))
                 for x in (.25, .375, .5, .625, .75) for y in (.055, .075, .095, .115, .135)]
        rgb = [median(values) for values in zip(*patch)]
        bars.append(''.join(ch for ch, value in zip('RGB', rgb) if value > 156))
    gray = image.convert('L')
    row = [gray.getpixel((round(w*(496+32*i)/1920), round(h*650/1080))) for i in range(30)]
    channel, frame = decode(row)
    return {'bars': bars, 'channel': channel, 'source_frame': frame,
            'framing_ok': bars == EXPECTED and channel == 'A'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    args = parser.parse_args()
    with zipfile.ZipFile(args.archive) as bundle:
        result = {name: inspect(bundle.read(name)) for name in CAPTURES}
    print(json.dumps(result, indent=2))
    return all(sample['framing_ok'] for sample in result.values())


if __name__ == '__main__':
    raise SystemExit(0 if main() else 1)
