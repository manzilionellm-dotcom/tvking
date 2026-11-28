"""Conserver des libellés prédéfinis et détecter le consentement avant toute commande."""
import csv
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

import tivimate_pilot as pilot
from PIL import Image,ImageDraw

real_snapshot=pilot.snapshot
phrases=("privacy policy","terms of use","terms of service","i agree","user agreement","consent","accept and continue","license agreement")
safe=set("tivimate welcome add playlist next done menu enter url epg settings guide television channels live m3u privacy policy terms use service i agree user agreement consent accept continue license account premium search retry network error got it close".split())


def capture(out,folder,step):
    try:
        values=real_snapshot(folder,step)
    except (OSError,ValueError,subprocess.TimeoutExpired):
        values=[]
    png=folder/f"ui-{step:02d}.png"
    if not png.exists() or png.stat().st_size<100:
        try:
            sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
            from display_capture import capture_png
            png.write_bytes(capture_png())
        except (OSError,RuntimeError,ValueError,subprocess.SubprocessError):
            pass
    tokens=[]
    if png.exists() and png.stat().st_size>100:
        with Image.open(png) as picture:
            masked=Image.new("RGB",picture.size,"black")
            proc=subprocess.run(["tesseract",str(png),"stdout","--psm","11","tsv"],capture_output=True,timeout=22,env={**os.environ,"OMP_THREAD_LIMIT":"1"})
            for row in csv.DictReader(io.StringIO(proc.stdout.decode(errors="replace")),delimiter="\t"):
                w=pilot.normalized(row.get("text",""))
                if not w: continue
                tokens.append(w)
                if w in safe:
                    x,y,width,height=(int(row[k]) for k in ("left","top","width","height"))
                    masked.paste(picture.crop((x,y,x+width,y+height)),(x,y))
            masked.save(out/f"public-{step:02d}.png")
    combined=[" ".join(tokens)]+[v for v,_,_ in values]
    found=sorted({w for w in phrases for v in combined if re.search(r"\b"+re.escape(w)+r"\b",v)})
    labels=sorted(set(" ".join(combined).split())&safe)
    with (out/"parcours.jsonl").open("a") as f:
        print(json.dumps(dict(step=step,host_s=time.monotonic(),labels=labels,consent=found)),file=f)
    if found:
        (out/"limite.txt").write_text("Écran de consentement observé avant accès à la mire : "+", ".join(found))
        raise RuntimeError("Consentement affiché")
    return values

if __name__=="__main__":
    out=Path(sys.argv[1]);folder=Path(sys.argv[2])
    pilot.snapshot=lambda folder,step:capture(out,folder,step)
    pilot.onboard(folder)
