"""Choix du serveur sur la rangée Live–Films–Séries–Serveur–Réglages du vrai hub."""
import statistics

from zuno_ui_path import control, normalized

NAMES = (('live', 'direct'), ('movies', 'films'), ('series',),
         ('server', 'serveur'), ('settings', 'reglages'))


def dpad_to_server(nodes, words, image, focused):
    size=image.size
    # Un libellé film dans le titre voisin ne constitue pas une rangée de boutons.
    server=control([], words, size, NAMES[3])
    if server is None:
        return None, None
    row=[v for v in words if abs(v[2]-server[1]) <= size[1]*.018]
    chips=[control([], row, size, names) for names in NAMES]
    if not all(chips) or any(a[0]>=b[0] for a,b in zip(chips,chips[1:])):
        return None, None
    rowfocus=[i for i,names in enumerate(NAMES) if any(
        normalized(line) in names for text in focused for line in text.splitlines())]
    if len(rowfocus)==1:
        index=rowfocus[0]
        evidence='accessibility'
    else:
        # Le bouton actif de TvCinematicHome est rempli en or. Les autres
        # ont tous le même fond sombre. Médiane hors glyphes, garde de contraste.
        luma=image.convert('L')
        def level(point):
            x,y=point
            pixels=[luma.getpixel((int(x+size[0]*dx),int(y+size[1]*dy)))
                    for dx in (-.006,-.003,0,.003,.006)
                    for dy in (-.013,-.011,.011,.013)]
            return statistics.median(pixels)
        scores=[level(p) for p in chips]
        ranked=sorted(range(len(scores)),key=scores.__getitem__,reverse=True)
        if scores[ranked[0]]<70 or scores[ranked[0]]-scores[ranked[1]]<40:
            return None,None
        index=ranked[0];evidence='chip-fill'
    key='DPAD_LEFT' if index>3 else ('DPAD_RIGHT' if index<3 else 'DPAD_CENTER')
    return key, (NAMES[index][0],evidence)

def live_row_visible(nodes, words, size):
    """Exiger cinq entrées distinctes du vrai hub sur la même ligne."""
    height = size[1]
    for items, optical in (([], words), (nodes, [])):
        anchor = control(items, optical, size, NAMES[3])
        if anchor is None:
            continue
        row_nodes = [v for v in items if abs(v[2] - anchor[1]) <= .022 * height]
        row_words = [v for v in optical if abs(v[2] - anchor[1]) <= .022 * height]
        chips = [control(row_nodes, row_words, size, names) for names in NAMES]
        if all(chips) and all(a[0] < b[0] for a, b in zip(chips, chips[1:])):
            return True
    return False
