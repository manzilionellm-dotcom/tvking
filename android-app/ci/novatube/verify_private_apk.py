#!/usr/bin/env python3
"""Contrôle l'APK privé signé et conserve les preuves réelles de la CI."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

from common import (
    APP_ROOT, BRANCH, ENTRYPOINT, LABEL, PACKAGE, REPO_ROOT,
    PRIVATE_VERSION_CODE as VERSION_CODE, PRIVATE_VERSION_NAME as VERSION_NAME,
    expected_certificate, require, sha256_file,
)
from verify_aab import flutter_test_results, native_test_results
from recording_device_evidence import device_test_results

REPOSITORY = "manzilionellm-dotcom/tvking"
ABIS = ["arm64-v8a", "armeabi-v7a", "x86_64"]
RAW_REPORTS = (
    "source-verification.json", "flutter-toolchain.json", "flutter-analyze.txt",
    "flutter-tests.jsonl", "flutter-tests-private.jsonl", "native-jvm-tests.txt",
    "static-tests.txt", "recording-native-tests.txt", "recording-device-tests.txt", "recording-device-tests.json",
)


def verify_sdk_versions(badging: str) -> dict:
    values = {"minSdk": [], "targetSdk": []}
    for line in badging.splitlines():
        if not re.match(r"^(sdkVersion|minSdkVersion|targetSdkVersion):", line):
            continue
        match = re.fullmatch(r"(sdkVersion|minSdkVersion|targetSdkVersion):'([0-9]+)'", line)
        require(match is not None, "Champ SDK Android malformé")
        field = "targetSdk" if match[1] == "targetSdkVersion" else "minSdk"
        values[field].append(int(match[2]))
    for field, expected in (("minSdk", 24), ("targetSdk", 36)):
        require(values[field] == [expected], "SDK Android absent, ambigu ou incorrect : " + field)
    return {field: entries[0] for field, entries in values.items()}


def apk_identity(badging: str, xml: str) -> dict:
    packages = re.findall(
        r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'",
        badging, re.M,
    )
    require(packages == [(PACKAGE, VERSION_CODE, VERSION_NAME)], "Package ou version APK incorrect")
    require(re.findall(r"^application-label:'([^']+)'$", badging, re.M) == [LABEL],
            "Nom affiché de l'APK incorrect")
    launchers = re.findall(r"^launchable-activity: name='([^']+)'", badging, re.M)
    require(launchers == [PACKAGE + ".NovatubeActivity"], "Activité de lancement incorrecte")
    require("application-debuggable" not in badging, "APK debuggable interdit")
    require(re.search(r"^uses-permission: name='android\.permission\.USE_BIOMETRIC'(?: |$)",
                      badging, re.M) is not None, "Permission USE_BIOMETRIC absente")
    for attribute in ("debuggable", "testOnly"):
        for line in xml.splitlines():
            if "android:" + attribute + "(" not in line:
                continue
            value = re.search(r"=\([^)]*\)(0x[0-9a-fA-F]+)", line)
            require(value is not None and int(value[1], 16) == 0,
                    "APK de debug ou de test natif interdit : " + attribute)
    return {
        "package": PACKAGE, "versionName": VERSION_NAME, "versionCode": int(VERSION_CODE),
        "appName": LABEL, **verify_sdk_versions(badging),
        "debuggable": False, "testOnly": False, "biometricPermissionVerified": True,
    }


def verify_apk_signature(output: str, certificate: str) -> None:
    signers = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)$", output, re.M)
    require([value.lower() for value in signers] == [certificate],
            "La signature ne correspond pas à l'unique clé NOVATUBE")


def apk_abis(apk: Path) -> list[str]:
    with zipfile.ZipFile(apk) as archive:
        entries = archive.namelist()
        require(len(entries) == len(set(entries)) and archive.testzip() is None,
                "Archive APK ambiguë ou endommagée")
        require("AndroidManifest.xml" in entries and "classes.dex" in entries, "Code Android absent")
        abis = sorted({name.split("/")[1] for name in entries
                       if name.startswith("lib/") and name.endswith("/libapp.so")})
        require(abis == ABIS and all(f"lib/{abi}/libflutter.so" in entries for abi in ABIS),
                "APK universel incomplet : trois ABI Flutter sont requises")
    return abis


def evidence_results(reports: Path, source_commit: str) -> dict:
    source = json.loads((reports / "source-verification.json").read_text(encoding="utf-8"))
    require(source.get("status") == "passed" and source.get("sourceCommit") == source_commit,
            "Vérification des sources absente ou d'une autre révision")
    require(source.get("privateApkWorkflowVerified") is True,
            "La séparation du build APK privé et du build Play n'est pas vérifiée")
    require(source.get("buildTargets", {}).get("private-apk") == {
        "versionName": VERSION_NAME, "versionCode": int(VERSION_CODE),
    }, "Version privée absente ou incohérente dans la provenance des sources")
    require(re.fullmatch(r"[0-9a-f]{40}", str(source.get("sourceTree", ""))) is not None,
            "Arbre Git de la validation absent")
    toolchain = json.loads((reports / "flutter-toolchain.json").read_text(encoding="utf-8"))
    require(toolchain.get("frameworkVersion") == "3.47.7", "Version Flutter inattendue")
    suites = {}
    for mode, filename in (("play", "flutter-tests.jsonl"), ("private", "flutter-tests-private.jsonl")):
        suites[mode] = flutter_test_results(reports / filename)
        require(suites[mode]["passed"] > 0 and suites[mode]["skipped"] == 0,
                "Suite Flutter vide ou partiellement ignorée : " + mode)
    analysis = (reports / "flutter-analyze.txt").read_text(encoding="utf-8")
    require(re.search(r"(?:No issues found!|\b\d+ issues? found\b)", analysis) is not None,
            "Analyse Flutter inachevée")
    require(re.search(r"^\s*(?:error\s+[•-]|Error:|Unhandled exception:)", analysis, re.M) is None,
            "Erreur dans l'analyse Flutter")
    native = native_test_results(reports / "native-jvm-tests.txt")
    recording_native = native_test_results(reports / "recording-native-tests.txt")
    for filename in ("native-jvm-tests.txt", "recording-native-tests.txt"):
        require("FAILURES!!!" not in (reports / filename).read_text(encoding="utf-8"),
                "Échec JVM présent dans le rapport : " + filename)
    static = (reports / "static-tests.txt").read_text(encoding="utf-8")
    counts = re.findall(r"^Ran (\d+) tests? in .+$", static, re.M)
    require(len(counts) == 1 and int(counts[0]) > 0 and re.search(r"^OK$", static, re.M)
            and not re.search(r"^(?:FAILED|FAIL:|ERROR:)", static, re.M),
            "Tests Python absents ou non réussis")
    device = device_test_results(reports, source_commit)
    return {"source": source, "flutterToolchain": toolchain,
            "tests": {**suites, "nativeJvm": native, "recordingNativeJvm": recording_native,
                      "recordingDevice": device,
                      "python": {"passed": int(counts[0])},
                      "deviceTests": "android-emulator-api-35"}}


def verify(apk: Path, reports: Path, output: Path, sdk_root: Path, build_tools: str) -> dict:
    require(apk.is_file() and apk.stat().st_size > 0, "APK absent ou vide")
    require(not output.exists(), "Le dossier de livraison existe déjà")
    source_commit = os.environ.get("GITHUB_SHA", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    attempt = os.environ.get("GITHUB_RUN_ATTEMPT", "")
    require(re.fullmatch(r"[0-9a-f]{40}", source_commit) is not None, "SHA de run absent")
    require(os.environ.get("GITHUB_REPOSITORY") == REPOSITORY
            and os.environ.get("GITHUB_REF") == "refs/heads/" + BRANCH
            and os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
            and run_id.isdigit() and attempt.isdigit(), "Contexte CI NOVATUBE incorrect")
    evidence = evidence_results(reports, source_commit)
    require(evidence["tests"]["recordingDevice"]["apkSha256"] == sha256_file(apk),
            "L'APK livré diffère de celui testé sur Android")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO_ROOT, text=True).strip()
    tree = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=REPO_ROOT, text=True).strip()
    require(commit == source_commit and tree == evidence["source"]["sourceTree"],
            "Le checkout ne correspond plus aux sources vérifiées")
    dependency_lock = APP_ROOT / "pubspec.lock"
    require(dependency_lock.is_file(), "Verrou des dépendances absent")
    tools = sdk_root / "build-tools" / build_tools
    require(all((tools / name).is_file() for name in ("apksigner", "aapt2")),
            "Build-tools Android incomplets : " + str(tools))
    signature = subprocess.run([str(tools / "apksigner"), "verify", "--verbose", "--print-certs", str(apk)],
                               capture_output=True, text=True, check=True)
    _, certificate = expected_certificate()
    verify_apk_signature(signature.stdout, certificate)
    badging = subprocess.check_output([str(tools / "aapt2"), "dump", "badging", str(apk)], text=True)
    xml = subprocess.check_output([str(tools / "aapt2"), "dump", "xmltree", str(apk),
                                   "--file", "AndroidManifest.xml"], text=True)
    identity = apk_identity(badging, xml)
    abis = apk_abis(apk)
    filename = f"NOVATUBE-{source_commit}.apk"
    report = {
        "status": "passed", "verifiedAtUtc": datetime.now(timezone.utc).isoformat(),
        "artifact": filename, **identity, "distribution": "private-apk", "androidAbis": abis,
        "sha256": sha256_file(apk), "sizeBytes": apk.stat().st_size,
        "uploadCertificateSha256": certificate, "releaseSignatureVerified": True,
        "repository": REPOSITORY, "branch": BRANCH, "sourceCommit": source_commit,
        "sourceTree": tree, "runId": run_id, "runAttempt": attempt,
        "runUrl": f"https://github.com/{REPOSITORY}/actions/runs/{run_id}",
        "entrypoint": ENTRYPOINT, "tests": evidence["tests"],
        "biometricEvidence": "source-tests-and-manifest", "physicalSensorTest": "not-run",
        "fingerprintOnlyGuaranteed": False, "googleUpload": False, "publishedToGooglePlay": False,
    }
    # Un dossier final n'apparaît qu'après tous les contrôles et toutes les copies.
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="novatube-apk-", dir=output.parent) as directory:
        stage = Path(directory) / "verified"
        stage.mkdir()
        shutil.copyfile(apk, stage / filename)
        require(sha256_file(stage / filename) == report["sha256"], "L'APK a changé pendant sa copie")
        for name in RAW_REPORTS:
            shutil.copyfile(reports / name, stage / name)
        shutil.copyfile(dependency_lock, stage / "pubspec.lock")
        for name, contents in (("apk-signature.txt", signature.stdout + signature.stderr),
                               ("apk-badging.txt", badging), ("apk-manifest.txt", xml)):
            (stage / name).write_text(contents, encoding="utf-8")
        (stage / "apk-verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        provenance = {**report, "status": "verified", "source": evidence["source"],
                      "flutterToolchain": evidence["flutterToolchain"],
                      "dependencyLockSha256": sha256_file(dependency_lock)}
        (stage / "build-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
        sums = [sha256_file(path) + "  " + path.name for path in sorted(stage.iterdir())]
        (stage / "SHA256SUMS.txt").write_text("\n".join(sums) + "\n", encoding="ascii")
        stage.rename(output)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--reports", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sdk-root", type=Path,
                        default=os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME"))
    parser.add_argument("--build-tools", default="36.0.0")
    args = parser.parse_args()
    try:
        require(args.sdk_root is not None, "ANDROID_SDK_ROOT/ANDROID_HOME ou --sdk-root requis")
        result = verify(args.apk.resolve(), args.reports.resolve(), args.output.resolve(),
                        Path(args.sdk_root).resolve(), args.build_tools)
        print(json.dumps({key: result[key] for key in ("status", "artifact", "sha256", "runUrl")}))
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print("APK NOVATUBE refusé : " + str(error), file=sys.stderr)
        raise SystemExit(1)
