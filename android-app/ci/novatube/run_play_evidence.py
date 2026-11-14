#!/usr/bin/env python3
"""Photographie le véritable AAB Play sur deux Android jetables, sans rebuild.

Ce script n'est ni un banc APK privé ni une publication Google. bundletool
transforme l'AAB déjà signé et vérifié en APK installable, signé uniquement
avec une clé éphémère d'émulateur. L'AAB et les sources restent inchangés.

Première étape volontairement bornée : accueil et « Mes sources », à vide,
sur téléphone et tablette. Une hiérarchie UI non reconnue fait échouer le
job. Aucune image de diagnostic n'est présentée comme capture validée et
aucune vidéo n'est qualifiée de preuve de service de premier plan.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

from common import (
    APP_ROOT, BRANCH, BUNDLETOOL_SHA256, BUNDLETOOL_VERSION, ENTRYPOINT,
    LABEL, PACKAGE, VERSION_CODE, VERSION_NAME,
    expected_certificate, require, sha256_file,
)
from verify_aab import manifest_identity, verify_play_source_target, verify_signature


REPOSITORY = "manzilionellm-dotcom/tvking"
IMAGE = "system-images;android-35;default;x86_64"
BUILD_TOOLS = "35.0.0"
SERIAL = "emulator-5582"
DEVICES = (
    {"name": "phone", "width": 1080, "height": 1920, "density": 420},
    {"name": "tablet", "width": 1600, "height": 2560, "density": 240},
)
HOME_KEYS = ("tvNavLive", "tvNavFilms", "tvNavSeries", "tvNavServer")
SOURCE_KEYS = ("tvMySources", "tvAddXtream", "tvAddM3u", "tvSourcesEmpty")


def run(command, *, timeout=120, environment=None, input_text=None) -> str:
    """Chaque outil a une limite ; aucun shell ne réinterprète les arguments."""
    return subprocess.run(
        [str(part) for part in command], cwd=APP_ROOT, env=environment,
        input=input_text, capture_output=True, text=True, check=True, timeout=timeout,
    ).stdout


def safe_diagnostic(value) -> str:
    text = value.decode("utf-8", errors="replace") if isinstance(value, bytes) else str(value or "")
    names = ("PASSWORD", "TOKEN", "SECRET", "CREDENTIAL", "KEYSTORE_BASE64")
    sensitive = {value for name, value in os.environ.items()
                 if value and any(part in name.upper() for part in names)}
    for value in sorted(sensitive, key=len, reverse=True):
        text = text.replace(value, "[MASQUÉ]")
    return text


def runner_context(environment=None) -> dict:
    """Doubler les gardes YAML avant tout téléchargement ou démarrage."""
    env = os.environ if environment is None else environment
    sha = env.get("GITHUB_SHA", "")
    owner = REPOSITORY.split("/", 1)[0]
    require(env.get("GITHUB_ACTIONS") == "true"
            and env.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
            and env.get("GITHUB_REPOSITORY") == REPOSITORY
            and env.get("GITHUB_REF") == "refs/heads/" + BRANCH
            and env.get("GITHUB_REPOSITORY_OWNER") == owner
            and env.get("GITHUB_ACTOR") == owner
            and env.get("GITHUB_TRIGGERING_ACTOR") == owner
            and env.get("NOVATUBE_CAPTURE_CONFIRMATION") == "COMPILER_NOVATUBE"
            and re.fullmatch(r"[0-9a-f]{40}", sha) is not None
            and env.get("REVIEWED_COMMIT") == sha,
            "Captures réservées au run Play manuel, propriétaire, branche et SHA approuvés")
    run_id, attempt = env.get("GITHUB_RUN_ID", ""), env.get("GITHUB_RUN_ATTEMPT", "")
    require(re.fullmatch(r"[1-9][0-9]*", run_id) is not None
            and re.fullmatch(r"[1-9][0-9]*", attempt) is not None,
            "Identifiant ou tentative du run absent")
    require(not any(env.get(name) for name in (
        "NOVATUBE_UPLOAD_KEYSTORE_BASE64", "NOVATUBE_UPLOAD_STORE_PASSWORD",
        "NOVATUBE_UPLOAD_KEY_PASSWORD", "NOVATUBE_UPLOAD_KEY_ALIAS", "NOVATUBE_KEYSTORE_PATH",
    )), "La capture ne doit pas recevoir de clé ni de secret de téléversement")
    return {"sourceCommit": sha, "runId": run_id, "runAttempt": attempt,
            "runUrl": f"https://github.com/{REPOSITORY}/actions/runs/{run_id}"}


def regular_file(folder: Path, name: str) -> Path:
    path = folder / name
    require(path.is_file() and not path.is_symlink() and path.resolve().parent == folder.resolve(),
            "Fichier de preuve absent ou indirect : " + name)
    return path


def validate_artifact(folder: Path, context: dict) -> tuple[Path, dict]:
    """Lier le binaire, les deux provenances et le run avant de l'exécuter."""
    filename = f"NOVATUBE-{VERSION_NAME}-{VERSION_CODE}.aab"
    aab = regular_file(folder, filename)
    provenance = json.loads(regular_file(folder, "build-provenance.json").read_text(encoding="utf-8"))
    source = json.loads(regular_file(folder, "source-verification.json").read_text(encoding="utf-8"))
    require(provenance.get("status") == "verified" and source.get("status") == "passed",
            "L'artefact n'a pas passé les vérifications de livraison")
    require(provenance.get("package") == PACKAGE and provenance.get("label") == LABEL
            and provenance.get("versionName") == VERSION_NAME
            and provenance.get("versionCode") == int(VERSION_CODE)
            and provenance.get("entrypoint") == ENTRYPOINT
            and provenance.get("testBuild") is False,
            "Identité ou mode du binaire Play inattendu")
    require(provenance.get("source") == source and source.get("sourceCommit") == context["sourceCommit"],
            "Les provenances ne correspondent pas au SHA approuvé")
    verify_play_source_target(source)
    for key in ("runId", "runAttempt", "runUrl"):
        require(provenance.get(key) == context[key], "L'artefact vient d'un autre run : " + key)
    _, certificate = expected_certificate()
    require(provenance.get("uploadCertificateSha256") == certificate
            and provenance.get("signing") == "dedicated-novatube-upload-key",
            "Certificat public de provenance inattendu")
    require(provenance.get("bundletoolVersion") == BUNDLETOOL_VERSION
            and provenance.get("bundletoolSha256") == BUNDLETOOL_SHA256,
            "Outil de vérification de provenance inattendu")
    digest = sha256_file(aab)
    require(digest == provenance.get("sha256") and aab.stat().st_size == provenance.get("sizeBytes"),
            "L'AAB ne correspond plus à sa somme de contrôle")
    sums = regular_file(folder, "SHA256SUMS.txt").read_text(encoding="ascii")
    require(sums == digest + "  " + filename + "\n", "Manifeste SHA256 de l'AAB incohérent")
    require(provenance.get("abis") == ["armeabi-v7a", "arm64-v8a", "x86_64"],
            "Le binaire vérifié ne déclare pas les architectures attendues")
    return aab, provenance


