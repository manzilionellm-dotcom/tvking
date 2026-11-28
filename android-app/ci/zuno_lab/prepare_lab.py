"""Prépare une copie de travail jetable de l'édition auto pour le canal LAB."""
import argparse
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

import yaml

APP = Path(__file__).resolve().parents[2]
RECIPE = APP.parent / ".github/workflows/build-zuno-play-editions.yml"
LAB = "com.sevenmotion.tv.seven_tv.lab"
ANDROID = "{http://schemas.android.com/apk/res/android}"
sys.path.insert(0, str(APP / "ci/mobile/free/ads"))
from prepare_ads import TEST_APP, TEST_BANNER, install_android


def official_step(name):
    steps = yaml.safe_load(RECIPE.read_text())["jobs"]["bundles"]["steps"]
    step, = [step for step in steps if step.get("name") == name]
    if set(step) != {"name", "run"} or "${{" in step["run"]:
        raise ValueError(f"Relire l’étape du constructeur : {name}")
    subprocess.run(["bash", "-eu", "-o", "pipefail", "-c", step["run"]], cwd=APP, check=True)


def prepare():
    subprocess.run([sys.executable, "ci/play_editions/prepare.py", "--edition", "auto"], cwd=APP, check=True)
    official_step("Conserver SharedPreferences déjà validé dans le bundle officiel")
    gradle = APP / "android/app/build.gradle.kts"
    source = gradle.read_text()
    key = 'applicationId = "com.sevenmotion.tv.seven_tv"'
    if source.count(key) != 1:
        raise ValueError("Identité historique ambiguë")
    gradle.write_text(source.replace(key, f'applicationId = "{LAB}"'))
    manifest = APP / "android/app/src/main/AndroidManifest.xml"
    tree = ET.parse(manifest)
    app = tree.getroot().find("application")
    if app.get(ANDROID + "label") != "ZUNO":
        raise ValueError("Le manifeste préparé doit être ZUNO adaptatif")
    app.set(ANDROID + "label", "ZUNO LAB")
    tree.write(manifest, encoding="utf-8", xml_declaration=True)
    install_android(APP, (TEST_APP, TEST_BANNER), expected_package=LAB)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--after-pub", action="store_true")
    args = parser.parse_args()
    if args.after_pub:
        official_step("Patch screen_brightness_android build.gradle (si nécessaire)")
    else:
        prepare()
