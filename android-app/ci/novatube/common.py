#!/usr/bin/env python3
"""Identité publique et petits contrôles communs de la livraison NOVATUBE."""

from __future__ import annotations

import base64
import hashlib
import json
from pathlib import Path
import re


PACKAGE = "com.sevenmotion.novatube"
LABEL = "NOVATUBE"
VERSION_NAME = "0.1.5"
VERSION_CODE = "5"
KEY_ALIAS = "novatube-upload"
BRANCH = "feature/novatube-play-aab"
BASE_TAG = "zuno-mobile-0.1.5-test"
BASE_COMMIT = "93d367e501905e0bd2478d021013d93e43b5794b"
ENTRYPOINT = "lib/main_zuno_mobile.dart"
ANDROID = "{http://schemas.android.com/apk/res/android}"
APP_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = APP_ROOT.parent
PUBLIC_CERT = Path(__file__).with_name("novatube-upload-cert.pem")
FINGERPRINT = Path(__file__).with_name("fingerprint.json")
# Cette somme provient de l'asset officiel Google (release 1.18.2), pas
# d'une copie tierce. Le vérificateur refuse un JAR différent.
BUNDLETOOL_VERSION = "1.18.2"
BUNDLETOOL_SHA256 = "378b5434cd1378bef6b2bc527b8c7f0ff2584b273830335bce54d6d0813c8584"


def require(condition: bool, message: str) -> None:
    """Ne pas utiliser assert : python -O ne doit pas enlever ces barrières."""
    if not condition:
        raise ValueError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pem_certificates(text: str) -> list[bytes]:
    certificates = re.findall(
        r"-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+?)\s*-----END CERTIFICATE-----",
        text,
    )
    return [base64.b64decode(re.sub(r"\s+", "", cert), validate=True) for cert in certificates]


def expected_certificate() -> tuple[bytes, str]:
    """Le certificat public doit correspondre à l'empreinte revue dans Git."""
    metadata = json.loads(FINGERPRINT.read_text(encoding="utf-8"))
    require(metadata.get("package") == PACKAGE, "Identité du certificat inattendue")
    require(metadata.get("alias") == KEY_ALIAS, "Alias NOVATUBE inattendu")
    digest = str(metadata.get("sha256", "")).lower()
    require(re.fullmatch(r"[0-9a-f]{64}", digest) is not None, "Empreinte publique SHA-256 invalide")
    certs = pem_certificates(PUBLIC_CERT.read_text(encoding="ascii"))
    require(len(certs) == 1, "Un seul certificat public NOVATUBE est attendu")
    require(hashlib.sha256(certs[0]).hexdigest() == digest, "Certificat et empreinte publique différents")
    return certs[0], digest
