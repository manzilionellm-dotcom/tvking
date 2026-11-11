#!/usr/bin/env python3
"""Publie un APK déjà vérifié ; avance le pointeur public uniquement à la fin."""

from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote
from urllib.request import Request, urlopen

from common import BRANCH, PACKAGE, VERSION_CODE, VERSION_NAME, expected_certificate, require, sha256_file
from verify_private_apk import REPOSITORY, evidence_results

MANIFEST_PATH = "android-app/ci/novatube/latest-download.json"
API_ROOT = "repos/" + REPOSITORY
BOOTSTRAP_URL = ("https://joe3v6of1vo5g2zl.public.blob.vercel-storage.com/"
                 "novatube-0.1.5-5-26193f18.apk")


class GitHub:
    """Le jeton vient du seul job de publication, jamais d'un argument ni d'un fichier."""

    def __init__(self, environment: dict):
        require(bool(environment.get("GITHUB_TOKEN")), "GITHUB_TOKEN absent")
        self.environment = dict(environment)
        # gh donne priorité à GH_TOKEN. On ignore une éventuelle valeur héritée.
        self.environment["GH_TOKEN"] = environment["GITHUB_TOKEN"]
        self.environment.pop("GH_DEBUG", None)

    def request(self, method: str, endpoint: str, *, body=None, upload: Path | None = None,
                allow_missing: bool = False):
        command = ["gh", "api", "--hostname", "github.com", "--method", method, endpoint,
                   "--header", "Accept: application/vnd.github+json"]
        data = None
        if upload is not None:
            command += ["--header", "Content-Type: application/octet-stream", "--input", str(upload)]
        elif body is not None:
            command += ["--input", "-"]
            data = json.dumps(body)
        result = subprocess.run(command, input=data, capture_output=True, text=True, env=self.environment)
        if result.returncode:
            if allow_missing and "HTTP 404" in result.stderr:
                return None
            # Ne jamais recopier une réponse de diagnostic susceptible de contenir
            # une variable d'environnement ou un en-tête d'authentification.
            raise ValueError(f"API GitHub refusée : {method} {endpoint.split('?')[0]}")
        return json.loads(result.stdout)


def checked_context(environment: dict) -> tuple[str, str]:
    sha = environment.get("GITHUB_SHA", "")
    run_id = environment.get("GITHUB_RUN_ID", "")
    require(environment.get("GITHUB_ACTIONS") == "true"
            and environment.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
            and environment.get("GITHUB_REPOSITORY") == REPOSITORY
            and environment.get("GITHUB_REF") == "refs/heads/" + BRANCH,
            "Publication réservée au lancement manuel de la branche NOVATUBE")
    require(re.fullmatch(r"[0-9a-f]{40}", sha) is not None and run_id.isdigit(), "SHA/run invalides")
    require(environment.get("REVIEWED_COMMIT") == sha
            and environment.get("NOVATUBE_PUBLICATION_CONFIRMATION") == "PUBLIER_NOVATUBE_APK_PRIVE",
            "Accord de publication privée absent ou différent du commit")
    return sha, run_id


def load_verified(directory: Path, sha: str, run_id: str, attempt: str) -> tuple[dict, Path]:
    require(directory.is_dir(), "Livraison vérifiée absente")
    sums = {}
    for line in (directory / "SHA256SUMS.txt").read_text(encoding="ascii").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9_.-]+)", line)
        require(match is not None and match[2] not in sums, "Sommes de contrôle malformées ou dupliquées")
        path = directory / match[2]
        require(path.is_file() and not path.is_symlink() and sha256_file(path) == match[1],
                "Fichier vérifié absent ou modifié : " + match[2])
        sums[match[2]] = match[1]
    require(set(sums) == {p.name for p in directory.iterdir() if p.name != "SHA256SUMS.txt"},
            "La livraison contient un fichier non couvert par ses sommes")
    proof = json.loads((directory / "apk-verification.json").read_text(encoding="utf-8"))
    provenance = json.loads((directory / "build-provenance.json").read_text(encoding="utf-8"))
    _, certificate = expected_certificate()
    expected = {
        "package": PACKAGE, "versionName": VERSION_NAME, "versionCode": int(VERSION_CODE),
        "distribution": "private-apk", "branch": BRANCH, "repository": REPOSITORY,
        "sourceCommit": sha, "runId": run_id, "runAttempt": attempt,
        "uploadCertificateSha256": certificate, "releaseSignatureVerified": True,
        "debuggable": False, "testOnly": False, "biometricPermissionVerified": True,
        "googleUpload": False, "publishedToGooglePlay": False,
    }
    require(proof.get("status") == "passed" and provenance.get("status") == "verified",
            "Rapport APK non réussi")
    for key, value in expected.items():
        require(proof.get(key) == value and provenance.get(key) == value,
                "Preuve incompatible avec cette publication : " + key)
    filename = f"NOVATUBE-{sha}.apk"
    apk = directory / filename
    require(proof.get("artifact") == filename and provenance.get("artifact") == filename,
            "Nom d'APK hors de l'identité NOVATUBE")
    require(proof.get("sha256") == sums.get(filename) == provenance.get("sha256"), "Empreinte APK différente")
    require(type(proof.get("sizeBytes")) is int and proof["sizeBytes"] > 0
            and apk.stat().st_size == proof["sizeBytes"] == provenance.get("sizeBytes"), "Taille APK différente")
    evidence = evidence_results(directory, sha)
    require(proof.get("tests") == evidence["tests"] == provenance.get("tests"), "Résultats de tests incohérents")
    require(proof.get("sourceTree") == evidence["source"]["sourceTree"] == provenance.get("sourceTree"),
            "Arbre Git des preuves incohérent")
    return proof, apk


