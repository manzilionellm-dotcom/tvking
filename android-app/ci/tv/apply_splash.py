#!/usr/bin/env python3
# =========================================================
#  apply_splash.py — premier écran Zuno TV (Maison Noir)
# =========================================================
#  Le template Flutter laisse une fenêtre BLANCHE le temps que le
#  moteur dessine. Le build TV collait ensuite la bannière Leanback
#  (PNG opaque, noir pur) sur #050505 : un rectangle plus noir que
#  le fond Flutter (TvTokens.bg = #070708) saute à l'œil.
#
#  Ici :
#    • API 21–30 : calligraphie or TRANSPARENTE, centrée, sur #070708.
#      Même noir que TvShell, donc le premier cadre Flutter ne « pop » pas.
#    • API 31+  : fond #070708 + icône du lanceur (zone sûre du masque
#      rond). Pas de second wordmark dans windowBackground : Android 12
#      masquerait une calligraphie large dans un cercle.
#    • NormalTheme : couleur unie, JAMAIS le bitmap. Sinon le logo reste
#      derrière Flutter (surfaces transparentes, lettre-box).
#
#  Le téléphone 7 MOTION ne lance pas ce script : ses fichiers sources
#  restent un aplat #070708, sans le mot Zuno.
# =========================================================
from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOGO = ROOT / 'android/app/src/main/res/drawable-nodpi/splash_logo.png'

# TvTokens.bg — noir profond Maison Noir, pas le #000 pur (banding OLED)
# ni le #050505 de l'ancien splash.
SPLASH = '#FF070708'

WORDMARK = f'''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/zuno_splash" />
    <item>
        <bitmap
            android:gravity="center"
            android:src="@drawable/splash_logo" />
    </item>
</layer-list>
'''

SOLID = '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/zuno_splash" />
</layer-list>
'''

STYLES = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Lancement : le drawable (wordmark avant Android 12, aplat ensuite). -->
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
    <!-- Après le 1er cadre : aplat seul. Le logo ne doit pas rester derrière. -->
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@color/zuno_splash</item>
    </style>
</resources>
'''

STYLES_V31 = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Android 12+ : fond Maison Noir, icône = lanceur (masque rond).
         Le wordmark large n'est pas repris ici : le cercle le couperait. -->
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowSplashScreenBackground">@color/zuno_splash</item>
        <item name="android:windowSplashScreenIconBackgroundColor">@color/zuno_splash</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@color/zuno_splash</item>
    </style>
</resources>
'''


def apply(res: Path | None = None) -> None:
    """Écrit les ressources de lancement Zuno TV dans [res]."""
    target = Path(res) if res is not None else Path(
        os.environ.get('ZUNO_SPLASH_RES', ROOT / 'android/app/src/main/res'),
    )
    if not LOGO.is_file():
        raise SystemExit(f'splash_logo.png manquant : {LOGO}')
    nodpi = target / 'drawable-nodpi'
    nodpi.mkdir(parents=True, exist_ok=True)
    dest_logo = nodpi / 'splash_logo.png'
    if dest_logo.resolve() != LOGO.resolve():
        dest_logo.write_bytes(LOGO.read_bytes())

    for folder, body in (
        ('drawable', WORDMARK),
        ('drawable-v21', WORDMARK),
        ('drawable-v31', SOLID),
    ):
        path = target / folder
        path.mkdir(parents=True, exist_ok=True)
        (path / 'launch_background.xml').write_text(body)

    values = target / 'values'
    values.mkdir(parents=True, exist_ok=True)
    colors = values / 'colors.xml'
    _ensure_color(colors)
    (values / 'styles.xml').write_text(STYLES)
    night = target / 'values-night'
    night.mkdir(parents=True, exist_ok=True)
    (night / 'styles.xml').write_text(STYLES)
    v31 = target / 'values-v31'
    v31.mkdir(parents=True, exist_ok=True)
    (v31 / 'styles.xml').write_text(STYLES_V31)
    print(f'✓ splash Maison Noir {SPLASH} → {target}')


def _ensure_color(path: Path) -> None:
    line = f'    <color name="zuno_splash">{SPLASH}</color>\n'
    if not path.exists():
        path.write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources>\n'
            f'{line}'
            '</resources>\n',
        )
        return
    text = path.read_text()
    import re
    if 'name="zuno_splash"' in text:
        text = re.sub(
            r'<color name="zuno_splash">[^<]*</color>',
            f'<color name="zuno_splash">{SPLASH}</color>',
            text,
            count=1,
        )
    else:
        text = text.replace('</resources>', f'{line}</resources>', 1)
    path.write_text(text)


if __name__ == '__main__':
    apply()
