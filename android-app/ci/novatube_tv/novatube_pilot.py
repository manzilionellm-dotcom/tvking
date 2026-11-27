"""Ouvre la mire A via le parcours normal NovaTube sur la TV de test."""
import argparse
import csv
import io
import json
import re
import subprocess
import time
from pathlib import Path

from PIL import Image

SERIAL = "emulator-5554"
URL = "http://127.0.0.1:18471/channels.m3u"


def adb(*args, output=False):
    result = subprocess.run(["adb", "-s", SERIAL, *args], check=True,
                            capture_output=True, timeout=18)
    return result.stdout if output else None


def words(path):
    with Image.open(path) as im:
        w, h = im.size
    data = subprocess.check_output(["tesseract", str(path), "stdout", "--psm", "11", "tsv"],
                                   stderr=subprocess.DEVNULL, text=True, timeout=18)
    result = []
    for row in csv.DictReader(io.StringIO(data), delimiter="\t"):
        text = re.sub("[^a-z0-9]", "", row["text"].lower())
        if not text:
            continue
        x = int(row["left"]) + int(row["width"]) // 2
        y = int(row["top"]) + int(row["height"]) // 2
        result.append((text, x, y, x / w, y / h))
    return result


def labels(tokens):
    return {t[0] for t in tokens}


def home(tokens):
    ts = labels(tokens)
    return "tonight" in ts or (bool(ts & {"live", "direct"}) and bool(ts & {"movies", "films", "series"}) and bool(ts & {"playlists", "settings", "reglages"}))


def row_a(tokens):
    # Les titres à droite décrivent l'aperçu. Seules les lignes centrales
    # sont cliquables. Le catalogue contrôlé s'affiche par ordre A puis B.
    hits = [t for t in tokens if .20 < t[3] < .595 and t[0] in {"mire", "mirea", "mireb"}]
    for t in hits:
        if t[0] == "mirea" or any(v[0] == "a" and t[1] < v[1] < t[1]+130 and abs(t[2]-v[2])<17 for v in tokens):
            return t
    if len(hits) >= 2:
        return min(hits, key=lambda t:t[2])
    return None


def run(folder):
    folder.mkdir(parents=True, exist_ok=True)
    def ss(name):
        path = folder / (name+".png")
        path.write_bytes(adb("exec-out", "screencap", "-p", output=True))
        return path
    def poll(name, predicate, seconds=28):
        end=time.monotonic()+seconds
        while True:
            ts=words(ss(name))
            if predicate(ts):
                return ts
            if time.monotonic() >= end:
                raise RuntimeError(f"{name}: écran attendu absent. Texte: "+' '.join(t[0] for t in ts)[:400])
            time.sleep(.65)
    def key(name):
        adb("shell", "input", "keyevent", name)
    def tap(t):
        adb("shell", "input", "tap", str(t[1]), str(t[2]))
    adb("reverse","tcp:18471","tcp:18471")
    ts=poll("nova-01-start",lambda t:home(t) or bool(labels(t) & {"welcome","bienvenue","xtream"}),45)
    if not home(ts):
        key("KEYCODE_DPAD_CENTER")
        poll("nova-02-form",lambda t:bool(labels(t) & {"source","url","http","file","fichier","link","m3u8"}))
        adb("shell","input","text", URL)
        ss("nova-03-url")
        key("KEYCODE_ENTER")
        time.sleep(2.5)
        state=words(ss("nova-04-submit"))
        if not home(state) and not labels(state) & {"welcome","bienvenue"}:
            # Sur certains IME l'envoi place d'abord le focus sur Valider.
            key("KEYCODE_DPAD_CENTER")
        ts=poll("nova-05-home",home,50)
    live=next((t for t in ts if t[0] in {"live","direct"} and t[4]<.5),None)
    if live:
        tap(live)
    else:
        key("KEYCODE_DPAD_CENTER")
    ts=poll("nova-06-grid",lambda t:row_a(t) is not None,35)
    tap(row_a(ts))
    time.sleep(3)
    ts=words(ss("nova-07-selected"))
    if row_a(ts):
        key("KEYCODE_DPAD_CENTER")
    # Confirmation indépendante de l'écran : le compteur matériel QA de ce
    # binaire distingue la première image du plein écran de celle de l'aperçu.
    pid=adb("shell","pidof","com.sevenmotion.novatube.tv",output=True).decode().strip()
    end=time.monotonic()+22
    while time.monotonic()<end:
        trace=adb("logcat","-d","--pid",pid,"-s","flutter:I",output=True).decode(errors="replace")
        if "action=open_screen outcome=first_frame" in trace:
            ss("nova-08-full")
            (folder/"nova-start.json").write_text(json.dumps({"first_full_frame":True,"requested_channel":"A"}))
            return
        time.sleep(.5)
    ss("nova-08-full")
    raise RuntimeError("Plein écran non confirmé par le marqueur QA de l'APK d'essai.")


if __name__=="__main__":
    a=argparse.ArgumentParser()
    a.add_argument("output",type=Path)
    run(a.parse_args().output)
