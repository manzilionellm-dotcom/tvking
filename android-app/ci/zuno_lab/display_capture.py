"""Lit uniquement les pixels affichés. La capture complète reste temporaire."""
import io
from pathlib import Path
import subprocess
import tempfile

from PIL import Image


def capture_png():
    # La console émulateur lit son affichage côté hôte, indépendamment du
    # screencap Android qui a expiré sur le banc. Sur une box, utiliser ADB.
    with tempfile.TemporaryDirectory(prefix="zuno-screen-") as temp:
        try:
            subprocess.run(["adb", "emu", "screenrecord", "screenshot", temp],
                           capture_output=True, timeout=6, check=True)
            for snapshot in Path(temp).glob("*.png"):
                data = snapshot.read_bytes()
                with Image.open(io.BytesIO(data)) as image:
                    image.verify()
                return data
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
    data = subprocess.check_output(["adb", "exec-out", "screencap", "-p"],
                                   stderr=subprocess.DEVNULL, timeout=10)
    with Image.open(io.BytesIO(data)) as image:
        image.verify()
    return data
