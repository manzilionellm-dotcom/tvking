#!/usr/bin/env python3
"""Encadrer le diagnostic réseau manuel, sans binaire d'application ni publication.

Les gardes sont répétées avant les dépendances puis avant l'ouverture du namespace.
Le processus privilégié reçoit seulement les chemins/outils nécessaires, jamais
l'environnement GitHub du runner. Ses espaces réseau, PID et montages sont jetables.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

REPOSITORY = "manzilionellm-dotcom/tvking"
BRANCH = "feature/novatube-play-aab"
CONFIRMATION = "DIAGNOSTIQUER_NOVATUBE_CAST_RESEAU"
JOB = "diagnose_cast_network"
WORKFLOW = ".github/workflows/novatube-play-aab.yml"
BASE_COMMIT = "6954bafc0596d6617caca4b287af8e42e40cf256"
# Ces deux valeurs sont calculées après revue du YAML proposé. Le SHA du job
# ferme aussi les étapes, arguments, dépendances, permissions et artefacts.
WORKFLOW_SHA256 = "a18b20ca1285f58398786c41575a83e8fff2482db66d780ab38fd3d86c71fee8"
TAP_JOB_SHA256 = "a4fc804f949d8eea7474546e38411e6b3152a576438472eb76bae7667e67a76d"
REPO_ROOT = Path(__file__).resolve().parents[3]
PROBE = Path(__file__).with_name("probe_tap_network.py")
FALSE_EVIDENCE_FIELDS = ("playEvidence", "foregroundServiceEvidence", "novatubeInstalled",
                         "receiverMediaPlaybackObserved", "aabModified")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def runtime_context(environment=None):
    env = os.environ if environment is None else environment
    owner, sha = REPOSITORY.split("/", 1)[0], env.get("GITHUB_SHA", "")
    require(env.get("GITHUB_ACTIONS") == "true" and env.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
            and env.get("GITHUB_REPOSITORY") == REPOSITORY
            and env.get("GITHUB_REPOSITORY_OWNER") == owner
            and env.get("GITHUB_REF") == "refs/heads/" + BRANCH
            and env.get("GITHUB_ACTOR") == owner and env.get("GITHUB_TRIGGERING_ACTOR") == owner
            and env.get("GITHUB_WORKFLOW_REF") == REPOSITORY + "/" + WORKFLOW + "@refs/heads/" + BRANCH
            and env.get("GITHUB_WORKFLOW_SHA") == sha and env.get("GITHUB_JOB") == JOB
            and env.get("NOVATUBE_CAST_DIAGNOSTIC_CONFIRMATION") == CONFIRMATION
            and re.fullmatch(r"[0-9a-f]{40}", sha) is not None and env.get("REVIEWED_COMMIT") == sha,
            "Diagnostic hors du workflow, job, propriétaire, intention, événement, branche ou SHA approuvés")
    for name in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"):
        require(re.fullmatch(r"[1-9][0-9]*", env.get(name, "")) is not None, "Contexte de run absent")
    require(not any(value for name, value in env.items() if name.startswith("NOVATUBE_UPLOAD_")
                    or name in ("NOVATUBE_KEYSTORE_PATH", "GITHUB_TOKEN", "GH_TOKEN")),
            "Le diagnostic ne doit recevoir ni clé de signature ni jeton explicite")
    return {"scriptCommit": sha, "diagnosticRunId": env["GITHUB_RUN_ID"],
            "diagnosticRunAttempt": env["GITHUB_RUN_ATTEMPT"], "purpose": "network-diagnostic-only",
            **{key: False for key in FALSE_EVIDENCE_FIELDS}}


def verify_workflow_bytes(data):
    require(hashlib.sha256(data).hexdigest() == WORKFLOW_SHA256,
            "Le workflow diffère du diagnostic réseau exactement relu")


def verify_tap_job(job):
    require(isinstance(job, dict), "Job de diagnostic Cast absent")
    canonical = json.dumps(job, sort_keys=True, separators=(",", ":")).encode()
    require(hashlib.sha256(canonical).hexdigest() == TAP_JOB_SHA256,
            "Le diagnostic Cast diffère de ses gardes, étapes ou permissions relues")


def command(arguments):
    return subprocess.run(arguments, cwd=REPO_ROOT, capture_output=True,
                          text=True, check=True, timeout=30).stdout


def preflight():
    context = runtime_context()
    verify_workflow_bytes((REPO_ROOT / WORKFLOW).read_bytes())
    require(command(["git", "rev-parse", "HEAD"]).strip() == context["scriptCommit"],
            "Le checkout du diagnostic n'est pas le SHA approuvé")
    require(not command(["git", "status", "--porcelain", "--untracked-files=no"]).strip(),
            "Les fichiers versionnés du diagnostic ont changé")
    command(["git", "merge-base", "--is-ancestor", BASE_COMMIT, context["scriptCommit"]])
    context["probeSha256"] = hashlib.sha256(PROBE.read_bytes()).hexdigest()
    context["workflowSha256"] = WORKFLOW_SHA256
    return context


def isolated_command(sdk, output, java_home, renderer, parent_netns):
    require(sdk.is_absolute() and sdk.is_dir(), "SDK Android absent")
    require(java_home.is_absolute() and (java_home / "bin/java").is_file(), "Java préparé absent")
    require(renderer.is_absolute() and renderer.is_file(), "Récepteur privé extrait absent")
    # --mount-proc ouvre son propre namespace de montages ; aucun /proc hôte
    # n'est remplacé. La fin du PID initial tue ses descendants éventuels.
    return ["sudo", "-n", "unshare", "--net", "--pid", "--fork", "--mount-proc",
            "--kill-child=KILL", "/usr/bin/env", "-i", "LANG=C.UTF-8",
            "PATH=" + str(java_home / "bin") + ":/usr/sbin:/usr/bin:/sbin:/bin",
            "JAVA_HOME=" + str(java_home), "ANDROID_HOME=" + str(sdk),
            "ANDROID_SDK_ROOT=" + str(sdk), "PYTHONDONTWRITEBYTECODE=1",
            "/usr/bin/python3", str(PROBE), "--run-diagnostic", "--sdk-root", str(sdk),
            "--renderer", str(renderer), "--output", str(output), "--parent-netns", parent_netns]


def stop_namespace(process):
    """Arrêt borné du seul groupe démarré ici ; aucun pkill global."""
    for sig, seconds in (("TERM", 120), ("KILL", 15)):
        if process.poll() is not None:
            return
        try:
            subprocess.run(["sudo", "-n", "kill", "-" + sig, "--", "-" + str(process.pid)],
                           capture_output=True, timeout=15, check=False)
        except (OSError, subprocess.SubprocessError):
            # Même si le premier arrêt expire, tenter le dernier recours borné.
            pass
        try:
            process.wait(timeout=seconds)
            return
        except subprocess.TimeoutExpired:
            pass
    raise RuntimeError("Le groupe du namespace ne s'est pas arrêté dans le délai prévu")


def run(output, context):
    previous = json.loads((output / "ci-preflight.json").read_text())
    require(previous == context, "Préflight absent ou différent du contexte courant")
    sdk_value = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME", "")
    require(sdk_value and os.environ.get("JAVA_HOME"), "SDK/Java non préparés")
    nested = output / "network"
    require(not nested.exists(), "Le dossier réseau doit être neuf")
    receiver = Path(os.environ["RUNNER_TEMP"]) / "novatube-tap-receiver/extracted/usr/bin/gmediarender"
    arguments = isolated_command(Path(sdk_value).resolve(), nested,
                                 Path(os.environ["JAVA_HOME"]).resolve(), receiver.resolve(),
                                 os.readlink("/proc/self/ns/net"))
    report = {**context, "status": "not-run", "startedAtUtc": datetime.now(timezone.utc).isoformat()}
    process = None
    try:
        with (output / "namespace-command.txt").open("w", encoding="utf-8") as log:
            # Ce fichier ne contient que les chemins du diagnostic et ses logs.
            process = subprocess.Popen(arguments, cwd=REPO_ROOT, stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            code = process.wait(timeout=720)
        require(code == 0, "Le diagnostic isolé a échoué ; consulter namespace-command.txt")
        observed = json.loads((nested / "network-diagnostic.json").read_text())
        require(observed.get("status") == "tap-ssdp-and-bidirectional-http-observed"
                and observed.get("cleanupErrors") == [], "Échanges ou nettoyage réseau incomplets")
        require(all(observed.get(key) is False for key in FALSE_EVIDENCE_FIELDS),
                "Un diagnostic réseau ne peut être présenté comme preuve Play, FGS ou lecture")
        report["status"] = "network-diagnostic-complete-not-play-evidence"
    except BaseException as error:
        report["status"] = "blocked"
        report["error"] = str(error)
        raise
    finally:
        try:
            if process is not None:
                stop_namespace(process)
        except Exception as error:
            report["status"] = "cleanup-incomplete"
            report["cleanupError"] = str(error)
            raise
        finally:
            report["completedAtUtc"] = datetime.now(timezone.utc).isoformat()
            (output / "ci-result.json").write_text(json.dumps(report, indent=2) + "\n")


def main():
    def interrupted(signum, _frame):
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        raise RuntimeError(f"Arrêt CI demandé par le signal {signum}")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    context = preflight()
    output = args.output.resolve()
    require(output == REPO_ROOT / "android-app/build/novatube/cast-network-diagnostic",
            "Dossier de diagnostic hors du chemin fermé du job")
    if args.preflight:
        require(not output.exists(), "Le dossier de préflight doit être neuf")
        output.mkdir(parents=True)
        (output / "ci-preflight.json").write_text(json.dumps(context, indent=2) + "\n")
    else:
        run(output, context)
    sys.stdout.write(json.dumps(context, indent=2) + "\n")


if __name__ == "__main__":
    main()
