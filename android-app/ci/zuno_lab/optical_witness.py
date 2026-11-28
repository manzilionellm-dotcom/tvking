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

APK_PACKAGE = os.environ.get("BENCH_PACKAGE", "com.sevenmotion.tv.seven_tv")
URL = "http://127.0.0.1:18471/channels.m3u"
ALLOWED = set("zuno live direct settings movies films series guide sources playlists channels add my source connect load paste file xtream m3u url server username password playlist list enter http mire a b all favourites favorites search watch now loading welcome allow while using app notifications ok continue start skip done english français deutsch select language".split())


def adb(*parts, timeout=15, check=True):
    return subprocess.run(["adb", *parts], capture_output=True, timeout=timeout, check=check).stdout


def key(code):
    adb("shell", "input", "keyevent", code)


def tap(x, y):
    adb("shell", "input", "tap", str(int(x)), str(int(y)))


def screen():
    raw = adb("exec-out", "screencap", "-p", timeout=12)
    return Image.open(io.BytesIO(raw)).convert("RGB")


def words(im):
    buff = io.BytesIO()
    im.save(buff, "PNG")
    output = subprocess.run(["tesseract", "stdin", "stdout", "--psm", "11", "tsv"], input=buff.getvalue(),
                            capture_output=True, timeout=20, check=True).stdout.decode(errors="replace")
    items = []
    for row in csv.DictReader(io.StringIO(output), delimiter="\t"):
        label = re.sub("[^a-z0-9]", "", row["text"].lower())
        if label in ALLOWED:
            x, y, w, h = [int(row[k]) for k in ("left","top","width","height")]
            items.append((label, x + w / 2, y + h / 2))
    return items


def nodes():
    data = adb("exec-out", "uiautomator", "dump", "/dev/tty", timeout=12, check=False)
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


def observe_ui(folder, state):
    ns = nodes()
    im = screen()
    ts = words(im)
    # Ne conserver que des mots d'interface connus et une empreinte des pixels.
    event(folder, state, ocr=[(w,int(x),int(y)) for w,x,y in ts], size=im.size,
          sha256_rgb=hashlib.sha256(im.tobytes()).hexdigest(),
          semantics=[(sorted(set(re.findall(r"[a-z]+", t)) & ALLOWED), int(x), int(y), c.endswith("EditText"))
                     for t,x,y,c in ns if (set(re.findall(r"[a-z]+", t)) & ALLOWED or c.endswith("EditText"))])
    return ns, ts, im.size


def wait_control(folder, state, pattern, ocr_fallback, timeout=40, editable=False):
    deadline = time.monotonic()+timeout
    while time.monotonic() < deadline:
        ns, ts, size = observe_ui(folder, state)
        for t,x,y,c in ns:
            if editable and c.endswith("EditText") and x < size[0]*.75:
                return x,y
            if re.search(pattern,t) and len(t)<105:
                return x,y
        point = ocr_fallback(ts,size) if ocr_fallback else None
        if point:
            return point
        if state == "mode-m3u":
            if any(t[0] in {"deutsch","français","language"} for t in ts):
                english = token(ts,{"english"})
                if english:
                    tap(*english)
                    time.sleep(1)
            elif any(t[0] in {"movies","films","settings"} for t in ts):
                sources = token(ts,{"server","sources","playlists"})
                if sources:
                    tap(*sources)
                    time.sleep(1)
        time.sleep(.5)
    raise RuntimeError("Contrôle non identifié : "+state)


def token(ts, names, predicate=lambda x,y: True):
    return next(((x,y) for t,x,y in ts if t in names and predicate(x,y)), None)


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
    chip=wait_control(folder,"mode-m3u",r"^m3u\s*/\s*url$",lambda ts,s:token(ts,{"m3u"},lambda x,y:x<s[0]*.72))
    tap(*chip)
    row=wait_control(folder,"field-url",r"m3u url|^http://$",lambda ts,s:token(ts,{"http"},lambda x,y:x<s[0]*.72),editable=True)
    tap(*row)
    adb("shell","input","text",URL)
    key("KEYCODE_ENTER")
    time.sleep(3)
    def target_a(ts, size):
        return token(ts,{"mire"},lambda x,y:x<size[0]*.75)
    deadline=time.monotonic()+65
    navigated=False
    confirmed=False
    while time.monotonic()<deadline:
        ns,ts,s=observe_ui(folder,"seek-channel")
        point=next(((x,y) for t,x,y,c in ns if re.search(r"\bmire a\b",t)),None) or target_a(ts,s)
        if point:
            tap(*point)
            break
        live=next(((x,y) for t,x,y,c in ns if t.strip()=="live"),None) or token(ts,{"live","direct"})
        if live and not navigated:
            tap(*live)
            navigated=True
        elif not confirmed:
            submit=next(((x,y) for t,x,y,c in ns if t in ("connect","confirm and load my list","add the list")),None) or token(ts,{"connect","load"})
            if submit:
                tap(*submit)
                confirmed=True
        time.sleep(1)
    else:
        raise RuntimeError("Aucune ligne A reconnue après import par le formulaire")
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
            key(code)
            end=motion(folder,str(i+1),target,9,rows,i<2)
            cases.append({"number":i+1,"phase":phase,"key":code,"target":target,"from":last_confirmed,"dispatch_s":dispatch,
                          "movement_upper_ms":round((end-dispatch)*1000,3) if end else None})
            persist()
            if end is None:
                raise RuntimeError("Destination non confirmée ; conserver l’expiration puis recalibrer hors série.")
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
