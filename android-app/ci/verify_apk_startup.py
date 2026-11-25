#!/usr/bin/env python3
"""Relie le vrai démarrage Android aux octets signés du même build Actions."""

import hashlib
from io import BytesIO
import json
import os
from pathlib import Path
import re
import runpy
import struct
import sys
from xml.etree import ElementTree
from zipfile import BadZipFile, ZipFile


PACKAGE = "com.sevenmotion.tv.seven_tv"
CLIENT_CERT = "5145b8e019f6d5fb96a207f2e73673fd954f799966fd598889211556cbdf9e61"
# Même contrôle complet des PNG que la preuve GPU : CRC, zlib et lignes.
verify_png = runpy.run_path(str(Path(__file__).with_name("verify-ai-picture-results.py")))["verify_png"]


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def expected_identity(environment):
    """Ces valeurs viennent de needs.build-tv, jamais d'une release mutable."""
    fields = {
        "sha256": "STARTUP_APK_SHA256",
        "size": "STARTUP_APK_SIZE",
        "versionName": "STARTUP_VERSION_NAME",
        "versionCode": "STARTUP_VERSION_CODE",
        "certificateSHA256": "STARTUP_APK_CERT",
        "buildCommit": "STARTUP_SOURCE_SHA",
        "buildRun": "GITHUB_RUN_ID",
        "buildAttempt": "STARTUP_BUILD_ATTEMPT",
        "artifactId": "STARTUP_ARTIFACT_ID",
        "artifactDigest": "STARTUP_ARTIFACT_DIGEST",
    }
    result = {"package": PACKAGE}
    for field, variable in fields.items():
        value = environment.get(variable, "")
        require(bool(value), f"Identité du build absente : {variable}")
        result[field] = value
    for field in ("size", "versionCode", "buildRun", "buildAttempt", "artifactId"):
        require(re.fullmatch(r"[1-9][0-9]*", result[field]) is not None,
                f"Identité numérique invalide : {field}")
        result[field] = int(result[field])
    require(re.fullmatch(r"[0-9a-f]{64}", result["sha256"]) is not None, "SHA-256 APK invalide.")
    require(re.fullmatch(r"[0-9a-f]{40}", result["buildCommit"]) is not None,
            "Commit source incomplet.")
    require(result["buildCommit"] == environment.get("SOURCE_SHA"),
            "Le build et le contrôle désignent deux commits différents.")
    require(re.fullmatch(r"[0-9]+(?:-test\.[0-9]+)?", result["versionName"]) is not None,
            "Version Zuno inattendue.")
    require(result["certificateSHA256"] == CLIENT_CERT,
            "Le build n'a pas la signature des box clientes.")
    digest = result["artifactDigest"].removeprefix("sha256:")
    require(re.fullmatch(r"[0-9a-f]{64}", digest) is not None,
            "Empreinte de l'artefact Actions absente ou invalide.")
    result["artifactDigest"] = f"sha256:{digest}"
    return result


def verify_bytes(path, digest, size):
    """Échoue aussi dans le publisher si les octets téléchargés ont changé."""
    require(re.fullmatch(r"[0-9a-f]{64}", digest) is not None, "SHA-256 APK absent ou invalide.")
    require(size > 0 and path.stat().st_size == size, "Taille APK différente du build.")
    with path.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha256").hexdigest()
    require(actual == digest, "Empreinte APK différente du build.")


def verify_archive(path, expected):
    verify_bytes(path, expected["sha256"], expected["size"])
    with ZipFile(path) as archive:
        require(archive.testzip() is None, "Archive APK corrompue.")
        for name in ("lib/x86_64/libapp.so", "lib/x86_64/libflutter.so"):
            require(name in archive.namelist(), f"ABI de test manquante : {name}")
    return dict(expected)


def verify_metadata(text, expected):
    match = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", text, re.M)
    require(match is not None, "Métadonnées aapt absentes.")
    require(match.groups() == (PACKAGE, str(expected["versionCode"]), expected["versionName"]),
            "Package ou version installable différents du build.")
    require(re.search(r"^sdkVersion:'21'$", text, re.M), "Le minSdk de la box n'est pas 21.")
    require(re.search(r"^leanback-launchable-activity:", text, re.M),
            "Activité Leanback absente de l'APK.")


def verify_signature(text, expected):
    # apksigner doit également sortir avec le code 0 dans le script Bash.
    certificates = re.findall(r"^Signer #[0-9]+ certificate SHA-256 digest: ([0-9a-f]{64})$",
                              text, re.M | re.I)
    require(re.search(r"^Verifies$", text, re.M) and
            len(certificates) == 1 and certificates[0].lower() == expected["certificateSHA256"],
            "L'APK téléchargé n'est pas vérifié avec la signature client attendue.")


def verify_samples(text):
    rows = [line.split("\t") for line in text.splitlines()]
    require(len(rows) == 15, "Les 30 secondes d'observation sont incomplètes.")
    require(all(len(row) == 3 and row[0] == str(index) and row[1].isdigit()
                and row[2] == "foreground" for index, row in enumerate(rows)),
            "Processus ou premier plan absent pendant l'observation.")
    require(len({row[1] for row in rows}) == 1, "Le processus a redémarré pendant l'observation.")


