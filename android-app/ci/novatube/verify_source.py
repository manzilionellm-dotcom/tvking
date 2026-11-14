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

import yaml

from common import (
    ANDROID, APP_ROOT, BASE_COMMIT, BASE_TAG, BRANCH, ENTRYPOINT, LABEL,
    PACKAGE, REPO_ROOT, VERSION_CODE, VERSION_NAME, PRIVATE_VERSION_CODE,
    PRIVATE_VERSION_NAME, expected_certificate,
    require, sha256_file,
)


PLAY_CONFIRMATION = "inputs.confirme == 'COMPILER_NOVATUBE'"
PRIVATE_CONFIRMATION = "inputs.confirme == 'PUBLIER_NOVATUBE_APK_PRIVE'"
COMMON_GUARD = (
    "github.event_name == 'workflow_dispatch' && "
    "github.repository == 'manzilionellm-dotcom/tvking' && "
    f"github.ref == 'refs/heads/{BRANCH}' && "
    "github.actor == github.repository_owner && "
    "github.triggering_actor == github.repository_owner"
)


class WorkflowLoader(yaml.BaseLoader):
    """Conserver `on` comme texte et refuser les clés YAML ambiguës."""


def unique_mapping(loader, node):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node)
        require(isinstance(key, str) and key not in result, "Clé YAML absente ou dupliquée")
        result[key] = loader.construct_object(value_node)
    return result


WorkflowLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)


def same_expression(actual, expected: str) -> bool:
    return isinstance(actual, str) and re.sub(r"\s+", "", actual) == re.sub(r"\s+", "", expected)


def verify_capture_job(capture: dict) -> None:
    """Les preuves ne compilent ni ne publient : elles lisent l'AAB de ce run.

    Énumérer les étapes et leurs arguments évite qu'un outil de capture se
    transforme plus tard en second chemin de livraison ou de signature.
    Aucun secret de téléversement n'est nécessaire à cet émulateur jetable.
    """
    require(set(capture) == {"name", "needs", "if", "permissions", "runs-on",
                             "timeout-minutes", "steps"}, "Configuration du job de captures inattendue")
    require(capture.get("needs") == "release" and capture.get("permissions") == {"contents": "read"},
            "Les captures doivent attendre la vérification et rester en lecture seule")
    require(same_expression(capture.get("if"), "needs.release.result == 'success' && " + COMMON_GUARD +
                            " && " + PLAY_CONFIRMATION + " && inputs.reviewed_commit == github.sha"),
            "Captures Play insuffisamment protégées")
    require(capture.get("runs-on") == "ubuntu-24.04" and capture.get("timeout-minutes") == "35",
            "Runner de captures inattendu")
    steps = capture.get("steps", [])
    ids = [step.get("id") for step in steps]
    require(ids == ["capture_checkout", "capture_java", "capture_android", "capture_aab",
                    "capture_screenshots", "upload_play_evidence", "upload_play_evidence_diagnostic"],
            "Étape de captures ajoutée, absente ou déplacée")
    actions = {
        "capture_checkout": ("actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", {
            "ref": "${{ github.sha }}", "fetch-depth": "0", "persist-credentials": "false",
        }),
        "capture_java": ("actions/setup-java@de7274f081f381c8f8158605e0321c36c376e2e6", {
            "distribution": "temurin", "java-version": "17",
        }),
        "capture_android": ("android-actions/setup-android@be39fa834029ff78f1a44aa3bb0819b8fc2bd8fd", None),
        "capture_aab": ("actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333", {
            "name": f"NOVATUBE-{VERSION_NAME}-{VERSION_CODE}-verified-"
                    "${{ github.sha }}-${{ github.run_attempt }}",
            "path": "android-app/build/novatube/capture-input/",
        }),
        "upload_play_evidence": ("actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9", {
            "name": "NOVATUBE-Play-evidence-${{ github.sha }}-${{ github.run_attempt }}",
            "path": "android-app/build/novatube/play-evidence/",
            "if-no-files-found": "error", "retention-days": "30",
        }),
        "upload_play_evidence_diagnostic": ("actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9", {
            "name": "NOVATUBE-Play-evidence-diagnostic-${{ github.sha }}-${{ github.run_attempt }}",
            "path": "android-app/build/novatube/play-evidence-diagnostic/",
            "if-no-files-found": "ignore", "retention-days": "7",
        }),
    }
    for step in steps:
        step_id = step["id"]
        allowed = {"name", "id"}
        if step_id in actions:
            action, arguments = actions[step_id]
            allowed.add("uses")
            require(step.get("uses") == action, "Action de captures non approuvée : " + step_id)
            if arguments is not None:
                allowed.add("with")
                require(step.get("with") == arguments, "Arguments de captures modifiés : " + step_id)
            if step_id.startswith("upload_"):
                allowed.add("if")
                condition = "failure()" if step_id.endswith("_diagnostic") else "success()"
                require(step.get("if") == condition, "Captures et diagnostics ne doivent pas être confondus")
        else:
            allowed.update(("run", "env"))
            require(step.get("env") == {
                "NOVATUBE_CAPTURE_CONFIRMATION": "${{ inputs.confirme }}",
                "REVIEWED_COMMIT": "${{ inputs.reviewed_commit }}",
            }, "Contexte des captures incomplet ou secret ajouté")
            run = " ".join(step.get("run", "").replace("\\\n", " ").split())
            require(run == "set -euo pipefail python3 ci/novatube/run_play_evidence.py "
                    "--verified build/novatube/capture-input --output build/novatube/play-evidence "
                    "--diagnostics build/novatube/play-evidence-diagnostic",
                    "Les captures doivent uniquement exécuter le vérificateur dédié")
        require(set(step) == allowed, "Configuration d'étape de captures inattendue : " + step_id)
    require("secrets." not in json.dumps(capture) and "GITHUB_TOKEN" not in json.dumps(capture),
            "Le job de captures ne doit recevoir aucun secret de publication")


