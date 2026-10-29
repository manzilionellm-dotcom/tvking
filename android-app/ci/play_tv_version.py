"""Numérotation Play séparée de l'horodatage des APK installés hors Store.

Après un import accepté par Play, reporter son code dans lastUploadedVersionCode.
Après diffusion effective seulement, avancer lastPublishedVersionCode. Un bundle
encore en examen consomme son code sans devenir une version publiée. Le prochain
code dépasse d'une unité le plus grand des deux, sans reprendre un code utilisé.
"""
import json
import re
import sys
from pathlib import Path


def validate_version(data):
    previous = data.get("lastPublishedVersionCode")
    # Les anciens manifestes ne distinguaient pas les imports : garder leur
    # comportement tant qu'aucun code importé supplémentaire n'est renseigné.
    uploaded = data.get("lastUploadedVersionCode", previous)
    current = data.get("versionCode")
    name = data.get("versionName")
    # bool est une sous-classe d'int en Python : refuser aussi true/false.
    if any(type(code) is not int for code in (previous, uploaded, current)):
        raise ValueError("Les codes Play doivent être des entiers")
    if not 1 <= previous < current <= 2_100_000_000 or not 1 <= uploaded < current:
        raise ValueError("Code Play hors limite ou non croissant")
    if current != max(previous, uploaded) + 1:
        raise ValueError("Un build Play avance d'une unité après le dernier code publié ou importé")
    if not isinstance(name, str) or not re.fullmatch(r"[1-9][0-9]{0,8}", name):
        raise ValueError("Nom de version Play numérique requis")
    return current, name


if __name__ == "__main__":
    code, name = validate_version(json.loads(Path(sys.argv[1]).read_text()))
    # Le fichier d'environnement ne reçoit que des chiffres validés ; les
    # valeurs TV_BUILD_NUMBER/TV_VERSION_NAME de l'APK restent inchangées.
    with Path(sys.argv[2]).open("a", encoding="utf-8") as output:
        output.write(f"PLAY_VERSION_CODE={code}\nPLAY_VERSION_NAME={name}\n")
    print(f"Google Play : versionCode={code}, versionName={name}")
