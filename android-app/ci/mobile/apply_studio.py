#!/usr/bin/env python3
"""Applique le studio à la base téléphone sans changer sa synchronisation.

Exécuter depuis le checkout téléphone, après les patches Sport et Radio.
Ce script ne signe, ne publie et ne contacte aucun service.
"""
from pathlib import Path
import hashlib
import subprocess
import sys

patch = Path(sys.argv[1]).resolve(strict=True)
# Tous les transports et points d'entrée sont conservés octet pour octet.
protected = [Path('lib/main.dart')]
for folder in ('lib/features/subscription', 'lib/features/playlists',
               'lib/core/backend', 'lib/core/realtime', 'lib/features/radio'):
    protected.extend(sorted(Path(folder).rglob('*.dart')))
before = {p: p.read_bytes() for p in protected}
subprocess.run(['git', 'apply', '--check', str(patch)], check=True)
subprocess.run(['git', 'apply', str(patch)], check=True)
assert all(p.read_bytes() == content for p, content in before.items()), \
    'Le patch a changé une entrée, un transport ou une source du téléphone'
print(f'PROUVÉ : {len(protected)} fichiers du téléphone inchangés')
print('Patch studio SHA-256 : ' + hashlib.sha256(patch.read_bytes()).hexdigest())
