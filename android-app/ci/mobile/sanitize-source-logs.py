#!/usr/bin/env python3
"""Retire les accès possibles des journaux lors du raccordement mobile."""
from pathlib import Path
import re

paths = [
    'lib/features/playlists/data/playlist_repository.dart',
    'lib/features/playlists/data/m3u_fetcher.dart',
    'lib/features/playlists/data/remote_source_repository.dart',
    'lib/features/playlists/data/cloud_backup_repository.dart',
    'lib/features/subscription/data/remote_activation_watch.dart',
    'lib/core/realtime/realtime_sync_service.dart',
    'lib/core/app/panel_live_wait.dart',
]
for name in paths:
    path = Path(name)
    # Les synchroniseurs Zuno et téléphone portent des noms différents.
    if not path.exists():
        continue
    text = path.read_text()
    def clean(match):
        block = match.group(0)
        block = block.replace('[Repo] GET $url', '[Repo] Téléchargement de la playlist')
        # Une exception HTTP peut contenir l'URL entière et son mot de passe.
        for variable in ['e', 'xtErr']:
            block = re.sub(r'\$' + variable + r'\b', '${' + variable + '.runtimeType}', block)
        return block
    updated = re.sub(r'(?:debugPrint|BlackBox\.instance\.(?:warn|error))\(.*?\);', clean, text, flags=re.S)
    path.write_text(updated)
