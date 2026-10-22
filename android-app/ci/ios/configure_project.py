#!/usr/bin/env python3
"""Configure le projet généré par Flutter, sans PlistBuddy ni erreurs masquées."""
import argparse
from pathlib import Path
import plistlib
import re


def configure(root: Path, bundle: str):
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)+', bundle):
        raise ValueError('Bundle ID Apple invalide')
    info = root / 'ios/Runner/Info.plist'
    project = root / 'ios/Runner.xcodeproj/project.pbxproj'
    podfile = root / 'ios/Podfile'
    for path in [info, project, podfile]:
        if not path.is_file():
            raise FileNotFoundError(str(path))
    data = plistlib.loads(info.read_bytes())
    data.update({
        'CFBundleDisplayName': '7 MOTION',
        'CFBundleName': '7 MOTION',
        'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
        'NSFaceIDUsageDescription': 'Unlock 7 MOTION using Face ID when you enable the app lock.',
        'UIBackgroundModes': ['audio'],
        # Les listes fournies par l'utilisateur peuvent employer HTTP. Cette
        # exception doit être expliquée à la revue Apple, pas dissimulée.
        'NSAppTransportSecurity': {'NSAllowsArbitraryLoads': True},
        'UISupportedInterfaceOrientations': [
            'UIInterfaceOrientationPortrait',
            'UIInterfaceOrientationLandscapeLeft',
            'UIInterfaceOrientationLandscapeRight',
        ],
    })
    # Pas de multicast : les fonctions Cast Android ne sont pas disponibles
    # dans ce premier port iPhone. La description Face ID est indispensable.
    for key in ['NSBonjourServices', 'NSLocalNetworkUsageDescription',
                'NSCameraUsageDescription', 'NSMicrophoneUsageDescription',
                'NSPhotoLibraryUsageDescription', 'NSPhotoLibraryAddUsageDescription']:
        data.pop(key, None)
    info.write_bytes(plistlib.dumps(data, sort_keys=False))
    text = project.read_text()
    def identifier(match):
        suffix = '.RunnerTests' if 'RunnerTests' in match.group(1) else ''
        return 'PRODUCT_BUNDLE_IDENTIFIER = ' + bundle + suffix + ';'
    text, count = re.subn(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', identifier, text)
    if count < 3:
        raise ValueError('Configurations Runner introuvables')
    text, targets = re.subn(r'IPHONEOS_DEPLOYMENT_TARGET = [^;]+;',
                            'IPHONEOS_DEPLOYMENT_TARGET = 15.0;', text)
    if targets < 3:
        raise ValueError('Cibles iOS introuvables')
    text = re.sub(r'TARGETED_DEVICE_FAMILY = [^;]+;', 'TARGETED_DEVICE_FAMILY = 1;', text)
    project.write_text(text)
    text = podfile.read_text()
    platform = "platform :ios, '15.0'"
    if re.search(r'^\s*#?\s*platform :ios,.*$', text, flags=re.M):
        text = re.sub(r'^\s*#?\s*platform :ios,.*$', platform, text, flags=re.M)
    else:
        text = platform + '\n' + text
    podfile.write_text(text)
    print('7 MOTION : iPhone, iOS 15+, Face ID et audio configurés')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('phone', type=Path)
    parser.add_argument('--bundle-id', default='com.manzilionellm.sevenmotion')
    args = parser.parse_args()
    configure(args.phone, args.bundle_id)
