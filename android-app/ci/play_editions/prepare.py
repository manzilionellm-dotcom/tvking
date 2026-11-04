#!/usr/bin/env python3
"""Prépare la mise à jour Play adaptative et les variantes de contrôle.

L'édition auto conserve le paquet, la signature et l'identité historiques sur
téléphone comme sur TV. Le plugin décide des capacités selon le matériel.
Les variantes explicites restent testables, mais ne sont plus construites par
le workflow de livraison. Toutes utilisent l'entrée main_tv.dart validée.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET

APP = Path(__file__).resolve().parents[2]
ANDROID = 'http://schemas.android.com/apk/res/android'
TOOLS = 'http://schemas.android.com/tools'
A = '{' + ANDROID + '}'
T = '{' + TOOLS + '}'
EDITION_KEY = 'com.sevenmotion.zuno.EDITION'
CAST_KEY = 'com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME'
CAST_SERVICE = 'com.manzilionellm.tvking.PlaybackForegroundService'
PACKAGES = {'auto': 'com.sevenmotion.tv.seven_tv',
            'tv': 'com.sevenmotion.tv.seven_tv', 'mobile': 'com.sevenmotion.zuno.mobile'}
LABELS = {'auto': 'ZUNO', 'tv': 'ZUNO TV', 'mobile': 'ZUNO Mobile'}
ET.register_namespace('android', ANDROID)
ET.register_namespace('tools', TOOLS)


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def version_for(edition):
    path = APP / 'ci' / ('play-mobile-version.json' if edition == 'mobile' else 'play-tv-version.json')
    data = json.loads(path.read_text())
    if edition != 'mobile':
        validator = load_module('play_tv_version', APP / 'ci/play_tv_version.py')
        return validator.validate_version(data)
    previous, uploaded, code = (data[k] for k in (
        'lastPublishedVersionCode', 'lastUploadedVersionCode', 'versionCode'))
    if any(type(n) is not int for n in (previous, uploaded, code)):
        raise ValueError('Codes Play mobile entiers requis')
    if not 0 <= previous <= uploaded < code <= 2_100_000_000:
        raise ValueError('Compteur mobile invalide')
    if code != max(previous, uploaded) + 1:
        raise ValueError('Un import mobile avance exactement le compteur indépendant')
    name = data['versionName']
    if not isinstance(name, str) or not re.fullmatch(r'[1-9][0-9]*(?:\.[0-9]+){0,2}', name):
        raise ValueError('Nom mobile invalide')
    return code, name


def set_named(parent, tag, name, **attributes):
    for old in list(parent.findall(tag)):
        if old.get(A + 'name') == name:
            parent.remove(old)
    return ET.SubElement(parent, tag, {A + 'name': name, **attributes})


def edition_manifest(source, edition):
    if edition not in PACKAGES:
        raise ValueError('Édition Play inconnue')
    root = ET.fromstring(source)
    application = root.find('application')
    activity = application.find('activity')
    application.set(A + 'label', LABELS[edition])
    set_named(application, 'meta-data', EDITION_KEY, **{A + 'value': edition})
    set_named(root, 'uses-feature', 'android.software.leanback',
              **{A + 'required': str(edition == 'tv').lower()})
    set_named(root, 'uses-feature', 'android.hardware.touchscreen',
              **{A + 'required': str(edition == 'mobile').lower()})
    # Le bundle ne télécharge ni n'installe d'autre exécutable : mises à jour Play.
    set_named(root, 'uses-permission', 'android.permission.REQUEST_INSTALL_PACKAGES',
              **{T + 'node': 'remove'})
    # Dans le paquet adaptatif, le PiP est déclaré pour les téléphones ;
    # le code natif refuse son activation sur TV et box.
    activity.set(A + 'supportsPictureInPicture', str(edition != 'tv').lower())
    if edition == 'mobile':
        application.attrib.pop(A + 'banner', None)
        for intent in activity.findall('intent-filter'):
            for category in list(intent.findall('category')):
                if category.get(A + 'name') == 'android.intent.category.LEANBACK_LAUNCHER':
                    intent.remove(category)
    elif edition == 'tv':
        # Élimine également la configuration et le service de l'émetteur du
        # manifeste fusionné ; le plugin refuse le Cast avant toute initialisation.
        set_named(application, 'meta-data', CAST_KEY, **{T + 'node': 'remove'})
        set_named(application, 'service', CAST_SERVICE, **{T + 'node': 'remove'})
    return ET.tostring(root, encoding='unicode') + '\n'


def prepare(edition):
    os.environ['ZUNO_APP_ID'] = PACKAGES[edition]
    os.environ['ZUNO_APP_LABEL'] = LABELS[edition]
    manifest_patch = load_module('zuno_manifest', APP / 'ci/tv/patch_manifest.py')
    gradle_patch = load_module('zuno_gradle', APP / 'ci/tv/patch_gradle.py')
    manifest = APP / 'android/app/src/main/AndroidManifest.xml'
    manifest.write_text(edition_manifest(manifest_patch.patch(manifest.read_text()), edition))
    gradle = APP / 'android/app/build.gradle.kts'
    code = gradle_patch.patch(gradle.read_text())
    code = code.replace('val kBoxMinSdk = 21', 'val kBoxMinSdk = 24')
    if 'val kBoxMinSdk = 24' not in code:
        raise ValueError('minSdk Play absent')
    gradle.write_text(code)
    shutil.copyfile(APP / 'ci/proguard-rules.pro', APP / 'android/app/proguard-rules.pro')
    res = APP / 'android/app/src/main/res'
    # L'édition auto conserve la même identité ZUNO sur les deux types d'écran.
    for directory, asset in [('drawable', 'zuno_tv_banner.png'),
                             ('drawable-xhdpi', 'zuno_tv_banner.png'),
                             ('drawable-xxhdpi', 'zuno_tv_banner_2x.png')]:
        target = res / directory
        target.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(APP / 'assets/branding' / asset, target / 'tv_banner.png')
    # Même premier écran que le build box : or transparent sur #070708,
    # pas la bannière opaque sur noir pur.
    load_module('zuno_splash', APP / 'ci/tv/apply_splash.py').apply(res)
    version, name = version_for(edition)
    fields = {'ZUNO_EDITION': edition, 'ZUNO_APP_ID': PACKAGES[edition],
              'PLAY_VERSION_CODE': str(version), 'PLAY_VERSION_NAME': name}
    with Path(os.environ['GITHUB_ENV']).open('a') as output:
        for key, value in fields.items():
            output.write(f'{key}={value}\n')
    print(f"{LABELS[edition]} : {PACKAGES[edition]} · {name} / {version}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--edition', required=True, choices=PACKAGES)
    prepare(parser.parse_args().edition)
