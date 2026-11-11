"""Rejoue les transformations existantes dans des dossiers temporaires.

Ce contrôle ne construit aucun paquet. Le checkout et les données de l'app
restent intacts ; les modifications préparées pour Play ne quittent pas le
dossier temporaire et ne participent jamais à l'APK du lot 1.
"""
import argparse
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[3]
PHONE_BASE = '37fdf3305c5de9d35e20fd6567df38008fc7a7ee'


def run(*args, cwd=ROOT, env=None):
    return subprocess.check_output(args, cwd=cwd, env=env, text=True)


def extract(revision, destination, *paths, repository=ROOT):
    archive = subprocess.check_output(
        ['git', 'archive', revision, *paths], cwd=repository)
    with tarfile.open(fileobj=io.BytesIO(archive)) as content:
        content.extractall(destination, filter='data')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--phone-checkout', type=Path, default=ROOT)
    args = parser.parse_args()
    # Un checkout secondaire exact évite de supposer que cette ancienne base
    # est encore atteignable depuis les branches de travail actuelles.
    if args.phone_checkout != ROOT:
        actual = run('git', 'rev-parse', 'HEAD', cwd=args.phone_checkout).strip()
        if actual != PHONE_BASE:
            raise SystemExit('Base temporaire du patch mobile inattendue.')
    sha = run('git', 'rev-parse', 'HEAD').strip()
    with tempfile.TemporaryDirectory(prefix='audit116-anchors-') as directory:
        temporary = Path(directory)
        phone = temporary / 'phone'
        phone.mkdir()
        extract(PHONE_BASE, phone, repository=args.phone_checkout)
        applied = []
        # Ordre exact des workflows player-debug-test puis mobile-gestures-test.
        # Le second ajoute seulement le dernier patch à la même préparation.
        patches = [
            'patches/mobile-sport-gratuit.patch',
            'patches/mobile-radio.patch',
            'patches/mobile-panel-sync.patch',
            'patches/mobile-identity.patch',
            'patches/mobile-stability.patch',
            'android-app/ci/mobile/adult-classification.patch',
            'android-app/ci/mobile/player-terminal-fallback.patch',
            'android-app/ci/mobile/mobile-back-gestures.patch',
        ]
        for patch in patches:
            path = str(ROOT / patch)
            run('git', 'apply', '--check', path, cwd=phone)
            run('git', 'apply', path, cwd=phone)
            applied.append(patch)
        current = temporary / 'current'
        current.mkdir()
        extract(sha, current, 'android-app')
        app = current / 'android-app'
        variables = dict(os.environ, GITHUB_ENV=str(temporary / 'prepare.env'))
        # Édition réellement utilisée par le workflow de référence. Aucun
        # pub get, aucun compilateur et aucun AAB ne sont appelés ici.
        output = run('python3', 'ci/play_editions/prepare.py', '--edition', 'auto',
                     cwd=app, env=variables)
        # Étape suivante réelle du workflow : vérifier aussi cette ancre,
        # sans résoudre de dépendances et sans toucher au pubspec du checkout.
        pubspec = app / 'pubspec.yaml'
        source = pubspec.read_text()
        anchor = '  shared_preferences: ^2.3.4\n'
        if source.count(anchor) != 1 or '  shared_preferences_android:' in source:
            raise SystemExit('Ancre SharedPreferences du workflow inattendue.')
        pubspec.write_text(source.replace(
            anchor, anchor + '  shared_preferences_android: 2.5.0\n', 1))
        print(json.dumps({
            'sourceSha': sha, 'phoneBase': PHONE_BASE,
            'patchesAppliedInOrder': applied,
            'playPreparation': {'edition': 'auto', 'output': output.strip(),
                                'sharedPreferencesAndroidPin': '2.5.0'},
            'packageBuilt': False,
        }, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
