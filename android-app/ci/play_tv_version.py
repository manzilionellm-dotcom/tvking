"""Numérotation Play séparée de l'horodatage des APK installés hors Store.

Après chaque publication Play, reporter son code dans lastPublishedVersionCode
et avancer versionCode d'une unité. Un bundle seulement importé, mais jamais
diffusé, ne devient pas la référence publiée. Google contrôle aussi l'unicité.
"""
import json
import re
import sys
from pathlib import Path


def validate_version(data):
    previous = data.get("lastPublishedVersionCode")
    current = data.get("versionCode")
    name = data.get("versionName")
    # bool est une sous-classe d'int en Python : refuser aussi true/false.
    if type(previous) is not int or type(current) is not int:
        raise ValueError("Les codes Play doivent être des entiers")
    if not 1 <= previous < current <= 2_100_000_000:
        raise ValueError("Code Play hors limite ou non croissant")
    if current != previous + 1:
        raise ValueError("Un build Play avance exactement d'une unité")
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
