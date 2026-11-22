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
import time
import unicodedata
from urllib.request import urlopen
import xml.etree.ElementTree as ET

from PIL import Image

PACKAGE = 'com.sevenmotion.novatube.tv'


def normalise(value):
    return ''.join(c for c in unicodedata.normalize('NFKD', value).lower() if c.isalnum())


class Scenario:
    def __init__(self, out, serial, expected_version=1794878684, expected_source=None, expected_api=34):
        self.out, self.serial = out, serial
        self.expected_version = expected_version
        self.expected_source = expected_source
        self.expected_api = expected_api
        self.started = time.monotonic()
        self.recording = None
        self.recording_quality_passed = False
        self.report = {'validated': False, 'package': PACKAGE,
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
        result = subprocess.check_output(['tesseract', str(path), 'stdout', '--psm', '11', 'tsv'],
                                         stderr=subprocess.DEVNULL, text=True, timeout=12)
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

    def key(self, value, delay=1.5):
        self.adb('shell', 'input', 'keyevent', value)
        time.sleep(delay)

    def accessibility_point(self, expression):
        self.require_public_screen()
        try:
            self.adb('shell', 'uiautomator', 'dump', '--compressed', '/sdcard/novatube-ui.xml', timeout=12)
            xml = self.adb('shell', 'cat', '/sdcard/novatube-ui.xml')
            self.require_public_screen()
            (self.out / 'current-ui.xml').write_text(xml)
            for node in ET.fromstring(xml).iter('node'):
                label = ' '.join([node.attrib.get('text', ''), node.attrib.get('content-desc', '')])
                if not re.search(expression, label, re.IGNORECASE):
                    continue
                coords = [int(n) for n in re.findall(r'\d+', node.attrib.get('bounds', ''))]
                if len(coords) == 4 and coords[2] > coords[0] and coords[3] > coords[1]:
                    return ((coords[0] + coords[2]) // 2, (coords[1] + coords[3]) // 2)
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError, ET.ParseError):
            return None
        return None

    def receiver(self):
        with urlopen('http://127.0.0.1:18999/status.json', timeout=5) as response:
            return json.load(response)

    def service(self, name):
        text = self.adb('shell', 'dumpsys', 'activity', 'services', PACKAGE)
        (self.out / f'{name}-services.txt').write_text(text)
        block = re.search(r'ServiceRecord[^\n]*PlaybackForegroundService[\s\S]*?(?=\n\s*\* ServiceRecord|\Z)', text)
        active = block is not None and 'isForeground=true' in block.group(0)
        if active:
            assert re.search(r'foregroundServiceType=(?:0x0*2|2)\b', block.group(0)), 'Type mediaPlayback du service non confirmé'
        return active, text

    def allow_notifications(self):
        # L'autorisation est donnée dans le dialogue système réellement visible.
        point = self.accessibility_point(r'^\s*Allow\s*$|^\s*Autoriser\s*$')
        if point:
            self.adb('shell', 'input', 'tap', str(point[0]), str(point[1]))
            self.step('Notification permission accepted using visible Android dialog')
            time.sleep(1)

    def run(self):
        self.require_public_screen()
        actual_api = int(self.adb('shell', 'getprop', 'ro.build.version.sdk').strip())
        self.report['android_api'] = actual_api
        self.report['android_release'] = self.adb('shell', 'getprop', 'ro.build.version.release').strip()
        assert actual_api == self.expected_api, 'Version Android inattendue'
        package = self.adb('shell', 'dumpsys', 'package', PACKAGE)
        version = re.search(r'\bversionCode=(\d+)\b', package)
        assert version, 'Version de l’APK installé absente'
        self.report['version_code'] = int(version.group(1))
        self.report['production_review_candidate'] = False
        assert self.report['version_code'] == self.expected_version, 'Mauvaise version APK installée'
        if self.expected_version == 1794878684:
            identity = json.loads((self.out / 'build-identity.json').read_text())
            assert self.expected_source and identity['source_commit'] == self.expected_source, 'Commit source non confirmé'
            assert identity['package'] == PACKAGE and identity['version_code'] == self.expected_version
            assert identity['play_build'] is True
            installed = self.adb('shell', 'pm', 'path', PACKAGE).strip().splitlines()
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
        self.step('Installed APK opened on the touchscreen emulator', android_api=actual_api)
        assert self.find('m3u', timeout=45), 'Accueil M3U absent'
        self.screenshot('01-welcome')
        # L'activation privée précédente peut avoir déplacé le focus. Le geste
        # vise donc le libellé M3U réellement visible, jamais un focus présumé.
        self.tap_word('m3u', timeout=10)
        self.screenshot('02-import-form')
        self.adb('shell', 'input', 'text', 'http://127.0.0.1:18999/review.m3u')
        self.key('KEYCODE_ENTER', 3)
        if not self.find('tonight', timeout=4):
            self.key('KEYCODE_DPAD_CENTER', 2)
        assert self.find('tonight', timeout=35), 'Accueil après import absent'
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
        if not self.find('cast', bounds=(0.55, 0, 1, 0.3), timeout=3):
            self.key('KEYCODE_DPAD_CENTER', 3)
        assert self.find('cast', bounds=(0.55, 0, 1, 0.3), timeout=12), 'Lecteur tactile ou bouton Cast absent'
        time.sleep(6)
        self.screenshot('04-local-playback')
        self.step('Synthetic video visibly opened in the normal full-screen player')
        before, _ = self.service('before-cast')
        assert not before, 'Le service était déjà actif avant le geste Cast'
        self.tap_word('cast', bounds=(0.55, 0, 1, 0.3))
        self.screenshot('05-cast-picker')
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
        assert resumed and '/' in home and home_package in resumed and PACKAGE not in resumed, 'Accueil Android repris non confirmé'
        self.step('Home displayed while receiver continues decoding and service stays foreground',
                  before_frames=background_start['decoded_frames'], after_frames=background_end['decoded_frames'],
                  before_relay_bytes=background_start['relay_upstream_bytes_sent'],
                  after_relay_bytes=background_end['relay_upstream_bytes_sent'])

        self.adb('shell', 'cmd', 'statusbar', 'expand-notifications')
        time.sleep(3)
        self.screenshot('08-media-notification')
        notifications = self.adb('shell', 'dumpsys', 'notification', '--noredact')
        # Seule la fiche du paquet contrôlé est conservée, sans les autres apps.
        match = re.search(r'NotificationRecord\([^\n]*pkg=' + re.escape(PACKAGE) + r'[^\n]*[\s\S]*?(?=\n\s*NotificationRecord\(|\n\s*Ranking Config|\Z)', notifications)
        (self.out / 'media-notification.txt').write_text(match.group(0) if match else 'Notification record not located\n')
        assert match and ('1002' in match.group(0) or 'playback_channel' in match.group(0)), 'Notification du service introuvable'
        visible_words = {word for word, _, _ in self.words('08-media-notification-visible')}
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
    parser.add_argument('--expected-version', type=int, default=1794878684)
    parser.add_argument('--expected-source')
    parser.add_argument('--expected-api', type=int, default=34)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.expected_source is None:
        expected_file = args.out / 'expected-source.txt'
        args.expected_source = (expected_file.read_text().strip() if expected_file.exists()
                                else os.environ.get('NOVATUBE_BUILD_COMMIT'))
    scenario = Scenario(args.out, args.serial, args.expected_version, args.expected_source, args.expected_api)
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
