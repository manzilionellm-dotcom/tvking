"""Vérifie deux ouvertures du binaire installé à partir des pixels de l'écran."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import time

from PIL import Image
from device_smoke import is_foreground, diagnostics
from display_capture import capture_png

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
    tsv = subprocess.run(["tesseract", "stdin", "stdout", "--psm", "11", "tsv"],
                         input=data, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                         timeout=25, check=True).stdout.decode(errors="replace")
    masked = Image.new("RGB", image.size, "black")
    labels = set()
    for row in csv.DictReader(io.StringIO(tsv), delimiter="\t", quoting=csv.QUOTE_NONE):
        word = (row.get("text") or "").lower().strip("·|()[] .:/")
        if not any(word in choices for choices in LABELS.values()) or float(row["conf"]) < 42:
            continue
        x, y, w, h = [int(row[key]) for key in ("left", "top", "width", "height")]
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
    print("Deux écrans interactifs ZUNO reconnus par leurs libellés sur la sortie Android.")


if __name__ == "__main__":
    main()
