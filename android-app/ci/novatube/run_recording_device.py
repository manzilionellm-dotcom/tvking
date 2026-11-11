#!/usr/bin/env python3
"""Teste le vrai APK privé dans un émulateur AOSP jetable du runner GitHub."""

import argparse
import base64
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

from common import APP_ROOT, BRANCH, PACKAGE, require, sha256_file
from create_recording_test_media import create
from recording_device_evidence import TEST_CLASS, instrumentation_results

SERIAL = "emulator-5580"
IMAGE = "system-images;android-35;default;x86_64"


def run(command, *, capture=False, timeout=900, cwd=APP_ROOT, input_text=None):
    return subprocess.run(command, cwd=cwd, check=True, timeout=timeout, text=True,
                          input=input_text, stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.STDOUT).stdout


def verify(apk: Path, reports: Path, sdk: Path) -> dict:
    sha = os.environ.get("GITHUB_SHA", "")
    require(os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("GITHUB_REPOSITORY") == "manzilionellm-dotcom/tvking"
            and os.environ.get("GITHUB_REF") == "refs/heads/" + BRANCH
            and re.fullmatch(r"[0-9a-f]{40}", sha) is not None,
            "Ce banc Android est réservé au runner NOVATUBE isolé")
    require(apk.is_file(), "APK release absent avant le test Android")
    digest = sha256_file(apk)
    reports.mkdir(parents=True, exist_ok=True)
    require(shutil.which("ffmpeg") is not None, "ffmpeg requis pour les seules mires de test")
    create(APP_ROOT / "android/app/src/androidTest/assets")
    # Même entrée et même mode que l'APK déjà construit. On conserve son
    # empreinte et on installe CE fichier, pas un autre APK trouvé au hasard.
    define = base64.b64encode(b"NOVATUBE_PRIVATE_APK=true").decode("ascii")
    print("Compilation du petit APK d'instrumentation, signé par la configuration NOVATUBE…", flush=True)
    run(["./gradlew", "--no-daemon", ":app:assembleReleaseAndroidTest",
         "-Ptarget=lib/main_zuno_mobile.dart", "-Pdart-defines=" + define], cwd=APP_ROOT / "android")
    require(sha256_file(apk) == digest, "L'APK release a changé pendant la préparation du test")
    test_apks = list((APP_ROOT / "build/app/outputs/apk/androidTest/release").glob("*.apk"))
    require(len(test_apks) == 1, "APK d'instrumentation absent ou ambigu")
    sdkmanager = sdk / "cmdline-tools/latest/bin/sdkmanager"
    avdmanager = sdk / "cmdline-tools/latest/bin/avdmanager"
    adb = sdk / "platform-tools/adb"
    emulator = sdk / "emulator/emulator"
    print("Préparation de l'émulateur Android 35 AOSP, sans compte Google…", flush=True)
    run([str(sdkmanager), IMAGE, "emulator"], timeout=900)
    require(Path("/dev/kvm").exists(), "Accélération KVM absente du runner")
    if not os.access("/dev/kvm", os.R_OK | os.W_OK):
        run(["sudo", "chown", f"{os.getuid()}:{os.getgid()}", "/dev/kvm"])
    avd = "novatube_export_" + os.environ["GITHUB_RUN_ID"]
    run([str(avdmanager), "create", "avd", "--name", avd, "--package", IMAGE,
         "--force"], input_text="no\n")
    process = None
    emulator_log = reports / "recording-emulator.txt"
    with emulator_log.open("w", encoding="utf-8") as log:
        try:
            process = subprocess.Popen([
                str(emulator), "-avd", avd, "-port", "5580", "-no-window", "-no-audio",
                "-no-boot-anim", "-no-snapshot", "-gpu", "software",
                "-memory", "2048", "-cores", "2", "-accel", "on",
            ], stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 300
            while time.monotonic() < deadline:
                require(process.poll() is None, "L'émulateur s'est arrêté avant le démarrage")
                probe = subprocess.run([str(adb), "-s", SERIAL, "shell", "getprop", "sys.boot_completed"],
                                       capture_output=True, text=True, timeout=15)
                if probe.returncode == 0 and probe.stdout.strip() == "1":
                    break
                time.sleep(3)
            else:
                raise ValueError("Android n'a pas terminé son démarrage")
            run([str(adb), "-s", SERIAL, "shell", "input", "keyevent", "82"])
            run([str(adb), "-s", SERIAL, "install", "-r", str(apk)], timeout=120)
            run([str(adb), "-s", SERIAL, "install", "-r", str(test_apks[0])], timeout=120)
            print("Vrais exports Android : copie AVC/AAC, conversion HEVC, refus faux MP4…", flush=True)
            output = run([str(adb), "-s", SERIAL, "shell", "am", "instrument", "-w", "-r",
                          "-e", "class", TEST_CLASS,
                          PACKAGE + ".test/androidx.test.runner.AndroidJUnitRunner"],
                         capture=True, timeout=360)
            report_path = reports / "recording-device-tests.txt"
            report_path.write_text(output, encoding="utf-8")
            print(output, flush=True)
            passed = instrumentation_results(output)
            result = {
                "status": "passed", "platform": "Android Emulator AOSP", "apiLevel": 35,
                "physicalDevice": False, "sourceCommit": sha, "apkSha256": digest,
                "passed": passed, "reportSha256": sha256_file(report_path),
            }
            (reports / "recording-device-tests.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
            return result
        finally:
            if process is not None:
                try:
                    subprocess.run([str(adb), "-s", SERIAL, "emu", "kill"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
                except subprocess.SubprocessError:
                    pass
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=15)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--reports", type=Path, required=True)
    args = parser.parse_args()
    sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    require(sdk is not None, "Android SDK absent")
    print(json.dumps(verify(args.apk.resolve(), args.reports.resolve(), Path(sdk))))
