#!/usr/bin/env python3
"""Parcours visible du vrai APK : M3U, lecture, Cast, fond, notification, arrêt.

Les gestes partent des libellés OCR ou d'accessibilité de l'écran courant.
Les critères du service et du récepteur sont contrôlés indépendamment de
l'image. Si un critère échoue, la capture reste un diagnostic, jamais une
démonstration validée.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import unicodedata
from urllib.request import urlopen
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops, ImageStat

PLAY_PACKAGE = 'com.sevenmotion.novatube.tv'
LAB_PACKAGE = 'com.sevenmotion.novatube.tv.lab.retour.rec'


def normalise(value):
    return ''.join(c for c in unicodedata.normalize('NFKD', value).lower() if c.isalnum())


def displayed_pattern(image):
    """Recognise the six colour bars of the generated FFmpeg testsrc2 pattern."""
    thumb = image.convert('RGB').resize((96, 54))
    bars = [(1, 0, 0), (0, 1, 0), (1, 1, 0), (0, 0, 1), (1, 0, 1), (0, 1, 1)]
    matches = 0
    for x, expected in enumerate(bars):
        hits = 0
        for y in range(17, 35):
            rgb = thumb.getpixel((8 + x * 16, y))
            peak = max(rgb)
            if peak > 70 and tuple(c > peak * .65 for c in rgb) == expected:
                hits += 1
        matches += hits >= 8
    return thumb.crop((10, 8, 86, 43)), matches


class Scenario:
    def __init__(self, out, serial, expected_version=1794878684, expected_source=None, expected_api=34,
                 package=PLAY_PACKAGE, expected_digest=None):
        self.out, self.serial = out, serial
        self.package, self.expected_digest = package, expected_digest
        self.expected_version = expected_version
        self.expected_source = expected_source
        self.expected_api = expected_api
        self.started = time.monotonic()
        self.recording = None
        self.recording_quality_passed = False
        self.report = {'validated': False, 'package': self.package,
                       'receiver': 'FFmpeg DLNA receiver (emulated)', 'steps': []}

    def adb(self, *args, timeout=20, binary=False):
        return subprocess.check_output(['adb', '-s', self.serial, *args],
                                       timeout=timeout, text=not binary)

    def step(self, text, **details):
        entry = {'elapsed_seconds': round(time.monotonic() - self.started, 2),
                 'step': text, **details}
        self.report['steps'].append(entry)
        self.save()
        print(json.dumps(entry), flush=True)

    def save(self):
        (self.out / 'scenario-report.json').write_text(json.dumps(self.report, indent=2) + '\n')

    def require_public_screen(self):
        if (self.out.parent / 'private-input-active').exists():
            raise RuntimeError('Private input is active; screen capture and recording refused')

    def screenshot(self, name='current'):
        self.require_public_screen()
        path = self.out / f'{name}.png'
        data = self.adb('exec-out', 'screencap', '-p', binary=True)
        # Le verrou peut apparaître pendant la commande ADB : ne rien écrire.
        self.require_public_screen()
        path.write_bytes(data)
        with Image.open(path) as im:
            self.width, self.height = im.size
        return path

    def words(self, name='current'):
        path = self.screenshot(name)
        # Sur certaines images Google, le canal alpha de screencap est nul.
        # Tesseract reçoit les couleurs visibles, indépendamment de cet alpha.
        with Image.open(path) as screen:
            pixels = io.BytesIO()
            screen.convert('RGB').save(pixels, format='PNG')
        result = subprocess.check_output(['tesseract', 'stdin', 'stdout', '--psm', '11', 'tsv'],
                                         input=pixels.getvalue(), stderr=subprocess.DEVNULL, timeout=20).decode()
        words = []
        for word in csv.DictReader(io.StringIO(result), delimiter='\t'):
            text = normalise(word['text'] or '')
            if text:
                words.append((text, int(word['left']) + int(word['width']) // 2,
                              int(word['top']) + int(word['height']) // 2))
        return words

    def find(self, expression, bounds=(0, 0, 1, 1), timeout=20):
        deadline = time.monotonic() + timeout
        while True:
            for word, x, y in self.words():
                if (re.fullmatch(expression, word)
                        and bounds[0] <= x / self.width <= bounds[2]
                        and bounds[1] <= y / self.height <= bounds[3]):
                    return x, y
            if time.monotonic() >= deadline:
                return None
            time.sleep(0.6)

    def tap_word(self, expression, bounds=(0, 0, 1, 1), timeout=20):
        point = self.find(expression, bounds, timeout)
        if point is None:
            raise RuntimeError(f'Libellé visible introuvable : {expression}')
        self.adb('shell', 'input', 'tap', str(point[0]), str(point[1]))
        time.sleep(1.2)

    def lab_import_button(self):
        deadline = time.monotonic() + 50
        while time.monotonic() < deadline:
            words = self.words()
            middle = [(word, x, y) for word, x, y in words if 0.25 < y / self.height < 0.80]
            for word, x, y in middle:
                if word == 'm3u':
                    return x, y
            # Certains rendus découpent mal « M3U ». Les mots voisins
            # identifient alors le même bouton visible « Add ... playlist ».
            for word, x, y in middle:
                if word in {'playlist', 'liste'} and any(
                    other in {'add', 'ajouter'} and 0 < x - ox < 0.25 * self.width
                    and abs(y - oy) < 0.025 * self.height for other, ox, oy in middle):
                    return x, y
            time.sleep(0.5)
        raise RuntimeError('Bouton M3U de l’accueil tactile introuvable')

    def lab_home(self, timeout):
        # Les deux variantes de l'accueil LAB ont la navigation en commun.
        deadline = time.monotonic() + timeout
        while True:
            words = {word for word, _, _ in self.words()}
            if 'tonight' in words or (words & {'live', 'direct'} and
                    words & {'settings', 'reglages', 'movies', 'films', 'series', 'favorites', 'favoris'}):
                return True
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.5)

    def cast_point(self, timeout):
        bounds = (0.55, 0, 1, 0.3)
        if self.package != LAB_PACKAGE:
            return self.find('cast', bounds=bounds, timeout=timeout)
        return (self.find('cast', bounds=bounds, timeout=min(timeout, 2))
                or self.accessibility_point(r'cast to a tv|caster vers|diffuser sur|cast vers')
                or self.find('cast', bounds=bounds, timeout=timeout))

    def key(self, value, delay=1.5):
        self.adb('shell', 'input', 'keyevent', value)
        time.sleep(delay)

    def accessibility_point(self, expression, resource=None, package=None, region=None):
        self.require_public_screen()
        try:
            self.adb('shell', 'uiautomator', 'dump', '--compressed', '/sdcard/novatube-ui.xml', timeout=12)
            xml = self.adb('shell', 'cat', '/sdcard/novatube-ui.xml')
            self.require_public_screen()
            (self.out / 'current-ui.xml').write_text(xml)
            for node in ET.fromstring(xml).iter('node'):
                label = ' '.join([node.attrib.get('text', ''), node.attrib.get('content-desc', '')])
                if package and node.attrib.get('package') != package:
                    continue
                if not (re.search(expression, label, re.IGNORECASE)
                        or (resource and re.search(resource, node.attrib.get('resource-id', '')))):
                    continue
                if node.attrib.get('visible-to-user') == 'false':
                    continue
                coords = [int(n) for n in re.findall(r'\d+', node.attrib.get('bounds', ''))]
                if len(coords) == 4 and coords[2] > coords[0] and coords[3] > coords[1]:
                    x, y = (coords[0] + coords[2]) // 2, (coords[1] + coords[3]) // 2
                    if region and not (region[0] <= x/self.width <= region[2] and region[1] <= y/self.height <= region[3]):
                        continue
                    return x, y
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError, ET.ParseError):
            return None
        return None

    def receiver(self):
        with urlopen('http://127.0.0.1:18999/status.json', timeout=5) as response:
            return json.load(response)

    def service(self, name):
        text = self.adb('shell', 'dumpsys', 'activity', 'services', self.package)
        (self.out / f'{name}-services.txt').write_text(text)
        block = re.search(r'ServiceRecord[^\n]*PlaybackForegroundService[\s\S]*?(?=\n\s*\* ServiceRecord|\Z)', text)
        active = block is not None and re.search(r'\bisForeground=true\b', block.group(0)) is not None
        if active:
            # API 34 écrit types=00000002. Certaines versions écrivent
            # foregroundServiceType=0x2 ou =2 dans ce même ServiceRecord.
            media_type = re.search(r'\b(?:types=0*2|foregroundServiceType=(?:0x)?0*2)\b', block.group(0))
            assert media_type, 'Type mediaPlayback du service non confirmé'
        return active, text

    def allow_notifications(self):
        # L'autorisation est donnée dans le dialogue système réellement visible.
        point = self.accessibility_point(r'^\s*Allow\s*$|^\s*Autoriser\s*$', resource=r':id/permission_allow_button$')
        if point:
            self.adb('shell', 'input', 'tap', str(point[0]), str(point[1]))
            self.step('Notification permission accepted using visible Android dialog')
            time.sleep(1)

    def local_pattern_motion(self):
        deadline = time.monotonic() + 45
        previous = None
        while time.monotonic() < deadline:
            path = self.screenshot('04-local-playback')
            with Image.open(path) as image:
                frame, bars = displayed_pattern(image)
            if bars >= 5:
                if previous is None:
                    (self.out / '04-local-playback-first.png').write_bytes(path.read_bytes())
                else:
                    movement = sum(max(pixel) > 30 for pixel in ImageChops.difference(previous, frame).getdata())
                    if movement >= frame.width * frame.height * .008:
                        self.report['local_playback_motion'] = {'recognized_bars': bars, 'changing_pixels': movement,
                            'analyzed_pixels': frame.width * frame.height}
                        return
                previous = frame
            time.sleep(0.65)
        raise RuntimeError('La mire en mouvement n’est pas apparue sur le téléphone avant le Cast')

    def run(self):
        self.require_public_screen()
        actual_api = int(self.adb('shell', 'getprop', 'ro.build.version.sdk').strip())
        self.report['android_api'] = actual_api
        self.report['android_release'] = self.adb('shell', 'getprop', 'ro.build.version.release').strip()
        assert actual_api == self.expected_api, 'Version Android inattendue'
        package = self.adb('shell', 'dumpsys', 'package', self.package)
        version = re.search(r'\bversionCode=(\d+)\b', package)
        assert version, 'Version de l’APK installé absente'
        self.report['version_code'] = int(version.group(1))
        self.report['production_review_candidate'] = False
        assert self.report['version_code'] == self.expected_version, 'Mauvaise version APK installée'
        if self.package == PLAY_PACKAGE and self.expected_version == 1794878684:
            identity = json.loads((self.out / 'build-identity.json').read_text())
            assert self.expected_source and identity['source_commit'] == self.expected_source, 'Commit source non confirmé'
            assert identity['package'] == self.package and identity['version_code'] == self.expected_version
            assert identity['play_build'] is True
            installed = self.adb('shell', 'pm', 'path', self.package).strip().splitlines()
            assert len(installed) == 1 and installed[0].startswith('package:'), 'APK universel attendu'
            digest = self.adb('shell', 'sha256sum', installed[0].removeprefix('package:'), timeout=90).split()[0]
            recording_apk = identity.get('recording_apk')
            if recording_apk is not None:
                expected = recording_apk['sha256']
            else:
                apk_files = [value for name, value in identity['files'].items() if name.endswith('.apk')]
                assert len(apk_files) == 1, 'L’APK à filmer doit être désigné sans ambiguïté'
                expected = apk_files[0]['sha256']
            assert digest == expected, 'Empreinte de l’APK installé différente du build vérifié'
            self.report.update(production_review_candidate=True, source_commit=identity['source_commit'],
                               apk_sha256=digest, build_environment=identity.get('build_environment', 'unspecified'))
        elif self.package != PLAY_PACKAGE:
            assert re.fullmatch(r'[0-9a-f]{64}', self.expected_digest or ''), 'Empreinte du LAB absente'
            installed = self.adb('shell', 'pm', 'path', self.package).strip().splitlines()
            assert len(installed) == 1 and installed[0].startswith('package:'), 'APK universel attendu'
            digest = self.adb('shell', 'sha256sum', installed[0].removeprefix('package:'), timeout=90).split()[0]
            assert digest == self.expected_digest, 'Le LAB installé diffère du fichier à livrer'
            self.report.update(apk_sha256=digest, source_commit=self.expected_source)
        self.step('Installed APK opened on the touchscreen emulator', android_api=actual_api)
        if self.package == LAB_PACKAGE:
            x, y = self.lab_import_button()
            self.screenshot('01-welcome')
            self.adb('shell', 'input', 'tap', str(x), str(y))
            assert self.find('source|url|http|file|fichier|link|m3u8', timeout=20), 'Formulaire M3U absent'
        else:
            assert self.find('m3u', timeout=45), 'Accueil M3U absent'
            self.screenshot('01-welcome')
            # L'activation précédente peut avoir déplacé le focus.
            self.tap_word('m3u', timeout=10)
        self.screenshot('02-import-form')
        self.adb('shell', 'input', 'text', 'http://127.0.0.1:18999/review.m3u')
        self.key('KEYCODE_ENTER', 3)
        home = self.lab_home if self.package == LAB_PACKAGE else lambda delay: self.find('tonight', timeout=delay)
        if not home(4):
            self.key('KEYCODE_DPAD_CENTER', 2)
        assert home(35), 'Accueil après import absent'
        self.step('User imported a local M3U containing one generated video only')
        self.screenshot('03-imported-home')

        self.require_public_screen()
        # Un échec de démarrage ne doit jamais recycler une vidéo précédente.
        self.adb('shell', 'rm', '-f', '/sdcard/novatube-fgs-review.mp4')
        (self.out / 'novatube-fgs-review.mp4').unlink(missing_ok=True)
        self.recording = subprocess.Popen(['adb', '-s', self.serial, 'shell', 'screenrecord',
            '--size', '1280x720', '--bit-rate', '3500000', '--time-limit', '170',
            '/sdcard/novatube-fgs-review.mp4'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.recording_started = time.monotonic()
        time.sleep(3)
        if self.recording.poll() is not None:
            raise RuntimeError('Android screen recording failed to start; no prior video accepted')
        self.step('Continuous unedited Android screen recording started')
        self.tap_word('live|direct')
        assert self.find('mire', timeout=20), 'Chaîne locale absente'
        self.tap_word('mire', bounds=(0.15, 0, 0.65, 1))
        if not self.cast_point(3):
            self.key('KEYCODE_DPAD_CENTER', 3)
        assert self.cast_point(12), 'Lecteur tactile ou bouton Cast absent'
        if self.package == LAB_PACKAGE:
            self.local_pattern_motion()
        else:
            time.sleep(6)
            self.screenshot('04-local-playback')
        self.step('Synthetic video visibly opened in the normal full-screen player')
        before, _ = self.service('before-cast')
        assert not before, 'Le service était déjà actif avant le geste Cast'
        point = self.cast_point(12)
        assert point, 'Commande Cast du lecteur introuvable'
        self.adb('shell', 'input', 'tap', str(point[0]), str(point[1]))
        time.sleep(1.2)
        self.screenshot('05-cast-picker')
        if self.package == LAB_PACKAGE:
            point = self.find('receiver', timeout=12) or self.accessibility_point(r'NOVATUBE QA Receiver')
            point = point or self.find('receiver', timeout=13)
            assert point, 'Récepteur DLNA de test introuvable dans le sélecteur'
            self.adb('shell', 'input', 'tap', str(point[0]), str(point[1]))
            time.sleep(1.2)
        else:
            self.tap_word('receiver', timeout=25)
        self.step('User selected the discovered emulated DLNA receiver from the normal Cast picker')

        deadline = time.monotonic() + 50
        while time.monotonic() < deadline:
            state = self.receiver()
            active, _ = self.service('during-cast')
            if active and state['decoded_frames'] >= 10 and state['state'] == 'PLAYING':
                break
            time.sleep(1)
        else:
            raise RuntimeError('Cast réel ou foreground service non confirmé')
        self.allow_notifications()
        self.screenshot('06-casting-service-active')
        self.step('Real relay decoded by receiver and Android foreground media service active', receiver=state)
        self.key('KEYCODE_HOME', 4)
        self.screenshot('07-home-while-casting')
        background_start = self.receiver()
        time.sleep(9)
        background_end = self.receiver()
        active, text = self.service('background')
        assert active, 'Service perdu après Home'
        assert background_end['decoded_frames'] > background_start['decoded_frames'] + 75, 'Le récepteur ne lit plus en arrière-plan'
        assert background_end['state'] == 'PLAYING'
        assert background_end['relay_upstream_bytes_sent'] > background_start['relay_upstream_bytes_sent'] + 24_000, 'Aucun nouvel octet du relais en arrière-plan'
        activities = self.adb('shell', 'dumpsys', 'activity', 'activities')
        resumed = '\n'.join(line for line in activities.splitlines() if 'ResumedActivity' in line)
        (self.out / 'background-resumed-activity.txt').write_text(resumed + '\n')
        home = self.adb('shell', 'cmd', 'package', 'resolve-activity', '--brief',
                        '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME').strip().splitlines()[-1]
        home_package = home.split('/')[0]
        assert resumed and '/' in home and home_package in resumed and self.package not in resumed, 'Accueil Android repris non confirmé'
        self.step('Home displayed while receiver continues decoding and service stays foreground',
                  before_frames=background_start['decoded_frames'], after_frames=background_end['decoded_frames'],
                  before_relay_bytes=background_start['relay_upstream_bytes_sent'],
                  after_relay_bytes=background_end['relay_upstream_bytes_sent'])

        self.adb('shell', 'cmd', 'statusbar', 'expand-notifications')
        time.sleep(3)
        self.screenshot('08-media-notification')
        notifications = self.adb('shell', 'dumpsys', 'notification', '--noredact')
        # Seule la fiche du paquet contrôlé est conservée, sans les autres apps.
        match = re.search(r'NotificationRecord\([^\n]*pkg=' + re.escape(self.package) + r'[^\n]*[\s\S]*?(?=\n\s*NotificationRecord\(|\n\s*Ranking Config|\Z)', notifications)
        (self.out / 'media-notification.txt').write_text(match.group(0) if match else 'Notification record not located\n')
        assert match and ('1002' in match.group(0) or 'playback_channel' in match.group(0)), 'Notification du service introuvable'
        visible_words = {word for word, _, _ in self.words('08-media-notification-visible')}
        if self.package == LAB_PACKAGE:
            title = self.accessibility_point(r'mire locale novatube', package='com.android.systemui')
            self.report['notification_title_in_systemui'] = title is not None
            assert title or ('mire' in visible_words and 'locale' in visible_words), 'Titre du relais absent du volet Android'
            self.screenshot('08-media-notification-visible')
        else:
            assert 'mire' in visible_words and ('streaming' in visible_words or 'diffusion' in visible_words), 'Notification du relais non visible à l’écran'
        self.step('Android media foreground notification displayed')
        time.sleep(4)
        self.key('KEYCODE_BACK', 1)
        self.adb('shell', 'am', 'start', '-n', self.component)
        time.sleep(4)
        point = self.accessibility_point(r'stop casting|arrêter la diffusion|arrêter le cast')
        if point is None:
            self.screenshot('stop-control-not-found')
            raise RuntimeError('Commande visible Stop casting introuvable : aucune commande interne substituée')
        self.adb('shell', 'input', 'tap', str(point[0]), str(point[1]))
        self.step('User pressed the visible Stop casting button')
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            active, _ = self.service('after-stop')
            stopped = self.receiver()
            if not active and stopped['state'] == 'STOPPED':
                break
            time.sleep(1)
        else:
            raise RuntimeError('Arrêt du relais/service non confirmé')
        self.screenshot('09-user-stopped-cast')
        time.sleep(4)
        self.step('Foreground service and receiver stopped after visible user command')

    def touch_record_control(self, start):
        expression = 'rec|record|enregistrer' if start else 'stop|arret|arreter'
        region = (0, 0.5, 1, 1)
        for attempt in range(3):
            point = self.find(expression, bounds=region, timeout=0)
            if point is None:
                point = self.accessibility_point(r'^\s*(?:' + expression + r')\s*$', region=region, package=self.package)
            if point:
                name = '10-tap-record' if start else '11-tap-stop-recording'
                self.screenshot(name)
                self.adb('shell', 'input', 'tap', str(point[0]), str(point[1]))
                return {'label': expression, 'x': point[0], 'y': point[1], 'screenshot': name + '.png'}
            # Au centre de l'image, le vrai geste ouvre la barre pendant six secondes.
            # L'aire de recherche exclut la pastille REC permanente en haut à gauche.
            if attempt < 2:
                self.adb('shell', 'input', 'tap', str(self.width // 2), str(self.height // 2))
                time.sleep(0.4)
        raise RuntimeError('Bouton tactile du lecteur introuvable : ' + expression)

    def verify_handset_recording(self):
        sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'novatube_tv'))
        from verify_local_recording import Device, MEDIA, audio_tone, wait_for_new_movie
        output = self.out / 'local-recording'
        output.mkdir(exist_ok=True)
        device = Device(self.serial)
        previous = device.rows()
        self.step('Touchscreen recording check started after the Cast scenario')
        start = self.touch_record_control(True)
        time.sleep(16)
        stop = self.touch_record_control(False)
        row = wait_for_new_movie(device, previous, self.package, 'Movies/NOVATUBE', 90)
        assert row['mime_type'] == 'video/mp4' and row['name'].lower().endswith('.mp4'), row
        video = output / 'handset-recording.mp4'
        digest = device.export(row, video)
        probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries',
            'format=format_name,duration:stream=codec_name,codec_type', '-of', 'json', str(video)]))
        tracks = {(s['codec_type'], s['codec_name']) for s in probe['streams']}
        assert {('video', 'h264'), ('audio', 'aac')} <= tracks, probe
        assert 'mp4' in probe['format']['format_name'].split(','), probe
        assert 9 <= float(probe['format']['duration']) <= 35, probe
        # Des vignettes de la mire décodées deux fois par seconde doivent changer.
        framemd5 = subprocess.check_output(['ffmpeg', '-nostdin', '-v', 'error', '-i', str(video),
            '-map', '0:v:0', '-vf', 'fps=2,scale=64:36', '-f', 'framemd5', '-'], text=True, timeout=45)
        (output / 'motion.framemd5').write_text(framemd5)
        hashes = [line.rsplit(',', 1)[-1].strip() for line in framemd5.splitlines()
                  if line and not line.startswith('#')]
        changes = sum(a != b for a, b in zip(hashes, hashes[1:]))
        assert len(hashes) >= 16 and changes > 0.80 * (len(hashes) - 1), 'Image de la mire figée'
        tone = audio_tone(video, output / 'audio-temp.pcm', 'A')
        self.adb('shell', 'am', 'force-stop', self.package)
        self.adb('shell', 'am', 'start', '-W', '-n', self.component)
        current = device.rows().get(row['id'])
        assert current == row, 'Ligne MediaStore modifiée après redémarrage'
        reread = output / 'after-restart.mp4'
        assert device.export(current, reread) == digest, 'Fichier MediaStore modifié après redémarrage'
        reread.unlink()
        proof = {'uri': f"{MEDIA}/{row['id']}", 'media_store': row, 'sha256': digest,
                 'record_control': start, 'stop_control': stop, 'probe': probe, 'audio': tone,
                 'decoded_thumbnails': len(hashes), 'changing_pairs': changes,
                 'identical_after_app_restart': True, 'apk_sha256': self.report['apk_sha256']}
        (output / 'proof.json').write_text(json.dumps(proof, indent=2) + '\n')
        self.report['handset_local_recording'] = proof
        self.step('User recorded the moving test pattern and its tone by touch; shared MP4 survived app restart')

    def verify_recorded_frames(self, video, duration):
        # Les images proviennent du MP4, jamais de screencap. Une capture ADB
        # correcte ne prouve pas que l'encodeur vidéo a enregistré l'écran.
        frames = []
        for number, fraction in enumerate((0.10, 0.30, 0.50, 0.70, 0.90), 1):
            timestamp = duration * fraction
            path = self.out / f'recorded-frame-{number:02d}.png'
            path.unlink(missing_ok=True)
            subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-nostdin',
                            '-y', '-ss', f'{timestamp:.3f}', '-i', str(video),
                            '-frames:v', '1', '-threads', '1', str(path)],
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
            with Image.open(path) as image:
                gray = image.convert('L')
                histogram = gray.histogram()
                black_fraction = sum(histogram[:16]) / (gray.width * gray.height)
                digest = hashlib.sha256(gray.tobytes()).hexdigest()
            frames.append({'file': path.name, 'timestamp_seconds': round(timestamp, 3),
                           'black_pixel_fraction': round(black_fraction, 6),
                           'mostly_black': black_fraction >= 0.98, 'pixels_sha256': digest})
        self.report['recorded_frame_checks'] = frames
        if sum(frame['mostly_black'] for frame in frames) >= 3:
            raise RuntimeError('Most sampled MP4 frames are black; recording is diagnostic only')
        if len({frame['pixels_sha256'] for frame in frames}) < 2:
            raise RuntimeError('Sampled MP4 frames are identical; frozen recording rejected')

        notification = next((step for step in self.report['steps']
                             if step['step'] == 'Android media foreground notification displayed'), None)
        if notification is None:
            raise RuntimeError('Notification stage unavailable for verification inside the MP4')
        timestamp = notification['elapsed_seconds'] - (self.recording_started - self.started)
        assert 0 <= timestamp < duration, 'Notification timestamp outside recorded video'
        path = self.out / 'recorded-notification.png'
        path.unlink(missing_ok=True)
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-nostdin',
                        '-y', '-ss', f'{timestamp:.3f}', '-i', str(video),
                        '-frames:v', '1', '-threads', '1', str(path)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        text = subprocess.check_output(['tesseract', str(path), 'stdout', '--psm', '11'],
                                       stderr=subprocess.DEVNULL, text=True, timeout=30)
        words = {normalise(word) for word in text.split()}
        visible = 'mire' in words and bool({'streaming', 'diffusion'} & words)
        if self.package == LAB_PACKAGE:
            # Le volet peut replier la ligne de description sur un téléphone en paysage.
            # La capture de référence a indépendamment confirmé le titre dans SystemUI.
            with Image.open(self.out / '08-media-notification-visible.png') as expected, Image.open(path) as actual:
                diff = ImageChops.difference(expected.convert('RGB').resize((160, 90)),
                                             actual.convert('RGB').resize((160, 90)))
                mae = sum(ImageStat.Stat(diff).mean) / 3
            self.report['notification_reference_mean_pixel_error'] = round(mae, 3)
            visible = mae < 12 and ('mire' in words or self.report.get('notification_title_in_systemui') is True)
        self.report['recorded_notification_check'] = {
            'file': path.name, 'timestamp_seconds': round(timestamp, 3), 'visible': visible}
        if not visible:
            raise RuntimeError('Expected media notification is not visible inside the MP4')
        self.recording_quality_passed = True

    def finish(self):
        if self.recording:
            # SIGINT ferme correctement le conteneur MP4 de screenrecord.
            elapsed = time.monotonic() - self.recording_started
            try:
                self.adb('shell', 'pkill', '-INT', 'screenrecord')
            except subprocess.CalledProcessError:
                pass
            try:
                self.recording.communicate(timeout=12)
            except subprocess.TimeoutExpired:
                self.recording.terminate()
            self.adb('pull', '/sdcard/novatube-fgs-review.mp4', str(self.out / 'novatube-fgs-review.mp4'), timeout=45)
            probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_format',
                '-show_streams', '-of', 'json', str(self.out / 'novatube-fgs-review.mp4')], text=True))
            (self.out / 'video-probe.json').write_text(json.dumps(probe, indent=2) + '\n')
            duration = float(probe['format']['duration'])
            assert duration > 0 and any(stream.get('codec_type') == 'video'
                                        for stream in probe['streams']), 'Recorded video stream absent'
            self.report['recording_seconds'] = duration
            if duration < elapsed - 4:
                self.report['validated'] = False
                self.report['failure'] = 'Screenrecord ended before the full scenario completed'
                self.save()
                raise RuntimeError(self.report['failure'])
            self.verify_recorded_frames(self.out / 'novatube-fgs-review.mp4', duration)
        self.screenshot('99-final-state')
        self.save()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--component', required=True)
    parser.add_argument('--package', default=PLAY_PACKAGE)
    parser.add_argument('--expected-digest')
    parser.add_argument('--expected-version', type=int, default=1794878684)
    parser.add_argument('--expected-source')
    parser.add_argument('--expected-api', type=int, default=34)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.expected_source is None:
        expected_file = args.out / 'expected-source.txt'
        args.expected_source = (expected_file.read_text().strip() if expected_file.exists()
                                else os.environ.get('NOVATUBE_BUILD_COMMIT'))
    scenario = Scenario(args.out, args.serial, args.expected_version, args.expected_source, args.expected_api,
                        args.package, args.expected_digest)
    scenario.component = args.component
    failure = None
    try:
        scenario.run()
    except Exception as error:
        failure = error
        scenario.report['failure'] = str(error)
        scenario.step('Scenario failed; video is diagnostic only', error=str(error))
    try:
        scenario.finish()
    except Exception as error:
        failure = failure or error
        scenario.report['finish_failure'] = str(error)
    if failure is None and args.package == LAB_PACKAGE:
        try:
            scenario.verify_handset_recording()
        except Exception as error:
            failure = error
            scenario.report['handset_recording_failure'] = str(error)
            scenario.step('Phone recording verification failed', error=str(error))
    scenario.report['validated'] = (failure is None and scenario.recording is not None
                                    and scenario.recording_quality_passed)
    if failure is None and not scenario.report['validated']:
        failure = RuntimeError('A complete non-black recording was not confirmed')
        scenario.report['failure'] = str(failure)
    scenario.save()
    if failure is not None:
        raise RuntimeError('Capture non validée : consulter scenario-report.json') from failure


if __name__ == '__main__':
    main()
