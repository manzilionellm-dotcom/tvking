#!/usr/bin/env python3
"""Vérifie l'identité et la révision approuvée, sans compiler l'application."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

from common import (
    ANDROID, APP_ROOT, BASE_COMMIT, BASE_TAG, BRANCH, ENTRYPOINT, LABEL,
    PACKAGE, REPO_ROOT, VERSION_CODE, VERSION_NAME, expected_certificate,
    require, sha256_file,
)


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=REPO_ROOT, text=True).strip()


def checked_repo_file(relative: str) -> Path:
    require(isinstance(relative, str) and bool(relative), "Chemin d'image absent")
    path = (REPO_ROOT / relative).resolve()
    require(REPO_ROOT in path.parents and path.is_file(), "Image absente ou hors du dépôt")
    return path


def verify_branding() -> dict:
    metadata = json.loads(Path(__file__).with_name("branding.json").read_text(encoding="utf-8"))
    source = checked_repo_file(metadata["source_path"])
    require(sha256_file(source) == metadata["source_sha256"], "Le logo source diffère du logo validé")
    icons = metadata.get("generated_icons")
    require(isinstance(icons, dict) and len(icons) >= 7, "Manifeste des icônes incomplet")
    for relative, expected in icons.items():
        require(sha256_file(checked_repo_file(relative)) == expected,
                "Une ressource d'icône diffère du résultat revu : " + relative)
    for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
        prefix = f"android-app/android/app/src/main/res/mipmap-{density}/"
        require(any(name.startswith(prefix) for name in icons), "Icône classique absente : " + density)
    require(any("mipmap-anydpi-v26/" in name and name.endswith(".xml") for name in icons),
            "Icône adaptative non vérifiée")
    return {"sourceSha256": metadata["source_sha256"], "verifiedResources": len(icons)}


def verify_source(reviewed_commit: str) -> dict:
    require(re.fullmatch(r"[0-9a-f]{40}", reviewed_commit) is not None,
            "Le commit approuvé doit être un SHA Git complet")
    source_commit = git("rev-parse", "HEAD")
    require(source_commit == reviewed_commit, "Le checkout diffère du commit approuvé")
    require(git("rev-parse", BASE_TAG + "^{commit}") == BASE_COMMIT, "Le tag source a changé")
    subprocess.run(["git", "merge-base", "--is-ancestor", BASE_COMMIT, source_commit],
                   cwd=REPO_ROOT, check=True, capture_output=True)
    require(not git("status", "--porcelain", "--untracked-files=no"), "Le checkout versionné a été modifié")
    if os.environ.get("GITHUB_ACTIONS") == "true":
        require(os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch", "Le build doit rester manuel")
        require(os.environ.get("GITHUB_REF") == "refs/heads/" + BRANCH, "Branche de build interdite")
        require(os.environ.get("GITHUB_SHA") == source_commit, "Révision du run différente")
    # Ni une variable injectée ni un fichier Gradle hérité ne doivent activer
    # le mode de test. La commande de compilation est entièrement explicite.
    require(not os.environ.get("DART_DEFINES") and not os.environ.get("DART_DEFINES_FROM_FILE"),
            "Paramètres Dart externes interdits pour cette livraison")
    gradle = (APP_ROOT / "android/app/build.gradle.kts").read_text(encoding="utf-8")
    gradle_code = re.sub(r"/\*.*?\*/|(?m:^\s*//[^\n]*)", "", gradle, flags=re.S)
    for field in ("namespace", "applicationId"):
        require(re.findall(rf'\b{field}\s*=\s*"([^"]+)"', gradle) == [PACKAGE],
                field + " NOVATUBE incorrect")
    require('signingConfigs.getByName("debug")' not in gradle_code,
            "Signature debug présente dans le Gradle release")
    require("ANDROID_KEYSTORE" not in gradle_code and "key.properties" not in gradle_code,
            "Référence à une signature héritée interdite")
    for name in ("NOVATUBE_KEYSTORE_PATH", "NOVATUBE_UPLOAD_STORE_PASSWORD",
                 "NOVATUBE_UPLOAD_KEY_PASSWORD", "NOVATUBE_UPLOAD_KEY_ALIAS"):
        require(name in gradle, "Configuration de signature absente : " + name)
    pubspec = (APP_ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    versions = re.findall(r"^version:\s*([^\s#]+)", pubspec, re.M)
    require(versions == [VERSION_NAME + "+" + VERSION_CODE], "Version pubspec inattendue")
    require((APP_ROOT / ENTRYPOINT).is_file(), "Point d'entrée mobile absent")
    root = ET.parse(APP_ROOT / "android/app/src/main/AndroidManifest.xml").getroot()
    app = root.find("application")
    require(app is not None and app.get(ANDROID + "label") == LABEL, "Nom Android inattendu")
    policy = (APP_ROOT / "lib/core/app/novatube_play_policy.dart").read_text(encoding="utf-8")
    for flag, value in {
        "isPlay": "true", "allowManualPlayback": "true",
        "allowPanelSources": "false", "allowGold": "false", "allowAdult": "false",
        "allowPromotions": "false", "allowExternalPurchase": "false", "allowSelfUpdate": "false",
    }.items():
        require(re.search(rf"static\s+const\s+bool\s+{flag}\s*=\s*{value}\s*;", policy) is not None,
                "Contrat Google Play modifié : " + flag)
    workflow = (REPO_ROOT / ".github/workflows/novatube-play-aab.yml").read_text(encoding="utf-8")
    require("ZUNO_CAST_TEST" not in workflow, "Drapeau de test interdit dans la CI NOVATUBE")
    require("NOVATUBE_PRIVATE_APK" not in workflow,
            "La fonction réservée à l'APK privé est interdite dans la CI Google Play")
    require("secrets.ANDROID_" not in workflow and "secrets.GOOGLE_" not in workflow,
            "Secret d'une autre livraison référencé")
    events = workflow.split("\non:\n", 1)[1].split("\npermissions:", 1)[0]
    require(re.findall(r"^  ([a-z_]+):", events, re.M) == ["workflow_dispatch"],
            "La CI NOVATUBE doit uniquement être lancée à la main")
    for filename in ("build-zuno-tv.yml", "quality-zuno.yml"):
        inherited = (REPO_ROOT / ".github/workflows" / filename).read_text(encoding="utf-8")
        require("'!" + BRANCH + "'" in inherited,
                "Un workflow hérité peut compiler NOVATUBE au push : " + filename)
    tracked_keys = git("ls-files", "*.jks", "*.keystore", "*key.properties")
    require(not tracked_keys, "Une clé privée ou une configuration de secrets est versionnée")
    _, certificate_sha256 = expected_certificate()
    return {
        "status": "passed", "sourceCommit": source_commit, "sourceTag": BASE_TAG,
        "sourceTagCommit": BASE_COMMIT, "package": PACKAGE, "entrypoint": ENTRYPOINT,
        "versionName": VERSION_NAME, "versionCode": int(VERSION_CODE),
        "uploadCertificateSha256": certificate_sha256, "branding": verify_branding(),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reviewed-commit", required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = verify_source(args.reviewed_commit)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("Révision, identité, politique, certificat public et icônes NOVATUBE vérifiés.")
    except (OSError, ValueError, KeyError, IndexError, subprocess.CalledProcessError) as error:
        print("Contrôle préalable NOVATUBE refusé : " + str(error), file=sys.stderr)
        raise SystemExit(1)
