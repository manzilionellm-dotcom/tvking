#!/usr/bin/env python3
"""Refuse un vert sans exécution réelle ni captures du test de rendu."""

from pathlib import Path
import json
import sys
import xml.etree.ElementTree as ET


PIXEL_METHOD = "defaultOn_changesRealPixels_andOffOnOffRestoresTheSameFrame"
MUTATION_MARKER = "PIXEL_CONTRAST_NOT_APPLIED"


def verify(output: Path, mode: str) -> None:
    cases = []
    for report in (output / "junit").rglob("*.xml"):
        root = ET.parse(report).getroot()
        cases.extend(
            case for case in root.iter("testcase")
            if case.get("classname", "").endswith("NativeContrastPixelTest")
        )
    if not any(case.get("name") == PIXEL_METHOD for case in cases):
        raise SystemExit("Test de pixels attendu non exécuté : preuve de rendu absente.")
    for case in cases:
        if any(case.find(tag) is not None for tag in ("error", "skipped")):
            raise SystemExit(f"Test de rendu interrompu/ignoré : {case.get('name', '?')}")
        failure = case.find("failure")
        if mode == "baseline" and failure is not None:
            raise SystemExit(f"Test de rendu non réussi : {case.get('name', '?')}")
        if mode == "mutation" and case.get("name") == PIXEL_METHOD:
            if failure is None or "AssertionError" not in failure.get("type", ""):
                raise SystemExit("La mutation doit échouer sur une assertion des pixels.")
            detail = failure.get("message", "") + " " + (failure.text or "")
            if MUTATION_MARKER not in detail:
                raise SystemExit("Échec différent de la régression de contraste recherchée.")
    captures = output / "contrast-pixels"
    images = ["01-default-on.png", "02-off.png"]
    if mode == "baseline":
        images.extend(["03-on-again.png", "04-off-again.png"])
    for image in images:
        if not (captures / image).is_file():
            raise SystemExit(f"Capture du test absente : {image}")
    measures = json.loads((captures / "measurements.json").read_text())
    if mode == "baseline" and measures.get("passed") is not True:
        raise SystemExit("Les mesures ne confirment pas la réussite du test de rendu.")
    # La comparaison numérique est faite dans Android par le test instrumenté,
    # ce contrôle ne remplace pas les assertions sur les pixels rendus.
    sys.stdout.write(f"Preuve {mode} collectée : {len(cases)} tests de rendu, PNG et JSON.\n")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[2] not in ("baseline", "mutation"):
        raise SystemExit("Usage: verify-contrast-results.py <sorties> baseline|mutation")
    verify(Path(sys.argv[1]), sys.argv[2])
