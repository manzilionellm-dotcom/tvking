#!/usr/bin/env python3
"""Teste le vrai APK privé dans un émulateur AOSP jetable du runner GitHub."""

import argparse
import base64
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

from common import APP_ROOT, BRANCH, PACKAGE, require, sha256_file
from create_recording_test_media import create
from recording_device_evidence import TEST_CLASS, instrumentation_results

SERIAL = "emulator-5580"
IMAGE = "system-images;android-35;default;x86_64"


def run(command, *, capture=False, timeout=900, cwd=APP_ROOT, input_text=None, env=None):
    return subprocess.run(command, cwd=cwd, check=True, timeout=timeout, text=True,
                          input=input_text, stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.STDOUT, env=env).stdout


def runner_identity() -> str:
    """Les deux modes restent réservés à la branche et au runner dédiés."""
    sha = os.environ.get("GITHUB_SHA", "")
    require(os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("GITHUB_REPOSITORY") == "manzilionellm-dotcom/tvking"
            and os.environ.get("GITHUB_REF") == "refs/heads/" + BRANCH
            and re.fullmatch(r"[0-9a-f]{40}", sha) is not None,
            "Ce banc Android est réservé au runner NOVATUBE isolé")
    require(re.fullmatch(r"[0-9]+", os.environ.get("GITHUB_RUN_ID", "")) is not None,
            "Identifiant de run GitHub absent ou invalide")
    return sha


def safe_diagnostic(value) -> str:
    """Ne jamais publier une valeur sensible qui aurait été répétée par un outil."""
    if isinstance(value, bytes):
        value = value.decode("utf-8", errors="replace")
    text = str(value or "")
    sensitive = ("PASSWORD", "TOKEN", "SECRET", "CREDENTIAL", "KEYSTORE_BASE64")
    values = {value for name, value in os.environ.items()
              if value and any(word in name.upper() for word in sensitive)}
    for value in sorted(values, key=len, reverse=True):
        text = text.replace(value, "[MASQUÉ]")
    return text


def emulator_environment() -> dict:
    """Un dossier AVD explicite partagé par les deux outils, sans changer HOME."""
    temporary = os.environ.get("RUNNER_TEMP")
    require(temporary is not None and Path(temporary).is_absolute(),
            "Répertoire temporaire absolu du runner absent")
    avd_home = (Path(temporary) / "novatube-avds").resolve()
    avd_home.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ)
    environment["ANDROID_AVD_HOME"] = str(avd_home)
    return environment


def prepare_emulator(sdk: Path, environment: dict) -> str:
    """Même image, même AVD et même accès KVM pour le prévol et les tests."""
    sdkmanager = sdk / "cmdline-tools/latest/bin/sdkmanager"
    avdmanager = sdk / "cmdline-tools/latest/bin/avdmanager"
    print("Préparation de l'émulateur Android 35 AOSP, sans compte Google…", flush=True)
    run([str(sdkmanager), IMAGE, "emulator"], timeout=900, env=environment)
    require(Path("/dev/kvm").exists(), "Accélération KVM absente du runner")
    if not os.access("/dev/kvm", os.R_OK | os.W_OK):
        run(["sudo", "chown", f"{os.getuid()}:{os.getgid()}", "/dev/kvm"])
    avd = "novatube_export_" + os.environ["GITHUB_RUN_ID"]
    avd_home = Path(environment["ANDROID_AVD_HOME"])
    avd_path = avd_home / (avd + ".avd")
    run([str(avdmanager), "create", "avd", "--name", avd, "--package", IMAGE,
         "--path", str(avd_path), "--force"], input_text="no\n", env=environment)
    # L'index .ini sert à résoudre « -avd nom ». --path seul ne garantit
    # pas que le lanceur et avdmanager recherchent cet index au même endroit.
    require((avd_home / (avd + ".ini")).is_file(),
            f"Index AVD absent du dossier explicite : {avd_home / (avd + '.ini')}")
    require(avd_path.is_dir(), f"Dossier de données AVD absent : {avd_path}")
    return avd


