#!/usr/bin/env python3
# =========================================================
#  compare_apk_video.py — Composants vidéo de deux APK, par SHA-256
# =========================================================
#  Usage : python3 ci/novatube_tv/compare_apk_video.py REF.apk CANDIDAT.apk
#  Sortie : tableau Markdown (stdout). Code 0 si tous les composants VIDÉO
#  natifs sont identiques octet pour octet, 1 sinon.
#
#  Ce qui est comparé :
#    • chaque bibliothèque native lib/<abi>/*.so, avec son SHA-256 ;
#    • les versions des bibliothèques AndroidX déclarées par l'APK
#      (META-INF/androidx.*.version), dont Media3 / ExoPlayer.
#  Composants VIDÉO surveillés : libffmpegJNI (décodeur FFmpeg de Media3),
#  libmpv + libmediakitandroidhelper (moteur media_kit), libflutter (rendu).
#  `libapp.so` (le code Dart compilé) change forcément d'une édition à
#  l'autre : il est listé pour information, pas compté comme composant vidéo.
#
#  Ce que la comparaison NE prouve PAS : l'image affichée. Le code Java
#  (DEX) du lecteur est recompilé et renommé par R8 à chaque build ; ses
#  versions viennent des fichiers .version ci-dessous. L'équivalence visuelle
#  se vérifie sur l'appareil, avec le même flux et les mêmes réglages.
# =========================================================
from __future__ import annotations

import hashlib
import sys
import zipfile

VIDEO_LIBS = ('libffmpegJNI.so', 'libmpv.so', 'libmediakitandroidhelper.so', 'libflutter.so')


def inventory(path: str) -> tuple[dict[str, str], dict[str, str]]:
    libs: dict[str, str] = {}
    versions: dict[str, str] = {}
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            name = info.filename
            if name.startswith('lib/') and name.endswith('.so'):
                libs[name] = hashlib.sha256(z.read(name)).hexdigest()
            elif name.startswith('META-INF/androidx.') and name.endswith('.version'):
                key = name[len('META-INF/'):-len('.version')]
                versions[key] = z.read(name).decode('utf-8', 'replace').strip()
    return libs, versions


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        raise SystemExit('usage : compare_apk_video.py REF.apk CANDIDAT.apk')
    ref_libs, ref_ver = inventory(argv[1])
    new_libs, new_ver = inventory(argv[2])
    print(f'Référence : `{argv[1]}`  \nCandidat : `{argv[2]}`\n')
    print('| Bibliothèque native | SHA-256 référence | SHA-256 candidat | Résultat |')
    print('|---|---|---|---|')
    video_diff = 0
    for name in sorted(set(ref_libs) | set(new_libs)):
        a, b = ref_libs.get(name), new_libs.get(name)
        base = name.rsplit('/', 1)[-1]
        video = base in VIDEO_LIBS
        if a == b:
            verdict = 'identique'
        elif a is None or b is None:
            verdict = 'ABSENTE d\'un côté'
        else:
            verdict = 'différente'
        if video and a != b:
            video_diff += 1
            verdict = f'**{verdict} (vidéo)**'
        elif base == 'libapp.so' and a != b:
            verdict = 'différente (code Dart de l\'édition, attendu)'
        print(f'| `{name}` | `{(a or "—")[:16]}…` | `{(b or "—")[:16]}…` | {verdict} |')
    print('\n| Bibliothèque AndroidX (vidéo et lecteur en gras) | Référence | Candidat |')
    print('|---|---|---|')
    for key in sorted(set(ref_ver) | set(new_ver)):
        a, b = ref_ver.get(key, '—'), new_ver.get(key, '—')
        label = f'**{key}**' if 'media3' in key or 'exoplayer' in key else key
        mark = '' if a == b else ' ⚠'
        print(f'| {label} | {a} | {b}{mark} |')
    media3_diff = sum(1 for k in set(ref_ver) | set(new_ver)
                      if 'media3' in k and ref_ver.get(k) != new_ver.get(k))
    print(f'\nComposants vidéo natifs différents : {video_diff} · versions Media3 différentes : {media3_diff}')
    return 0 if video_diff == 0 and media3_diff == 0 else 1


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
