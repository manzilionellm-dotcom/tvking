"""Les deux écrans sont préparés séparément ; le stimulus, l'horloge et l'observateur sont communs."""
from pathlib import Path
import sys
from unittest.mock import patch

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root))
sys.path.insert(0, str(root / 'zaps_cadences'))
from zaps_cadences import observer

# Le seul remplacement vise la préparation propre au banc ZUNO. L'écran de
# départ de chaque application doit ensuite montrer deux compteurs A croissants.
def deja_ouvert(_out):
    return

if __name__ == '__main__':
    with patch.object(observer, "open_fixture", deja_ouvert):
        observer.run(Path(sys.argv[1]), 100)
