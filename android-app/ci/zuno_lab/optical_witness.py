"""Importe deux mires par les contrôles de ZUNO, puis observe les pixels de la sortie Android."""
import argparse
import csv
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image
from read_display_capture import decode
from display_capture import capture_png
from zuno_ui_path import next_step, normalized

APK_PACKAGE = os.environ.get("BENCH_PACKAGE", "com.sevenmotion.tv.seven_tv")
URL = "http://127.0.0.1:18471/channels.m3u"
ALLOWED = set("zuno live direct settings movies films series guide sources playlists channels add my source connect load paste file xtream m3u url server username password playlist list enter http mire a b all favourites favorites search watch now loading welcome allow while using app notifications ok continue start skip done english francais deutsch select language langue serveur reglages mes ma liste listes ajouter ajouter ma source coller fichier codes sign in and se connecter et charger autoriser sources series my channels toutes les chaines favoris".split())


def adb(*parts, timeout=15, check=True):
    return subprocess.run(["adb", *parts], capture_output=True, timeout=timeout, check=check).stdout


def key(code):
    adb("shell", "input", "keyevent", code)


def tap(x, y):
    adb("shell", "input", "tap", str(int(x)), str(int(y)))


def screen():
    return Image.open(io.BytesIO(capture_png())).convert("RGB")


def words(im):
    buff = io.BytesIO()
    im.save(buff, "PNG")
    output = subprocess.run(["tesseract", "stdin", "stdout", "--psm", "11", "tsv"], input=buff.getvalue(),
                            capture_output=True, timeout=20, check=True).stdout.decode(errors="replace")
    items = []
    for row in csv.DictReader(io.StringIO(output), delimiter="\t"):
        labels = normalized(row["text"]).split()
        x, y, w, h = [int(row[k]) for k in ("left","top","width","height")]
        for i, label in enumerate(labels):
            if label in ALLOWED:
                items.append((label, x + (i + .5) * w / len(labels), y + h / 2))
    return items


def nodes():
    data = adb("exec-out", "uiautomator", "dump", "/dev/tty", timeout=4, check=False)
    start, end = data.find(b"<hierarchy"), data.rfind(b"</hierarchy>")
    if start < 0 or end < start:
        return []
    try:
        root = ET.fromstring(data[start:end+12])
    except ET.ParseError:
        return []
    items = []
    for node in root.iter("node"):
        if node.get("package") != APK_PACKAGE:
            continue
        box = [int(i) for i in re.findall(r"\d+", node.get("bounds", ""))]
        if len(box) != 4 or box[2] <= box[0] or box[3] <= box[1]:
            continue
        label = " ".join([node.get("content-desc", ""), node.get("text", "")]).lower().strip()
        items.append((label, (box[0]+box[2])/2, (box[1]+box[3])/2, node.get("class","")))
    return items


def event(folder, state, **details):
    with (folder / "events.jsonl").open("a") as f:
        f.write(json.dumps({"utc": datetime.now(timezone.utc).isoformat(), "monotonic": time.monotonic(),
                            "state": state, **details})+"\n")


def observe_ui(folder, state, classify=None):
    ns = []
    try:
        im = screen()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        event(folder, "screen-unavailable", stage=state, reason=type(exc).__name__)
        raise
    try:
        ts = words(im)
    except (OSError, subprocess.SubprocessError):
        event(folder, "ocr-unavailable", stage=state)
        ts = []
    # Le dump de l’émulateur peut attendre une interface idle. Un contrôle
    # OCR déjà reconnu évite tout appel à uiautomator sur cet écran.
    if classify is None or classify([], ts, im.size)[0] == "wait":
        try:
            ns = nodes()
        except (OSError, subprocess.SubprocessError):
            event(folder, "semantics-unavailable", stage=state)
    # Ne conserver que des mots d'interface connus et une empreinte des pixels.
    event(folder, state, ocr=[(w,int(x),int(y)) for w,x,y in ts], size=im.size,
          sha256_rgb=hashlib.sha256(im.tobytes()).hexdigest(),
          semantics=[(sorted(set(re.findall(r"[a-z]+", t)) & ALLOWED), int(x), int(y), c.endswith("EditText"))
                     for t,x,y,c in ns if (set(re.findall(r"[a-z]+", t)) & ALLOWED or c.endswith("EditText"))])
    return ns, ts, im.size


