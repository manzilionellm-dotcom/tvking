#!/usr/bin/env python3
"""Vérifie sur les pixels de l'APK signé les accès visibles de l'accueil TV.

L'émulateur est neuf et son réseau est coupé avant l'installation. Les captures
et la sortie d'OCR brutes restent en mémoire. Les images exportées ne gardent
que les pixels des mots publics autorisés, à leur emplacement original.
"""
import argparse
import csv
import hashlib
import io
import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

# Libellés anglais de la TV de test. Le code appareil reste toujours privé.
HOME = {
    "welcome": r"welcome to novatube",
    "m3u": r"m3u playlist",
    "xtream": r"xtream codes",
    "device-code": r"device code",
    "check-access": r"check my access",
    "access-code": r"(?<!my )access code\b",
}
M3U = {"paste": r"\bpaste\b", "file": r"\bfile\b", "optional-name": r"name optional"}
XTREAM = {"username": r"(?m)^user\s*name$", "password": r"(?m)^password$"}
ACCESS = {"activation": r"activate", "cancel": r"cancel"}
PUBLIC_WORDS = set("""
welcome to novatube max add an m3u playlist sign in with xtream codes device
code check my access enter the you received activate this cancel give your
reseller stays same after update awaiting activation licence license network
unavailable connection no channels or tv subscription are provided player
is a and password username url epg optional name list server address support
verification free time if available retry help settings reseller provider
paste file provider's started get to it the is this device and as not on view
""".split())


def adb(*parts, raw=False, check=True):
    proc = subprocess.run(["adb", *parts], check=check, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, timeout=50)
    return proc.stdout if raw else proc.stdout.decode(errors="replace").strip()


def ident(result):
    return hashlib.sha256(result).hexdigest()


