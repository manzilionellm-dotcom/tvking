#!/usr/bin/env python3
"""Prépare uniquement le checkout CI de NOVATUBE MAX pour Google Play.

Ce script s'exécute après les scripts TV et NovaTube existants. Il conserve
les choix déjà présents dans l'AAB 1794878683 : nom MAX, Android 7 minimum,
pas d'installation d'APK et pas d'accès global aux photos/vidéos. Les
permissions sont aussi retirées du manifeste fusionné des dépendances.
Les autres éditions du dépôt ne lancent pas ce script et restent intactes.
"""
from __future__ import annotations

import argparse
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID = 'http://schemas.android.com/apk/res/android'
TOOLS = 'http://schemas.android.com/tools'
ET.register_namespace('android', ANDROID)
ET.register_namespace('tools', TOOLS)


def prepare(root: Path) -> None:
    manifest_path = root / 'android/app/src/main/AndroidManifest.xml'
    gradle_path = root / 'android/app/build.gradle.kts'
    manifest = ET.parse(manifest_path)
    application = manifest.getroot().find('application')
    if application is None:
        raise SystemExit('Manifeste Android sans application : arrêt.')
    application.set(f'{{{ANDROID}}}label', 'NOVATUBE MAX')

    # Les suppressions explicites empêchent une bibliothèque de réintroduire
    # des permissions que cette édition Play ne demande pas à l'utilisateur.
    for permission in (
        'android.permission.REQUEST_INSTALL_PACKAGES',
        'android.permission.READ_MEDIA_IMAGES',
        'android.permission.READ_MEDIA_VIDEO',
    ):
        for child in list(manifest.getroot()):
            if child.tag in ('uses-permission', 'uses-permission-sdk-23') and child.get(f'{{{ANDROID}}}name') == permission:
                manifest.getroot().remove(child)
        removal = ET.Element('uses-permission')
        removal.set(f'{{{ANDROID}}}name', permission)
        removal.set(f'{{{TOOLS}}}node', 'remove')
        manifest.getroot().insert(0, removal)

    gradle = gradle_path.read_text(encoding='utf-8')
    if 'applicationId = "com.sevenmotion.novatube.tv"' not in gradle:
        raise SystemExit('Identité NovaTube TV absente : lancer les scripts TV avant celui-ci.')
    gradle, count = re.subn(r'\bval kBoxMinSdk\s*=\s*\d+', 'val kBoxMinSdk = 24', gradle)
    if count != 1:
        raise SystemExit('Réglage minSdk TV inattendu : aucun fichier modifié.')
    # La version actuellement acceptée par la Console cible Android 16/API36.
    gradle, target_count = re.subn(r'\btargetSdk\s*=\s*(?:flutter\.targetSdkVersion|\d+)', 'targetSdk = 36', gradle)
    if target_count != 1:
        raise SystemExit('Réglage targetSdk inattendu : aucun fichier modifié.')

    manifest.write(manifest_path, encoding='utf-8', xml_declaration=True)
    gradle_path.write_text(gradle, encoding='utf-8')
    print('NOVATUBE MAX Play : package TV, minSdk24, targetSdk36, permissions de médias/installation retirées.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    prepare(parser.parse_args().root)
