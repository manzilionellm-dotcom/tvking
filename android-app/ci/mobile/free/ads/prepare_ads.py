#!/usr/bin/env python3
"""Installe la bannière AdMob dans le projet Android généré pour la fiche 7 MOTION."""
import argparse
import os
import re
from pathlib import Path
from shutil import copyfile
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
PACKAGE = "com.manzilionellm.tvking"
TEST_APP = "ca-app-pub-3940256099942544~3347511713"
TEST_BANNER = "ca-app-pub-3940256099942544/9214589741"
ANDROID = "{http://schemas.android.com/apk/res/android}"
ET.register_namespace("android", ANDROID[1:-1])
ET.register_namespace("tools", "http://schemas.android.com/tools")


def configured_ids(env):
    app_id = env.get("SEVEN_ADMOB_APP_ID", "").strip()
    banner_id = env.get("SEVEN_ADMOB_BANNER_ID", "").strip()
    if env.get("SEVEN_ADMOB_TEST_ADS", "").lower() == "true":
        if app_id or banner_id:
            raise ValueError("Les identifiants de test et de production sont exclusifs")
        return TEST_APP, TEST_BANNER
    if not app_id and not banner_id:
        return None
    app = re.fullmatch(r"ca-app-pub-([0-9]{16})~[0-9]{10}", app_id)
    banner = re.fullmatch(r"ca-app-pub-([0-9]{16})/[0-9]{10}", banner_id)
    if not app or not banner or app[1] != banner[1] or app[1] == "3940256099942544":
        raise ValueError("Fournir les deux identifiants AdMob du même compte de production")
    return app_id, banner_id


def install_android(project, ids, *, expected_package=PACKAGE):
    module = project / "android/app"
    gradle = module / "build.gradle.kts"
    build = gradle.read_text()
    application_ids = re.findall(r'^\s*applicationId\s*=\s*"([^"]+)"', build, re.M)
    if application_ids != [expected_package]:
        raise ValueError(f"Le paquet Play attendu pour cette configuration est {expected_package}")
    if ids is None:
        # Une deuxième exécution sur un arbre déjà monétisé ne doit jamais le
        # faire passer silencieusement pour un bundle sans publicité.
        if "play-services-ads:" in build:
            raise ValueError("Repartir d'un projet Android propre pour désactiver AdMob")
        return

    app_id, banner_id = ids
    manifest = module / "src/main/AndroidManifest.xml"
    tree = ET.parse(manifest)
    application = tree.getroot().find("application")
    if application is None:
        raise ValueError("Manifeste sans application")
    for name, value in {
        "com.google.android.gms.ads.APPLICATION_ID": app_id,
        "com.google.android.gms.ads.DELAY_APP_MEASUREMENT_INIT": "true",
    }.items():
        entries = [e for e in application.findall("meta-data") if e.get(ANDROID + "name") == name]
        if len(entries) > 1:
            raise ValueError(f"Métadonnée en double : {name}")
        entry = entries[0] if entries else ET.SubElement(application, "meta-data")
        entry.set(ANDROID + "name", name)
        entry.set(ANDROID + "value", value)

    activities = list((module / "src/main/kotlin").rglob("MainActivity.kt"))
    if len(activities) != 1:
        raise ValueError("L'activité Android générée est ambiguë")
    activity = activities[0]
    text = activity.read_text()
    package = re.search(r"^package ([\w.]+)\s*$", text, re.M)
    hook = "        super.configureFlutterEngine(flutterEngine)"
    registration = "        SevenMotionAds(this, flutterEngine)"
    if not package or text.count(hook) != 1:
        raise ValueError("Point d'intégration Flutter/Cast absent")
    if registration not in text:
        text = text.replace(hook, hook + "\n" + registration)

    # Les dépendances natives restent absentes des autres saveurs et du verrou Dart.
    deps = '''dependencies {
    implementation("com.google.android.gms:play-services-ads:25.5.0")
    implementation("com.google.android.ump:user-messaging-platform:4.0.0")
}
'''
    if deps not in build:
        if "play-services-ads:" in build or "user-messaging-platform:" in build:
            raise ValueError("Une configuration publicitaire différente existe déjà")
        build = build.rstrip() + "\n\n" + deps

    bridge = (HERE / "SevenMotionAds.kt").read_text()
    bridge = bridge.replace("package com.manzilionellm.tvking", "package " + package[1], 1)
    bridge = bridge.replace("__SEVEN_BANNER_ID__", banner_id)
    activity.with_name("SevenMotionAds.kt").write_text(bridge)
    activity.write_text(text)
    gradle.write_text(build)
    tree.write(manifest, encoding="utf-8", xml_declaration=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("dart", "android"))
    args = parser.parse_args()
    project = Path.cwd()
    if args.phase == "dart":
        target = project / "lib/features/ads/presentation/seven_motion_ads.dart"
        target.parent.mkdir(parents=True, exist_ok=True)
        copyfile(HERE / target.name, target)
    else:
        ids = configured_ids(os.environ)
        install_android(project, ids)
        print("AdMob configuré" if ids else "Aucun identifiant AdMob : bundle sans SDK publicitaire")


if __name__ == "__main__":
    main()
