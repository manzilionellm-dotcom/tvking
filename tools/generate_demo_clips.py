"""Fabrique les clips du mode démo — aucun téléchargement, aucun CDN.

On a passé la journée à courir après des hébergeurs : l'un renvoie 403,
l'autre exige un TLS que l'app ne négociait pas. Un mode démo ne doit
dépendre de personne : il se déclenche DEVANT un client, et il n'a pas
droit à l'erreur. Ces clips sont donc dessinés ici, encodés en H.264 +
AAC, et embarqués dans l'APK.

Trois mouvements par clip pour qu'on voie tout de suite que c'est une
vidéo et pas une image fixe : une lueur qui tourne, une barre qui se
remplit, un chronomètre qui court.
"""
import math
import os
import subprocess

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont

FF = imageio_ffmpeg.get_ffmpeg_exe()
W, H = 1280, 720
FPS = 12
SECONDS = 10
BG = (10, 10, 12)
ORANGE = (240, 122, 38)
WHITE = (240, 237, 233)
GREY = (138, 138, 144)

FONT_DIR = "/usr/share/fonts/truetype/dejavu"
F_TITLE = ImageFont.truetype(f"{FONT_DIR}/DejaVuSans-Bold.ttf", 74)
F_LABEL = ImageFont.truetype(f"{FONT_DIR}/DejaVuSans-Bold.ttf", 24)
F_MARK = ImageFont.truetype(f"{FONT_DIR}/DejaVuSans-Bold.ttf", 30)
F_TIME = ImageFont.truetype(f"{FONT_DIR}/DejaVuSansMono.ttf", 26)

# (nom de fichier, titre affiché, teinte de la lueur)
CLIPS = [
    ("sport", "SPORT", (240, 122, 38)),
    ("info", "INFO", (70, 140, 220)),
    ("divertissement", "DIVERTISSEMENT", (200, 80, 160)),
    ("enfants", "ENFANTS", (90, 190, 120)),
    ("musique", "MUSIQUE", (170, 100, 230)),
    ("documentaire", "DOCUMENTAIRE", (210, 170, 60)),
    ("film1", "FILM 1", (230, 90, 70)),
    ("film2", "FILM 2", (60, 180, 190)),
    ("film3", "FILM 3", (220, 140, 50)),
    ("film4", "FILM 4", (120, 130, 220)),
    ("guide1", "AJOUTER MA SOURCE", (240, 122, 38)),
    ("guide2", "TROUVER UNE CHAÎNE", (240, 122, 38)),
    ("guide3", "ENVOYER SUR MA TÉLÉ", (240, 122, 38)),
]


def glow(img, cx, cy, radius, colour, strength=0.30):
    """Lueur radiale douce, dessinée en anneaux concentriques."""
    d = ImageDraw.Draw(img, "RGBA")
    steps = 26
    for i in range(steps, 0, -1):
        r = radius * i / steps
        a = int(255 * strength * (1 - i / steps) ** 2)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*colour, a))


def centre(d, text, font, y, fill):
    w = d.textbbox((0, 0), text, font=font)[2]
    d.text(((W - w) / 2, y), text, font=font, fill=fill)


def frame(title, tint, t):
    """Une image à l'instant t (secondes)."""
    img = Image.new("RGB", (W, H), BG)
    # 1) la lueur ORBITE lentement — le mouvement de fond.
    ang = 2 * math.pi * t / SECONDS
    glow(img, W / 2 + math.cos(ang) * 430, H * 0.62 + math.sin(ang) * 190, 430,
         tint, strength=0.26)
    # VOILE sous le texte : sans lui, la lueur passe derrière le titre au
    # milieu du clip et le rend illisible — vu sur le premier rendu.
    scrim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(scrim)
    for i in range(90):
        a = int(150 * (1 - abs(i - 45) / 45))
        sd.line([(0, H * 0.22 + i * 3), (W, H * 0.22 + i * 3)],
                fill=(BG[0], BG[1], BG[2], a), width=3)
    img = Image.alpha_composite(img.convert("RGBA"), scrim).convert("RGB")
    d = ImageDraw.Draw(img, "RGBA")

    # Filet horizontal discret, pour asseoir le titre.
    d.line([(W * 0.18, H * 0.5), (W * 0.82, H * 0.5)], fill=(*tint, 60), width=2)

    centre(d, "MODE DÉMO", F_LABEL, H * 0.30, tint)
    centre(d, title, F_TITLE, H * 0.37, WHITE)
    centre(d, "7 MOTION ne fournit aucune chaîne", F_LABEL, H * 0.56, GREY)

    # 2) la barre se REMPLIT sur toute la durée.
    bx0, bx1, by = W * 0.18, W * 0.82, H * 0.72
    d.rounded_rectangle([bx0, by, bx1, by + 8], 4, fill=(45, 45, 52))
    d.rounded_rectangle(
        [bx0, by, bx0 + (bx1 - bx0) * (t / SECONDS), by + 8], 4, fill=tint
    )

    # 3) le chronomètre COURT.
    d.text((W * 0.18, H * 0.78), f"00:{int(t):02d} / 00:{SECONDS:02d}",
           font=F_TIME, fill=GREY)
    mark = "7 MOTION"
    mw = d.textbbox((0, 0), mark, font=F_MARK)[2]
    d.text((W * 0.82 - mw, H * 0.775), mark, font=F_MARK, fill=ORANGE)
    return img


def build(name, title, tint, outdir):
    out = os.path.join(outdir, f"{name}.mp4")
    proc = subprocess.Popen(
        [FF, "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
         "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
         "-shortest",
         "-c:v", "libx264", "-profile:v", "main", "-pix_fmt", "yuv420p",
         "-preset", "veryslow", "-crf", "30", "-g", str(FPS * 2),
         "-c:a", "aac", "-b:a", "48k",
         "-movflags", "+faststart", out],
        stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    for i in range(FPS * SECONDS):
        proc.stdin.write(frame(title, tint, i / FPS).tobytes())
    proc.stdin.close()
    proc.wait()
    return out


if __name__ == "__main__":
    import sys
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    total = 0
    for name, title, tint in CLIPS:
        p = build(name, title, tint, outdir)
        size = os.path.getsize(p)
        total += size
        print(f"{name:16s} {size/1024:7.0f} Ko")
    print(f"{'TOTAL':16s} {total/1024/1024:7.2f} Mo")
