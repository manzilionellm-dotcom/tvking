#!/usr/bin/env python3
# =========================================================
#  make_brand_assets.py — Images de marque de l'édition NovaTube TV
# =========================================================
#  Pourquoi un script plutôt que des PNG dessinés à la main ?
#    • Reproductible : n'importe qui régénère EXACTEMENT les mêmes images
#      (mêmes couleurs que la palette Dart `TvNovatube`, même police).
#    • Original : rien n'est copié d'une autre application. Le logo est un
#      simple mot-symbole « NovaTube » (police Inter, licence OFL déjà
#      embarquée dans assets/fonts/) précédé d'un triangle « lecture ».
#    • Sans cadre : la demande du propriétaire est un logo intégré, SANS
#      carré ni cadre. Le mot-symbole est donc sur fond TRANSPARENT.
#      Seules l'icône du lanceur et la bannière Android TV ont un fond,
#      parce que le système Android l'exige pour ces deux emplacements.
#
#  Images produites (dans assets/branding/) :
#    novatube_tv_wordmark.png  1600×400, transparent — logo dans l'app
#    novatube_tv_splash.png     640×372, transparent — écran de lancement
#    novatube_tv_icon.png      1024×1024, fond pétrole — icône classique
#    novatube_tv_icon_fg.png   1024×1024, transparent — icône adaptative
#    novatube_tv_banner.png     320×180  — bannière Leanback (xhdpi)
#    novatube_tv_banner_2x.png  640×360  — bannière Leanback (xxhdpi)
#
#  Usage : python3 ci/novatube_tv/make_brand_assets.py
#  Dépendance : Pillow (déjà utilisée par les autres scripts ci/).
# =========================================================
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / 'assets/fonts/Inter-ExtraBold.ttf'
OUT = ROOT / 'assets/branding'

# Couleurs : IDENTIQUES à lib/features/tv/core/tv_novatube_palette.dart.
# Relevées sur la capture de référence du propriétaire (vert pétrole sombre,
# noir profond, turquoise discret). Un test vérifie que les deux restent
# alignées (test/novatube_tv/novatube_brand_assets_test.py).
BG = (0x05, 0x0F, 0x0C)          # fond « noir pétrole »
GLOW = (0x0B, 0x2A, 0x24)        # halo très sombre derrière le logo
TEXT = (0xE6, 0xEF, 0xEC)        # « Nova » : blanc doux (anti-halo)
ACCENT = (0x4E, 0xA8, 0x9C)      # turquoise discret (accent au repos)
ACCENT_BRIGHT = (0x73, 0xCD, 0xC3)  # turquoise vif (« Tube », focus)


def _font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT), size)


def _play_triangle(draw: ImageDraw.ImageDraw, box: tuple[float, float, float, float],
                   colour: tuple[int, int, int]) -> None:
    """Triangle « lecture » arrondi par un léger flou de bord (anti-aliasing)."""
    x0, y0, x1, y1 = box
    draw.polygon([(x0, y0), (x1, (y0 + y1) / 2), (x0, y1)], fill=colour + (255,))


def wordmark(width: int, height: int) -> Image.Image:
    """Mot-symbole transparent : ▶ Nova(blanc) Tube(turquoise)."""
    # On dessine 4× plus grand puis on réduit : bords nets, sans escalier.
    scale = 4
    w, h = width * scale, height * scale
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    size = int(h * 0.62)
    font = _font(size)
    nova, tube = 'Nova', 'Tube'
    nova_w = draw.textlength(nova, font=font)
    tube_w = draw.textlength(tube, font=font)
    tri = size * 0.62               # côté du triangle
    gap = size * 0.18               # espace triangle → texte
    total = tri + gap + nova_w + tube_w
    x = (w - total) / 2
    # Ligne de base : on centre la hauteur de capitale (≈ 0,73 em pour Inter).
    cap = size * 0.73
    top = (h - cap) / 2
    _play_triangle(draw, (x, top + cap * 0.08, x + tri * 0.87, top + cap * 0.92), ACCENT)
    x += tri + gap
    # anchor 'ls' = gauche / ligne de base → alignement exact des deux mots.
    baseline = top + cap
    draw.text((x, baseline), nova, font=font, fill=TEXT + (255,), anchor='ls')
    draw.text((x + nova_w, baseline), tube, font=font, fill=ACCENT_BRIGHT + (255,), anchor='ls')
    return img.resize((width, height), Image.LANCZOS)


def _petrol_background(width: int, height: int) -> Image.Image:
    """Fond pétrole avec un halo très doux au centre (pas d'aplat plat)."""
    img = Image.new('RGB', (width, height), BG)
    glow = Image.new('L', (width, height), 0)
    d = ImageDraw.Draw(glow)
    d.ellipse((width * 0.15, height * 0.1, width * 0.85, height * 0.9), fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(radius=max(width, height) * 0.18))
    halo = Image.new('RGB', (width, height), GLOW)
    return Image.composite(halo, img, glow)


def banner(width: int, height: int) -> Image.Image:
    """Bannière Leanback (16:9) : fond pétrole + mot-symbole centré."""
    img = _petrol_background(width, height).convert('RGBA')
    mark = wordmark(int(width * 0.84), int(width * 0.84 / 4))
    img.alpha_composite(mark, ((width - mark.width) // 2, (height - mark.height) // 2))
    return img.convert('RGB')


def icon_foreground(size: int, ratio: float) -> Image.Image:
    """Triangle « lecture » turquoise centré, sur transparent.

    `ratio` = part du côté occupée par le symbole. 0,58 pour l'icône
    adaptative : le masque rond d'Android ne garde que les 66 % centraux.
    """
    scale = 4
    s = size * scale
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    side = s * ratio
    # Le centre optique d'un triangle est décalé vers la gauche : on le
    # recentre d'environ 1/12 du côté pour qu'il « paraisse » centré.
    x0 = (s - side * 0.87) / 2 + side * 0.04
    y0 = (s - side) / 2
    _play_triangle(draw, (x0, y0, x0 + side * 0.87, y0 + side), ACCENT_BRIGHT)
    return img.resize((size, size), Image.LANCZOS)


def icon_full(size: int) -> Image.Image:
    img = _petrol_background(size, size).convert('RGBA')
    img.alpha_composite(icon_foreground(size, 0.50))
    return img.convert('RGB')


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    outputs = {
        'novatube_tv_wordmark.png': wordmark(1600, 400),
        'novatube_tv_splash.png': wordmark(640, 160),
        'novatube_tv_icon.png': icon_full(1024),
        'novatube_tv_icon_fg.png': icon_foreground(1024, 0.42),
        'novatube_tv_banner.png': banner(320, 180),
        'novatube_tv_banner_2x.png': banner(640, 360),
    }
    for name, image in outputs.items():
        # optimize=True : PNG plus léger, contenu identique.
        image.save(OUT / name, optimize=True)
        print(f'✓ {name} {image.size[0]}×{image.size[1]}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
