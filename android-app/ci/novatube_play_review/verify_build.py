#!/usr/bin/env python3
"""Vérifie identité, permissions et même code Dart entre AAB et APK."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile

out = Path(sys.argv[1]).resolve()
apk = out / 'NOVATUBE-MAX-1794878684-ci.apk'
aab = out / 'NOVATUBE-MAX-1794878684-ci.aab'
sdk = Path(os.environ.get('ANDROID_HOME') or os.environ['ANDROID_SDK_ROOT'])
build_tools = sorted((sdk / 'build-tools').iterdir(), key=lambda p: [int(n) for n in re.findall(r'\d+', p.name)])[-1]
badging = subprocess.check_output([str(build_tools / 'aapt'), 'dump', 'badging', str(apk)], text=True)
permissions = subprocess.check_output([str(build_tools / 'aapt'), 'dump', 'permissions', str(apk)], text=True)
signature = subprocess.check_output([str(build_tools / 'apksigner'), 'verify', '--print-certs', str(apk)], text=True)
(out / 'badging.txt').write_text(badging)
(out / 'permissions.txt').write_text(permissions)
(out / 'signature-ci.txt').write_text(signature)
assert "name='com.sevenmotion.novatube.tv'" in badging
assert "versionCode='1794878684'" in badging
assert "application-label:'NOVATUBE MAX'" in badging
assert "sdkVersion:'24'" in badging
assert "targetSdkVersion:'36'" in badging
assert 'leanback-launchable-activity:' in badging
for permission in ['REQUEST_INSTALL_PACKAGES', 'READ_MEDIA_IMAGES', 'READ_MEDIA_VIDEO']:
    assert permission not in permissions, f'Permission inutile encore présente : {permission}'
assert 'FOREGROUND_SERVICE_MEDIA_PLAYBACK' in permissions

# L’enregistrement sur émulateur utilisera cet APK. Ses bibliothèques Dart
# doivent être celles de l’AAB remis pour signature ; aucune variante de démo.
libraries = {}
with zipfile.ZipFile(apk) as ap, zipfile.ZipFile(aab) as bundle:
    for abi in ['armeabi-v7a', 'arm64-v8a', 'x86_64']:
        path = f'lib/{abi}/libapp.so'
        av = ap.read(path)
        bv = bundle.read(f'base/{path}')
        assert av == bv, f'Code Dart APK/AAB différent : {abi}'
        libraries[abi] = hashlib.sha256(av).hexdigest()

identity = {
    'package': 'com.sevenmotion.novatube.tv',
    'version_code': 1794878684,
    'version_name': os.environ.get('NOVATUBE_VERSION_NAME', '1.0.1'),
    'source_commit': os.environ['GITHUB_SHA'],
    'source_run_id': os.environ['GITHUB_RUN_ID'],
    'play_build': True,
    'signing': 'CI debug key only; final stable-key signing happens separately',
    'dart_libraries_sha256': libraries,
    'files': {p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in [apk, aab]},
}
(out / 'build-identity.json').write_text(json.dumps(identity, indent=2) + '\n')
(out / 'SHA256SUMS.txt').write_text(''.join(f"{v['sha256']}  {k}\n" for k, v in identity['files'].items()))
print(json.dumps(identity, indent=2))
