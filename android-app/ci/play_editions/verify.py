#!/usr/bin/env python3
"""Contrôle le manifeste FUSIONNÉ du bundle et écrit sa provenance publique."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from prepare import A, CAST_KEY, CAST_SERVICE, EDITION_KEY, LABELS, PACKAGES, version_for


def verify_manifest(source, edition):
    root = ET.fromstring(source)
    app = root.find('application')
    activity = next(x for x in app.findall('activity')
                    if x.get(A + 'name', '').endswith('MainActivity'))
    assert root.get('package') == PACKAGES[edition], 'Mauvais package'
    code, name = version_for(edition)
    assert root.get(A + 'versionCode') == str(code), 'Mauvais code Play'
    assert root.get(A + 'versionName') == name, 'Mauvaise version'
    sdk = root.find('uses-sdk')
    assert sdk.get(A + 'minSdkVersion') == '24'
    assert int(sdk.get(A + 'targetSdkVersion')) >= 36
    assert app.get(A + 'label') == LABELS[edition]
    metadata = {x.get(A + 'name'): x.get(A + 'value') for x in app.findall('meta-data')}
    assert metadata.get(EDITION_KEY) == edition, 'Édition native absente'
    permissions = {x.get(A + 'name') for x in root.findall('uses-permission')}
    assert 'android.permission.REQUEST_INSTALL_PACKAGES' not in permissions
    features = {x.get(A + 'name'): x.get(A + 'required', 'true') for x in root.findall('uses-feature')}
    assert features['android.software.leanback'] == str(edition == 'tv').lower()
    assert features['android.hardware.touchscreen'] == str(edition == 'mobile').lower()
    categories = {x.get(A + 'name') for x in activity.findall('intent-filter/category')}
    assert ('android.intent.category.LEANBACK_LAUNCHER' in categories) == (edition != 'mobile')
    assert 'android.intent.category.LAUNCHER' in categories, 'Launcher téléphone absent'
    assert activity.get(A + 'supportsPictureInPicture') == str(edition != 'tv').lower()
    services = {x.get(A + 'name') for x in app.findall('service')}
    assert (CAST_KEY in metadata) == (edition != 'tv'), 'Configuration Cast incorrecte'
    assert (CAST_SERVICE in services) == (edition != 'tv'), 'Service Cast incorrect'
    return {'edition': edition, 'package': PACKAGES[edition], 'version_code': code,
            'version_name': name, 'cast_sender': edition != 'tv',
            'picture_in_picture': edition != 'tv',
            'sender_device_scope': 'handset-only' if edition != 'tv' else 'none',
            'min_sdk': 24}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--edition', required=True, choices=PACKAGES)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--source-sha', required=True)
    args = parser.parse_args()
    report = verify_manifest(args.manifest.read_text(), args.edition)
    report.update(source_sha=args.source_sha,
                  sha256=hashlib.sha256(args.bundle.read_bytes()).hexdigest(),
                  file=args.bundle.name)
    args.bundle.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
