#!/usr/bin/env python3
"""Compare l'APK public de référence, sa reconstruction et l'APK issu de l'AAB.

Trois fichiers sont lus, aucun n'est modifié :

* ``--reference``  : les octets réellement servis par https://zuno8k.com/mobile.apk ;
* ``--rebuilt``    : l'APK recompilé depuis le même commit avec les paramètres
  du build d'origine (preuve de reproductibilité) ;
* ``--play``       : l'APK universel produit par bundletool à partir de l'AAB
  Google Play (ce que le bundle installe réellement).

Le rapport distingue ce qui est IDENTIQUE, ce qui diffère PAR NÉCESSITÉ pour
Google Play (permission d'installation retirée, minSdk 24, drapeau
PLAY_BUILD compilé dans libapp.so) et ce qui serait INATTENDU. Seul
l'inattendu fait échouer le contrôle : il ne valide jamais un écart en
silence, et il n'invente aucune identité que les octets ne montrent pas.

Dépendances : bibliothèque standard Python, ``aapt2`` et ``apksigner`` du SDK
Android. Aucune clé, aucun secret, aucun accès réseau.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from zipfile import ZipFile

INSTALL_PERMISSION = "android.permission.REQUEST_INSTALL_PACKAGES"
COMPONENT_TAGS = ("activity", "activity-alias", "service", "receiver", "provider")
# Balises ajoutées par bundletool à tout APK qu'il fabrique : elles décrivent
# le découpage du bundle, pas l'application.
BUNDLETOOL_METADATA = re.compile(
    r"com\.android\.(vending\.(splits|derived\.apk\.id)|stamp\.(source|type)|"
    r"dynamic\.apk\.fused\.modules)")
# Attribut de conditionnement : bundletool stocke les bibliothèques natives non
# compressées dès Android 6, AGP les extrait quand minSdk < 23. Ce n'est pas
# une différence de l'application ; elle est rapportée, jamais masquée.
PACKAGING_ATTRIBUTES = {"extractNativeLibs"}
MARKERS_DEX = {
    "media3": b"Landroidx/media3/",
    "google_cast": b"Lcom/google/android/gms/cast/",
    "flutter_embedding": b"Lio/flutter/embedding/",
}


def run(*command: str) -> str:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"{Path(command[0]).name} a échoué ({result.returncode}) : "
                           f"{result.stderr.strip()[:400]}")
    return result.stdout


def file_identity(path: Path) -> dict:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return {"file": path.name, "size": path.stat().st_size, "sha256": digest.hexdigest()}


def zip_entries(path: Path) -> dict:
    with ZipFile(path) as archive:
        return {info.filename: (info.CRC, info.file_size) for info in archive.infolist()
                if not info.is_dir()}


def category(name: str) -> str:
    if name == "AndroidManifest.xml":
        return "manifeste"
    if re.fullmatch(r"classes\d*\.dex", name):
        return "dex"
    if name.startswith("lib/"):
        return "natif"
    if name.startswith("assets/"):
        return "assets"
    if name.startswith("res/") or name == "resources.arsc":
        return "ressources"
    if name.startswith("META-INF/"):
        return "meta-inf"
    return "autre"


def compare_entries(left: dict, right: dict) -> dict:
    by_category: dict = {}
    for name in sorted(set(left) | set(right)):
        bucket = by_category.setdefault(category(name), {
            "identiques": 0, "differents": [], "seulement_reference": [], "seulement_autre": []})
        if name not in right:
            bucket["seulement_reference"].append(name)
        elif name not in left:
            bucket["seulement_autre"].append(name)
        elif left[name] == right[name]:
            bucket["identiques"] += 1
        else:
            bucket["differents"].append(name)
    return by_category


def parse_badging(text: str) -> dict:
    def one(pattern: str):
        match = re.search(pattern, text, re.M)
        return match.group(1) if match else None

    package = re.search(
        r"^package: name='([^']*)' versionCode='([^']*)' versionName='([^']*)'", text, re.M)
    if package is None:
        raise ValueError("Métadonnées aapt2 absentes : ce fichier n'est pas un APK lisible.")
    native = re.search(r"^native-code:(.*)$", text, re.M)
    return {
        "package": package.group(1),
        "versionCode": package.group(2),
        "versionName": package.group(3),
        "minSdk": one(r"^(?:sdkVersion|minSdkVersion):'([^']*)'"),
        "targetSdk": one(r"^targetSdkVersion:'([^']*)'"),
        "compileSdk": one(r"compileSdkVersion='([^']*)'"),
        "label": one(r"^application-label:'([^']*)'"),
        "launchable": one(r"^launchable-activity: name='([^']*)'"),
        "leanbackLaunchable": one(r"^leanback-launchable-activity: name='([^']*)'"),
        "abis": sorted(re.findall(r"'([^']+)'", native.group(1))) if native else [],
        "permissions": sorted(set(re.findall(
            r"^uses-permission(?:-sdk-23)?: name='([^']*)'", text, re.M))),
        "features": sorted(set(re.findall(r"^\s*uses-feature: name='([^']*)'", text, re.M))),
        "featuresNotRequired": sorted(set(re.findall(
            r"^\s*uses-feature-not-required: name='([^']*)'", text, re.M))),
    }


def parse_xmltree(text: str) -> dict:
    """Lit ``aapt2 dump xmltree`` : composants, permissions et balises nommées."""
    elements = []  # (indentation, balise, attributs)
    current = None
    for line in text.splitlines():
        element = re.match(r"^(\s*)E: (\S+)", line)
        if element:
            current = (len(element.group(1)), element.group(2), {})
            elements.append(current)
            continue
        attribute = re.match(
            r'^\s*A: (?:[a-z]+://[^\s="]+:|[A-Za-z_][\w.-]*:)?([A-Za-z0-9_.]+)'
            r'(?:\(0x[0-9a-fA-F]+\))?=(.*)$', line)
        if attribute and current is not None:
            raw = re.search(r'\(Raw: "(.*)"\)\s*$', attribute.group(2))
            quoted = re.match(r'^"(.*?)"', attribute.group(2))
            value = raw.group(1) if raw else quoted.group(1) if quoted else attribute.group(2).strip()
            # Un identifiant de ressource dépend de la compilation, pas du code.
            if re.fullmatch(r"@0x[0-9a-fA-F]+", value):
                value = "@ressource"
            current[2].setdefault(attribute.group(1), value)
    result = {tag: [] for tag in COMPONENT_TAGS}
    result.update({"uses-permission": [], "uses-feature": [], "meta-data": [],
                   "uses-library": [], "categories": [], "application": {}, "main-activity": {}})
    for _, tag, attributes in elements:
        name = attributes.get("name", "")
        if tag in COMPONENT_TAGS:
            result[tag].append(name)
            if tag == "activity" and name.endswith("MainActivity"):
                result["main-activity"] = {
                    key: attributes[key] for key in sorted(attributes)
                    if key in {"screenOrientation", "supportsPictureInPicture", "resizeableActivity",
                               "launchMode", "exported", "hardwareAccelerated", "configChanges"}}
        elif tag in {"uses-permission", "uses-permission-sdk-23"}:
            result["uses-permission"].append(name)
        elif tag == "uses-feature":
            result["uses-feature"].append(f"{name}={attributes.get('required', 'true')}")
        elif tag == "meta-data":
            result["meta-data"].append(
                f"{name}={attributes.get('value', attributes.get('resource', ''))}")
        elif tag == "uses-library":
            result["uses-library"].append(name)
        elif tag == "category":
            result["categories"].append(name)
        elif tag == "application":
            result["application"] = {
                key: attributes[key] for key in sorted(attributes)
                if key in {"largeHeap", "usesCleartextTraffic", "allowBackup", "banner",
                           "networkSecurityConfig", "name", "extractNativeLibs"}}
    for key, value in result.items():
        if isinstance(value, list):
            result[key] = sorted(set(value))
    return result


def parse_signature(text: str) -> dict:
    certificates = re.findall(
        r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})$", text, re.M)
    schemes = {}
    for version in ("v1", "v2", "v3", "v3.1", "v4"):
        match = re.search(rf"^Verified using {re.escape(version)} scheme[^:]*: (true|false)$",
                          text, re.M)
        if match:
            schemes[version] = match.group(1) == "true"
    return {"verifies": bool(re.search(r"^Verifies$", text, re.M)),
            "certificates": [c.lower() for c in certificates], "schemes": schemes}


def scan_markers(path: Path, source_sha: str, backend: str) -> dict:
    found = {"sourceShaInLibapp": {}, "backendInLibapp": {}, "dex": {},
             "flutterEngine": {}}
    with ZipFile(path) as archive:
        names = archive.namelist()
        dex = b"".join(archive.read(n) for n in names if re.fullmatch(r"classes\d*\.dex", n))
        for label, needle in MARKERS_DEX.items():
            found["dex"][label] = needle in dex
        for abi in sorted({n.split("/")[1] for n in names if n.startswith("lib/")}):
            found["flutterEngine"][abi] = f"lib/{abi}/libflutter.so" in names
            application = f"lib/{abi}/libapp.so"
            if application in names:
                data = archive.read(application)
                found["sourceShaInLibapp"][abi] = source_sha.encode() in data
                found["backendInLibapp"][abi] = backend.encode() in data
            else:
                found["sourceShaInLibapp"][abi] = False
                found["backendInLibapp"][abi] = False
    return found


def describe(path: Path, aapt2: str, apksigner: str, source_sha: str, backend: str) -> dict:
    tree_text = run(aapt2, "dump", "xmltree", "--file", "AndroidManifest.xml", str(path))
    return {
        "identity": file_identity(path),
        "badging": parse_badging(run(aapt2, "dump", "badging", str(path))),
        "manifest": parse_xmltree(tree_text),
        "signature": parse_signature(
            run(apksigner, "verify", "--verbose", "--print-certs", str(path))),
        "markers": scan_markers(path, source_sha, backend),
        "entries": zip_entries(path),
    }


def set_difference(reference: list, other: list) -> dict:
    return {"retire": sorted(set(reference) - set(other)),
            "ajoute": sorted(set(other) - set(reference))}


def evaluate(reference: dict, rebuilt: dict, play: dict, expected: dict) -> dict:
    """Retourne les constats ; ``echecs`` liste uniquement l'inattendu."""
    failures: list = []
    notes: list = []

    def require(condition: bool, message: str) -> None:
        if not condition:
            failures.append(message)

    ref_b, play_b, rebuilt_b = reference["badging"], play["badging"], rebuilt["badging"]

    # 1. La référence est bien le fichier annoncé.
    require(reference["identity"]["sha256"] == expected["reference_sha256"],
            "SHA-256 de l'APK public différent de la valeur attendue : la référence a changé.")
    require(reference["identity"]["size"] == expected["reference_size"],
            "Taille de l'APK public différente de la valeur attendue.")
    require(ref_b["package"] == expected["package"], "Package de l'APK public inattendu.")
    require(ref_b["versionName"] == expected["version_name"],
            "versionName de l'APK public inattendu.")
    require(ref_b["versionCode"] == expected["reference_version_code"],
            "versionCode de l'APK public inattendu.")
    require(reference["signature"]["verifies"] and
            reference["signature"]["certificates"] == [expected["certificate"]],
            "Certificat de l'APK public inattendu ou signature invalide.")
    for abi, present in reference["markers"]["sourceShaInLibapp"].items():
        require(present, f"Commit source absent de libapp.so ({abi}) dans l'APK public.")

    # 2. L'édition Play garde l'identité et ne change que le nécessaire.
    require(play_b["package"] == ref_b["package"], "Package différent entre APK public et AAB.")
    require(play_b["versionName"] == ref_b["versionName"],
            "versionName différent entre APK public et AAB.")
    require(play_b["versionCode"] == expected["play_version_code"],
            "versionCode de l'AAB différent de la valeur prévue.")
    require(play_b["label"] == ref_b["label"], "Nom affiché différent entre APK public et AAB.")
    require(play_b["targetSdk"] == ref_b["targetSdk"], "targetSdk différent.")
    require(play_b["minSdk"] == expected["play_min_sdk"], "minSdk de l'AAB inattendu.")
    require(play_b["abis"] == ref_b["abis"], "Architectures ABI différentes.")
    require(play_b["launchable"] == ref_b["launchable"] and
            play_b["leanbackLaunchable"] == ref_b["leanbackLaunchable"],
            "Activité de lancement différente.")
    require(play["signature"]["verifies"] and
            play["signature"]["certificates"] == [expected["certificate"]],
            "L'APK issu de l'AAB n'est pas signé avec la clé d'import attendue.")

    permissions = set_difference(reference["manifest"]["uses-permission"],
                                 play["manifest"]["uses-permission"])
    require(set(permissions["retire"]) <= {INSTALL_PERMISSION} and not permissions["ajoute"],
            f"Écart de permissions inattendu : {permissions}")
    require(INSTALL_PERMISSION not in play["manifest"]["uses-permission"],
            "REQUEST_INSTALL_PACKAGES encore présente dans l'édition Play.")

    components = {}
    for tag in COMPONENT_TAGS:
        components[tag] = set_difference(reference["manifest"][tag], play["manifest"][tag])
        require(not components[tag]["retire"] and not components[tag]["ajoute"],
                f"Composants <{tag}> différents : {components[tag]}")
    features = set_difference(reference["manifest"]["uses-feature"],
                              play["manifest"]["uses-feature"])
    require(not features["retire"] and not features["ajoute"],
            f"Fonctionnalités matérielles déclarées différentes : {features}")
    metadata = set_difference(reference["manifest"]["meta-data"], play["manifest"]["meta-data"])
    metadata_unexpected = {
        "retire": metadata["retire"],
        "ajoute": [m for m in metadata["ajoute"]
                   if not BUNDLETOOL_METADATA.match(m.split("=", 1)[0])]}
    require(not metadata_unexpected["retire"] and not metadata_unexpected["ajoute"],
            f"Balises meta-data différentes : {metadata_unexpected}")
    def without_packaging(attributes: dict) -> dict:
        return {k: v for k, v in attributes.items() if k not in PACKAGING_ATTRIBUTES}

    require(without_packaging(reference["manifest"]["application"]) ==
            without_packaging(play["manifest"]["application"]),
            "Attributs <application> différents.")
    packaging = {name: {"apkPublic": reference["manifest"]["application"].get(name),
                        "editionPlay": play["manifest"]["application"].get(name)}
                 for name in sorted(PACKAGING_ATTRIBUTES)}
    for name, values in packaging.items():
        if values["apkPublic"] != values["editionPlay"]:
            notes.append(f"Conditionnement : android:{name} vaut {values['apkPublic']} dans "
                         f"l'APK public et {values['editionPlay']} dans l'édition Play "
                         "(écart attendu d'un bundle minSdk 24).")
    require((play_b["targetSdk"] or "").isdigit() and int(play_b["targetSdk"]) >= 36,
            "targetSdk inférieur à 36 : refusé par l'exigence d'API cible de Google Play.")
    require(reference["manifest"]["main-activity"] == play["manifest"]["main-activity"],
            "Attributs de MainActivity différents.")
    require(reference["manifest"]["categories"] == play["manifest"]["categories"],
            "Catégories d'intention différentes.")

    for label in MARKERS_DEX:
        require(play["markers"]["dex"][label] == reference["markers"]["dex"][label],
                f"Présence de {label} différente dans le DEX.")
    for abi in ref_b["abis"]:
        require(play["markers"]["flutterEngine"].get(abi, False),
                f"libflutter.so absent pour {abi} dans l'édition Play.")
        require(play["markers"]["sourceShaInLibapp"].get(abi, False),
                f"Commit source absent de libapp.so ({abi}) dans l'édition Play.")
        require(play["markers"]["backendInLibapp"].get(abi, False) ==
                reference["markers"]["backendInLibapp"].get(abi, False),
                f"Backend compilé différent ({abi}).")

    play_diff = compare_entries(reference["entries"], play["entries"])
    native = play_diff.get("natif", {})
    unexpected_native = [n for n in native.get("differents", []) if not n.endswith("/libapp.so")]
    if unexpected_native:
        notes.append("Bibliothèques natives différentes hors libapp.so (à examiner) : "
                     + ", ".join(unexpected_native))
    require(not native.get("seulement_reference") and not native.get("seulement_autre"),
            "Jeu de bibliothèques natives différent.")
    assets = play_diff.get("assets", {})
    if assets.get("differents") or assets.get("seulement_reference") or assets.get("seulement_autre"):
        notes.append("Écarts dans assets/ (à examiner) : "
                     + json.dumps({k: v for k, v in assets.items() if k != "identiques"},
                                  ensure_ascii=False))

    # 3. Reconstruction : informative, elle mesure la reproductibilité.
    rebuilt_diff = compare_entries(reference["entries"], rebuilt["entries"])
    byte_identical = reference["identity"]["sha256"] == rebuilt["identity"]["sha256"]
    require(rebuilt_b["package"] == ref_b["package"] and
            rebuilt_b["versionCode"] == ref_b["versionCode"] and
            rebuilt_b["versionName"] == ref_b["versionName"] and
            rebuilt_b["minSdk"] == ref_b["minSdk"],
            "La reconstruction n'a pas l'identité de l'APK public.")
    require(reference["manifest"] == rebuilt["manifest"],
            "Le manifeste reconstruit diffère de celui de l'APK public : "
            "le commit ou la recette ne sont pas ceux de la référence.")

    return {
        "echecs": failures, "notes": notes,
        "reconstruction": {"octetsIdentiques": byte_identical, "parCategorie": rebuilt_diff},
        "editionPlay": {"parCategorie": play_diff, "permissions": permissions,
                        "composants": components, "features": features, "metaData": metadata,
                        "conditionnement": packaging},
    }


