"""Génère une mire publique sans contenu tiers pour comparer deux lecteurs sur la même TV."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


WIDTH = 3840
HEIGHT = 2160
MOVIE = 'mire-uhd-sdr.ts'
PLAYLIST = 'mire-uhd.m3u'
SUMS = 'mire-uhd-sommes.txt'


def image_ppm(path):
    # Une bande de gris et des lignes grises évitent de confondre sous-échantillonnage
    # des couleurs (4:2:0) et perte de netteté sur les détails de luminance.
    bars = [(220, 220, 220), (220, 220, 44), (44, 220, 220), (44, 220, 44),
            (220, 44, 220), (220, 44, 44), (44, 44, 220), (30, 30, 30)]
    top = b''.join(bytes(rgb) * (WIDTH // 8) for rgb in bars)
    grey = b''.join(bytes([round(x * 255 / (WIDTH - 1))]) * 3 for x in range(WIDTH))
    steps = (1, 2, 4, 8)
    vertical = b''.join(bytes([28 if (x // step) % 2 == 0 else 228]) * 3
                        for step in steps for x in range(WIDTH // 4))
    with path.open('wb') as dest:
        dest.write(f'P6\n{WIDTH} {HEIGHT}\n255\n'.encode('ascii'))
        for row in (top, grey, vertical):
            for _ in range(HEIGHT // 4):
                dest.write(row)
        for y in range(HEIGHT // 4):
            for step in steps:
                dest.write(bytes([28 if (y // step) % 2 == 0 else 228]) * (WIDTH // 4 * 3))


def ffmpeg(*args):
    subprocess.run(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error',
                    '-xerror', '-y', *map(str, args)], check=True)


def check_stream(path):
    data = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-of', 'json',
                                              '-show_streams', '-show_format', str(path)]))
    video, audio = data['streams']
    expected = {'codec_name': 'h264', 'profile': 'High', 'width': WIDTH, 'height': HEIGHT,
                'pix_fmt': 'yuv420p', 'color_range': 'tv', 'color_space': 'bt709',
                'color_transfer': 'bt709', 'color_primaries': 'bt709', 'avg_frame_rate': '25/1'}
    for key, value in expected.items():
        if video.get(key) != value:
            raise ValueError(f'Format vidéo inattendu : {key} = {video.get(key)!r}')
    if (audio.get('codec_name'), audio.get('sample_rate'), audio.get('channels')) != ('aac', '48000', 2):
        raise ValueError('Piste AAC stéréo 48 kHz attendue.')
    if abs(float(data['format']['duration']) - 60) > 0.1:
        raise ValueError('Durée attendue de 60 secondes.')
    # Décode une trame réelle et contrôle le contraste des traits verticaux
    # et horizontaux. Une mise à l’échelle ou une mire vide invalide le fichier.
    frame = subprocess.check_output(['ffmpeg', '-nostdin', '-v', 'error', '-xerror',
                                     '-threads', '2', '-i', str(path), '-map', '0:v:0',
                                     '-frames:v', '1', '-pix_fmt', 'gray', '-f', 'rawvideo', '-'])
    if len(frame) != WIDTH * HEIGHT:
        raise ValueError('Trame complète introuvable.')
    for index, step in enumerate((1, 2, 4, 8)):
        x = index * (WIDTH // 4) + 32
        vertical = (HEIGHT // 2 + 50) * WIDTH + x
        horizontal = (HEIGHT * 3 // 4 + 32) * WIDTH + x
        contrast_v = frame[vertical + step] - frame[vertical]
        contrast_h = frame[horizontal + step * WIDTH] - frame[horizontal]
        if min(contrast_v, contrast_h) < 120:
            raise ValueError(f'Contraste perdu sur les traits de {step} pixel(s).')


def generate(output, release_url):
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output) as tmp:
        root = Path(tmp)
        image_ppm(root / 'mire.ppm')
        # Une seconde intra/inter, répétée en copie sans 60 encodages UHD.
        # Le silence stéréo a une fréquence et des horodatages continus.
        ffmpeg('-loop', '1', '-framerate', '25', '-i', root / 'mire.ppm', '-t', '1', '-an',
               '-vf', 'scale=in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p',
               '-filter_threads', '1', '-c:v', 'libx264', '-threads', '2', '-profile:v', 'high',
               '-level:v', '5.1', '-preset', 'veryfast', '-crf', '12', '-g', '25', '-bf', '0',
               '-x264-params', 'colorprim=bt709:transfer=bt709:colormatrix=bt709',
               '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
               '-color_range', 'tv', root / 'seconde.mkv')
        ffmpeg('-stream_loop', '59', '-i', root / 'seconde.mkv', '-f', 'lavfi', '-i',
               'anullsrc=r=48000:cl=stereo', '-t', '60', '-map', '0:v:0', '-map', '1:a:0',
               '-c:v', 'copy', '-c:a', 'aac', '-b:a', '96k', '-f', 'mpegts', root / MOVIE)
        check_stream(root / MOVIE)
        (root / PLAYLIST).write_text('#EXTM3U\n#EXTINF:-1 group-title="Test",Mire UHD SDR 2160p25\n'
                                   + release_url.rstrip('/') + '/' + MOVIE + '\n', encoding='utf-8')
        with (root / SUMS).open('w', encoding='ascii') as manifest:
            for name in (MOVIE, PLAYLIST):
                with (root / name).open('rb') as asset:
                    digest = hashlib.file_digest(asset, 'sha256').hexdigest()
                manifest.write(f'{digest}  {name}\n')
        subprocess.run(['sha256sum', '--check', SUMS], cwd=root, check=True)
        for name in (MOVIE, PLAYLIST, SUMS):
            (root / name).replace(output / name)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sortie', type=Path)
    parser.add_argument('url_preversion', help='URL GitHub releases/download du tag de test')
    args = parser.parse_args()
    generate(args.sortie, args.url_preversion)