def download_bundletool(folder: Path) -> Path:
    """N'utiliser que le JAR Google dont la somme est déjà revue dans Git."""
    jar = folder / "bundletool.jar"
    url = ("https://github.com/google/bundletool/releases/download/" + BUNDLETOOL_VERSION
           + "/bundletool-all-" + BUNDLETOOL_VERSION + ".jar")
    with urllib.request.urlopen(url, timeout=60) as response, jar.open("wb") as target:
        shutil.copyfileobj(response, target)
    require(sha256_file(jar) == BUNDLETOOL_SHA256, "JAR bundletool non approuvé")
    return jar


def verify_real_bundle(aab: Path, bundletool: Path, provenance: dict) -> dict:
    run(["java", "-jar", bundletool, "validate", "--bundle=" + str(aab)], timeout=180)
    xml = run(["java", "-jar", bundletool, "dump", "manifest", "--bundle=" + str(aab), "--module=base"])
    identity = manifest_identity(xml)
    require(all(provenance.get(key) == value for key, value in identity.items()),
            "Le manifeste réel diffère de la provenance de livraison")
    certificate, _ = verify_signature(aab)
    require(certificate == provenance["uploadCertificateSha256"], "Signature réelle inattendue")
    return identity


def convert_bundle(aab: Path, bundletool: Path, temporary: Path, sdk: Path) -> Path:
    """La clé jetable signe l'APK dérivé, jamais l'AAB destiné à Google Play."""
    key, password_file = temporary / "emulator-only.p12", temporary / "emulator-only.password"
    password_file.write_text(secrets.token_urlsafe(36), encoding="ascii")
    password_file.chmod(0o600)
    run(["keytool", "-genkeypair", "-noprompt", "-keystore", key, "-storetype", "PKCS12",
         "-alias", "emulator-only", "-storepass:file", password_file, "-keypass:file", password_file,
         "-keyalg", "RSA", "-keysize", "2048", "-validity", "2",
         "-dname", "CN=NOVATUBE ephemeral emulator evidence"])
    archive = temporary / "emulator-only.apks"
    run(["java", "-jar", bundletool, "build-apks", "--bundle=" + str(aab),
         "--output=" + str(archive), "--mode=universal", "--ks=" + str(key),
         "--ks-key-alias=emulator-only", "--ks-pass=file:" + str(password_file),
         "--key-pass=file:" + str(password_file)], timeout=480)
    apk = temporary / "emulator-only.apk"
    with zipfile.ZipFile(archive) as files, files.open("universal.apk") as source, apk.open("wb") as target:
        shutil.copyfileobj(source, target)
    # Comparer les octets exécutés au lieu de croire seulement le nom donné
    # à l'APK : bundletool ne doit changer ni code Dex ni moteur/app x86_64.
    with zipfile.ZipFile(aab) as original, zipfile.ZipFile(apk) as converted:
        code = [name for name in original.namelist()
                if re.fullmatch(r"base/dex/classes[0-9]*\.dex", name)
                or name in ("base/lib/x86_64/libapp.so", "base/lib/x86_64/libflutter.so")]
        require(all("base/lib/x86_64/" + name in code for name in ("libapp.so", "libflutter.so"))
                and any(name.endswith(".dex") for name in code), "Code exécutable du bundle absent")
        for name in code:
            destination = name.removeprefix("base/dex/") if name.startswith("base/dex/") else name.removeprefix("base/")
            require(hashlib.sha256(original.read(name)).digest() == hashlib.sha256(converted.read(destination)).digest(),
                    "Le code de l'APK dérivé a changé : " + destination)
    badging = run([sdk / "build-tools" / BUILD_TOOLS / "aapt", "dump", "badging", apk])
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
    require(package is not None and package.groups() == (PACKAGE, VERSION_CODE, VERSION_NAME),
            "Identité de l'APK dérivé inattendue")
    run([sdk / "build-tools" / BUILD_TOOLS / "apksigner", "verify", "--verbose", apk])
    return apk


