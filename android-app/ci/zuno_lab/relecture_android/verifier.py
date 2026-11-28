"""Vérifie l'écran final du TS local créé par REC, après redémarrage, source débranchée."""
import csv
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from android_ui import visible_nodes
from optical_witness import ALLOWED, APK_PACKAGE, adb, key, read_marker, screen, tap, words
from zuno_ui_path import control, normalized

RECORDINGS = ('my recordings', 'mes enregistrements')
ENDED = ('playback finished', 'lecture terminee')
ALLOWED.update('recordings recorded videos button recording playback finished enregistrements enregistre termine terminee lecture parental device profiles back return press'.split())


def scene():
    image = screen()
    try:
        nodes = visible_nodes(APK_PACKAGE)
    except (OSError, subprocess.SubprocessError):
        nodes = []
    return nodes, words(image), image.size


def verify(out):
    history = json.loads((out.parent / 'rec' / 'session.json').read_text())
    decoded = next(item for item in history if item['event'] == 'decode_apres_reboot')
    duration = float(decoded['file']['format']['duration'])
    if not 598 <= duration <= 680:
        raise RuntimeError('Durée du TS non conforme à la série fixée')
    out.mkdir()
    def note(action, **values):
        with (out / 'actions.jsonl').open('a') as target:
            print(json.dumps(dict(action=action, host_s=time.monotonic(),
                                  utc=datetime.now(timezone.utc).isoformat(), **values)), file=target)
    adb('reverse', '--remove', 'tcp:18471', check=False)
    if 'tcp:18471' in adb('reverse', '--list').decode():
        raise RuntimeError('La mire reste joignable par le port source')
    note('mire_deconnectee', sha256_ts=decoded['sha256'], duration_s=duration)
    settings_opened = False
    last_card = -10
    for shot in range(45):
        nodes, labels, size = scene()
        def find(group):
            return control(nodes, labels, size, group)
        card, row = find(RECORDINGS), find(('mire a',))
        settings = find(('settings', 'reglages'))
        hub = settings and find(('server', 'serveur')) and find(('live', 'direct'))
        if card and row and (settings_opened or not hub):
            tap(*row)
            note('ouvrir_ligne_fichier', mode='ligne Mire A dans Mes enregistrements')
            break
        if hub and not settings_opened:
            tap(*settings)
            settings_opened = True
            note('ouvrir_reglages')
        elif card and shot - last_card >= 2:
            tap(*card)
            time.sleep(.8)
            inside, _, _ = scene()
            row_open = any('mire a' in normalized(entry[0]) for entry in inside)
            if not row_open:
                key('KEYCODE_DPAD_CENTER')
            last_card = shot
            note('choisir_rubrique', clic_et_ok=not row_open)
        elif settings_opened:
            key('KEYCODE_DPAD_RIGHT')
            note('parcourir_ruban', index=shot)
        elif shot in (2, 6, 12, 19):
            key('KEYCODE_BACK')
        time.sleep(.6)
    else:
        raise RuntimeError('La ligne du fichier reste non identifiée')
    start = time.monotonic()
    moving = 0
    last = first = finish = None
    with (out / 'compteurs.csv').open('w') as target:
        writer = csv.writer(target)
        writer.writerow(('capture_avant_s', 'capture_apres_s', 'chaine', 'compteur'))
        while time.monotonic() < start + duration + 40:
            beginning = time.monotonic()
            try:
                channel, count, _ = read_marker(screen())
            except (OSError, subprocess.SubprocessError):
                channel, count = None, None
            end = time.monotonic()
            writer.writerow((beginning, end, channel, count))
            target.flush()
            if channel == 'A':
                if first is None:
                    first = end
                if last is not None and 0 < (count - last) % 3000 < 300:
                    moving += 1
                last = count
            if end - start > duration - 10:
                nodes, labels, size = scene()
                if control(nodes, labels, size, ENDED):
                    finish = time.monotonic()
                    break
            if end - start > 40 and moving == 0:
                break
            time.sleep(max(0, 2 - (time.monotonic() - beginning)))
    note('issue', mouvements_observes=moving, premiere_image_s=first-start if first else None,
         fin_ecran_s=finish-start if finish else None, duree_media_s=duration)
    if moving < duration * .30 or finish is None or finish - start < duration - 8:
        raise RuntimeError('Mouvement et écran de fin du fichier ne sont pas tous deux prouvés')


if __name__ == '__main__':
    verify(Path(sys.argv[1]))
