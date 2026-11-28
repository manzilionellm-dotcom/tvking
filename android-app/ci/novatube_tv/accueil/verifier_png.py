"""Vérifie les dimensions et relit le MK dans le raster avec Tesseract."""
import hashlib
import io
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageOps
from glyphes import alphabet, decode

def recognize(image):
    image = ImageOps.grayscale(image)
    # Rendu de texte clair sur fond sombre : Tesseract reçoit le glyphe sombre.
    image = ImageOps.invert(image)
    image = image.resize((image.width*2, image.height*2), Image.Resampling.LANCZOS)
    image = ImageOps.expand(image,border=18,fill=255)
    stream = io.BytesIO()
    image.save(stream,format="PNG")
    cmd = ['tesseract','stdin','stdout','-l','eng','--psm','7',
           '-c','tessedit_char_whitelist=MK:0123456789ABCDEF']
    res = subprocess.run(cmd,input=stream.getvalue(),capture_output=True,check=True)
    return ''.join(res.stdout.decode().split())

root = Path(sys.argv[1])
refs = alphabet(Path(sys.argv[2]) if len(sys.argv)>2 else Path("assets/fonts/JetBrainsMono-SemiBold.ttf"))
results = []
for file in sorted(root.glob('*p-x*.json')):
    row = json.loads(file.read_text())
    png = file.with_suffix('.png')
    with Image.open(png) as image:
        assert list(image.size)==[row['width'],row['height']], file
        l,t,r,b = row['rectanglesPx']['mk']
        # Une seule zone définie par le texte peint, sans injection du MK dans l'OCR.
        crop = image.crop((int(l)-4,int(t)-4,int(r)+5,int(b)+5))
        obs = recognize(crop)
        glyphs = decode(crop,refs)
    results.append(dict(id=row['id'],mkTesseract=obs,tesseractExact=obs==row['mk'],mkGlyphes=glyphs,exact=glyphs==row['mk'],
                        pngSHA256=hashlib.sha256(png.read_bytes()).hexdigest()))
(root/'ocr.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
print(f'{sum(r["exact"] for r in results)}/{len(results)} MK relus caractère par caractère, {sum(r["tesseractExact"] for r in results)}/{len(results)} par Tesseract.')
if len(results)!=12 or not all(r['exact'] for r in results):
    for r in results:
        if not r['exact']: print(r['id'],r['mkGlyphes'])
    sys.exit(1)
