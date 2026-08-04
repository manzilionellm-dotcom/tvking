"""Vidéos d'annonce pour la campagne Google Ads App — 7 MOTION.

Trois orientations, celles que Google réclame : 16:9, 9:16, 1:1.
15 secondes (le minimum est 10), H.264 + AAC.

Sans vidéo, l'inventaire YouTube est FERMÉ à la campagne : Google ne
peut diffuser que sur une partie de son réseau, la concurrence se
concentre sur ce qui reste, et le coût par installation monte. C'est ce
que coûte réellement le score « Médiocre » — pas une amende, un
rendement en moins pour le même budget.

Le fond et la capture sont calculés UNE FOIS : seuls le texte, le
balayage lumineux et la barre de progression changent d'une image à
l'autre. Recalculer un flou gaussien 300 fois par vidéo prendrait des
minutes pour un résultat identique.
"""
import os
import subprocess

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFilter, ImageFont

BG = (10, 10, 12)
ORANGE = (240, 122, 38)
WHITE = (240, 237, 233)
GREY = (150, 150, 158)

F = "/usr/share/fonts/truetype/dejavu"
SHOT = "marketing/play/screenshots/01-accueil-categories.png"
FPS = 20
SECONDS = 15


def font(size, bold=True):
    return ImageFont.truetype(
        f"{F}/DejaVuSans{'-Bold' if bold else ''}.ttf", size)


def glow(img, cx, cy, radius, colour, strength):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    r = radius * 0.42
    ImageDraw.Draw(layer).ellipse([cx - r, cy - r, cx + r, cy + r],
                                  fill=(*colour, int(255 * strength)))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius * 0.30)))


def phone(height):
    im = Image.open(SHOT).convert("RGB")
    w = round(im.width * height / im.height)
    im = im.resize((w, height), Image.LANCZOS)
    rad = round(height * 0.045)
    mask = Image.new("L", (w, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, height - 1], rad, fill=255)
    out = Image.new("RGBA", (w, height), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    ImageDraw.Draw(out).rounded_rectangle([0, 0, w - 1, height - 1], rad,
                                          outline=(255, 255, 255, 45), width=3)
    return out


def layout(w, h):
    """Position de la capture et ancrage du texte, selon l'orientation."""
    if w > h:                       # 16:9 — capture à droite
        ph = round(h * 0.86)
        p = phone(ph)
        return p, (round(w * 0.66), round((h - ph) / 2)), round(w * 0.07), False
    if w == h:                      # 1:1 — capture en bas
        ph = round(h * 0.56)
        p = phone(ph)
        return p, (round((w - phone(ph).width) / 2), round(h * 0.40)), w // 2, True
    ph = round(h * 0.54)            # 9:16 — capture en bas
    p = phone(ph)
    return p, (round((w - p.width) / 2), round(h * 0.40)), w // 2, True


def background(w, h):
    img = Image.new("RGBA", (w, h), (*BG, 255))
    glow(img, w * 0.80, h * 0.80, max(w, h) * 0.70, ORANGE, 0.55)
    glow(img, w * 0.05, h * 0.08, max(w, h) * 0.55, (50, 110, 190), 0.30)
    p, pos, tx, centred = layout(w, h)
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 150), (pos[0], pos[1] + 16), p.split()[3])
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(24)))
    img.alpha_composite(p, pos)
    return img, p, pos, tx, centred


def sweep(size, box, t):
    """Éclat qui traverse la capture — le seul mouvement sur l'écran fixe.

    Peint UNIQUEMENT sur la zone de la capture : une barre lumineuse en
    travers du fond noir se lirait comme un défaut d'encodage.
    """
    x, y, pw, ph = box
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    if not 0 <= t <= 1:
        return layer
    cx = x - pw * 0.4 + (pw * 1.8) * t
    band = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(band).polygon(
        [(cx, y), (cx + pw * 0.16, y), (cx + pw * 0.16 - ph * 0.30, y + ph),
         (cx - ph * 0.30, y + ph)], fill=(255, 255, 255, 46))
    band = band.filter(ImageFilter.GaussianBlur(pw * 0.05))
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([x, y, x + pw, y + ph],
                                           round(ph * 0.045), fill=255)
    layer.paste(band, (0, 0), mask)
    return layer


def build(w, h, out):
    base, p, pos, tx, centred = background(w, h)
    box = (pos[0], pos[1], p.width, p.height)
    s = min(w, h) / 1080          # échelle typographique
    f_mark, f_big, f_sub, f_fine = (font(round(46 * s)), font(round(64 * s)),
                                    font(round(34 * s), False),
                                    font(round(26 * s), False))
    anchor = "mm" if centred else None
    ty = (0.14, 0.22, 0.28) if centred else (0.22, 0.34, 0.50)

    # Les phrases apparaissent l'une après l'autre : à la 3ᵉ seconde on
    # sait CE QUE FAIT l'app, avant que le spectateur ne passe.
    lines = [(ty[0], "7 MOTION", f_mark, ORANGE, 0.0),
             (ty[1], "VOTRE M3U. VOTRE XTREAM.", f_big if centred else f_big,
              WHITE, 0.6),
             (ty[2], "Direct · Films · Séries · EPG", f_sub, GREY, 2.0)]

    proc = subprocess.Popen(
        [imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-f", "rawvideo",
         "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-r", str(FPS), "-i", "-",
         "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-shortest",
         "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p",
         "-preset", "medium", "-crf", "23", "-g", str(FPS * 2),
         "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", out],
        stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL)

    for i in range(FPS * SECONDS):
        t = i / FPS
        img = base.copy()
        img.alpha_composite(sweep((w, h), box, (t - 4.0) / 2.2))
        img.alpha_composite(sweep((w, h), box, (t - 10.0) / 2.2))
        d = ImageDraw.Draw(img, "RGBA")
        for y, txt, fnt, col, delay in lines:
            a = max(0.0, min(1.0, (t - delay) / 0.5))
            if a <= 0:
                continue
            d.text((tx, h * y), txt, font=fnt,
                   fill=(*col, int(255 * a)), anchor=anchor)
        # Barre de progression : elle donne le tempo et signale la fin.
        bx0, bx1, by = w * 0.07, w * 0.93, h * 0.955
        d.rounded_rectangle([bx0, by, bx1, by + max(3, 6 * s)], 3,
                            fill=(45, 45, 52, 200))
        d.rounded_rectangle(
            [bx0, by, bx0 + (bx1 - bx0) * (t / SECONDS), by + max(3, 6 * s)],
            3, fill=(*ORANGE, 235))
        d.text((tx, h * 0.90), "Lecteur — aucune chaîne fournie",
               font=f_fine, fill=(125, 125, 133), anchor=anchor)
        proc.stdin.write(img.convert("RGB").tobytes())

    proc.stdin.close()
    proc.wait()
    return out


if __name__ == "__main__":
    import sys
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    for w, h, name in [(1920, 1080, "video-16x9-1920x1080.mp4"),
                       (1080, 1920, "video-9x16-1080x1920.mp4"),
                       (1080, 1080, "video-1x1-1080x1080.mp4")]:
        p = build(w, h, os.path.join(outdir, name))
        print(f"{name:30s} {w}x{h}  {SECONDS}s  "
              f"{os.path.getsize(p)/1024/1024:5.2f} Mo")
