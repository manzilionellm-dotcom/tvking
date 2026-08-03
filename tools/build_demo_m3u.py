"""Réécrit demo/7motion-demo.m3u en épinglant les clips au commit courant.

Les URL pointent sur GitHub à un SHA FIGÉ, jamais sur une branche : une
playlist qui suit une branche change de contenu sous les pieds de celui
qui la lit, et se casse le jour où la branche est supprimée.

Usage :  python3 tools/build_demo_m3u.py
"""
import os
import subprocess

REPO = "manzilionellm-dotcom/tvking"
ASSETS = "assets/demo"
OUT = "demo/7motion-demo.m3u"

# (fichier, nom affiché, groupe)
ENTRIES = [
    ("7motion_promo.mp4", "Démo — Découvrir 7 MOTION", "DÉMO || Présentation"),
    ("sport.mp4", "Démo Sport", "DÉMO || Sport"),
    ("info.mp4", "Démo Info", "DÉMO || Info"),
    ("divertissement.mp4", "Démo Divertissement", "DÉMO || Divertissement"),
    ("enfants.mp4", "Démo Enfants", "DÉMO || Enfants"),
    ("musique.mp4", "Démo Musique", "DÉMO || Musique"),
    ("documentaire.mp4", "Démo Documentaire", "DÉMO || Documentaire"),
    ("film1.mp4", "Démo — Film de démonstration 1", "DÉMO FILMS || Catalogue"),
    ("film2.mp4", "Démo — Film de démonstration 2", "DÉMO FILMS || Catalogue"),
    ("film3.mp4", "Démo — Film de démonstration 3", "DÉMO FILMS || Catalogue"),
    ("film4.mp4", "Démo — Film de démonstration 4", "DÉMO FILMS || Catalogue"),
    ("guide1.mp4", "Guide 1 — Ajouter ma source", "DÉMO FILMS || Guide"),
    ("guide2.mp4", "Guide 2 — Trouver une chaîne", "DÉMO FILMS || Guide"),
    ("guide3.mp4", "Guide 3 — Envoyer sur ma télé", "DÉMO FILMS || Guide"),
]


def main() -> None:
    sha = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True,
                         text=True, check=True).stdout.strip()
    base = f"https://raw.githubusercontent.com/{REPO}/{sha}/{ASSETS}"

    missing = [f for f, _, _ in ENTRIES
               if not os.path.exists(os.path.join(ASSETS, f))]
    if missing:
        raise SystemExit(
            "Clips absents de " + ASSETS + " : " + ", ".join(missing) +
            "\nLance d'abord tools/generate_demo_clips.py."
        )

    lines = ["#EXTM3U"]
    for f, name, group in ENTRIES:
        tvg = os.path.splitext(f)[0]
        lines.append(f'#EXTINF:-1 tvg-id="demo-{tvg}" tvg-name="{name}" '
                     f'group-title="{group}",{name}')
        lines.append(f"{base}/{f}")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"{OUT} — {len(ENTRIES)} entrées, épinglées sur {sha[:8]}")
    print("ATTENTION : les URL ne répondront qu'une fois ce commit POUSSÉ.")


if __name__ == "__main__":
    main()
