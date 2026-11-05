#!/usr/bin/env python3
"""Refuse un vert sans exécution réelle ni captures du test de rendu."""

from pathlib import Path
import json
import sys
import xml.etree.ElementTree as ET


PIXEL_METHOD = "defaultOff_directPixels_onChangesRealPixels_offRestoresTheSameFrame"
MUTATION_MARKER = "PIXEL_CONTRAST_NOT_APPLIED"
RECOVERY_METHODS = {
    "pauseDuringHttp502Retry_staysPausedAndKeepsVodPosition",
    "sourceChangeSilenceBackgroundCastAndDispose_cancelPendingRetry",
    "sameSourceDirectRebuild_keepsTrackPreferences_newUrlClearsOverrides",
}
RECOVERY_PROOFS = (
    "pause-502", "cancel-new-url", "cancel-silence", "cancel-background",
    "cancel-suspendForCast", "cancel-dispose", "track-rebuild",
)


def verify(output: Path, mode: str) -> None:
    cases = []
    recovery = []
    for report in (output / "junit").rglob("*.xml"):
        root = ET.parse(report).getroot()
        cases.extend(
            case for case in root.iter("testcase")
            if case.get("classname", "").endswith("NativeContrastPixelTest")
        )
        recovery.extend(case for case in root.iter("testcase")
                        if case.get("classname", "").endswith("NativeRecoveryPlaybackTest"))
    if not any(case.get("name") == PIXEL_METHOD for case in cases):
        raise SystemExit("Test de pixels attendu non exécuté : preuve de rendu absente.")
    for case in cases:
        if any(case.find(tag) is not None for tag in ("error", "skipped")):
            raise SystemExit(f"Test de rendu interrompu/ignoré : {case.get('name', '?')}")
        failure = case.find("failure")
        if mode == "baseline" and failure is not None:
            raise SystemExit(f"Test de rendu non réussi : {case.get('name', '?')}")
        if mode == "mutation" and case.get("name") == PIXEL_METHOD:
            if failure is None:
                raise SystemExit("La mutation doit échouer sur une assertion des pixels.")
            failure_type = failure.get("type", "").strip()
            if not failure_type:
                # AGP place l'exception en tête du texte de <failure>, sans
                # attribut type. Ne lire que cette tête : une cause imbriquée
                # ou un marqueur cité dans une autre erreur ne prouve rien.
                lines = (failure.text or "").lstrip().splitlines()
                failure_type = lines[0].partition(":")[0].strip() if lines else ""
            if failure_type not in ("AssertionError", "java.lang.AssertionError"):
                raise SystemExit("La mutation doit échouer sur une assertion des pixels.")
            detail = failure.get("message", "") + " " + (failure.text or "")
            if MUTATION_MARKER not in detail:
                raise SystemExit("Échec différent de la régression de contraste recherchée.")
    captures = output / "contrast-pixels"
    images = ["01-default-off.png", "02-on.png"]
    if mode == "baseline":
        images.extend(["03-off-again.png", "04-on-again.png"])
    for image in images:
        if not (captures / image).is_file():
            raise SystemExit(f"Capture du test absente : {image}")
    measures = json.loads((captures / "measurements.json").read_text())
    if mode == "baseline" and measures.get("passed") is not True:
        raise SystemExit("Les mesures ne confirment pas la réussite du test de rendu.")
    if mode == "baseline":
        if not RECOVERY_METHODS.issubset({case.get("name") for case in recovery}):
            raise SystemExit("Régressions de reprise non exécutées : preuve de stabilité absente.")
        if any(case.find(tag) is not None for case in recovery for tag in ("error", "failure", "skipped")):
            raise SystemExit("Régression de reprise échouée ou ignorée.")
        for name in RECOVERY_PROOFS:
            path = captures / "recovery" / f"{name}.json"
            if not path.is_file() or json.loads(path.read_text()).get("passed") is not True:
                raise SystemExit(f"Preuve de reprise absente ou échouée : {name}")
    # La comparaison numérique est faite dans Android par le test instrumenté,
    # ce contrôle ne remplace pas les assertions sur les pixels rendus.
    sys.stdout.write(f"Preuve {mode} collectée : {len(cases)} tests de rendu, PNG et JSON.\n")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[2] not in ("baseline", "mutation"):
        raise SystemExit("Usage: verify-contrast-results.py <sorties> baseline|mutation")
    verify(Path(sys.argv[1]), sys.argv[2])