def read_manifest(github) -> tuple[dict, str]:
    result = github.request("GET", API_ROOT + "/contents/" + MANIFEST_PATH + "?ref=" + quote(BRANCH, safe=""))
    require(result.get("type") == "file" and result.get("encoding") == "base64"
            and re.fullmatch(r"[0-9a-f]{40}", str(result.get("sha", ""))) is not None,
            "Le manifeste courant ne fournit pas de SHA de blob fiable")
    manifest = json.loads(base64.b64decode(result["content"], validate=False))
    _, certificate = expected_certificate()
    require(manifest.get("schemaVersion") == 1 and manifest.get("status") == "verified"
            and manifest.get("package") == PACKAGE and manifest.get("distribution") == "private-apk"
            and manifest.get("uploadCertificateSha256") == certificate,
            "Identité du manifeste courant incorrecte")
    require(re.fullmatch(r"[0-9a-f]{40}", str(manifest.get("sourceCommit", ""))) is not None
            and re.fullmatch(r"[0-9a-f]{64}", str(manifest.get("sha256", ""))) is not None,
            "Empreintes du manifeste courant invalides")
    return manifest, result["sha"]


def check_no_downgrade(github, current: dict, sha: str, run_id: str, digest: str) -> None:
    previous_run = current.get("runId")
    require(previous_run is None or (str(previous_run).isdigit() and int(run_id) >= int(previous_run)),
            "Un ancien run ne peut pas remplacer le dernier APK")
    previous_sha = current["sourceCommit"]
    if previous_sha == sha:
        require(current["sha256"] == digest, "Le même commit possède déjà un APK différent")
    else:
        comparison = github.request("GET", API_ROOT + f"/compare/{previous_sha}...{sha}")
        require(comparison.get("status") == "ahead", "Révision publiée plus récente ou divergente")
    head = github.request("GET", API_ROOT + "/git/ref/heads/" + BRANCH)
    require(head.get("object", {}).get("type") == "commit", "Branche NOVATUBE introuvable")
    head_sha = head["object"].get("sha", "")
    require(re.fullmatch(r"[0-9a-f]{40}", head_sha) is not None, "Tête de branche invalide")
    if head_sha != sha:
        comparison = github.request("GET", API_ROOT + f"/compare/{sha}...{head_sha}")
        require(comparison.get("status") == "ahead", "Le commit n'appartient plus à la branche NOVATUBE")


def verify_public_download(url: str, digest: str, size: int) -> None:
    """Relecture publique sans token ; une page HTML ou un téléchargement partiel échoue."""
    request = Request(url, headers={"User-Agent": "NOVATUBE-verifier", "Accept": "application/octet-stream"})
    actual = hashlib.sha256()
    received = 0
    with urlopen(request, timeout=45) as response:
        require(response.status == 200 and response.geturl().startswith("https://"),
                "L'APK n'est pas disponible publiquement en HTTPS")
        for chunk in iter(lambda: response.read(1024 * 1024), b""):
            received += len(chunk)
            require(received <= size, "Le téléchargement public dépasse la taille vérifiée")
            actual.update(chunk)
    require(received == size and actual.hexdigest() == digest,
            "Le téléchargement public diffère de l'APK vérifié")


