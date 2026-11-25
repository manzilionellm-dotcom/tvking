"""Prépare le projet natif Play avec un paquet et une clé réservés aux essais."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

import yaml

FREE = Path(__file__).resolve().parent
MOBILE = FREE.parent
WORKFLOW = FREE.parents[3] / ".github/workflows/build-7motion-sport-test.yml"

# Ces étapes locales n'ont ni paramètres GitHub, ni accès à la signature.
# Lire leurs corps évite une deuxième recette Gradle, Cast et notifications.
NATIVE_STEPS = [
    "Fixer minSdk 24 (téléphone — requis par ffmpeg_kit)",
    "Harmoniser le nom Android 7 MOTION",
    "Patch AndroidManifest for network (cleartext HTTP + INTERNET)",
    "Patch AndroidManifest for privacy (allowBackup=false)",
    "Patch AndroidManifest for Android TV (leanback)",
    "Apply Google Cast SDK overlay",
    "FLAG_SECURE OFF (l'image doit sortir)",
    "Patch AndroidManifest for Picture-in-Picture",
    "Patch screen_brightness_android build.gradle",
    "Generate launcher icons (7 MOTION)",
    "Patch build.gradle.kts for notifications (desugaring)",
    "Patch AndroidManifest for notifications",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("debug", "release"), default="debug")
    mode = parser.parse_args().mode
    recipe = yaml.safe_load(WORKFLOW.read_text())["jobs"]["phone"]["steps"]
    steps = NATIVE_STEPS.copy()
    if mode == "release":
        steps.append("Enable R8 + ProGuard (shrink code & resources)")
    native = [step for step in recipe if step.get("name") in steps]
    if [step["name"] for step in native] != steps:
        raise SystemExit("La recette native a changé, vérifier la préparation QA")
    for step in native:
        if set(step) != {"name", "run"} or "${{" in step["run"]:
            raise SystemExit(f"Étape native non autonome : {step['name']}")
        print(step["name"], flush=True)
        subprocess.run(["bash", "-eo", "pipefail", "-c", step["run"]], check=True)

    subprocess.run([sys.executable, MOBILE / "prepare_notifications.py"], check=True)
    subprocess.run([sys.executable, MOBILE / "prepare_play.py"], check=True)
    subprocess.run(
        [sys.executable, FREE / "ads/prepare_ads.py", "android"],
        env={**os.environ, "SEVEN_ADMOB_TEST_ADS": "true"}, check=True,
    )

    gradle = Path("android/app/build.gradle.kts")
    text = gradle.read_text()
    start = "    buildTypes {"
    if text.count(start) != 1 or "applicationIdSuffix" in text:
        raise SystemExit("Configuration debug Gradle inattendue")
    debug = '        getByName("debug") { applicationIdSuffix = ".qa" }'
    if mode == "release":
        release = "        release {"
        if text.count(release) != 1:
            raise SystemExit("Configuration release Gradle inattendue")
        text = text.replace(release, release + '\n            applicationIdSuffix = ".qa.perf"')
        # Le contrôle de l’unité AdMob lit le bytecode de la bannière après R8.
        with Path("android/app/proguard-rules.pro").open("a") as rules:
            rules.write("\n-keep class com.manzilionellm.tvking.tv_king.SevenMotionAds$Banner { *; }\n")
    # Gradle et le contrôle final utilisent la même clé de test éphémère,
    # indépendamment du profil Android préinstallé sur le runner.
    signing = '''    signingConfigs {
        getByName("debug") {
            storeFile = file(System.getenv("RUNNER_TEMP") + "/7motion-qa.jks")
        }
    }

'''
    gradle.write_text(text.replace(start, signing + start + "\n" + debug))


if __name__ == "__main__":
    main()
