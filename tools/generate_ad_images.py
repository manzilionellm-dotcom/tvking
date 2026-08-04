"""Visuels d'annonce pour la campagne Google Ads App — 7 MOTION.

Trois formats exigés par Google : paysage 1200x628, carré 1200x1200,
portrait 1200x1500.

Parti pris : une VRAIE capture de l'application au centre du visuel.
Une campagne App qui ne montre pas l'app promet quelque chose que le
clic ne tient pas — et Google le sanctionne par un score d'efficacité
« Médiocre », qui coûte plus cher que le visuel lui-même.

Le texte reprend la promesse exacte de la fiche : c'est un LECTEUR, le
client apporte sa source. Écrire autre chose sur une annonce, c'est
acheter des installations qui désinstallent en trois minutes.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

BG = (10, 10, 12)
ORANGE = (240, 122, 38)
WHITE = (240, 237, 233)
GREY = (150, 150, 158)

F = "/usr/share/fonts/truetype/dejavu"
SHOT = "marketing/play/screenshots/01-accueil-categories.png"


def font(size, bold=True):
    return ImageFont.truetype(
        f"{F}/DejaVuSans{'-Bold' if bold else ''}.ttf", size)


def glow(img, cx, cy, radius, colour, strength=0.34):
    """Lueur douce.

    Première version : trente ellipses concentriques semi-transparentes.
    Résultat à 1200 px de large — des DISQUES PLEINS aux bords nets, qui
    écrasaient le texte. L'alpha de trente calques qui se recouvrent
    s'accumule jusqu'à l'opacité, ce qui passe inaperçu sur une petite
    surface et saute aux yeux sur une grande.

    Un seul disque, puis un flou gaussien large : c'est ainsi qu'on
    dessine une lueur, et ça ne dépend plus de la taille du visuel.
    """
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    r = radius * 0.42
    ImageDraw.Draw(layer).ellipse(
        [cx - r, cy - r, cx + r, cy + r],
        fill=(*colour, int(255 * strength)))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius * 0.30)))


def phone(shot, height):
    """La capture, coins arrondis et fine bordure — lisible en vignette."""
    im = Image.open(shot).convert("RGB")
    w = round(im.width * height / im.height)
    im = im.resize((w, height), Image.LANCZOS)
    radius = round(height * 0.045)

    mask = Image.new("L", (w, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, height - 1],
                                           radius, fill=255)
    out = Image.new("RGBA", (w, height), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    ImageDraw.Draw(out).rounded_rectangle(
        [0, 0, w - 1, height - 1], radius,
        outline=(255, 255, 255, 40), width=3)
    return out


def shadow(base, layer, x, y):
    """Ombre portée : sans elle, la capture semble collée sur le fond."""
    sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
    sh.paste((0, 0, 0, 150), (x, y + 14), layer.split()[3])
    base.alpha_composite(sh.filter(ImageFilter.GaussianBlur(22)))
    base.alpha_composite(layer, (x, y))


def text(d, xy, s, f, fill, anchor=None):
    d.text(xy, s, font=f, fill=fill, anchor=anchor)


def build(w, h, out):
    img = Image.new("RGBA", (w, h), (*BG, 255))
    glow(img, w * 0.80, h * 0.78, max(w, h) * 0.70, ORANGE, 0.55)
    glow(img, w * 0.05, h * 0.08, max(w, h) * 0.55, (50, 110, 190), 0.30)
    d = ImageDraw.Draw(img, "RGBA")

    if w > h:  # ---- PAYSAGE : texte à gauche, capture à droite -------
        ph = round(h * 0.92)
        p = phone(SHOT, ph)
        shadow(img, p, round(w * 0.70), round((h - ph) / 2))
        x = round(w * 0.06)
        text(d, (x, h * 0.20), "7 MOTION", font(44), ORANGE)
        text(d, (x, h * 0.32), "VOTRE M3U.", font(62), WHITE)
        text(d, (x, h * 0.45), "VOTRE XTREAM.", font(62), WHITE)
        text(d, (x, h * 0.62), "Direct · Films · Séries · EPG", font(30, False), GREY)
        text(d, (x, h * 0.72), "Lecteur — aucune chaîne fournie", font(22, False),
             (120, 120, 128))
    elif w == h:  # ---- CARRÉ : texte en haut, capture en bas ---------
        text(d, (w / 2, h * 0.09), "7 MOTION", font(52), ORANGE, "mm")
        text(d, (w / 2, h * 0.19), "VOTRE M3U. VOTRE XTREAM.", font(46), WHITE, "mm")
        text(d, (w / 2, h * 0.27), "Direct · Films · Séries · EPG",
             font(30, False), GREY, "mm")
        ph = round(h * 0.62)
        p = phone(SHOT, ph)
        shadow(img, p, round((w - p.width) / 2), round(h * 0.34))
        text(d, (w / 2, h * 0.975), "Lecteur — aucune chaîne fournie",
             font(22, False), (120, 120, 128), "mm")
    else:  # ---- PORTRAIT ------------------------------------------
        text(d, (w / 2, h * 0.08), "7 MOTION", font(58), ORANGE, "mm")
        text(d, (w / 2, h * 0.16), "VOTRE M3U.", font(60), WHITE, "mm")
        text(d, (w / 2, h * 0.215), "VOTRE XTREAM.", font(60), WHITE, "mm")
        text(d, (w / 2, h * 0.285), "Direct · Films · Séries · EPG",
             font(32, False), GREY, "mm")
        ph = round(h * 0.60)
        p = phone(SHOT, ph)
        shadow(img, p, round((w - p.width) / 2), round(h * 0.34))
        text(d, (w / 2, h * 0.975), "Lecteur — aucune chaîne fournie",
             font(24, False), (120, 120, 128), "mm")

    img.convert("RGB").save(out, "PNG", optimize=True)
    return out


if __name__ == "__main__":
    import sys
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    for w, h, name in [(1200, 628, "ads-paysage-1200x628.png"),
                       (1200, 1200, "ads-carre-1200x1200.png"),
                       (1200, 1500, "ads-portrait-1200x1500.png")]:
        p = build(w, h, os.path.join(outdir, name))
        print(f"{name:32s} {w}x{h}  {os.path.getsize(p)/1024:6.0f} Ko")
