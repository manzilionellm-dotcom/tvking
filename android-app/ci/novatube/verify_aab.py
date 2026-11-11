#!/usr/bin/env python3
"""Vérifie le véritable AAB signé, puis crée la livraison et sa provenance."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

from common import (
    ANDROID, APP_ROOT, BUNDLETOOL_SHA256, BUNDLETOOL_VERSION, ENTRYPOINT,
    KEY_ALIAS, LABEL, PACKAGE, PUBLIC_CERT, VERSION_CODE, VERSION_NAME,
    expected_certificate, pem_certificates, require, sha256_file,
)


def is_media_playback_type(value: str | None) -> bool:
    if value == "mediaPlayback":
        return True
    if value is None:
        return False
    # bundletool imprime les entiers hexadécimaux avec huit chiffres.
    # Le masque doit être exactement 2, sans aucun type de service ajouté.
    if re.fullmatch(r"[0-9]+", value):
        return int(value, 10) == 2
    if re.fullmatch(r"0[xX][0-9a-fA-F]+", value):
        return int(value, 16) == 2
    return False


def manifest_identity(xml: str) -> dict:
    root = ET.fromstring(xml)
    require(root.get("package") == PACKAGE, "Package du bundle incorrect")
    require(root.get(ANDROID + "versionName") == VERSION_NAME, "versionName du bundle incorrect")
    require(root.get(ANDROID + "versionCode") == VERSION_CODE, "versionCode du bundle incorrect")
    app = root.find("application")
    require(app is not None, "Application absente du manifeste fusionné")
    require(app.get(ANDROID + "label") == LABEL, "Nom affiché du bundle incorrect")
    for flag in ("debuggable", "testOnly"):
        require(app.get(ANDROID + flag, "false") in ("false", "0", "0x0"),
                "Un bundle release ne doit pas activer " + flag)
    require(app.get(ANDROID + "icon") is not None, "Icône de l'application absente")
    launchers = []
    for activity in app.findall("activity"):
        for intent in activity.findall("intent-filter"):
            actions = {item.get(ANDROID + "name") for item in intent.findall("action")}
            categories = {item.get(ANDROID + "name") for item in intent.findall("category")}
            if "android.intent.action.MAIN" in actions and "android.intent.category.LAUNCHER" in categories:
                launchers.append(activity)
    require(len(launchers) == 1, "Lanceur mobile absent ou ambigu")
    require(launchers[0].get(ANDROID + "name", "").startswith(PACKAGE + "."),
            "Le lanceur appartient à un autre namespace")
    require(not any(item.get(ANDROID + "name") == "android.intent.category.LEANBACK_LAUNCHER"
                    for item in root.iter("category")), "Lanceur Android TV inattendu")
    require(not any("leanback" in item.get(ANDROID + "name", "")
                    for item in root.findall("uses-feature")), "Fonction TV imposée au mobile")
    permissions = {item.get(ANDROID + "name") for item in root.findall("uses-permission")}
    required = {"android.permission." + name for name in (
        "INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE", "CHANGE_WIFI_MULTICAST_STATE",
        "FOREGROUND_SERVICE", "FOREGROUND_SERVICE_MEDIA_PLAYBACK", "POST_NOTIFICATIONS",
    )}
    require(required <= permissions, "Permissions de lecture/Cast incomplètes")
    require(any(item.get(ANDROID + "name") == "com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME"
                and item.get(ANDROID + "value") == PACKAGE + ".CastOptionsProviderImpl"
                for item in app.findall("meta-data")), "Options Google Cast NOVATUBE absentes")
    for name in ("RecordingForegroundService", "PlaybackForegroundService"):
        matches = [item for item in app.findall("service") if item.get(ANDROID + "name") == PACKAGE + "." + name]
        require(len(matches) == 1, "Service mobile absent : " + name)
        service_type = matches[0].get(ANDROID + "foregroundServiceType")
        require(is_media_playback_type(service_type),
                f"Type du service de lecture incorrect : {name} = {service_type!r} (attendu : mediaPlayback / 2)")
        require(matches[0].get(ANDROID + "exported", "false") in ("false", "0", "0x0"),
                "Service de lecture exposé à une autre application")
    sdk = root.find("uses-sdk")
    require(sdk is not None, "Contraintes SDK absentes")
    return {
        "package": PACKAGE, "label": LABEL, "versionName": VERSION_NAME,
        "versionCode": int(VERSION_CODE), "launcher": launchers[0].get(ANDROID + "name"),
        "minSdk": sdk.get(ANDROID + "minSdkVersion"), "targetSdk": sdk.get(ANDROID + "targetSdkVersion"),
        "debuggable": False, "testOnly": False, "castManifest": "verified",
    }


def flutter_test_results(path: Path) -> dict:
    events = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("{"):
            events.append(json.loads(line))
    finished = [event for event in events if event.get("type") == "done"]
    require(len(finished) == 1 and finished[0].get("success") is True,
            "Le rapport Flutter ne prouve pas une exécution terminée avec succès")
    require(not any(event.get("type") == "error" for event in events), "Erreur de test Flutter présente")
    completed = [event for event in events if event.get("type") == "testDone" and not event.get("hidden", False)]
    require(bool(completed), "Aucun test Flutter terminé")
    require(all(event.get("result") == "success" for event in completed), "Un test Flutter n'a pas réussi")
    return {
        "passed": sum(not event.get("skipped", False) for event in completed),
        "skipped": sum(bool(event.get("skipped", False)) for event in completed),
        "reportSha256": sha256_file(path),
    }


def native_test_results(path: Path) -> dict:
    counts = re.findall(r"^OK \((\d+) tests?\)\s*$", path.read_text(encoding="utf-8"), re.M)
    require(len(counts) == 1 and int(counts[0]) > 0, "Le rapport JVM ne prouve pas la réussite des tests")
    return {"passed": int(counts[0]), "reportSha256": sha256_file(path)}


def verify_signature(aab: Path) -> tuple[str, str]:
    _, expected = expected_certificate()
    result = subprocess.run(["keytool", "-printcert", "-rfc", "-jarfile", str(aab)],
                            capture_output=True, text=True, check=True)
    certificates = pem_certificates(result.stdout)
    require(len(certificates) == 1, "Signataire absent, multiple ou chaîne non attendue")
    require(hashlib.sha256(certificates[0]).hexdigest() == expected,
            "L'AAB n'est pas signé avec la nouvelle clé NOVATUBE")
    # La clé privée n'intervient jamais dans cette vérification. Un truststore
    # temporaire ne contient que le certificat public dont l'empreinte a été
    # revue. Cela permet -strict sans assimiler un certificat auto-signé valide
    # pour Android à une autorité publique manquante.
    with tempfile.TemporaryDirectory(prefix="novatube-cert-check-") as directory:
        truststore = str(Path(directory) / "public-truststore.p12")
        environment = dict(os.environ)
        environment["NOVATUBE_VERIFY_STORE_PASSWORD"] = secrets.token_urlsafe(32)
        subprocess.run(["keytool", "-importcert", "-noprompt", "-alias", KEY_ALIAS,
                        "-file", str(PUBLIC_CERT), "-keystore", truststore,
                        "-storetype", "PKCS12", "-storepass:env", "NOVATUBE_VERIFY_STORE_PASSWORD"],
                       env=environment, capture_output=True, check=True)
        verified = subprocess.run(
            ["jarsigner", "-J-Duser.language=en", "-J-Duser.country=US", "-verify", "-strict",
             "-keystore", truststore, "-storepass:env", "NOVATUBE_VERIFY_STORE_PASSWORD",
             str(aab), KEY_ALIAS],
            env=environment, capture_output=True, text=True, check=True,
        )
    # jarsigner peut renvoyer 0 pour certains fichiers non signés : vérifier
    # explicitement le résultat en plus du certificat et du code de retour.
    require("jar verified." in verified.stdout, "La vérification cryptographique JAR n'a pas abouti")
    return expected, verified.stdout + verified.stderr


def verify(aab: Path, bundletool: Path, reports: Path, output: Path) -> dict:
    require(aab.is_file() and aab.stat().st_size > 0, "AAB absent ou vide")
    require(sha256_file(bundletool) == BUNDLETOOL_SHA256, "JAR bundletool non approuvé")
    source = json.loads((reports / "source-verification.json").read_text(encoding="utf-8"))
    require(source.get("status") == "passed", "Vérification des sources manquante")
    require(source.get("sourceCommit") == os.environ.get("GITHUB_SHA"), "Les sources ne correspondent pas au run")
    flutter = flutter_test_results(reports / "flutter-tests.jsonl")
    native = native_test_results(reports / "native-jvm-tests.txt")
    toolchain = json.loads((reports / "flutter-toolchain.json").read_text(encoding="utf-8"))
    require(toolchain.get("frameworkVersion") == "3.47.7", "Version Flutter différente du tag approuvé")
    dependency_lock = APP_ROOT / "pubspec.lock"
    require(dependency_lock.is_file(), "Le verrou des dépendances résolues est absent")
    subprocess.run(["java", "-jar", str(bundletool), "validate", "--bundle=" + str(aab)],
                   capture_output=True, text=True, check=True)
    xml = subprocess.check_output(
        ["java", "-jar", str(bundletool), "dump", "manifest", "--bundle=" + str(aab), "--module=base"],
        text=True,
    )
    identity = manifest_identity(xml)
    with zipfile.ZipFile(aab) as archive:
        entries = set(archive.namelist())
        require("BundleConfig.pb" in entries and "base/manifest/AndroidManifest.xml" in entries,
                "Structure Android App Bundle incomplète")
        require(any(name.startswith("base/dex/") and name.endswith(".dex") for name in entries),
                "Code Android absent")
        abis = []
        for abi in ("armeabi-v7a", "arm64-v8a", "x86_64"):
            require(all(f"base/lib/{abi}/{name}" in entries for name in ("libapp.so", "libflutter.so")),
                    "Moteur Flutter release incomplet pour " + abi)
            abis.append(abi)
    certificate, signature_report = verify_signature(aab)
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    require(repository == "manzilionellm-dotcom/tvking" and run_id.isdigit(), "Identité du run absente")
    provenance = {
        "status": "verified", "verifiedAtUtc": datetime.now(timezone.utc).isoformat(),
        **identity, "entrypoint": ENTRYPOINT, "abis": abis,
        "source": source, "uploadCertificateSha256": certificate,
        "signing": "dedicated-novatube-upload-key", "testBuild": False,
        "bundletoolVersion": BUNDLETOOL_VERSION, "bundletoolSha256": BUNDLETOOL_SHA256,
        "flutterToolchain": toolchain, "dependencyLockSha256": sha256_file(dependency_lock),
        "sha256": sha256_file(aab), "sizeBytes": aab.stat().st_size,
        "runId": run_id, "runAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
        "runUrl": f"https://github.com/{repository}/actions/runs/{run_id}",
        "tests": {"flutter": flutter, "nativeJvm": native, "deviceTests": "not-run"},
        "googleUpload": False, "published": False,
    }
    # Ce dossier n'existe qu'après TOUS les contrôles. Aucun AAB non validé
    # n'est téléversé si la compilation ou une vérification échoue.
    output.mkdir(parents=True, exist_ok=False)
    filename = f"NOVATUBE-{VERSION_NAME}-{VERSION_CODE}.aab"
    shutil.copyfile(aab, output / filename)
    (output / "AndroidManifest.xml").write_text(xml, encoding="utf-8")
    (output / "signature-verification.txt").write_text(signature_report, encoding="utf-8")
    (output / "build-provenance.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "SHA256SUMS.txt").write_text(provenance["sha256"] + "  " + filename + "\n", encoding="ascii")
    for report in ("source-verification.json", "flutter-tests.jsonl", "native-jvm-tests.txt", "flutter-analyze.txt", "static-tests.txt", "flutter-toolchain.json"):
        shutil.copyfile(reports / report, output / report)
    shutil.copyfile(dependency_lock, output / "pubspec.lock")
    return provenance


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aab", type=Path, required=True)
    parser.add_argument("--bundletool", type=Path, required=True)
    parser.add_argument("--reports", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = verify(args.aab.resolve(), args.bundletool.resolve(), args.reports.resolve(), args.output.resolve())
        print(json.dumps({key: report[key] for key in ("status", "package", "versionName", "versionCode", "sha256", "runUrl")}, ensure_ascii=False))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, ET.ParseError, zipfile.BadZipFile) as error:
        print("AAB NOVATUBE refusé : " + str(error), file=sys.stderr)
        raise SystemExit(1)