def app_labels(xml):
    root = ElementTree.fromstring(xml)
    return [node.get(key, "").strip() for node in root.iter("node")
            if node.get("package") == PACKAGE for key in ("text", "content-desc")
            if node.get(key, "").strip()]


def verify_capture(png, name):
    require(len(png) >= 33, "Capture PNG absente ou tronquée.")
    width, height = struct.unpack(">II", png[16:24])
    # Dimensions bornées avant la décompression ; la densité de l'AVD peut
    # modifier la capture, mais une image vide ou démesurée ne vaut pas preuve.
    require(100 <= width <= 4096 and 100 <= height <= 4096,
            "Capture de dimensions invalides.")
    verify_png(png, (width, height), name)


def verify_screen(xml, png, expected):
    verify_capture(png, "écran Zuno")
    labels = [label for label in app_labels(xml)
              if label.casefold() not in {"zuno", "zuno tv", expected["versionName"].casefold()}]
    require(bool(labels), "Aucun contenu Zuno lisible : splash, écran vide ou UI non vérifiée.")
    return {"labels": labels, "pixels": verify_visible_pixels(xml, png)}


def verify_visible_pixels(xml, png):
    """Un arbre accessible encore vivant ne valide pas une surface noire.

    Pillow sert seulement à décoder les pixels du PNG déjà vérifié, dans le
    venv de ce job CI. Le publisher (mode bytes) n'importe pas Pillow.
    """
    from PIL import Image, ImageDraw, ImageStat, __version__ as pillow_version

    root = ElementTree.fromstring(xml)
    nodes = list(root.iter("node"))

    def bounds(node):
        match = re.fullmatch(r"\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]", node.get("bounds", ""))
        return tuple(map(int, match.groups())) if match else None

    with Image.open(BytesIO(png)) as image:
        width, height = image.size
        windows = [bounds(node) for node in nodes if node.get("package") == PACKAGE]
        windows = [rect for rect in windows if rect is not None and
                   0 <= rect[0] < rect[2] <= width and 0 <= rect[1] < rect[3] <= height]
        require(bool(windows), "Limites de la fenêtre Zuno absentes.")
        left, top, right, bottom = max(windows, key=lambda rect: (rect[2] - rect[0]) * (rect[3] - rect[1]))
        # Intérieur de la fenêtre applicative : les bords de l'écran peuvent
        # encore contenir les barres Android, même en mode bord à bord.
        inset_x, inset_y = max(12, (right - left) // 10), max(12, (bottom - top) // 10)
        region = (left + inset_x, top + inset_y, right - inset_x, bottom - inset_y)
        require(region[2] - region[0] >= 32 and region[3] - region[1] >= 32,
                "Zone applicative trop petite pour contrôler les pixels.")
        opaque = Image.alpha_composite(Image.new("RGBA", image.size, (0, 0, 0, 255)),
                                       image.convert("RGBA")).convert("RGB")
        crop = opaque.crop(region)
        mask = Image.new("L", crop.size, 255)
        draw = ImageDraw.Draw(mask)
        # Si Android fournit une barre système dans la hiérarchie, ses pixels
        # sont exclus explicitement, même lorsqu'elle empiète sur cette marge.
        for node in nodes:
            rect = bounds(node)
            if node.get("package") == "com.android.systemui" and rect is not None:
                x0, y0 = max(rect[0], region[0]), max(rect[1], region[1])
                x1, y1 = min(rect[2], region[2]), min(rect[3], region[3])
                if x0 < x1 and y0 < y1:
                    draw.rectangle((x0 - region[0], y0 - region[1],
                                    x1 - region[0] - 1, y1 - region[1] - 1), fill=0)
        stats = ImageStat.Stat(crop, mask)
        require(stats.count[0] >= 1024, "Aucune zone Zuno suffisante hors interface système.")
        peak_range = max(high - low for low, high in stats.extrema)
        deviation = max(stats.stddev)
        # Seuils modestes : on refuse l'aplat et le bruit d'un pixel isolé,
        # sans noter le contraste ni la qualité d'une image vidéo.
        require(peak_range >= 16 and deviation >= 2,
                "Surface Zuno noire ou uniforme malgré ses libellés accessibles.")
        return {"region": list(region), "sampledPixels": stats.count[0],
                "peakRange": peak_range, "maximumStandardDeviation": round(deviation, 4),
                "decoder": f"Pillow {pillow_version}"}


def verify_quit_dialog(xml):
    # Sur l'activation vierge, Retour ouvre ce dialogue. Un simple am start
    # pendant qu'il est encore ouvert ne serait PAS une preuve de réouverture.
    labels = {label.casefold() for label in app_labels(xml)}
    require(any(words <= labels for words in (
        {"stay", "restart", "exit"}, {"continuer", "redémarrer", "quitter"},
    )), "La boîte de sortie Zuno n'est pas présente : aucune action à l'aveugle.")


def verify_background(text):
    resumed = [line for line in text.splitlines()
               if re.search(r"mResumedActivity|topResumedActivity", line)]
    require(any(re.search(r"\bActivityRecord\{[^}\n]*\b[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+", line)
                for line in resumed) and all(f"{PACKAGE}/" not in line for line in resumed),
            "Zuno n'a pas quitté le premier plan avant sa réouverture.")


def verify_crashes(crash, logcat):
    require(PACKAGE not in crash, "Un crash du processus Zuno figure dans le tampon Android.")
    for line in logcat.splitlines():
        if PACKAGE in line:
            require(not re.search(r"ANR in|am_anr|not responding|FATAL EXCEPTION", line, re.I),
                    "Crash ou ANR Zuno détecté.")


def verify_evidence(folder, expected):
    receipt = json.loads((folder / "apk-identity.json").read_text())
    require(receipt == expected, "La preuve ne désigne pas les octets du build attendu.")
    require((folder / "checker-sha.txt").read_text().strip() == expected["buildCommit"],
            "Le contrôle n'a pas extrait le même commit que le build.")
    verify_metadata((folder / "apk-badging.txt").read_text(), expected)
    verify_signature((folder / "signature.txt").read_text(), expected)
    installed = (folder / "installed-package.txt").read_text()
    require(re.search(rf"\bversionCode={expected['versionCode']}\b", installed) and
            re.search(rf"^\s*versionName={re.escape(expected['versionName'])}$", installed, re.M),
            "La version réellement installée ne correspond pas au build.")
    api = int((folder / "api.txt").read_text())
    require(api in {29, 35}, "API Android non prévue.")
    for name in ("connectivity.txt", "final-connectivity.txt"):
        require(re.search(r"Active default network: (none|null)", (folder / name).read_text()),
                "Le réseau de l'émulateur n'est pas isolé.")
    verify_crashes((folder / "crash.txt").read_text(), (folder / "logcat.txt").read_text())
    verify_quit_dialog((folder / "quit-dialog.xml").read_text())
    verify_capture((folder / "quit-dialog.png").read_bytes(), "boîte Quitter")
    verify_background((folder / "after-back.txt").read_text())
    verify_capture((folder / "after-back.png").read_bytes(), "après Quitter")
    phases = {}
    for phase in ("cold", "reopen"):
        directory = folder / phase
        verify_samples((directory / "samples.tsv").read_text())
        phases[phase] = {"observedSeconds": 30, **verify_screen(
            (directory / "ui.xml").read_text(), (directory / "screen.png").read_bytes(), expected)}
    return {"passed": True, "apk": receipt, "api": api, "abi": "x86_64", "network": "offline",
            "leftForegroundBeforeReopen": True, "phases": phases,
            "limits": ["Émulateur, aucun appareil client physique.",
                       "Pas de playlist, lecture fournisseur, panel en ligne ou Cast vérifié."]}


def main():
    mode = sys.argv[1]
    if mode == "bytes":
        # Ce contrôle d'intégrité est aussi valable pour la variante téléphone.
        # Il ne lui applique ni le package box ni le scénario de sortie TV.
        verify_bytes(Path(sys.argv[2]), sys.argv[3], int(sys.argv[4]))
        return
    expected = expected_identity(os.environ)
    if mode == "identity":
        return
    elif mode == "archive":
        receipt = verify_archive(Path(sys.argv[2]), expected)
        (Path(sys.argv[3]) / "apk-identity.json").write_text(json.dumps(receipt, indent=2) + "\n")
    elif mode == "metadata":
        folder = Path(sys.argv[2])
        verify_metadata((folder / "apk-badging.txt").read_text(), expected)
        verify_signature((folder / "signature.txt").read_text(), expected)
    elif mode == "quit-dialog":
        verify_quit_dialog(Path(sys.argv[2]).read_text())
    elif mode == "background":
        verify_background(Path(sys.argv[2]).read_text())
    elif mode == "evidence":
        folder = Path(sys.argv[2])
        result = verify_evidence(folder, expected)
        (folder / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        (folder / "summary.md").write_text(
            f"## Zuno {expected['versionName']} — démarrage API {result['api']} x86_64\n\n"
            "L'APK signé du même build a été installé et ouvert hors ligne. Le processus et son "
            "activité sont restés au premier plan 30 secondes au démarrage, puis 30 secondes après "
            "Retour, Quitter et réouverture. Les pixels de la fenêtre Zuno ne sont pas uniformes ; "
            "les barres système sont exclues de ce contrôle. Les captures et le contenu accessible sont joints ; "
            "aucun crash Zuno ni ANR détecté.\n\n"
            f"Build : {expected['buildRun']}, tentative {expected['buildAttempt']}. "
            f"Artefact : {expected['artifactId']}. Commit : {expected['buildCommit']}.\n\n"
            f"APK SHA-256 : {expected['sha256']}.\n\n"
            "Ce résultat ne valide pas une box physique, une playlist client, le panel en ligne ou le Cast.\n")
    else:
        raise ValueError("Vérification inconnue.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, BadZipFile, ElementTree.ParseError) as error:
        raise SystemExit(f"Échec du contrôle de démarrage : {error}")
