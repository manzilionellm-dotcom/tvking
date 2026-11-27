"""Contre-épreuve géométrique de l'appel PixelCopy, sans émuler un décodeur."""
import argparse
import json
from pathlib import Path
import re
from PIL import Image, ImageDraw

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("--out", type=Path, required=True)
args = parser.parse_args()
args.out.mkdir(parents=True, exist_ok=True)
code = args.source.read_text()
old = "PixelCopy.request(surfaceView, rect, bmp," in code
full = "PixelCopy.request(surfaceView, bmp," in code
assert old != full, "Appel PixelCopy inconnu"
if old:
    assert all(x in code for x in ("minOf(w, 1280)", "minOf(h, 720)", "(w - rw) / 2", "(h - rh) / 2"))
rows = []
colors = ["#ff0000", "#00ff00", "#0000ff", "#ffff00"]
for width, height in [(1920, 1080), (3840, 2160), (1440, 1080), (1080, 1920), (640, 360)]:
    frame = Image.new("RGB", (width, height), "#222222")
    draw = ImageDraw.Draw(frame)
    size = min(width, height) // 12
    for color, (x, y) in zip(colors, [(0,0),(width-size,0),(0,height-size),(width-size,height-size)]):
        draw.rectangle((x, y, x+size-1, y+size-1), fill=color)
    if old:
        w, h = min(width, 1280), min(height, 720)
        l, t = (width-w)//2, (height-h)//2
        rect = l, t, l+w, t+h
    else:
        rect = (0, 0, width, height)
        scale = max(1, width / 1280, height / 720)
        w, h = round(width / scale), round(height / scale)
    image = frame.crop(rect).resize((w, h), Image.Resampling.NEAREST)
    corners = [image.getpixel(p) for p in [(0,0),(w-1,0),(0,h-1),(w-1,h-1)]]
    expected = [(255,0,0),(0,255,0),(0,0,255),(255,255,0)]
    count = sum(a==b for a,b in zip(corners,expected))
    rows.append(dict(source=[width,height], bitmap=[w,h], rectangle=rect, corners=count,
                     source_fraction=(rect[2]-rect[0])*(rect[3]-rect[1])/(width*height)))
    if width == 1920:
        image.resize((480,270)).save(args.out/"modele-1080p.png")
(args.out/"geometry.json").write_text(json.dumps({"kind":"modele_geometrique_sans_appareil","rows":rows}, indent=2)+"\n")
raise SystemExit(0 if all(r["corners"]==4 for r in rows) else 1)