def stop_emulator(process, adb: Path) -> None:
    """Ferme uniquement l'émulateur créé ici, y compris s'il ne répond plus à adb."""
    if process.poll() is None:
        try:
            subprocess.run([str(adb), "-s", SERIAL, "emu", "kill"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        except (OSError, subprocess.SubprocessError):
            pass
        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            # Popen a créé sa propre session : aucun autre processus du runner
            # ne partage ce groupe. Le lanceur et son éventuel enfant QEMU
            # sont arrêtés ensemble, même si le démarrage Android a échoué.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=15)
    else:
        process.wait(timeout=15)


@contextmanager
def booted_emulator(reports: Path, sdk: Path, *, preflight=False):
    """Conserve les erreurs de démarrage et garantit l'arrêt après utilisation."""
    reports.mkdir(parents=True, exist_ok=True)
    environment = emulator_environment()
    avd = prepare_emulator(sdk, environment)
    adb = sdk / "platform-tools/adb"
    emulator = sdk / "emulator/emulator"
    process = None
    failure = None
    suffix = "-preflight" if preflight else ""
    emulator_log = reports / f"recording-emulator{suffix}.txt"
    with emulator_log.open("w", encoding="utf-8") as log:
        try:
            process = subprocess.Popen([
                str(emulator), "-avd", avd, "-port", "5580", "-no-window", "-no-audio",
                "-no-boot-anim", "-no-snapshot", "-gpu", "software",
                "-memory", "2048", "-cores", "2", "-accel", "on",
            ], stdout=log, stderr=subprocess.STDOUT, start_new_session=True, env=environment)
            deadline = time.monotonic() + 300
            while time.monotonic() < deadline:
                code = process.poll()
                require(code is None, f"L'émulateur s'est arrêté avant le démarrage (code {code})")
                probe = subprocess.run([str(adb), "-s", SERIAL, "shell", "getprop", "sys.boot_completed"],
                                       capture_output=True, text=True, timeout=15)
                if probe.returncode == 0 and probe.stdout.strip() == "1":
                    break
                time.sleep(3)
            else:
                raise ValueError("Android n'a pas terminé son démarrage")
            run([str(adb), "-s", SERIAL, "shell", "input", "keyevent", "82"])
            yield adb
        except BaseException as error:
            failure = error
            raise
        finally:
            before_cleanup = process.poll() if process is not None else "non lancé"
            cleanup_error = None
            if process is not None:
                try:
                    stop_emulator(process, adb)
                except (OSError, subprocess.SubprocessError) as error:
                    cleanup_error = error
            log.flush()
            # Après l'arrêt, le fichier ne reçoit plus de sortie du processus.
            # La même version expurgée sert au journal Actions et à l'artefact.
            diagnostic = safe_diagnostic(emulator_log.read_text(encoding="utf-8", errors="replace"))
            emulator_log.write_text(diagnostic, encoding="utf-8")
            if failure is not None or cleanup_error is not None:
                print(f"Diagnostic émulateur : code avant nettoyage = {before_cleanup}", flush=True)
                print("\n".join(diagnostic.splitlines()[-120:]) or "Aucune sortie de l'émulateur.", flush=True)
            if cleanup_error is not None:
                print("Erreur pendant l'arrêt de l'émulateur : " + safe_diagnostic(cleanup_error), flush=True)
                if failure is None:
                    raise cleanup_error


def preflight(reports: Path, sdk: Path) -> dict:
    """Valide seulement le démarrage de l'infrastructure, jamais les exports."""
    sha = runner_identity()
    with booted_emulator(reports, sdk, preflight=True):
        print("Prévol Android terminé : démarrage confirmé ; aucun test d'export exécuté.", flush=True)
    return {"status": "booted", "stage": "emulator-preflight", "apiLevel": 35,
            "sourceCommit": sha, "testsExecuted": 0}


def capture_test_logcat(adb: Path, reports: Path) -> None:
    """Journal limité au pont d'export et aux tags du banc synthétique."""
    try:
        output = run([str(adb), "-s", SERIAL, "logcat", "-d", "-v", "threadtime", "-t", "2000",
                      "GalleryExporter:V", "TestRunner:V", "AndroidJUnitRunner:V",
                      "InstrumentationResultPrinter:V", "*:S"], capture=True, timeout=20)
    except (OSError, subprocess.SubprocessError) as error:
        output = "Journal du test indisponible : " + str(error)
    output = safe_diagnostic(output)
    (reports / "recording-android-logcat.txt").write_text(output, encoding="utf-8")
    print("Journal limité à l'export NOVATUBE et au test Android :\n" + output, flush=True)


def verify(apk: Path, reports: Path, sdk: Path) -> dict:
    sha = runner_identity()
    require(apk.is_file(), "APK release absent avant le test Android")
    digest = sha256_file(apk)
    reports.mkdir(parents=True, exist_ok=True)
    # Les deux mires synthétiques sont versionnées et vérifiées par SHA-256 :
    # aucun téléchargement de logiciel ni de vidéo externe pour les préparer.
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
    with booted_emulator(reports, sdk) as adb:
        instrumentation_started = False
        try:
            run([str(adb), "-s", SERIAL, "install", "-r", str(apk)], timeout=120)
            run([str(adb), "-s", SERIAL, "install", "-r", str(test_apks[0])], timeout=120)
            # L'émulateur est jetable et ne contient que nos mires. Effacer
            # son historique garantit un diagnostic borné à cette exécution.
            run([str(adb), "-s", SERIAL, "logcat", "-c"], timeout=20)
            print("Vrais exports Android : copie AVC/AAC, conversion HEVC, refus faux MP4…", flush=True)
            report_path = reports / "recording-device-tests.txt"
            instrumentation_started = True
            try:
                output = run([str(adb), "-s", SERIAL, "shell", "am", "instrument", "-w", "-r",
                              "-e", "class", TEST_CLASS,
                              PACKAGE + ".test/androidx.test.runner.AndroidJUnitRunner"],
                             capture=True, timeout=360)
            except subprocess.SubprocessError as error:
                partial = safe_diagnostic(getattr(error, "output", ""))
                report_path.write_text(partial, encoding="utf-8")
                print(partial, flush=True)
                raise
            output = safe_diagnostic(output)
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
        except BaseException:
            if instrumentation_started:
                capture_test_logcat(adb, reports)
            raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight", action="store_true",
                        help="Démarrer puis arrêter Android avant la compilation, sans tests d'export")
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--reports", type=Path, required=True)
    args = parser.parse_args()
    if args.preflight and args.apk is not None:
        parser.error("--apk ne s'utilise pas avec --preflight")
    if not args.preflight and args.apk is None:
        parser.error("--apk est obligatoire pour tester les exports")
    sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    require(sdk is not None, "Android SDK absent")
    result = (preflight(args.reports.resolve(), Path(sdk)) if args.preflight
              else verify(args.apk.resolve(), args.reports.resolve(), Path(sdk)))
    print(json.dumps(result))
