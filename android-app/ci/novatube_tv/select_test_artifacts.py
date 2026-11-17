"""Conserve un APK déjà signé quand seul son parcours de test est corrigé."""
import json
import os
import re
import subprocess
from pathlib import Path


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def github(endpoint):
    return json.loads(subprocess.check_output(['gh', 'api', endpoint], text=True))


repo = os.environ['GITHUB_REPOSITORY']
head = os.environ['GITHUB_SHA']
sha = head
run = os.environ['GITHUB_RUN_ID']
provenance = re.findall(r'^Recontrole-APK: ([a-f0-9]{40})$', git('log', '-1', '--format=%B'), re.M)
if provenance:
    if len(provenance) != 1:
        raise SystemExit('Provenance ambiguë pour le contrôle de l’APK.')
    sha = provenance[0]
    git('fetch', '--depth=1', 'origin', sha)
    checks = {'emulator_media.sh', 'emulator_smoke.sh', 'screen_label.py', 'profile_catalogs.py',
              'make_test_media.sh', 'select_test_artifacts.py'}
    allowed = {f'android-app/ci/novatube_tv/{name}' for name in checks}
    allowed.add('.github/workflows/novatube-tv-test.yml')
    diff = set(git('diff', '--name-only', sha, head).splitlines())
    if not diff or diff - allowed:
        raise SystemExit('Le code ou les entrées du build ont changé. Il faut tester son nouvel APK.')
    workflow = 'novatube-tv-test.yml'
    runs = github(f'repos/{repo}/actions/workflows/{workflow}/runs?head_sha={sha}&per_page=30')
    for item in runs['workflow_runs']:
        if item['head_sha'] != sha or item['head_branch'] != os.environ['GITHUB_REF_NAME']:
            continue
        jobs = github(f"repos/{repo}/actions/runs/{item['id']}/jobs")['jobs']
        if any(j['name'] == 'Compiler, tester et signer NovaTube TV' and j['conclusion'] == 'success' for j in jobs):
            run = item['id']
            break
    else:
        raise SystemExit('Aucune compilation vérifiée pour cette provenance.')
with Path(os.environ['GITHUB_OUTPUT']).open('a') as out:
    out.write(f'sha={sha}\nrun={run}\n')
print(f'APK issu du commit {sha}, exécution {run}. Contrôles du commit {head}.')
