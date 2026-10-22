#!/usr/bin/env python3
"""Reconstitue la dernière app mobile publiée, puis applique le port iPhone.

Les SHA contrôlent la provenance. Un patch absent, modifié ou déjà appliqué
arrête la préparation : aucune compilation silencieuse d'une autre version.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess


def prepare(mission: Path, phone: Path):
    config = mission / 'android-app/ci/ios'
    lock = json.loads((config / 'source.lock.json').read_text())
    head = subprocess.check_output(['git', '-C', str(phone), 'rev-parse', 'HEAD'], text=True).strip()
    if head != lock['mobile_base_commit']:
        raise SystemExit('La base mobile ne correspond pas à source.lock.json')
    for patch in lock['patches']:
        source = mission / patch['path']
        sha = subprocess.check_output(['git', 'hash-object', str(source)], text=True).strip()
        if sha != patch['git_blob']:
            raise SystemExit('Patch mobile modifié : ' + patch['path'])
        subprocess.run(['git', '-C', str(phone), 'apply', '--check', str(source)], check=True)
        subprocess.run(['git', '-C', str(phone), 'apply', str(source)], check=True)
    overlay = config / 'iphone.patch'
    subprocess.run(['git', '-C', str(phone), 'apply', '--check', str(overlay)], check=True)
    subprocess.run(['git', '-C', str(phone), 'apply', str(overlay)], check=True)
    shutil.copytree(config / 'overlay', phone, dirs_exist_ok=True)
    (phone / 'IOS_SOURCE_PROVENANCE.json').write_text(json.dumps(lock, indent=2) + '\n')
    subprocess.run(['git', '-C', str(phone), 'diff', '--check'], check=True)
    print('Source iPhone préparée à partir de ' + lock['source_release'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('mission', type=Path)
    parser.add_argument('phone', type=Path)
    args = parser.parse_args()
    prepare(args.mission.resolve(), args.phone.resolve())