def verify_workflow(workflow: str) -> None:
    """Le define privé est admis uniquement dans deux étapes fermées de l'APK.

    L'AAB conserve sa commande exacte. Le seul droit d'écriture appartient
    au job de publication, après réussite du job qui vérifie l'APK réel.
    """
    require("ZUNO_CAST_TEST" not in workflow, "Drapeau de test interdit dans la CI NOVATUBE")
    require("secrets.ANDROID_" not in workflow and "secrets.GOOGLE_" not in workflow,
            "Secret d'une autre livraison référencé")
    document = yaml.load(workflow, Loader=WorkflowLoader)
    require(isinstance(document, dict), "Workflow YAML invalide")
    events = document.get("on", {})
    require(set(events) == {"workflow_dispatch"}, "La CI NOVATUBE doit uniquement être lancée à la main")
    inputs = events["workflow_dispatch"].get("inputs", {})
    require(set(inputs) == {"confirme", "reviewed_commit"} and
            all(item.get("type") == "string" and item.get("required") == "true" for item in inputs.values()),
            "Confirmation et SHA approuvé obligatoires")
    require(document.get("permissions") == {"contents": "read"}, "Permissions globales trop larges")
    jobs = document.get("jobs", {})
    require(set(jobs) == {"release", "publish_private", "capture_play"}, "Jobs de livraison inattendus")
    verify_capture_job(jobs["capture_play"])
    release, publish = jobs["release"], jobs["publish_private"]
    require(release.get("permissions", {"contents": "read"}) == {"contents": "read"},
            "Le job de compilation doit rester en lecture seule")
    require(same_expression(release.get("if"), COMMON_GUARD + " && (" + PLAY_CONFIRMATION +
                            " || " + PRIVATE_CONFIRMATION + ") && inputs.reviewed_commit == github.sha"),
            "Garde du build manuel/branche/propriétaire/SHA modifiée")
    require(publish.get("needs") == "release" and publish.get("permissions") == {"contents": "write"},
            "La publication doit dépendre de la vérification et seule détenir contents:write")
    require(same_expression(publish.get("if"), "needs.release.result == 'success' && " + COMMON_GUARD +
                            " && " + PRIVATE_CONFIRMATION + " && inputs.reviewed_commit == github.sha"),
            "Publication privée insuffisamment protégée")
    steps = release.get("steps", [])
    identified = {step["id"]: step for step in steps if "id" in step}
    require(len(identified) == sum("id" in step for step in steps), "Identifiant d'étape dupliqué")
    private_ids = ("tests_private", "build_private_apk", "tests_recording_device", "verify_private_apk", "upload_private_apk")
    play_ids = ("build_play_aab", "verify_play_aab", "upload_play_aab")
    for step_id, condition in [(name, PRIVATE_CONFIRMATION) for name in (*private_ids, "preflight_recording_device")] + [
            (name, PLAY_CONFIRMATION) for name in play_ids]:
        require(step_id in identified and same_expression(identified[step_id].get("if"), condition),
                "Étape hors de son mode explicite : " + step_id)
    for step_id in ("analyze", "tests_play", "tests_recording_native"):
        require(step_id in identified and "if" not in identified[step_id], "Validation commune absente : " + step_id)
    order = {step.get("id"): index for index, step in enumerate(steps) if "id" in step}
    for sequence in (("tests_recording_native", "analyze", "tests_play", *private_ids), ("tests_play", *play_ids)):
        require(all(order[a] < order[b] for a, b in zip(sequence, sequence[1:])),
                "Vérification, compilation ou conservation dans un ordre incorrect")
    require(order["preflight_recording_device"] < order["build_private_apk"],
            "Le démarrage Android doit être vérifié avant de compiler l'APK privé")
    expected_builds = {
        "build_play_aab": (
            "flutter build appbundle --release --target=lib/main_zuno_mobile.dart "
            f"--build-name={VERSION_NAME} --build-number={VERSION_CODE}"
        ),
        "build_private_apk": (
            "flutter build apk --release --target=lib/main_zuno_mobile.dart "
            f"--build-name={PRIVATE_VERSION_NAME} --build-number={PRIVATE_VERSION_CODE} "
            "--dart-define=NOVATUBE_PRIVATE_APK=true"
        ),
    }
    for step_id, command in expected_builds.items():
        run = identified[step_id].get("run", "").replace("\\\n", " ")
        commands = [" ".join(line.split()) for line in run.splitlines() if line.strip().startswith("flutter build")]
        require(commands == [command], "Commande release non approuvée : " + step_id)
    require("--dart-define=NOVATUBE_PRIVATE_APK=true" in identified["tests_private"].get("run", ""),
            "La suite privée doit réellement activer la fonction privée")
    private_verifier = " ".join(identified["verify_private_apk"].get("run", "").replace("\\\n", " ").split())
    require("python3 ci/novatube/verify_private_apk.py --apk build/app/outputs/flutter-apk/app-release.apk "
            "--reports build/novatube/reports --output build/novatube/private-verified" in private_verifier,
            "Vérification réelle de l'APK privé absente")
    require("ci/novatube/verify_aab.py" in identified["verify_play_aab"].get("run", ""),
            "Vérification réelle de l'AAB absente")
    require("python3 ci/novatube/run_recording_logic.py" in identified["tests_recording_native"].get("run", ""),
            "Tests des règles natives d'export MP4 absents")
    device_verifier = " ".join(identified["tests_recording_device"].get("run", "").replace("\\\n", " ").split())
    require("python3 ci/novatube/run_recording_device.py --apk build/app/outputs/flutter-apk/app-release.apk "
            "--reports build/novatube/reports" in device_verifier and "--preflight" not in device_verifier,
            "Test du vrai export Android absent")
    require("python3 ci/novatube/run_recording_device.py --preflight" in identified["preflight_recording_device"].get("run", ""),
            "Contrôle du démarrage de l'émulateur absent")
    for step_id in ("analyze", "tests_play", "tests_private", "tests_recording_native", "preflight_recording_device", "tests_recording_device", "build_play_aab", "build_private_apk",
                    "verify_play_aab", "verify_private_apk"):
        require("set -euo pipefail" in identified[step_id].get("run", ""),
                "Une erreur de pipeline pourrait être ignorée : " + step_id)
    # Retirer seulement les deux corps autorisés avant de chercher un define
    # qui aurait fui dans l'AAB, un environnement global ou un autre job.
    for step_id in ("tests_private", "build_private_apk"):
        identified[step_id]["run"] = ""
    remaining = json.dumps(document)
    require("NOVATUBE_PRIVATE_APK" not in remaining and "DART_DEFINES" not in workflow,
            "Le define privé fuit hors des tests/du build APK dédiés")
    require("GITHUB_TOKEN" not in json.dumps(release), "Jeton d'écriture exposé au job de compilation")
    for job in jobs.values():
        require(job.get("continue-on-error", "false") == "false", "Un job ne peut ignorer un échec")
        for step in job.get("steps", []):
            require(step.get("continue-on-error", "false") == "false", "Une étape ne peut ignorer un échec")
    publication = publish.get("steps", [])
    require(len(publication) == 3 and publication[-1].get("id") == "publish_private_apk" and
            publication[-1].get("run") == "python3 ci/novatube/publish_private_apk.py --verified build/novatube/private-verified",
            "Publication extérieure au script NOVATUBE vérifié")
    require(publication[-1].get("env") == {
        "GITHUB_TOKEN": "${{ secrets.GITHUB_TOKEN }}",
        "NOVATUBE_PUBLICATION_CONFIRMATION": "${{ inputs.confirme }}",
        "REVIEWED_COMMIT": "${{ inputs.reviewed_commit }}",
    }, "Contexte de publication incomplet")
    require(publication[0].get("with", {}) == {
        "ref": "${{ github.sha }}", "fetch-depth": "0", "persist-credentials": "false",
    }, "Le script de publication doit provenir du commit approuvé")
    artifact = {
        "name": "NOVATUBE-PRIVATE-APK-verified-${{ github.sha }}-${{ github.run_attempt }}",
        "path": "android-app/build/novatube/private-verified/",
    }
    require(publication[1].get("with", {}) == artifact and
            identified["upload_private_apk"].get("with", {}) == {
                **artifact, "if-no-files-found": "error", "retention-days": "30",
            }, "Artifact privé incohérent")
    require(identified["upload_play_aab"].get("with", {}) == {
        "name": f"NOVATUBE-{VERSION_NAME}-{VERSION_CODE}-verified-"
                "${{ github.sha }}-${{ github.run_attempt }}",
        "path": "android-app/build/novatube/verified/",
        "if-no-files-found": "error", "retention-days": "30",
    }, "Artifact Play incohérent avec la version approuvée")
    for step, action in ((publication[0], "checkout"), (publication[1], "download-artifact"),
                         (identified["upload_private_apk"], "upload-artifact")):
        require(re.fullmatch(r"actions/" + action + r"@[0-9a-f]{40}", step.get("uses", "")) is not None,
                "Action de transfert non épinglée : " + action)


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
    verify_workflow(workflow)
    for filename in ("build-zuno-tv.yml", "quality-zuno.yml"):
        inherited = (REPO_ROOT / ".github/workflows" / filename).read_text(encoding="utf-8")
        require("'!" + BRANCH + "'" in inherited,
                "Un workflow hérité peut compiler NOVATUBE au push : " + filename)
    tracked_keys = git("ls-files", "*.jks", "*.keystore", "*key.properties")
    require(not tracked_keys, "Une clé privée ou une configuration de secrets est versionnée")
    _, certificate_sha256 = expected_certificate()
    return {
        "status": "passed", "sourceCommit": source_commit, "sourceTree": git("rev-parse", "HEAD^{tree}"),
        "privateApkWorkflowVerified": True, "sourceTag": BASE_TAG,
        "sourceTagCommit": BASE_COMMIT, "package": PACKAGE, "entrypoint": ENTRYPOINT,
        # Il s'agit de versions de compilation autorisées, pas d'une preuve
        # de version binaire : celle-ci est lue ensuite dans l'AAB ou l'APK.
        "pubspecVersion": VERSION_NAME + "+" + VERSION_CODE,
        "buildTargets": {
            "play-aab": {"versionName": VERSION_NAME, "versionCode": int(VERSION_CODE)},
            "private-apk": {
                "versionName": PRIVATE_VERSION_NAME, "versionCode": int(PRIVATE_VERSION_CODE),
            },
        },
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
    except (OSError, ValueError, KeyError, IndexError, subprocess.CalledProcessError, yaml.YAMLError) as error:
        print("Contrôle préalable NOVATUBE refusé : " + str(error), file=sys.stderr)
        raise SystemExit(1)
