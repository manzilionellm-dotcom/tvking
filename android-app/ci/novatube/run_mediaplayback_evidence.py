#!/usr/bin/env python3
"""Capturer le Cast du seul AAB8 approuvé avec le vrai renderer Rygel.

La préparation télécharge des octets officiels vérifiés et convertit le bundle
existant. Le parcours UI n'a accès qu'à un réseau Linux privé, sans jeton GitHub.
Une vidéo n'est proposée à la revue humaine qu'après qualification et nettoyage.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import urllib.request

import run_datasync_evidence as rec
from run_tap_diagnostic import stop_namespace

REPOSITORY = rec.REPOSITORY
BRANCH = rec.BRANCH
WORKFLOW = rec.WORKFLOW
BASE_COMMIT = "f8467063651072095c2125adca973b7dbd9bbcaf"
JOB = "capture_mediaplayback"
CONFIRMATION = "CAPTURER_NOVATUBE_MEDIAPLAYBACK"
WORKFLOW_SHA256 = "af64cbb3df5f2deaf59f106c2ecfcc82d711c5797e5d9a0840f17a7e2924e315"
MEDIAPLAYBACK_JOB_SHA256 = "aeb7698d6d74067056778f285f7132dc15cae8c4542a748bf8dd894c340c4ff9"
ROOT = Path(__file__).resolve().parents[3]
MODULE = Path(__file__).resolve().parent
DIAGNOSTICS = ROOT / "android-app/build/novatube/mediaplayback-diagnostic"
OUTPUT = ROOT / "android-app/build/novatube/mediaplayback-evidence"
ORIGINAL = ROOT / "novatube-binary-source/android-app"
ARCHIVE = ROOT / "android-app/build/novatube/mediaplayback-artifact"


def require(value, message):
    if not value:
        raise ValueError(message)


def context(environment=None):
    env = os.environ if environment is None else environment
    owner, sha = REPOSITORY.split("/", 1)[0], env.get("GITHUB_SHA", "")
    require(env.get("GITHUB_ACTIONS") == "true" and env.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
        and env.get("GITHUB_REPOSITORY") == REPOSITORY and env.get("GITHUB_REPOSITORY_OWNER") == owner
        and env.get("GITHUB_REF") == "refs/heads/" + BRANCH
        and env.get("GITHUB_ACTOR") == owner and env.get("GITHUB_TRIGGERING_ACTOR") == owner
        and env.get("GITHUB_WORKFLOW_REF") == REPOSITORY + "/" + WORKFLOW + "@refs/heads/" + BRANCH
        and env.get("GITHUB_WORKFLOW_SHA") == sha and env.get("GITHUB_JOB") == JOB
        and env.get("NOVATUBE_MEDIAPLAYBACK_CONFIRMATION") == CONFIRMATION
        and re.fullmatch(r"[0-9a-f]{40}", sha) is not None and env.get("REVIEWED_COMMIT") == sha,
        "Banc mediaPlayback hors intention, propriétaire, branche, événement, workflow ou SHA approuvés")
    for name in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"):
        require(re.fullmatch(r"[1-9][0-9]*", env.get(name, "")), "Run de capture absent")
    require(not any(value for name, value in env.items() if name.startswith("NOVATUBE_UPLOAD_")
        or name in ("NOVATUBE_KEYSTORE_PATH", "GH_TOKEN", "GITHUB_TOKEN")),
        "Aucun secret de livraison ni jeton explicite n'est permis dans ce processus")
    return {"scriptCommit": sha, "evidenceRunId": env["GITHUB_RUN_ID"],
        "evidenceRunAttempt": env["GITHUB_RUN_ATTEMPT"], "appCommit": rec.APP_COMMIT,
        "appRun": rec.APP_RUN, "artifactId": rec.ARTIFACT_ID, "aabSha256": rec.AAB_SHA256}


def verify_mediaplayback_job(job):
    canonical = json.dumps(job, sort_keys=True, separators=(",", ":")).encode()
    require(isinstance(job, dict) and hashlib.sha256(canonical).hexdigest() == MEDIAPLAYBACK_JOB_SHA256,
        "Job mediaPlayback différent de ses gardes, dépendances, binaire ou permissions relus")


def preflight():
    value = context()
    require(rec.digest(ROOT / WORKFLOW) == WORKFLOW_SHA256, "Workflow mediaPlayback modifié")
    for root, expected in ((ROOT, value["scriptCommit"]), (ORIGINAL, rec.APP_COMMIT)):
        require(rec.command(["git", "rev-parse", "HEAD"], cwd=root).strip() == expected,
            "Checkout différent du commit attendu")
        require(not rec.command(["git", "status", "--porcelain", "--untracked-files=no"], cwd=root).strip(),
            "Une source versionnée a changé")
    rec.command(["git", "merge-base", "--is-ancestor", BASE_COMMIT, value["scriptCommit"]], cwd=ROOT)
    return value


def temporary_paths():
    parent = Path(os.environ["RUNNER_TEMP"]).resolve()
    require(parent.is_absolute() and parent.is_dir() and parent != Path("/"), "RUNNER_TEMP invalide")
    return parent / "novatube-mediaplayback-prepared", parent / "novatube-mediaplayback-private"


def json_file(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def prepare(value):
    prepared, _ = temporary_paths()
    require(not prepared.exists(), "Préparation temporaire déjà présente")
    prepared.mkdir(mode=0o700)
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ["ANDROID_HOME"]).resolve()
    helpers = rec.original_helpers(ORIGINAL)
    verified = rec.extract_original_archive(ARCHIVE, prepared / "verified-aab")
    aab, provenance = helpers.validate_artifact(verified, rec.original_context())
    require(rec.digest(aab) == rec.AAB_SHA256, "AAB différent du binaire immuable approuvé")
    # Le keystore de conversion reste dans ce contexte temporaire et disparaît
    # avant le runtime ; aucune clé de livraison n'est chargée ou produite.
    with tempfile.TemporaryDirectory(prefix="convert-", dir=prepared) as folder:
        temporary = Path(folder)
        bundletool = helpers.download_bundletool(temporary)
        identity = helpers.verify_real_bundle(aab, bundletool, provenance)
        apk = helpers.convert_bundle(aab, bundletool, temporary, sdk)
        shutil.copyfile(apk, prepared / "emulator-only.apk")
    pins = json.loads((MODULE / "rygel-official-pins.json").read_text())
    renderer = prepared / "renderer"
    renderer.mkdir()
    for package in pins["packages"]:
        target = prepared / (package["name"] + ".deb")
        with urllib.request.urlopen(package["url"], timeout=60) as response, target.open("wb") as output:
            shutil.copyfileobj(response, output)
        require(target.stat().st_size == package["bytes"] and rec.digest(target) == package["sha256"],
            "Paquet Rygel officiel différent : " + package["name"])
        # Extraction de données uniquement : aucun postinst, daemon hôte ou
        # activation de session n'est exécuté par dpkg-deb --extract.
        rec.command(["dpkg-deb", "--extract", target, renderer])
        (DIAGNOSTICS / (package["name"] + "-package.txt")).write_text(rec.command(["dpkg-deb", "--field", target]))
    for relative, expected in pins["files"].items():
        require(rec.digest(renderer / relative) == expected, "Exécutable/plugin Rygel non approuvé")
    plugins = prepared / "playbin-plugins"
    plugins.mkdir()
    for name in ("librygel-playbin.so", "playbin.plugin"):
        shutil.copyfile(renderer / "usr/lib/x86_64-linux-gnu/rygel-2.8/plugins" / name, plugins / name)
    (prepared / "empty-engines").mkdir()
    layer = prepared / "share-layer"
    layer.mkdir()
    shutil.copytree(renderer / "usr/share/rygel", layer / "rygel")
    require({x.name for x in layer.iterdir()} == {"rygel"}, "Couche de données privée inattendue")
    toolchain = {}
    for relative in ("emulator/emulator", "platform-tools/adb"):
        path = sdk / relative
        toolchain[relative] = {"bytes": path.stat().st_size, "sha256": rec.digest(path)}
    manifest = {**value, "originalSource": str(ORIGINAL), "identity": identity,
        "apkRelativePath": "emulator-only.apk", "aabRelativePath": str(aab.relative_to(prepared)),
        "rendererPins": pins, "sdkExecutables": toolchain,
        "appRecompiled": False, "deliverySigningKeyUsed": False,
        "files": {str(path.relative_to(prepared)): rec.digest(path) for path in sorted(prepared.rglob("*")) if path.is_file()}}
    json_file(prepared / "prepared.json", manifest)
    json_file(DIAGNOSTICS / "prepared-provenance.json", {**manifest,
        "preparedManifestSha256": rec.digest(prepared / "prepared.json")})


def isolated_command(prepared, private, sdk, java):
    require(sdk.is_absolute() and (sdk / "platform-tools/adb").is_file(), "SDK préparé absent")
    require(java.is_absolute() and (java / "bin/java").is_file(), "Java préparé absent")
    return ["sudo", "-n", "unshare", "--net", "--mount", "--pid", "--ipc", "--fork", "--mount-proc",
        "--propagation", "private", "--kill-child=KILL", "/usr/bin/env", "-i", "LANG=C.UTF-8",
        "PATH=" + str(java / "bin") + ":/usr/sbin:/usr/bin:/sbin:/bin", "JAVA_HOME=" + str(java),
        "ANDROID_HOME=" + str(sdk), "ANDROID_SDK_ROOT=" + str(sdk), "PYTHONDONTWRITEBYTECODE=1",
        "/usr/bin/python3", str(MODULE / "mediaplayback_runtime.py"),
        "--output", str(DIAGNOSTICS / "observations"), "--private-root", str(private),
        "--sdk-root", str(sdk), "--prepared", str(prepared),
        "--parent-netns", os.readlink("/proc/self/ns/net"), "--parent-mntns", os.readlink("/proc/self/ns/mnt")]


def capture(value):
    from mediaplayback_scenario import qualify
    prepared, private = temporary_paths()
    original = json.loads((DIAGNOSTICS / "prepared-provenance.json").read_text())
    require(original["preparedManifestSha256"] == rec.digest(prepared / "prepared.json")
        and all(original.get(key) == item for key, item in value.items()), "Préparation d'un autre contexte")
    require(not private.exists() and not OUTPUT.exists(), "Sortie de capture ou namespace déjà utilisée")
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ["ANDROID_HOME"]).resolve()
    arguments = isolated_command(prepared, private, sdk, Path(os.environ["JAVA_HOME"]).resolve())
    process = None
    report = {**value, "status": "blocked", "humanReviewRequired": True, "googleSubmission": False,
        "appRecompiled": False, "deliverySigningKeyUsed": False, "startedAtUtc": datetime.now(timezone.utc).isoformat()}
    try:
        with (DIAGNOSTICS / "namespace-command.txt").open("w") as log:
            process = subprocess.Popen(arguments, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            code = process.wait(timeout=1200)
        require(code == 0, "Parcours isolé échoué ; consulter le diagnostic, aucune preuve Play qualifiée")
        stage = DIAGNOSTICS / "observations"
        result = json.loads((stage / "runtime-result.json").read_text())
        require(result.get("qualified") is True and result.get("cleanupErrors") == [], "Parcours ou nettoyage incomplet")
        qualify(result["observations"])
        require(rec.digest(prepared / original["aabRelativePath"]) == rec.AAB_SHA256, "L'AAB original a changé")
        require(all(rec.digest(prepared / name) == sha for name, sha in original["files"].items()),
            "Une dépendance préparée a changé pendant la capture")
        report.update(status="qualified-recordings-human-review-required", originalAabUnchanged=True,
            workflowSha256=WORKFLOW_SHA256, renderer="Rygel Playbin 0.42.5-1ubuntu3",
            physicalSpeaker=False, observations=result["observations"],
            recordings={name: {"sha256": rec.digest(stage / name), "bytes": (stage / name).stat().st_size}
                        for name in ("mediaplayback-phone.mp4", "renderer-demo.mp4")})
        OUTPUT.mkdir()
        for name in ("mediaplayback-phone.mp4", "renderer-demo.mp4", "events.json", "observations.json",
                     "playback-notification-present.png", "playback-notification-removed.png"):
            shutil.copyfile(stage / name, OUTPUT / name)
        json_file(OUTPUT / "evidence-provenance.json", report)
    except BaseException as error:
        report["error"] = rec.safe_error(error)
        if OUTPUT.exists():
            shutil.rmtree(OUTPUT)
        raise
    finally:
        try:
            if process is not None:
                stop_namespace(process)
        finally:
            report["completedAtUtc"] = datetime.now(timezone.utc).isoformat()
            json_file(DIAGNOSTICS / "ci-result.json", report)


def cleanup():
    # Les seuls dossiers visés sont deux noms fermés, créés par ce job dans
    # RUNNER_TEMP. Aucune sortie de preuve ou source n'est supprimée ici.
    for path in temporary_paths():
        require(not path.is_symlink(), "Refus d'un dossier temporaire indirect")
        if path.exists():
            rec.command(["sudo", "-n", "rm", "-rf", "--", str(path)], timeout=60)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    for mode in ("preflight", "prepare", "capture", "cleanup"):
        modes.add_argument("--" + mode, action="store_true")
    args = parser.parse_args()
    if args.cleanup:
        context()
        cleanup()
        return
    value = preflight()
    if args.preflight:
        require(not DIAGNOSTICS.exists(), "Préflight déjà présent")
        DIAGNOSTICS.mkdir(parents=True)
        json_file(DIAGNOSTICS / "ci-preflight.json", value)
        return
    require(json.loads((DIAGNOSTICS / "ci-preflight.json").read_text()) == value, "Contexte de préflight différent")
    def interrupted(signum, _frame):
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        raise RuntimeError(f"Capture interrompue par le signal {signum}")
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    prepare(value) if args.prepare else capture(value)


if __name__ == "__main__":
    main()
