"""Repère un libellé de la mire locale sur un écran réellement rendu."""
import csv
import io
import re
import subprocess
import sys
import unicodedata


def normaliser(texte):
    return ''.join(c for c in unicodedata.normalize('NFKD', texte).lower()
                   if c.isalnum())


def chercher(fichier, motif, gauche, droite):
    # Les coordonnées et les mots viennent uniquement de la capture du moment.
    from PIL import Image
    with Image.open(fichier) as im:
        largeur = im.width
    for psm in ('11', '6'):
        result = subprocess.run(['tesseract', fichier, 'stdout', '--psm', psm, 'tsv'],
                                capture_output=True, text=True, check=True)
        for mot in csv.DictReader(io.StringIO(result.stdout), delimiter='\t'):
            texte = normaliser(mot['text'] or '')
            x = int(mot['left']) + int(mot['width']) // 2
            y = int(mot['top']) + int(mot['height']) // 2
            if texte and re.fullmatch(motif, texte) and gauche <= x / largeur <= droite:
                return x, y
    return None


if __name__ == '__main__':
    point = chercher(sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]))
    if point is None:
        sys.exit(1)
    print(*point)
