#!/usr/bin/env python3
# =========================================================
#  prepare_build.py — Prépare un checkout pour compiler NovaTube TV
# =========================================================
#  À lancer UNE fois, dans android-app/, sur un checkout de CI (ou une copie
#  locale jetable), AVANT `flutter pub get` / `flutter gen-l10n` / build :
#
#      python3 ci/novatube_tv/prepare_build.py
#
#  Pourquoi un script de build plutôt que des fichiers modifiés dans Git ?
#  Le propriétaire a demandé de NE PAS toucher à Zuno. Tout ce qui suit ne
#  concerne que l'APK NovaTube : le dépôt (et donc le build Zuno) reste
#  identique ; seul le dossier de travail de la CI NovaTube est adapté.
#
#  Ce que fait le script (idempotent : le relancer ne change plus rien) :
#    1. pubspec.yaml : déclare le mot-symbole NovaTube (asset du logo).
#    2. Traductions : remplace le NOM « Zuno » par « NovaTube » dans les
#       textes affichés (17 langues). Les CLÉS ne changent pas, et aucun
#       autre mot n'est touché (mot entier, sensible à la casse).
#    3. Écran de lancement : logo NovaTube à la place du logo Zuno (le
#       script ci/tv/apply_splash.py le reprend tel quel ensuite).
#    4. Bannière Android TV (Leanback) NovaTube.
#  La couleur de fond de l'écran de lancement est posée APRÈS
#  apply_splash.py par `prepare_build.py --splash-color` (voir workflow).
# =========================================================
from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BRANDING = ROOT / 'assets/branding'
RES = ROOT / 'android/app/src/main/res'

WORDMARK_ASSET = 'assets/branding/novatube_tv_wordmark.png'
# Ancre stable du pubspec (liste des assets de marque déjà déclarés).
PUBSPEC_ANCHOR = '    - assets/branding/prive_icon.png\n'
# Fond de l'écran de lancement = TvNovatube.bg (#050F0C), opaque.
SPLASH_COLOR = '#FF050F0C'

# « Zuno » comme MOT ENTIER uniquement : « Zunova » ou une clé technique
# `zuno.flag.x` (minuscule) ne sont jamais modifiées.
NAME = re.compile(r'\bZuno\b')


def declare_wordmark() -> bool:
    pubspec = ROOT / 'pubspec.yaml'
    text = pubspec.read_text(encoding='utf-8')
    line = f'    - {WORDMARK_ASSET}\n'
    if line in text:
        return False
    if text.count(PUBSPEC_ANCHOR) != 1:
        raise SystemExit('❌ ancre des assets introuvable dans pubspec.yaml')
    pubspec.write_text(text.replace(PUBSPEC_ANCHOR, PUBSPEC_ANCHOR + line, 1),
                       encoding='utf-8')
    return True


def rename_in_translations() -> int:
    """Remplace le nom affiché dans les VALEURS des .arb (jamais les clés)."""
    changed = 0
    for arb in sorted((ROOT / 'lib/l10n').glob('app_*.arb')):
        data = json.loads(arb.read_text(encoding='utf-8'))
        count = 0
        for key, value in list(data.items()):
            if key.startswith('@') or not isinstance(value, str):
                continue
            new, n = NAME.subn('NovaTube', value)
            if n:
                data[key] = new
                count += n
        if count:
            # ensure_ascii=False : on garde l'arabe, le chinois… lisibles.
            arb.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n',
                           encoding='utf-8')
            changed += count
    return changed


def brand_images() -> None:
    nodpi = RES / 'drawable-nodpi'
    nodpi.mkdir(parents=True, exist_ok=True)
    # apply_splash.py copie ce fichier dans l'écran de lancement.
    shutil.copyfile(BRANDING / 'novatube_tv_splash.png', nodpi / 'splash_logo.png')
    for folder, name in (('drawable', 'novatube_tv_banner.png'),
                         ('drawable-xhdpi', 'novatube_tv_banner.png'),
                         ('drawable-xxhdpi', 'novatube_tv_banner_2x.png')):
        target = RES / folder
        target.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(BRANDING / name, target / 'tv_banner.png')


def splash_color() -> None:
    """À lancer APRÈS ci/tv/apply_splash.py : fond pétrole au démarrage."""
    colors = RES / 'values/colors.xml'
    text = colors.read_text(encoding='utf-8')
    new, n = re.subn(r'<color name="zuno_splash">[^<]*</color>',
                     f'<color name="zuno_splash">{SPLASH_COLOR}</color>', text)
    if n != 1:
        raise SystemExit('❌ couleur zuno_splash introuvable (apply_splash.py lancé ?)')
    colors.write_text(new, encoding='utf-8')


def main(argv: list[str]) -> int:
    if argv[1:] == ['--splash-color']:
        splash_color()
        print(f'✓ fond de lancement NovaTube {SPLASH_COLOR}')
        return 0
    if argv[1:]:
        raise SystemExit('usage : prepare_build.py [--splash-color]')
    print('✓ logo déclaré' if declare_wordmark() else '• logo déjà déclaré')
    print(f'✓ nom remplacé dans {rename_in_translations()} texte(s) traduit(s)')
    brand_images()
    print('✓ écran de lancement et bannière Android TV NovaTube')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
