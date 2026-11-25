"""Décline l'icône de la fiche Play pour le lanceur et le premier écran TV."""
from pathlib import Path
from PIL import Image, ImageOps

APP = Path(__file__).resolve().parents[3]
LOGO = Path(__file__).with_name('zuno-play.png')


def apply():
    res = APP / 'android/app/src/main/res'
    with Image.open(LOGO) as icon:
        artwork = icon.convert('RGBA')
    for name in ('mipmap-*/ic_launcher.png', 'drawable-*/ic_launcher_foreground.png'):
        paths = list(res.glob(name))
        if not paths and name.startswith('mipmap'):
            raise ValueError(f'Icônes Android absentes : {name}')
        for path in paths:
            with Image.open(path) as image:
                size = image.size
            if 'foreground' in path.name:
                # Les lanceurs adaptatifs peuvent masquer le tiers extérieur.
                layer = Image.new('RGBA', size)
                side = round(size[0] * 2 / 3)
                tile = artwork.resize((side, side), Image.Resampling.LANCZOS)
                layer.alpha_composite(tile, ((size[0]-side)//2, (size[1]-side)//2))
            else:
                layer = artwork.resize(size, Image.Resampling.LANCZOS)
            layer.save(path)
    for folder, size in [('drawable', (320, 180)), ('drawable-xhdpi', (320, 180)),
                         ('drawable-xxhdpi', (640, 360))]:
        # Conserver le rapport du monogramme et son fond noir sur la tuile large.
        banner = ImageOps.pad(artwork.convert('RGB'), size, Image.Resampling.LANCZOS,
                              color=artwork.getpixel((0, 0))[:3])
        banner.save(res / folder / 'tv_banner.png')
    splash = res / 'drawable-nodpi/splash_logo.png'
    artwork.resize((160, 160), Image.Resampling.LANCZOS).save(splash)
    artwork.save(APP / 'assets/branding/zuno_logo.png')


if __name__ == '__main__':
    apply()