def publish(directory: Path, *, environment: dict | None = None, github=None,
            download=verify_public_download) -> dict:
    environment = dict(os.environ) if environment is None else environment
    sha, run_id = checked_context(environment)
    proof, apk = load_verified(directory, sha, run_id, environment.get("GITHUB_RUN_ATTEMPT", ""))
    github = github or GitHub(environment)
    metadata = github.request("GET", API_ROOT)
    require(metadata.get("full_name") == REPOSITORY and metadata.get("private") is False,
            "Le dépôt de téléchargement doit être le dépôt public NOVATUBE attendu")
    current, expected_blob_sha = read_manifest(github)
    check_no_downgrade(github, current, sha, run_id, proof["sha256"])
    tag = "novatube-private-" + sha
    reference = github.request("GET", API_ROOT + "/git/ref/tags/" + tag, allow_missing=True)
    if reference is None:
        reference = github.request("POST", API_ROOT + "/git/refs",
                                   body={"ref": "refs/tags/" + tag, "sha": sha})
    require(reference.get("object", {}).get("type") == "commit"
            and reference["object"].get("sha") == sha, "Tag NOVATUBE déjà attribué à une autre révision")
    release = github.request("GET", API_ROOT + "/releases/tags/" + tag, allow_missing=True)
    if release is None:
        release = github.request("POST", API_ROOT + "/releases", body={
            "tag_name": tag, "target_commitish": sha,
            "name": f"NOVATUBE {VERSION_NAME} ({VERSION_CODE}) — APK privé {sha[:8]}",
            "body": f"APK NOVATUBE vérifié.\nCommit : {sha}\nSHA-256 : {proof['sha256']}\n"
                    f"Run : https://github.com/{REPOSITORY}/actions/runs/{run_id}\n"
                    "Distribution directe ; aucune publication Google Play.",
            "draft": False, "prerelease": True, "make_latest": "false",
        })
    require(release.get("tag_name") == tag and release.get("draft") is False
            and release.get("prerelease") is True and type(release.get("id")) is int,
            "Release incompatible avec l'APK privé NOVATUBE")
    release_id = release["id"]
    assets = github.request("GET", API_ROOT + f"/releases/{release_id}/assets?per_page=100")
    matches = [asset for asset in assets if asset.get("name") == apk.name]
    require(len(matches) <= 1, "Asset APK dupliqué")
    if matches:
        asset = matches[0]
    else:
        asset = github.request("POST", f"https://uploads.github.com/{API_ROOT}/releases/{release_id}/assets"
                               + "?name=" + quote(apk.name), upload=apk)
    url = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{apk.name}"
    require(asset.get("name") == apk.name and asset.get("state") == "uploaded"
            and asset.get("size") == proof["sizeBytes"] and asset.get("browser_download_url") == url,
            "Asset existant ou publié incompatible ; aucun remplacement autorisé")
    if asset.get("digest") is not None:
        require(asset["digest"] == "sha256:" + proof["sha256"], "Empreinte de l'asset GitHub différente")
    download(url, proof["sha256"], proof["sizeBytes"])
    manifest = {
        "schemaVersion": 1, "status": "verified", "package": PACKAGE,
        "versionName": VERSION_NAME, "versionCode": int(VERSION_CODE), "distribution": "private-apk",
        "sourceCommit": sha, "sha256": proof["sha256"], "sizeBytes": proof["sizeBytes"],
        "uploadCertificateSha256": proof["uploadCertificateSha256"], "url": url,
        "filename": apk.name, "releaseTag": tag, "runId": run_id,
        "runUrl": f"https://github.com/{REPOSITORY}/actions/runs/{run_id}",
        "verifiedAtUtc": datetime.now(timezone.utc).isoformat(),
    }
    # Dernière et unique écriture du pointeur. Une concurrence produit un 409 :
    # aucun force-push, aucun retry aveugle, aucun retour à un ancien manifeste.
    content = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    github.request("PUT", API_ROOT + "/contents/" + MANIFEST_PATH, body={
        "message": "NOVATUBE : APK privé vérifié " + sha[:8] + " [skip ci]",
        "branch": BRANCH, "sha": expected_blob_sha,
        "content": base64.b64encode(content).decode("ascii"),
    })
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verified", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = publish(args.verified.resolve())
        print(json.dumps({key: result[key] for key in ("sourceCommit", "sha256", "url", "runId")}))
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print("Publication NOVATUBE refusée : " + str(error), file=sys.stderr)
        raise SystemExit(1)
