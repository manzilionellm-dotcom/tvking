#!/usr/bin/env python3
"""Ajoute le pont NOVATUBE au bundle Atlas vérifié, sans reconstruire l'ancien code."""
import argparse
import hashlib
import json
from pathlib import Path

BASE_SHA256 = '6788284148b1bfb451a63fadf2953f3e2c0713c36155fbf7c1889e3763363bce'
BASE_VERSION = 'd34918d0-f3bf-47a8-adb3-c02c55df0250'
EXPORTED_BASE_SHA256 = '8cc5a991e818e35fb26ec9818cb706c3d94f6153fd0892e0a5451807235b659d'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    base = args.base.read_bytes()
    supplied_hash = hashlib.sha256(base).hexdigest()
    if supplied_hash not in {BASE_SHA256, EXPORTED_BASE_SHA256}:
        raise SystemExit('Le bundle Atlas a changé : vérifier la nouvelle version avant publication.')
    original = base.decode('utf-8')
    anchor = 'export {\n  RealtimeHub,\n  gold_default as default,'
    replacement = ('export {\n  worker_default as atlasOriginal,\n'
                   '  recordAck,\n  markRevisionAck,\n  rateLimitOk,\n  recordPresence,\n'
                   '  ensureOrderTables,\n  markOrderSent,\n  ensureScaleSchema,\n'
                   '  updateDeviceInfo,\n  resetAtFor,\n  blackboxRequestedAt,\n'
                   '  ensureSourcesVersion,\n  notifyBox,\n'
                   '  adminSecretMatches,\n  parseExtendDays,\n  nextTrialEnd,\n  ensureTrialAnchorTable,\n'
                   '  RealtimeHub,\n  gold_default as default,')
    # Les versions déjà publiées ne diffèrent de la base que par cet export.
    # Accepter ce module vérifié évite de rechercher un ancien bundle, sans
    # accepter d'autre changement ni réécrire une fonction historique.
    if supplied_hash == EXPORTED_BASE_SHA256:
        if original.count(replacement) != 1:
            raise SystemExit('Export du module Atlas publié non reconnu.')
        original = original.replace(replacement, anchor, 1)
        if hashlib.sha256(original.encode('utf-8')).hexdigest() != BASE_SHA256:
            raise SystemExit('Le corps du module Atlas publié diffère de la base.')
    if original.count(anchor) != 1:
        raise SystemExit('Export du bundle Atlas non reconnu.')
    patched = original.replace(anchor, replacement, 1)
    # L'export rend les fonctions internes accessibles au nouveau module ;
    # le corps de toutes les fonctions existantes reste identique.
    assert patched.replace(replacement, anchor, 1) == original
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / 'atlas-live.js').write_text(patched)
    here = Path(__file__).resolve().parent
    modules = ('novatube4k.js', 'novatube4k-wrapper.js', 'novatube4k-panel.js',
               'novatube4k-panel-admin.js', 'novatube4k-transfer.js', 'novatube4k-trial.js',
               'novatube4k-recovery.js', 'novatube4k-trial-entitlement.js',
               'novatube4k-commerce.js', 'insights.js', 'page_query.js',
               'panel-alerts.js', 'panel-alerts-api.js', 'panel-alerts-blackbox.js')
    for name in modules:
        (args.out / name).write_bytes((here / name).read_bytes())
    entry = """import legacy, { atlasOriginal, recordAck, markRevisionAck, rateLimitOk, recordPresence,
  ensureOrderTables, markOrderSent, ensureScaleSchema, updateDeviceInfo,
  resetAtFor, blackboxRequestedAt, ensureSourcesVersion, notifyBox,
  adminSecretMatches, parseExtendDays, nextTrialEnd, ensureTrialAnchorTable } from './atlas-live.js';
import { createNovatube4kEntry } from './novatube4k-wrapper.js';
export { RealtimeHub, normMac, shouldAutoProvision } from './atlas-live.js';
export default createNovatube4kEntry(legacy, atlasOriginal, { recordAck, markRevisionAck, rateLimitOk, recordPresence,
  ensureOrderTables, markOrderSent, ensureScaleSchema, updateDeviceInfo, resetAtFor, blackboxRequestedAt,
  ensureSourcesVersion, notifyBox, adminSecretMatches, parseExtendDays, nextTrialEnd, ensureTrialAnchorTable });
"""
    (args.out / 'novatube4k-live-entry.js').write_text(entry)
    names = ['atlas-live.js', *modules, 'novatube4k-live-entry.js']
    audit = {
        'base_version': BASE_VERSION,
        'base_sha256': BASE_SHA256,
        'supplied_base_sha256': supplied_hash,
        'legacy_function_bodies_unchanged': True,
        'main_module': 'novatube4k-live-entry.js',
        'files': {name: hashlib.sha256((args.out / name).read_bytes()).hexdigest() for name in names},
    }
    (args.out / 'release-audit.json').write_text(json.dumps(audit, indent=2) + '\n')
    print(json.dumps(audit))


if __name__ == '__main__':
    main()