def open_fixture(folder):
    phase = "choose"
    via_sources = False
    backed_out = False
    deadline = time.monotonic() + 180
    actions = {}
    last_action = {}
    while time.monotonic() < deadline:
        def classify(ns, ts, size):
            return next_step(ns, ts, size, phase, via_sources, backed_out)
        ns, ts, size = observe_ui(folder, phase, classify)
        action, point = classify(ns, ts, size)
        now = time.monotonic()
        if action == "wait" or now - last_action.get(action, 0) < 6:
            time.sleep(.4)
            continue
        actions[action] = actions.get(action, 0) + 1
        if actions[action] > 2 or (action in {"type-url", "submit-button"} and actions[action] > 1):
            event(folder, "navigation-stalled", phase=phase, action=action)
            raise RuntimeError("Le contrôle TV ne change pas d’écran : " + action)
        event(folder, "ui-action", phase=phase, action=action)
        last_action[action] = now
        if point is not None:
            tap(*point)
        if action == "channel-a":
            return
        if action in {"return-to-hub", "return-from-settings"}:
            key("KEYCODE_BACK")
            backed_out = True
        elif action == "add-m3u":
            via_sources = True
            phase = "url"  # route dédiée ouverte avec initialMode=m3u
        elif action == "choose-m3u":
            phase = "url"
        elif action == "type-url":
            adb("shell", "input", "text", URL)
            key("KEYCODE_ENTER")  # TextInputAction.done => _submit
            phase = "after-submit"
            last_action["submit-button"] = time.monotonic()
        time.sleep(.7)
    event(folder, "navigation-timeout", phase=phase, actions=actions)
    raise RuntimeError("Aucune ouverture de la chaîne A confirmable dans le délai")


def read_marker(im):
    gray = im.convert("L")
    w,h=im.size
    for top,bottom in ((0,0),(0,24),(0,48),(24,0),(24,24),(48,0),(48,48)):
        vh=min(h-top-bottom,w*9/16)
        vw=vh*16/9
        x=(w-vw)/2
        y=top+(h-top-bottom-vh)/2
        cy=round(y+vh*650/1080)
        scores=[gray.getpixel((round(x+vw*(496+32*i)/1920),cy)) for i in range(30)]
        ch,n=decode(scores)
        if ch:
            return ch,n,(round(x+vw*.25),round(y+vh*640/1080),round(x+vw*.75),round(y+vh*660/1080))
    return None,None,None


def motion(folder, name, target, timeout, rows, save=False):
    deadline=time.monotonic()+timeout
    prev=None
    while time.monotonic()<deadline:
        start=time.monotonic()
        im=screen()
        ch,n,box=read_marker(im)
        end=time.monotonic()
        rows.append([name,start,end,ch,n])
        if ch and ch==target:
            if save:
                # Cette bande contient exclusivement les cases binaires vérifiées de la mire.
                im.crop(box).save(folder / f"marker-{name}-{n}.png")
            if prev is not None and 0<(n-prev)%3000<300:
                return end
            prev=n
        else:
            prev=None
    return None


def run(folder, count):
    folder.mkdir(exist_ok=True, parents=True)
    event(folder,"started", package=APK_PACKAGE, source="two synthetic HLS 1080p25; 2 s segments")
    open_fixture(folder)
    rows=[]
    cases=[]
    def persist():
        with (folder/"samples.csv").open("w",newline="") as f:
            w=csv.writer(f);w.writerow(["trial","host_before_s","host_after_s","channel","counter"]);w.writerows(rows)
        (folder/"trials.json").write_text(json.dumps(cases,indent=2))
    try:
        seen=motion(folder,"onboard","A",10,rows,True)
        if not seen:
            key("KEYCODE_DPAD_CENTER")
            seen=motion(folder,"confirm","A",15,rows,True)
        if not seen:
            observe_ui(folder,"missing-motion")
            raise RuntimeError("Plein écran A non confirmé par deux compteurs croissants")
        event(folder,"first-moving-channel",channel="A")
        # Suite prédéfinie, même ordre quel que soit le résultat. Les délais sont des bornes hautes.
        last_confirmed="A"
        for i in range(count*2):
            phase="spaced" if i<count else "burst"
            target="B" if i%2==0 else "A"
            code="KEYCODE_CHANNEL_DOWN" if i%2==0 else "KEYCODE_CHANNEL_UP"
            if last_confirmed == target or last_confirmed is None:
                raise RuntimeError("Destination initiale non prouvée ; série interrompue.")
            dispatch=time.monotonic()
            attempt = {"number":i+1,"phase":phase,"key":code,"target":target,
                       "from":last_confirmed,"dispatch_s":dispatch,"movement_upper_ms":None,
                       "status":"dispatch-requested"}
            cases.append(attempt)
            persist()
            try:
                key(code)
                attempt["status"] = "command-returned"
                end=motion(folder,str(i+1),target,9,rows,i<2)
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
                event(folder, "trial-collection-failure", number=i+1, stage=attempt["status"],
                      reason=type(exc).__name__)
                attempt["status"] = ("dispatch-uncertain" if attempt["status"] == "dispatch-requested"
                                     else "capture-failed")
                raise
            if end is None:
                attempt["status"] = "target-timeout"
                raise RuntimeError("Destination non confirmée ; conserver l’expiration puis recalibrer hors série.")
            attempt.update(status="verified-motion",movement_upper_ms=round((end-dispatch)*1000,3))
            persist()
            last_confirmed=target
            if phase=="spaced":
                time.sleep(max(0,dispatch+5-time.monotonic()))
    finally:
        persist()


if __name__ == "__main__":
    p=argparse.ArgumentParser()
    p.add_argument("folder",type=Path)
    p.add_argument("--count",type=int,default=100)
    a=p.parse_args()
    run(a.folder,a.count)
