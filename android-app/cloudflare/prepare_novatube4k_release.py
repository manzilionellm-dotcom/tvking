#!/usr/bin/env python3
"""Ajoute le pont NOVATUBE au bundle Atlas vérifié, sans reconstruire l'ancien code."""
import argparse
import hashlib
import json
from pathlib import Path

BASE_SHA256 = '6788284148b1bfb451a63fadf2953f3e2c0713c36155fbf7c1889e3763363bce'
BASE_VERSION = 'd34918d0-f3bf-47a8-adb3-c02c55df0250'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    base = args.base.read_bytes()
    if hashlib.sha256(base).hexdigest() != BASE_SHA256:
        raise SystemExit('Le bundle Atlas a changé : vérifier la nouvelle version avant publication.')
    original = base.decode('utf-8')
    anchor = 'export {\n  RealtimeHub,\n  gold_default as default,'
    replacement = ('export {\n  worker_default as atlasOriginal,\n'
                   '  recordAck,\n  markRevisionAck,\n  rateLimitOk,\n  recordPresence,\n'
                   '  RealtimeHub,\n  gold_default as default,')
    if original.count(anchor) != 1:
        raise SystemExit('Export du bundle Atlas non reconnu.')
    patched = original.replace(anchor, replacement, 1)
    # L'export rend les fonctions internes accessibles au nouveau module ;
    # le corps de toutes les fonctions existantes reste identique.
    assert patched.replace(replacement, anchor, 1) == original
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / 'atlas-live.js').write_text(patched)
    here = Path(__file__).resolve().parent
    for name in ('novatube4k.js', 'novatube4k-wrapper.js'):
        (args.out / name).write_bytes((here / name).read_bytes())
    entry = """import legacy, { atlasOriginal, recordAck, markRevisionAck, rateLimitOk, recordPresence } from './atlas-live.js';
import { createNovatube4kEntry } from './novatube4k-wrapper.js';
export { RealtimeHub, normMac, shouldAutoProvision } from './atlas-live.js';
export default createNovatube4kEntry(legacy, atlasOriginal, { recordAck, markRevisionAck, rateLimitOk, recordPresence });
"""
    (args.out / 'novatube4k-live-entry.js').write_text(entry)
    names = ['atlas-live.js', 'novatube4k.js', 'novatube4k-wrapper.js', 'novatube4k-live-entry.js']
    audit = {
        'base_version': BASE_VERSION,
        'base_sha256': BASE_SHA256,
        'legacy_function_bodies_unchanged': True,
        'main_module': 'novatube4k-live-entry.js',
        'files': {name: hashlib.sha256((args.out / name).read_bytes()).hexdigest() for name in names},
    }
    (args.out / 'release-audit.json').write_text(json.dumps(audit, indent=2) + '\n')
    print(json.dumps(audit))


if __name__ == '__main__':
    main()
