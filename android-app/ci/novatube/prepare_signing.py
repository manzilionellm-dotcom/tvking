#!/usr/bin/env python3
"""Charge uniquement la nouvelle clé NOVATUBE, sans afficher aucun secret."""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
from pathlib import Path
import subprocess
import sys

from common import KEY_ALIAS, REPO_ROOT, expected_certificate, require


SECRET_NAMES = (
    "NOVATUBE_UPLOAD_KEYSTORE_BASE64",
    "NOVATUBE_UPLOAD_STORE_PASSWORD",
    "NOVATUBE_UPLOAD_KEY_PASSWORD",
    "NOVATUBE_UPLOAD_KEY_ALIAS",
)


def prepare(check_only: bool) -> None:
    # Les erreurs nomment les secrets absents, jamais leur contenu.
    missing = [name for name in SECRET_NAMES if not os.environ.get(name)]
    require(not missing, "Secrets NOVATUBE absents : " + ", ".join(missing))
    require(os.environ["NOVATUBE_UPLOAD_KEY_ALIAS"] == KEY_ALIAS, "Alias de signature NOVATUBE incorrect")
    _, expected = expected_certificate()
    if check_only:
        return
    path = Path(os.environ["NOVATUBE_KEYSTORE_PATH"]).resolve()
    require(REPO_ROOT not in path.parents, "La clé doit être créée hors du checkout Git")
    require(not path.exists(), "Un keystore existe déjà au chemin temporaire prévu")
    # Création exclusive et mode 0600 dès l'ouverture, avant le premier octet.
    value = base64.b64decode("".join(os.environ[SECRET_NAMES[0]].split()), validate=True)
    require(512 <= len(value) <= 32768, "Taille de keystore NOVATUBE inattendue")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(value)
        result = subprocess.run(
            ["keytool", "-exportcert", "-keystore", str(path), "-alias", KEY_ALIAS,
             "-storepass:env", "NOVATUBE_UPLOAD_STORE_PASSWORD"],
            capture_output=True,
            check=False,
        )
        # stderr reste privé : certains outils réimpriment leurs arguments.
        require(result.returncode == 0, "Lecture du certificat NOVATUBE impossible")
        require(hashlib.sha256(result.stdout).hexdigest() == expected,
                "La clé des secrets ne correspond pas au certificat NOVATUBE validé")
    except BaseException:
        path.unlink(missing_ok=True)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    try:
        prepare(args.check_only)
        print("Secrets NOVATUBE présents." if args.check_only else "Clé NOVATUBE chargée et certificat vérifié.")
    except (OSError, ValueError, KeyError):
        # Aucun traceback, objet d'exception ou contenu de secret en sortie.
        print("Échec du contrôle de signature NOVATUBE ; aucune clé alternative utilisée.", file=sys.stderr)
        raise SystemExit(1)
