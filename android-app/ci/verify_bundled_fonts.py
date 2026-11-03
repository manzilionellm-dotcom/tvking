#!/usr/bin/env python3
"""Vérifie les fontes livrées, sans réseau ni dépendance Python externe.

Sans argument : contrôle les fichiers du dépôt. Avec --apk : contrôle aussi
les mêmes octets dans l'archive compilée. Ce contrôle d'assets ne remplace ni
la vérification du certificat ni les vrais tests de démarrage Android.
"""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
from zipfile import BadZipFile, ZipFile


APP_ROOT = Path(__file__).resolve().parents[1]
MANIFEST = "assets/fonts/provenance.json"
PACKAGE_SHA = "ba03d03bcaa2f6cb7bd920e3b5027181db75ab524f8891c8bc3aa603885b8055"
VARIANTS = {
    "Inter": {400, 500, 600, 700, 800},
    "Oswald": {500, 600},
    "JetBrainsMono": {400, 600},
    "BricolageGrotesque": {700, 800},
    "Manrope": {500, 700, 800},
}
WEIGHTS = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold", 800: "ExtraBold"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def checked_records(manifest):
    require(manifest.get("schema_version") == 1, "Version de provenance inconnue")
    package = manifest["google_fonts"]
    require(package["version"] == "6.3.3", "Le catalogue doit rester google_fonts 6.3.3")
    require(package["archive_sha256"] == PACKAGE_SHA, "Archive du catalogue différente")
    require(
        package["archive_url"] == "https://pub.dev/api/archives/google_fonts-6.3.3.tar.gz",
        "Source du catalogue différente",
    )
    fonts, licenses = manifest["fonts"], manifest["licenses"]
    expected = {(family, weight) for family, weights in VARIANTS.items() for weight in weights}
    actual = {(font["family"], font["weight"]) for font in fonts}
    require(actual == expected and len(fonts) == 14, "Inventaire des 14 variantes incomplet")
    require(
        {license["family"] for license in licenses} == set(VARIANTS) and len(licenses) == 5,
        "Inventaire des cinq licences incomplet",
    )
    for font in fonts:
        require(font["style"] == "normal", "Style inattendu")
        filename = f'{font["family"]}-{WEIGHTS[font["weight"]]}.ttf'
        require(font["asset"] == f"assets/fonts/{filename}", "Nom non reconnu par google_fonts")
        require(
            font["url"] == f'https://fonts.gstatic.com/s/a/{font["sha256"]}.ttf',
            f"Source non figée : {filename}",
        )
    for license in licenses:
        require(
            license["asset"] == f'assets/fonts/licenses/{license["family"]}-OFL.txt',
            "Chemin de licence inattendu",
        )
        commit = license["repository_commit"]
        require(re.fullmatch(r"[0-9a-f]{40}", commit) is not None, "Licence non versionnée")
        require(
            license["url"].startswith(f"https://raw.githubusercontent.com/google/fonts/{commit}/"),
            "Source de licence non figée",
        )
    records = fonts + licenses
    paths = [record["asset"] for record in records]
    require(len(paths) == len(set(paths)), "Asset déclaré plusieurs fois")
    for record in records:
        path = PurePosixPath(record["asset"])
        require(not path.is_absolute() and ".." not in path.parts, "Chemin d'asset invalide")
        require(re.fullmatch(r"[0-9a-f]{64}", record["sha256"]) is not None, "SHA-256 invalide")
        require(isinstance(record["bytes"], int) and record["bytes"] > 0, "Taille d'asset invalide")
    return records


def verify_bytes(data, record):
    name = record["asset"]
    require(len(data) == record["bytes"], f"Taille différente : {name}")
    require(hashlib.sha256(data).hexdigest() == record["sha256"], f"SHA-256 différent : {name}")
    if name.endswith(".ttf"):
        require(data.startswith(b"\x00\x01\x00\x00"), f"Fonte TrueType invalide : {name}")
    else:
        require(b"SIL OPEN FONT LICENSE Version 1.1" in data, f"Licence OFL manquante : {name}")


def verify(root=APP_ROOT, apk=None):
    root = Path(root)
    manifest_bytes = (root / MANIFEST).read_bytes()
    manifest = json.loads(manifest_bytes)
    records = checked_records(manifest)
    pubspec = (root / "pubspec.yaml").read_text()
    require(re.search(r"(?m)^  google_fonts: 6\.3\.3$", pubspec) is not None, "google_fonts non fixé")
    for directory in ("assets/fonts/", "assets/fonts/licenses/"):
        require(f"    - {directory}\n" in pubspec, f"Assets absents du pubspec : {directory}")
    for record in records:
        verify_bytes((root / record["asset"]).read_bytes(), record)
    if apk is not None:
        with ZipFile(apk) as archive:
            names = archive.namelist()
            for asset in [MANIFEST] + [record["asset"] for record in records]:
                name = f"assets/flutter_assets/{asset}"
                require(names.count(name) == 1, f"Asset APK absent ou dupliqué : {asset}")
            require(
                archive.read(f"assets/flutter_assets/{MANIFEST}") == manifest_bytes,
                "Provenance APK différente de la source inspectée",
            )
            for record in records:
                verify_bytes(archive.read(f'assets/flutter_assets/{record["asset"]}'), record)
    return {
        "fonts": len(manifest["fonts"]),
        "font_bytes": sum(font["bytes"] for font in manifest["fonts"]),
        "licenses": len(manifest["licenses"]),
        "provenance_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "apk_assets_verified": apk is not None,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, help="APK exact à inspecter, après compilation/signature")
    args = parser.parse_args()
    try:
        result = verify(apk=args.apk)
    except (ValueError, KeyError, OSError, BadZipFile) as error:
        parser.exit(1, f"Échec polices embarquées : {error}\n")
    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
