"""Prépare le même projet natif que Play, avec un paquet debug isolé."""
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
    recipe = yaml.safe_load(WORKFLOW.read_text())["jobs"]["phone"]["steps"]
    native = [step for step in recipe if step.get("name") in NATIVE_STEPS]
    if [step["name"] for step in native] != NATIVE_STEPS:
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
    gradle.write_text(text.replace(start, start + "\n" + debug))


if __name__ == "__main__":
    main()
