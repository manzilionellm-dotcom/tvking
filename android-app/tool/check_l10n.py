#!/usr/bin/env python3
"""Refuse les catalogues incomplets et les paramètres de traduction perdus.

La grammaire ICU complète est ensuite vérifiée par flutter gen-l10n. Ce contrôle
ne confond pas une marque ou un mot commun à deux langues avec une omission.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
ARB = ROOT / 'lib' / 'l10n'


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'Clé JSON répétée : {key}')
        result[key] = value
    return result


def read(path):
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique_object)


def check():
    template = read(ARB / 'app_fr.arb')
    keys = {key for key in template if not key.startswith('@')}
    errors = []
    paths = sorted(ARB.glob('app_*.arb'))
    for path in paths:
        messages = read(path)
        actual = {key for key in messages if not key.startswith('@')}
        for key in sorted(keys - actual):
            errors.append(f'{path.name}: traduction absente : {key}')
        for key in sorted(actual - keys):
            errors.append(f'{path.name}: clé sans modèle : {key}')
        for key in sorted(keys & actual):
            value = messages[key]
            if not isinstance(value, str) or not value.strip():
                errors.append(f'{path.name}: texte vide : {key}')
                continue
            expected = set(template.get('@' + key, {}).get('placeholders', {}))
            used = set(re.findall(r'\{([a-zA-Z_]\w*)\s*[,}]', value))
            if used != expected:
                errors.append(f'{path.name}: paramètres {key} : {used} ≠ {expected}')
    # L'ancien raccourci ramenait toutes les langues hors anglais au français.
    for path in (ROOT / 'lib').rglob('*.dart'):
        if 'generated' not in path.parts and re.search(r'\bboxText\s*\(', path.read_text()):
            errors.append(f'{path.relative_to(ROOT)}: retour du sélecteur bilingue boxText')
    if errors:
        raise ValueError('\n'.join(errors))
    return f'{len(paths)} langues × {len(keys)} messages : complets, paramètres vérifiés.'


if __name__ == '__main__':
    try:
        print(check())
    except (ValueError, OSError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