def normalize(text):
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def pixels():
    image = Image.open(io.BytesIO(adb("exec-out", "screencap", "-p", raw=True))).convert("RGB")
    stream = io.BytesIO()
    image.save(stream, format="PNG")
    rows = subprocess.run(["tesseract", "stdin", "stdout", "--psm", "11", "tsv"],
                          input=stream.getvalue(), stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, check=True, timeout=40).stdout
    words = [r for r in csv.DictReader(io.StringIO(rows.decode()), delimiter="\t")
             if r.get("level") == "5" and r["text"].strip()]
    lines = {}
    for word in words:
        group = (word["block_num"], word["par_num"], word["line_num"])
        lines.setdefault(group, []).append(word["text"])
    # Le D-pad peut faire descendre la vue ; chaque capture est jugée seule.
    # Le code doit exister dans les pixels, mais seule sa présence sort du test.
    code = None
    for line in lines.values():
        match = re.search(r"MK[:.;-]?(?:[0-9A-F]{2}[:.;-]?){4}[0-9A-F]{2}",
                          "".join(line).upper())
        if match:
            code = re.sub(r"[^0-9A-Z]", "", match.group())
    if code is None:
        # Une seconde lecture de la seule ligne située sous « Device code »
        # écarte les confusions du moteur de mise en page, sans exporter sa valeur.
        for group_words in lines.values():
            if normalize(" ".join(group_words)) == "device code":
                label = next((w for w in words if w["text"].lower() == "device"), None)
                if label is None:
                    break
                bottom = int(label["top"]) + int(label["height"])
                width, height = image.size
                crop = image.crop((width // 5, bottom, width * 4 // 5,
                                   min(height, bottom + max(70, height // 14))))
                crop.thumbnail((1500, 160))
                region = io.BytesIO()
                crop.save(region, format="PNG")
                value = subprocess.run(
                    ["tesseract", "stdin", "stdout", "--psm", "7", "-c",
                     "tessedit_char_whitelist=MK0123456789ABCDEF:"],
                    input=region.getvalue(), stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL, check=True, timeout=10).stdout.decode()
                m = re.fullmatch(r"MK:?(?:[0-9A-F]{2}:?){4}[0-9A-F]{2}",
                                 re.sub(r"\s", "", value))
                if m:
                    code = m.group().replace(":", "")
                break
    semantic_text = "\n".join(normalize(" ".join(line)) for line in lines.values())
    return image, words, semantic_text, code


def sanitized(image, words, dest):
    view = Image.new("RGB", image.size, "#111723")
    for w in words:
        if w["text"].lower().strip(".,:?!()") not in PUBLIC_WORDS:
            continue
        x, y, width, height = [int(w[k]) for k in ("left", "top", "width", "height")]
        rect = (x, y, x + width, y + height)
        view.paste(image.crop(rect), (x, y))
    view.save(dest)


def key(name):
    adb("shell", "input", "keyevent", "KEYCODE_" + name)
    time.sleep(.8)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("apk", type=Path)
    p.add_argument("package")
    p.add_argument("out", type=Path)
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    report = {"package": args.package, "sha256_apk": ident(args.apk.read_bytes()),
              "started_utc": datetime.now(timezone.utc).isoformat(), "views": [],
              "image": adb("shell", "getprop", "ro.build.product"),
              "sdk": adb("shell", "getprop", "ro.build.version.sdk"),
              "display": adb("shell", "wm", "size"), "density": adb("shell", "wm", "density")}
    matched_codes = []

    def save():
        (args.out / "mesures.json").write_text(json.dumps(report, indent=2) + "\n")

    def installed():
        paths = adb("shell", "pm", "path", args.package).splitlines()
        return [ident(adb("exec-out", "cat", line.split(":", 1)[1], raw=True)) for line in paths]

    def verify_view(name, wanted, seconds, home=False, allow_back=False):
        deadline = time.monotonic() + seconds
        while True:
            image, words, text, code = pixels()
            checks = {k: bool(re.search(pattern, text)) for k, pattern in wanted.items()}
            if home:
                checks["device-value"] = code is not None
            foreground = adb("shell", "dumpsys", "activity", "activities")
            checks["foreground"] = any(args.package + "/" in line for line in foreground.splitlines()
                                       if "ResumedActivity" in line or "topResumedActivity" in line)
            if all(checks.values()) or time.monotonic() > deadline:
                break
            if allow_back and time.monotonic() + seconds - deadline > 3:
                key("BACK")
                allow_back = False
            time.sleep(1)
        sanitized(image, words, args.out / (name + ".png"))
        report["views"].append({"name": name, "utc": datetime.now(timezone.utc).isoformat(),
                                "size": list(image.size), "checks": checks})
        save()
        if not all(checks.values()):
            raise RuntimeError(name + " : " + ", ".join(k for k, ok in checks.items() if not ok))
        if home:
            matched_codes.append(code)

    try:
        assert "Success" in adb("install", "-r", str(args.apk))
        report["installed_sha256"] = installed()
        if report["installed_sha256"] != [report["sha256_apk"]]:
            raise RuntimeError("Empreinte des octets installés différente")
        activity = adb("shell", "cmd", "package", "resolve-activity", "--brief", "-a",
                       "android.intent.action.MAIN", "-c", "android.intent.category.LEANBACK_LAUNCHER",
                       args.package).splitlines()[-1]
        if not activity.startswith(args.package + "/"):
            raise RuntimeError("Lanceur TV absent")
        for opening in (1, 2):
            adb("shell", "am", "force-stop", args.package)
            launch = adb("shell", "am", "start", "-W", "-n", activity)
            if "Status: ok" not in launch:
                raise RuntimeError("Démarrage Activity en échec")
            verify_view("accueil-" + str(opening), HOME, 55, home=True)
        report["device_value_stable"] = matched_codes[0] == matched_codes[1]
        if not report["device_value_stable"]:
            raise RuntimeError("Code appareil différent après réouverture")
        key("DPAD_CENTER")
        verify_view("m3u", M3U, 12)
        key("BACK")
        verify_view("retour-m3u", HOME, 12, allow_back=True)
        adb("shell", "am", "force-stop", args.package)
        adb("shell", "am", "start", "-W", "-n", activity)
        verify_view("avant-xtream", HOME, 25)
        key("DPAD_RIGHT")
        key("DPAD_CENTER")
        verify_view("xtream", XTREAM, 12)
        key("BACK")
        verify_view("retour-xtream", HOME, 12, allow_back=True)
        # À partir du focus de retour, une relance rétablit la case M3U
        # pour rendre le parcours indépendant de la mémorisation du focus.
        adb("shell", "am", "force-stop", args.package)
        adb("shell", "am", "start", "-W", "-n", activity)
        verify_view("avant-code", HOME, 25)
        key("DPAD_RIGHT")
        key("DPAD_DOWN")
        key("DPAD_CENTER")
        verify_view("saisie-code", ACCESS, 15)
        report["final_installed_sha256"] = installed()
        assert report["final_installed_sha256"] == report["installed_sha256"]
        report["success"] = True
    finally:
        save()


if __name__ == "__main__":
    main()