def table_row(label: str, *cells) -> str:
    return "| " + " | ".join([label, *[str(c) if c not in (None, "") else "—" for c in cells]]) + " |"


def render(reference: dict, rebuilt: dict, play: dict, verdict: dict, expected: dict) -> str:
    ref_b, rebuilt_b, play_b = reference["badging"], rebuilt["badging"], play["badging"]
    lines = ["# ZUNO 116 — APK public, reconstruction et édition Google Play", "",
             f"Référence : `{expected['reference_url']}` · commit `{expected['source_sha']}`.", "",
             "| Champ | APK public | Reconstruction | Édition Play (APK issu de l'AAB) |",
             "|---|---|---|---|"]
    for label, key in [("Package", "package"), ("versionName", "versionName"),
                       ("versionCode", "versionCode"), ("minSdk", "minSdk"),
                       ("targetSdk", "targetSdk"), ("Nom affiché", "label")]:
        lines.append(table_row(label, ref_b[key], rebuilt_b[key], play_b[key]))
    lines.append(table_row("ABI", *[", ".join(x["abis"]) for x in (ref_b, rebuilt_b, play_b)]))
    lines.append(table_row("Certificat SHA-256", *[
        ", ".join(x["signature"]["certificates"]) for x in (reference, rebuilt, play)]))
    lines.append(table_row("Schémas de signature", *[
        ", ".join(k for k, v in x["signature"]["schemes"].items() if v)
        for x in (reference, rebuilt, play)]))
    lines.append(table_row("Taille (octets)", *[
        x["identity"]["size"] for x in (reference, rebuilt, play)]))
    lines.append(table_row("SHA-256", *[
        x["identity"]["sha256"] for x in (reference, rebuilt, play)]))
    lines += ["", "## Reconstruction de l'APK public", ""]
    if verdict["reconstruction"]["octetsIdentiques"]:
        lines.append("La reconstruction est **identique octet pour octet** à l'APK public.")
    else:
        lines.append("La reconstruction n'est pas identique octet pour octet ; détail par famille "
                     "de fichiers (CRC et taille de chaque entrée) :")
    lines += ["", "| Famille | Identiques | Différents | Seulement public | Seulement reconstruit |",
              "|---|---|---|---|---|"]
    for name, bucket in sorted(verdict["reconstruction"]["parCategorie"].items()):
        lines.append(table_row(name, bucket["identiques"], len(bucket["differents"]),
                               len(bucket["seulement_reference"]), len(bucket["seulement_autre"])))
    lines += ["", "## Édition Google Play comparée à l'APK public", "",
              "| Famille | Identiques | Différents | Seulement public | Seulement Play |",
              "|---|---|---|---|---|"]
    for name, bucket in sorted(verdict["editionPlay"]["parCategorie"].items()):
        lines.append(table_row(name, bucket["identiques"], len(bucket["differents"]),
                               len(bucket["seulement_reference"]), len(bucket["seulement_autre"])))
    play_v = verdict["editionPlay"]
    lines += ["", f"Permissions retirées : {', '.join(play_v['permissions']['retire']) or 'aucune'} ; "
              f"ajoutées : {', '.join(play_v['permissions']['ajoute']) or 'aucune'}.",
              f"Balises meta-data ajoutées : {', '.join(play_v['metaData']['ajoute']) or 'aucune'} ; "
              f"retirées : {', '.join(play_v['metaData']['retire']) or 'aucune'}.",
              "Activités, services, récepteurs et fournisseurs : "
              + ("identiques." if all(not d["retire"] and not d["ajoute"]
                                      for d in play_v["composants"].values())
                 else "DIFFÉRENTS (voir comparison.json)."), ""]
    lines += ["## Marqueurs relus dans les binaires", "",
              "| Marqueur | APK public | Reconstruction | Édition Play |", "|---|---|---|---|"]
    for label in MARKERS_DEX:
        lines.append(table_row(f"DEX {label}", *[
            "oui" if x["markers"]["dex"][label] else "non" for x in (reference, rebuilt, play)]))
    for key, label in [("sourceShaInLibapp", "Commit source dans libapp.so"),
                       ("backendInLibapp", "Backend dans libapp.so"),
                       ("flutterEngine", "libflutter.so")]:
        lines.append(table_row(label, *[
            ", ".join(f"{abi}:{'oui' if ok else 'non'}" for abi, ok in x["markers"][key].items())
            for x in (reference, rebuilt, play)]))
    lines += ["", "## Verdict", ""]
    if verdict["echecs"]:
        lines.append("**ÉCHEC — écarts inattendus :**")
        lines += [f"- {item}" for item in verdict["echecs"]]
    else:
        lines.append("Aucun écart inattendu : l'édition Play ne diffère de l'APK public que par "
                     "la permission d'installation retirée, le minSdk et le code Dart compilé "
                     "avec PLAY_BUILD.")
    if verdict["notes"]:
        lines += ["", "À examiner (non bloquant) :"] + [f"- {item}" for item in verdict["notes"]]
    lines += ["", "Ce rapport compare des fichiers. Il ne prouve ni la lecture d'un flux, ni le "
              "Cast, ni le comportement sur un appareil physique.", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    for name in ("reference", "rebuilt", "play", "out"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    for name in ("aapt2", "apksigner", "reference-url", "reference-sha256", "package",
                 "version-name", "reference-version-code", "play-version-code",
                 "certificate", "source-sha"):
        parser.add_argument(f"--{name}", required=True)
    parser.add_argument("--reference-size", type=int, required=True)
    parser.add_argument("--play-min-sdk", default="24")
    parser.add_argument("--backend", default="https://api.zuno8k.com")
    args = parser.parse_args()
    expected = {key: getattr(args, key) for key in (
        "reference_url", "reference_sha256", "reference_size", "package", "version_name",
        "reference_version_code", "play_version_code", "certificate", "source_sha",
        "play_min_sdk")}
    described = [describe(path, args.aapt2, args.apksigner, args.source_sha, args.backend)
                 for path in (args.reference, args.rebuilt, args.play)]
    verdict = evaluate(*described, expected)
    args.out.mkdir(parents=True, exist_ok=True)
    report = {"attendu": expected, "verdict": verdict}
    for label, item in zip(("reference", "reconstruction", "editionPlay"), described):
        report[label] = {key: value for key, value in item.items() if key != "entries"}
    (args.out / "comparison.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.out / "comparison.md").write_text(
        render(*described, verdict, expected), encoding="utf-8")
    print((args.out / "comparison.md").read_text(encoding="utf-8"))
    return 1 if verdict["echecs"] else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, OSError) as error:
        raise SystemExit(f"Comparaison impossible : {error}")
