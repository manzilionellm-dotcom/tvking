"""Réutiliser l'encodeur préparé avant l'essai et ajouter une troisième signature vidéo."""
from pathlib import Path
import sys

s=Path(sys.argv[1]).read_text()
assert s.count("for ch in ('A','B')")==2
s=s.replace("for ch in ('A','B')","for ch in ('A','B','C')")
s=s.replace("440 if ch=='A' else 660","440 if ch=='A' else (660 if ch=='B' else 880)")
s=s.replace("('hflip,' if ch=='B' else '')","({'A':'','B':'hflip,','C':'vflip,'}[ch])")
Path(sys.argv[2]).write_text(s)
