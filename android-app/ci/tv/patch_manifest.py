#!/usr/bin/env python3
# =========================================================
#  patch_manifest.py — Manifeste Android du build Zuno TV
# =========================================================
#  Appelé par le workflow racine `.github/workflows/build-zuno-tv.yml`
#  (ou à la main, pour un build TV local) :
#
#      python3 ci/tv/patch_manifest.py android/app/src/main/AndroidManifest.xml
#
#  POURQUOI un script plutôt que 40 lignes de `sed` dans le YAML : le
#  dossier `android/` est versionné (généré par `flutter create`) et
#  PARTAGÉ avec le build téléphone. On ne veut pas y graver en dur les
#  réglages propres à la télévision (paysage forcé, Leanback, bannière…).
#  Ce script les applique AU MOMENT du build TV, de façon IDEMPOTENTE
#  (le relancer deux fois ne change rien) et LISIBLE (chaque bloc dit
#  pourquoi il existe). Il est testable en local avec un simple Python.
#
#  Ce qu'il fait, dans l'ordre :
#    1. Nom affiché « Zuno » (icône du launcher / Leanback).
#    2. Réseau : INTERNET + trafic HTTP en clair (les flux IPTV sont
#       très souvent en http://), + REQUEST_INSTALL_PACKAGES (updater
#       sideload), + notifications (rappels sport).
#    3. Android TV : Leanback (non obligatoire → les box bon marché sans
#       cette « feature » restent installables), écran tactile non requis,
#       catégorie LEANBACK_LAUNCHER (visible sur la home à côté de Netflix),
#       bannière @drawable/tv_banner (copiée par le workflow).
#    4. Compatibilité box : paysage verrouillé, PiP, largeHeap (anti-OOM
#       sur box 1 Go), Impeller OFF (rendu Skia — anti écran noir GPU sur
#       vieilles box ; ignoré sans effet sur les Flutter qui n'ont plus Skia),
#       micro/caméra/portrait/faketouch non requis (sinon certaines box
#       refusent l'install : « incompatible »).
#    5. Propreté : `android.permission.DUMP` (injecté par un plugin)
#       retiré via tools:node="remove" — inutile et effrayant pour les
#       scanners de stores.
#    6. Box Android 5/6 : 4 plugins officiels annoncent minSdk 24 par simple
#       alignement sur la politique Flutter ; on autorise leur fusion dans un
#       APK minSdk 21 (`tools:overrideLibrary`), sinon le build échoue.
# =========================================================
import re
import sys

APP_LABEL = "Zuno"

# Plugins dont le build.gradle annonce minSdk 24 (namespaces Android).
OVERRIDE_LIBRARIES = (
    "io.flutter.plugins.flutter_plugin_android_lifecycle",
    "io.flutter.plugins.localauth",
    "io.flutter.plugins.sharedpreferences",
    "io.flutter.plugins.urllauncher",
)


def _add_after_manifest_tag(s: str, line: str) -> str:
    """Insère `line` juste après la balise <manifest …>, si absente."""
    if line.strip() in s:
        return s
    return re.sub(r"(<manifest[^>]*>)", r"\1\n    " + line, s, count=1)


def _add_application_attr(s: str, attr: str, value: str) -> str:
    """Ajoute `android:<attr>="<value>"` sur <application>, si absent."""
    if f"android:{attr}=" in s:
        return s
    return s.replace("<application", f'<application\n        android:{attr}="{value}"', 1)


def patch(s: str) -> str:
    # --- 0. Espace de noms `tools:` (nécessaire au retrait de DUMP) ---
    if "xmlns:tools" not in s:
        s = s.replace(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android"',
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android"'
            ' xmlns:tools="http://schemas.android.com/tools"',
            1,
        )

    # --- 1. Nom affiché ---
    s = re.sub(r'android:label="[^"]*"', f'android:label="{APP_LABEL}"', s, count=1)

    # --- 2. Réseau + updater + notifications ---
    for perm in (
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.REQUEST_INSTALL_PACKAGES",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.RECEIVE_BOOT_COMPLETED",
        "android.permission.WAKE_LOCK",
    ):
        s = _add_after_manifest_tag(s, f'<uses-permission android:name="{perm}"/>')
    s = _add_application_attr(s, "usesCleartextTraffic", "true")

    # --- 3. Android TV / Leanback ---
    for feat in (
        "android.software.leanback",
        "android.hardware.touchscreen",
        "android.hardware.microphone",
        "android.hardware.camera",
        "android.hardware.screen.portrait",
        "android.hardware.faketouch",
    ):
        s = _add_after_manifest_tag(
            s, f'<uses-feature android:name="{feat}" android:required="false"/>'
        )
    if "LEANBACK_LAUNCHER" not in s:
        s = s.replace(
            '<category android:name="android.intent.category.LAUNCHER"/>',
            '<category android:name="android.intent.category.LAUNCHER"/>\n'
            '                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
            1,
        )
    s = _add_application_attr(s, "banner", "@drawable/tv_banner")

    # --- 4. Compatibilité box ---
    s = _add_application_attr(s, "largeHeap", "true")
    if "android:screenOrientation" not in s:
        s = s.replace(
            'android:name=".MainActivity"',
            'android:name=".MainActivity"\n'
            '            android:screenOrientation="landscape"\n'
            '            android:supportsPictureInPicture="true"\n'
            '            android:resizeableActivity="true"',
            1,
        )
    if "EnableImpeller" not in s:
        s = s.replace(
            "</application>",
            "    <meta-data\n"
            '            android:name="io.flutter.embedding.android.EnableImpeller"\n'
            '            android:value="false" />\n'
            "    </application>",
            1,
        )

    # --- 6. Box Android 5/6 : fusion des plugins annoncés « minSdk 24 » ---
    s = _add_after_manifest_tag(
        s,
        '<uses-sdk tools:overrideLibrary="' + ",".join(OVERRIDE_LIBRARIES) + '"/>',
    )

    # --- 5. Propreté stores ---
    s = _add_after_manifest_tag(
        s, '<uses-permission android:name="android.permission.DUMP" tools:node="remove"/>'
    )
    return s


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_manifest.py <AndroidManifest.xml>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path, encoding="utf-8") as f:
        before = f.read()
    after = patch(before)
    with open(path, "w", encoding="utf-8") as f:
        f.write(after)
    # Garde-fous : on refuse un manifeste qui n'aurait pas TOUT ce qu'il faut.
    required = (
        f'android:label="{APP_LABEL}"',
        "android.permission.INTERNET",
        'android:usesCleartextTraffic="true"',
        "LEANBACK_LAUNCHER",
        'android:banner="@drawable/tv_banner"',
        'android:screenOrientation="landscape"',
        "tools:overrideLibrary",
    )
    missing = [r for r in required if r not in after]
    if missing:
        print("❌ manifeste TV incomplet, manque :", missing, file=sys.stderr)
        return 1
    print("✓ manifeste Zuno TV patché :", path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
