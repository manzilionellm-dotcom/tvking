#!/usr/bin/env python3
"""Télécharge seulement l'APK vérifié du commit de production demandé."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

repo = os.environ['GITHUB_REPOSITORY']
commit = os.environ['NOVATUBE_BUILD_COMMIT']
out = Path('build/novatube_review_input')
out.mkdir(parents=True, exist_ok=True)
endpoint = f'repos/{repo}/actions/workflows/novatube-max-play-review.yml/runs?per_page=30'
deadline = time.monotonic() + 35 * 60
while time.monotonic() < deadline:
    response = json.loads(subprocess.check_output(['gh', 'api', endpoint], text=True))
    runs = [r for r in response['workflow_runs'] if r['head_sha'] == commit]
    if runs:
        run = runs[0]
        if run['status'] == 'completed':
            if run['conclusion'] != 'success':
                raise SystemExit(f"Build {run['id']} terminé avec {run['conclusion']} : capture refusée.")
            break
        print(f"Attente du build {run['id']} : {run['status']}", flush=True)
    else:
        print(f'Attente du build du commit {commit}', flush=True)
    time.sleep(15)
else:
    raise SystemExit('Build vérifié absent après 35 minutes.')

subprocess.run(['gh', 'run', 'download', str(run['id']), '--repo', repo,
                '--name', f'novatube-max-play-1794878684-{commit}', '--dir', str(out)], check=True)
identity = json.loads((out / 'build-identity.json').read_text())
assert identity['source_commit'] == commit
assert identity['version_code'] == 1794878684
assert identity['package'] == 'com.sevenmotion.novatube.tv'
for name, expected in identity['files'].items():
    data = (out / name).read_bytes()
    assert len(data) == expected['bytes']
    assert hashlib.sha256(data).hexdigest() == expected['sha256']
print(f"APK et AAB vérifiés : build {run['id']}, commit {commit}")
