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

LABELS = {
    "home": {"live", "movies", "series", "guide", "server", "settings", "direct", "films", "serveur", "réglages"},
    "source": {"m3u", "xtream", "portal", "url", "playlist", "connect", "source", "liste", "portail"},
    "language": {"english", "français", "deutsch", "español", "italiano"},
}


def command(*args, timeout=25):
    return subprocess.check_output(args, stderr=subprocess.DEVNULL, timeout=timeout)


def screen_evidence(out, phase):
    data = command("adb", "exec-out", "screencap", "-p")
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
    page = next((key for key, choices in LABELS.items() if len(choices & labels) >= 2), None)
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
        command("adb", "shell", "am", "start", "-W", "-n", activity)
        rows = []
        deadline = time.monotonic() + 55
        while time.monotonic() < deadline:
            item = screen_evidence(out, phase)
            rows.append(item)
            if item["page"] and command("adb","shell","pidof",pkg).strip():
                break
            time.sleep(1)
        (out / f"{phase}.json").write_text(json.dumps(rows, indent=2))
        if not rows[-1]["page"]:
            raise SystemExit(f"{phase} : aucun écran ZUNO reconnu")
    print("Deux écrans interactifs ZUNO reconnus par leurs libellés sur la sortie Android.")


if __name__ == "__main__":
    main()
