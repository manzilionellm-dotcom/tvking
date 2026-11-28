"""Vérifie deux ouvertures du binaire installé à partir des pixels de l'écran."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import time

from PIL import Image
from device_smoke import is_foreground, diagnostics
from display_capture import capture_png
from android_ui import visible_nodes
from zuno_ui_path import normalized

LABELS = {
    "home": {"live", "movies", "series", "guide", "server", "settings", "direct", "films", "serveur", "réglages"},
    "source": {"m3u", "xtream", "portal", "url", "playlist", "connect", "source", "liste", "portail"},
    "source_title": {"source", "sources", "add", "ajouter", "my", "ma", "own", "list", "liste"},
    "language": {"english", "français", "deutsch", "español", "italiano"},
}


def command(*args, timeout=25):
    return subprocess.check_output(args, stderr=subprocess.DEVNULL, timeout=timeout)


def screen_evidence(out, phase):
    data = capture_png()
    image = Image.open(io.BytesIO(data)).convert("RGB")
    # Le profil téléphone ancien a une sortie de 640×320. Reconnaître les
    # petits caractères à taille suffisante, sans modifier les pixels sources.
    scale = 2 if max(image.size) < 1300 else 1
    ocr_image = image.resize((image.width * scale, image.height * scale), Image.Resampling.LANCZOS)
    buffer = io.BytesIO()
    ocr_image.save(buffer, "PNG")
    tsv = subprocess.run(["tesseract", "stdin", "stdout", "--psm", "11", "tsv"],
                         input=buffer.getvalue(), env={**os.environ, "OMP_THREAD_LIMIT": "1"}, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                         timeout=25, check=True).stdout.decode(errors="replace")
    masked = Image.new("RGB", image.size, "black")
    labels = set()
    for row in csv.DictReader(io.StringIO(tsv), delimiter="\t", quoting=csv.QUOTE_NONE):
        word = (row.get("text") or "").lower().strip("·|()[] .:/")
        if not any(word in choices for choices in LABELS.values()) or float(row["conf"]) < 42:
            continue
        x, y, w, h = [int(row[key]) // scale for key in ("left", "top", "width", "height")]
        masked.paste(image.crop((x, y, x+w, y+h)), (x, y))
        labels.add(word)
    page = next((key for key, choices in LABELS.items() if key != "source_title"
                 and len(choices & labels) >= 2), None)
    # Libellés littéraux du premier écran adaptatif, lisibles même sur téléphone.
    if {"add", "my", "source"} <= labels or {"ajouter", "ma", "source"} <= labels:
        page = "add_source"
    # Une miniature de 16 colonnes permet de reconnaître une surface uniforme
    # en cas d’échec sans rendre de texte ni d’identifiants lisibles.
    thumb = image.resize((16, 9), Image.Resampling.BOX)
    thumb.resize((256, 144), Image.Resampling.NEAREST).save(out / f"{phase}-couleurs.png")
    if page:
        masked.save(out / f"{phase}-anonyme.png")
    return {"utc": datetime.now(timezone.utc).isoformat(), "page": page,
            "screen_sha256": hashlib.sha256(data).hexdigest(), "labels": sorted(labels)}


def verify_form_interaction(pkg):
    """Vérifier une action sans saisir ni publier de données de liste."""
    before = visible_nodes(pkg)
    def form(nodes):
        labels = {normalized(line) for label, _, _, _ in nodes for line in label.splitlines()}
        return (bool(labels & {"add my source", "ajouter ma source"}) or
                (bool(labels & {"paste", "coller"}) and bool(labels & {"file", "fichier"})))
    def inputs(nodes):
        return sum(kind.endswith("EditText") for _, _, _, kind in nodes)
    if not form(before):
        return None
    n = inputs(before)
    modes = {3: ({"m3u url"}, 1), 1: ({"xtream codes", "codes xtream"}, 3)}
    if n not in modes:
        return None
    targets, expected = modes[n]
    for label, x, y, _ in before:
        if not any(normalized(line) in targets for line in label.splitlines()):
            continue
        command("adb","shell","input","tap",str(round(x)),str(round(y)))
        for _ in range(3):
            if not is_foreground(pkg):
                return None
            after = visible_nodes(pkg)
            if form(after) and inputs(after) == expected:
                return {"page":"add_source","evidence":"form_interaction",
                        "fields_before":n,"fields_after":expected}
            time.sleep(.5)
        break
    return None


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("out", type=Path)
    p.add_argument("--package", default="com.sevenmotion.tv.seven_tv.lab")
    args = p.parse_args()
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    pkg = args.package
    if not re.fullmatch(r"[a-z][a-z0-9_.]+", pkg):
        p.error("Paquet invalide")
    activity = pkg + "/com.example.tv_king.MainActivity"
    for phase in ("ouverture", "reouverture"):
        command("adb", "shell", "am", "force-stop", pkg)
        command("adb", "shell", "am", "start", "-n", activity)
        rows = []
        deadline = time.monotonic() + 70
        while time.monotonic() < deadline:
            try:
                item = screen_evidence(out, phase)
                item["foreground"] = is_foreground(pkg)
            except (subprocess.SubprocessError, OSError, ValueError) as error:
                item = {"utc": datetime.now(timezone.utc).isoformat(), "page": None,
                        "foreground": False, "capture_error": type(error).__name__}
            if item["page"]:
                item["evidence"] = "ocr_pixels"
            elif item["foreground"] and len(rows) >= 2:
                try:
                    confirmed = verify_form_interaction(pkg)
                    if confirmed:
                        item.update(confirmed)
                except (subprocess.SubprocessError, OSError, ValueError) as error:
                    item["interaction_error"] = type(error).__name__
            rows.append(item)
            (out / f"{phase}.json").write_text(json.dumps(rows, indent=2))
            if item["page"] and item["foreground"] and command("adb","shell","pidof",pkg).strip():
                break
            time.sleep(1)
        (out / f"{phase}.json").write_text(json.dumps(rows, indent=2))
        if not rows[-1]["page"] or not rows[-1]["foreground"]:
            diagnostics(out, pkg, "", phase)
            pid = subprocess.run(["adb", "shell", "pidof", "-s", pkg], capture_output=True, text=True, timeout=10).stdout.strip()
            if pid.isdigit():
                log = subprocess.run(["adb", "logcat", "-d", "--pid="+pid, "-t", "1500"],
                                     capture_output=True, text=True, errors="replace", timeout=15).stdout
                # Uniquement les types et noms de symboles, jamais les messages libres.
                symbols = re.findall(r"(?:[a-zA-Z0-9_.$]+(?:Exception|Error)|#[0-9]+\s+[a-zA-Z0-9_.$<>]+)", log)
                (out / f"{phase}-symboles.json").write_text(json.dumps(sorted(set(symbols))[:120]))
            raise SystemExit(f"{phase} : aucun écran ZUNO reconnu")
    print("Deux ouvertures de ZUNO vérifiées. Le JSON distingue lecture des pixels et action sur le formulaire.")


if __name__ == "__main__":
    main()
