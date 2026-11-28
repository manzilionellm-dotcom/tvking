"""Compare les bibliothèques d'exécution du LAB avec l'AAB officiel 119."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile

def libs(archive, prefix):
    with zipfile.ZipFile(archive) as z:
        return {n.removeprefix(prefix): hashlib.sha256(z.read(n)).hexdigest()
                for n in z.namelist() if n.startswith(prefix) and n.endswith(".so")
                and not n.endswith("/libapp.so")}

original = libs(sys.argv[1], "base/lib/")
candidate = libs(sys.argv[2], "lib/")
evidence = {"baseline": original, "candidate": candidate,
            "identical": original == candidate}
Path(sys.argv[3]).write_text(json.dumps(evidence, indent=2, sort_keys=True)+"\n")
if not original or not evidence["identical"]:
    raise SystemExit("Inventaires natifs différents : contrôler le détail avant livraison")
