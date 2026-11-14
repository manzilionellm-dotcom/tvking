"""Dérive les icônes PWA des rectangles du favicon existant, sans changer le logo."""
from pathlib import Path
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
svg = ET.parse(root / 'public/favicon.svg').getroot()
rectangles = list(svg)
if any(node.tag.split('}')[-1] != 'rect' for node in rectangles):
    raise SystemExit('Le favicon contient une forme non prise en charge : vérifier le rendu.')
view = [float(part) for part in svg.attrib['viewBox'].split()]
output = root / 'public/icons'
output.mkdir(exist_ok=True)

def render(size, *, background=False, badge=False):
    scale = size * 4 / view[2]
    image = Image.new('RGBA', (size * 4, size * 4), rectangles[0].attrib['fill'] if background else (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for node in rectangles[1:] if badge else rectangles:
        a = node.attrib
        x, y = float(a.get('x', 0)), float(a.get('y', 0))
        w, h = float(a['width']), float(a['height'])
        draw.rounded_rectangle((x * scale, y * scale, (x + w) * scale, (y + h) * scale),
                               radius=float(a.get('rx', 0)) * scale, fill='#FFFFFF' if badge else a['fill'])
    return image.resize((size, size), Image.Resampling.LANCZOS)

for size in (192, 512):
    render(size).save(output / f'panel-{size}.png')
render(512, background=True).save(output / 'panel-maskable-512.png')
render(180, background=True).save(output / 'panel-apple-180.png')
render(96, badge=True).save(output / 'panel-badge.png')
print('5 icônes dérivées du favicon existant.')