def normalize(text: str) -> str:
    # Selon la génération des ARB, le retour peut rester littéral dans la
    # source puis devenir un saut réel dans la sémantique Android.
    return " ".join(text.replace("\\n", "\n").split()).casefold()


def node_labels(node) -> set[str]:
    result = set()
    for key in ("text", "content-desc"):
        value = node.get(key, "")
        result.update(normalize(part) for part in (value, *value.splitlines()) if part.strip())
    return result


def recognized_screen(xml: str, translations: dict, screen: str) -> str | None:
    """Des titres propres à l'écran sont nécessaires ; un logo ne suffit pas."""
    root = ET.fromstring(xml)
    labels = set().union(*(node_labels(node) for node in root.iter("node")
                           if node.get("package") == PACKAGE))
    keys = HOME_KEYS if screen == "home" else SOURCE_KEYS if screen == "sources" else ()
    require(bool(keys), "Écran de capture non prévu")
    for language, values in translations.items():
        if all(normalize(values[key]) in labels for key in keys):
            return language
    return None


def tap_target(xml: str, label: str, width: int, height: int) -> tuple[int, int]:
    matches = []
    for node in ET.fromstring(xml).iter("node"):
        if node.get("package") != PACKAGE or normalize(label) not in node_labels(node):
            continue
        if node.get("enabled", "true") != "true":
            continue
        bounds = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
        if bounds:
            left, top, right, bottom = map(int, bounds.groups())
            if 0 <= left < right <= width and 0 <= top < bottom <= height:
                matches.append(((right - left) * (bottom - top), (left + right) // 2, (top + bottom) // 2))
    require(bool(matches), "Le bouton observé n'est pas présent à l'écran : " + label)
    # En cas de sémantique fusionnée, prendre le rectangle le plus précis.
    _, x, y = min(matches)
    return x, y


def png_dimensions(data: bytes) -> tuple[int, int]:
    require(len(data) >= 33 and data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR",
            "La capture adb n'est pas un PNG")
    return struct.unpack(">II", data[16:24])


class Device:
    def __init__(self, adb: Path):
        self.adb = adb

    def command(self, *arguments, timeout=60) -> str:
        return run([self.adb, "-s", SERIAL, *arguments], timeout=timeout)

    def binary(self, *arguments) -> bytes:
        return subprocess.run([str(self.adb), "-s", SERIAL, *arguments],
                              capture_output=True, check=True, timeout=60).stdout

    def foreground(self) -> str:
        activity = self.command("shell", "dumpsys", "activity", "activities")
        lines = [line for line in activity.splitlines()
                 if "mResumedActivity:" in line or "topResumedActivity=" in line]
        require(any(re.search(re.escape(PACKAGE) + r"/[\w.$]+", line) for line in lines),
                "NOVATUBE n'est pas l'activité au premier plan")
        return "\n".join(lines)

    def hierarchy(self) -> str:
        self.command("shell", "uiautomator", "dump", "/sdcard/novatube-ui.xml", timeout=30)
        return self.command("exec-out", "cat", "/sdcard/novatube-ui.xml")


def await_screen(device: Device, translations: dict, screen: str, timeout=100) -> tuple[str, str]:
    deadline, previous, consecutive = time.monotonic() + timeout, None, 0
    last_error = "Aucun écran reconnu"
    while time.monotonic() < deadline:
        try:
            device.foreground()
            xml = device.hierarchy()
            language = recognized_screen(xml, translations, screen)
            consecutive = consecutive + 1 if language is not None and language == previous else 0
            previous = language
            if consecutive >= 1:
                return xml, language
            last_error = "Les libellés de l'écran " + screen + " ne sont pas tous visibles"
        except (ValueError, ET.ParseError, subprocess.SubprocessError) as error:
            previous, consecutive, last_error = None, 0, safe_diagnostic(error)
        time.sleep(2)
    raise ValueError("Écran chargé non reconnu : " + last_error)


def capture_screen(device: Device, translations: dict, screen: str, specification: dict, output: Path) -> dict:
    xml, language = await_screen(device, translations, screen)
    foreground = device.foreground()
    data = device.binary("exec-out", "screencap", "-p")
    width, height = png_dimensions(data)
    require((width, height) == (specification["width"], specification["height"])
            and len(data) > 10000, "Dimensions ou taille de capture inattendues")
    after = device.hierarchy()
    require(recognized_screen(after, translations, screen) == language,
            "L'écran a changé pendant la capture")
    device.foreground()
    stem = specification["name"] + "-" + screen
    png, hierarchy = output / (stem + ".png"), output / (stem + ".xml")
    png.write_bytes(data)
    hierarchy.write_text(xml, encoding="utf-8")
    return {"device": specification["name"], "screen": screen, "language": language,
            "width": width, "height": height, "density": specification["density"],
            "file": "screenshots/" + png.name, "sha256": sha256_file(png),
            "uiFile": "screenshots/" + hierarchy.name, "uiSha256": sha256_file(hierarchy),
            "foregroundActivity": foreground, "capturedAtUtc": datetime.now(timezone.utc).isoformat(),
            "rawAdbCapture": True, "humanReviewRequired": True}


def collect_diagnostic(device: Device, directory: Path, name: str) -> None:
    """Une image d'échec reste dans le dossier explicitement non qualifié."""
    commands = {
        "activity": ("shell", "dumpsys", "activity", "activities"),
        "logcat": ("logcat", "-d", "-t", "1200"),
    }
    for kind, command in commands.items():
        try:
            (directory / f"{name}-{kind}.txt").write_text(safe_diagnostic(device.command(*command)), encoding="utf-8")
        except (OSError, subprocess.SubprocessError):
            pass
    try:
        (directory / f"{name}-unqualified-ui.xml").write_text(device.hierarchy(), encoding="utf-8")
        image = device.binary("exec-out", "screencap", "-p")
        png_dimensions(image)
        (directory / f"{name}-unqualified-screen.png").write_bytes(image)
    except (ValueError, ET.ParseError, OSError, subprocess.SubprocessError):
        pass


def stop_emulator(process, device: Device) -> None:
    """Ne toucher qu'au processus et au port créés par ce script."""
    if process.poll() is None:
        try:
            device.command("emu", "kill", timeout=15)
        except (OSError, subprocess.SubprocessError):
            pass
        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=15)


@contextmanager
def booted_device(sdk: Path, temporary: Path, diagnostics: Path, specification: dict):
    environment = dict(os.environ)
    avd_home = temporary / "avds"
    avd_home.mkdir(exist_ok=True)
    environment["ANDROID_AVD_HOME"] = str(avd_home)
    name = "novatube_play_" + specification["name"]
    avd_path = avd_home / (name + ".avd")
    run([sdk / "cmdline-tools/latest/bin/avdmanager", "create", "avd", "--name", name,
         "--package", IMAGE, "--path", avd_path, "--force"], environment=environment, input_text="no\n")
    require((avd_home / (name + ".ini")).is_file(), "Index de l'appareil jetable absent")
    # Les dimensions appartiennent à l'appareil, jamais à une retouche du PNG.
    config = avd_path / "config.ini"
    values = {"hw.lcd.width": specification["width"], "hw.lcd.height": specification["height"],
              "hw.lcd.density": specification["density"], "hw.mainKeys": "no",
              "hw.keyboard": "yes", "hw.ramSize": 2048, "showDeviceFrame": "no"}
    lines = [line for line in config.read_text().splitlines() if line.split("=", 1)[0].strip() not in values]
    config.write_text("\n".join([*lines, *(f"{key}={value}" for key, value in values.items())]) + "\n")
    device = Device(sdk / "platform-tools/adb")
    emulator_log = diagnostics / (specification["name"] + "-emulator.txt")
    with emulator_log.open("w", encoding="utf-8") as log:
        process = subprocess.Popen([
            str(sdk / "emulator/emulator"), "-avd", name, "-port", "5582", "-no-window", "-no-audio",
            "-no-boot-anim", "-no-snapshot", "-gpu", "software", "-memory", "2048", "-cores", "2",
            "-accel", "on", "-skin", f"{specification['width']}x{specification['height']}",
        ], stdout=log, stderr=subprocess.STDOUT, env=environment, start_new_session=True)
        try:
            deadline = time.monotonic() + 300
            while time.monotonic() < deadline:
                require(process.poll() is None, "L'émulateur s'est arrêté avant Android")
                try:
                    if device.command("shell", "getprop", "sys.boot_completed", timeout=15).strip() == "1":
                        break
                except subprocess.SubprocessError:
                    pass
                time.sleep(3)
            else:
                raise ValueError("Android n'a pas démarré dans le délai prévu")
            device.command("shell", "input", "keyevent", "82")
            device.command("shell", "settings", "put", "system", "accelerometer_rotation", "0")
            device.command("shell", "settings", "put", "system", "user_rotation", "0")
            yield device
        except BaseException:
            collect_diagnostic(device, diagnostics, specification["name"])
            raise
        finally:
            stop_emulator(process, device)
    emulator_log.write_text(safe_diagnostic(emulator_log.read_text(errors="replace")), encoding="utf-8")


def create_evidence(verified: Path, output: Path, diagnostics: Path) -> dict:
    context = runner_context()
    require(run(["git", "rev-parse", "HEAD"]).strip() == context["sourceCommit"], "Checkout non approuvé")
    require(not run(["git", "status", "--porcelain", "--untracked-files=no"]).strip(), "Sources versionnées modifiées")
    require(not output.exists(), "Le dossier de captures doit être neuf")
    aab, provenance = validate_artifact(verified, context)
    temporary_root = Path(os.environ.get("RUNNER_TEMP", ""))
    require(temporary_root.is_absolute() and temporary_root.is_dir(), "Dossier temporaire du runner absent")
    sdk_value = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME", "")
    require(sdk_value and Path(sdk_value).is_absolute(), "Android SDK absent")
    sdk = Path(sdk_value)
    require(Path("/dev/kvm").exists(), "Accélération KVM absente du runner")
    if not os.access("/dev/kvm", os.R_OK | os.W_OK):
        run(["sudo", "chown", f"{os.getuid()}:{os.getgid()}", "/dev/kvm"])
    translations = {language: json.loads((APP_ROOT / "lib/l10n" / f"app_{language}.arb").read_text(encoding="utf-8"))
                    for language in ("en", "fr")}
    with tempfile.TemporaryDirectory(prefix="novatube-play-evidence-", dir=temporary_root) as directory:
        temporary = Path(directory)
        bundletool = download_bundletool(temporary)
        identity = verify_real_bundle(aab, bundletool, provenance)
        run([sdk / "cmdline-tools/latest/bin/sdkmanager", IMAGE, "emulator", "platform-tools",
             "build-tools;" + BUILD_TOOLS], timeout=900)
        apk = convert_bundle(aab, bundletool, temporary, sdk)
        stage = temporary / "qualified"
        screenshots = stage / "screenshots"
        screenshots.mkdir(parents=True)
        captures = []
        for specification in DEVICES:
            with booted_device(sdk, temporary, diagnostics, specification) as device:
                device.command("install", str(apk), timeout=180)
                installed = device.command("shell", "dumpsys", "package", PACKAGE)
                require(re.search(r"\bversionCode=" + VERSION_CODE + r"\b", installed) is not None
                        and re.search(r"\bversionName=" + re.escape(VERSION_NAME) + r"\b", installed) is not None,
                        "La version installée ne correspond pas au Play vérifié")
                device.command("shell", "am", "start", "-W", "-n", PACKAGE + "/" + identity["launcher"])
                captures.append(capture_screen(device, translations, "home", specification, screenshots))
                xml, language = await_screen(device, translations, "home")
                x, y = tap_target(xml, translations[language]["tvNavServer"], specification["width"], specification["height"])
                device.command("shell", "input", "tap", str(x), str(y))
                captures.append(capture_screen(device, translations, "sources", specification, screenshots))
        require(len(captures) == 4, "Les quatre captures téléphone/tablette sont obligatoires")
        require(sha256_file(aab) == provenance["sha256"], "L'AAB a changé pendant la capture")
        report = {
            "status": "captured-ui-recognized", "humanReviewRequired": True,
            "verifiedAtUtc": datetime.now(timezone.utc).isoformat(), **context,
            "package": PACKAGE, "versionName": VERSION_NAME, "versionCode": int(VERSION_CODE),
            "aabSha256": provenance["sha256"], "uploadCertificateSha256": provenance["uploadCertificateSha256"],
            "bundletoolVersion": BUNDLETOOL_VERSION, "bundletoolSha256": BUNDLETOOL_SHA256,
            "emulatorImage": IMAGE, "devices": list(DEVICES), "captures": captures,
            "conversion": {"appRecompiled": False, "aabModified": False,
                           "apkSigning": "ephemeral-emulator-only", "apkPublished": False,
                           "dexAndX86CodeCompared": True},
            "content": "fresh-install-no-playlist-or-account",
            "foregroundServiceVideo": {"status": "not-attempted", "qualified": False,
                                       "reason": "Recording UI scenario requires a separate observed run."},
            "googleUpload": False,
        }
        (stage / "evidence.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        require(all(path.suffix in (".png", ".xml", ".json") for path in stage.rglob("*") if path.is_file()),
                "Fichier non prévu parmi les preuves publiables")
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(stage, output)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verified", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--diagnostics", type=Path, required=True)
    arguments = parser.parse_args()
    diagnostics = arguments.diagnostics.resolve()
    diagnostics.mkdir(parents=True, exist_ok=False)
    try:
        report = create_evidence(arguments.verified.resolve(), arguments.output.resolve(), diagnostics)
        print(json.dumps({"status": report["status"], "captures": len(report["captures"]),
                          "foregroundServiceVideo": "not-attempted"}, ensure_ascii=False))
        return 0
    except (ValueError, KeyError, OSError, ET.ParseError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        diagnostic = {"status": "failed", "qualifiedEvidence": False, "errorType": type(error).__name__,
                      "message": safe_diagnostic(error), "foregroundServiceVideo": "not-attempted"}
        if isinstance(error, subprocess.CalledProcessError):
            diagnostic["toolOutput"] = safe_diagnostic(error.stdout) + safe_diagnostic(error.stderr)
        (diagnostics / "diagnostic.json").write_text(json.dumps(diagnostic, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("Captures Play non qualifiées : " + safe_diagnostic(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
