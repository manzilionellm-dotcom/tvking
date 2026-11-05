#!/usr/bin/env python3
"""Exige les pixels du modèle et les replis réels, sans score de box inventé."""

import json
import math
from pathlib import Path
import struct
import sys
import xml.etree.ElementTree as ET
import zlib


AI_METHOD = "realModelAndNativeFallbacksAreVerified"
REQUIRED_PROOFS = (
    "baselinePassed", "referenceExecuted", "activeFrameVerified",
    "gpuErrorFallbackVerified", "flushAndSessionVerified", "timestampsPreserved",
    "deadlineFallbackVerified", "noLateActivationVerified", "exactGeometryVerified",
    "lostMetadataFallbackVerified", "boundedStatusHeartbeatVerified",
)
IMAGES = {
    "reference-input.png": (16, 12),
    "reference-output.png": (32, 24),
    "model-output.png": (32, 24),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify_png(data: bytes, size: tuple[int, int], name: str) -> None:
    """Valide les captures RGB/RGBA 8 bits non entrelacées du test Android.

    L'en-tête seul ne prouve pas qu'une capture est consultable : chaque chunk
    doit être complet et avoir son CRC, puis les lignes d'image doivent pouvoir
    être décompressées jusqu'au bout. Aucune dépendance d'imagerie dans la CI.
    """
    def valid(condition, detail):
        require(condition, f"Capture IA illisible : {name} ({detail}).")

    valid(data[:8] == b"\x89PNG\r\n\x1a\n", "signature PNG")
    offset = 8
    header = None
    image_chunks = []
    image_ended = False
    palette_seen = False
    end_seen = False
    while offset < len(data):
        valid(len(data) - offset >= 12, "chunk tronqué")
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        end = offset + length + 12
        valid(length <= 0x7fffffff and end <= len(data), "données tronquées")
        valid(all(65 <= value <= 90 or 97 <= value <= 122 for value in kind) and
              not (kind[2] & 0x20), "type de chunk PNG invalide")
        payload = data[offset + 8:end - 4]
        crc = struct.unpack_from(">I", data, end - 4)[0]
        valid(zlib.crc32(kind + payload) & 0xffffffff == crc, "CRC incorrect")
        valid(header is not None or kind == b"IHDR", "IHDR absent en tête")
        if kind == b"IHDR":
            valid(header is None and length == 13, "IHDR invalide ou répété")
            header = struct.unpack(">IIBBBBB", payload)
            width, height, depth, color, compression, filtering, interlace = header
            valid((width, height) == size, "dimensions inattendues")
            valid(depth == 8 and color in (2, 6) and
                  (compression, filtering, interlace) == (0, 0, 0),
                  "capture attendue RGB/RGBA 8 bits non entrelacée")
        elif kind == b"IDAT":
            valid(not image_ended, "chunks IDAT non consécutifs")
            image_chunks.append(payload)
        elif kind == b"IEND":
            valid(length == 0 and image_chunks and end == len(data), "fin PNG invalide")
            end_seen = True
        else:
            if kind == b"PLTE":
                valid(not palette_seen and not image_chunks and
                      0 < length <= 768 and length % 3 == 0, "palette invalide")
                palette_seen = True
            else:
                valid(kind[0] & 0x20, "chunk critique inconnu")
            if image_chunks:
                image_ended = True
        offset = end

    valid(end_seen and header is not None and image_chunks, "image ou IEND manquant")
    channels = 3 if header[3] == 2 else 4
    stride = 1 + size[0] * channels
    expected_bytes = stride * size[1]
    decoder = zlib.decompressobj()
    try:
        # La taille attendue vient du contrat de fixture, pas du fichier.
        # Un octet supplémentaire suffit pour détecter une image trop longue.
        pixels = decoder.decompress(b"".join(image_chunks), expected_bytes + 1)
    except zlib.error as error:
        raise ValueError(f"Capture IA illisible : {name} (données zlib invalides).") from error
    valid(decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail and
          len(pixels) == expected_bytes, "lignes d'image tronquées ou excédentaires")
    valid(all(pixels[row * stride] <= 4 for row in range(size[1])), "filtre PNG invalide")


def verify(output: Path, expected: dict) -> dict:
    cases = []
    for report in (output / "junit").rglob("*.xml"):
        cases.extend(case for case in ET.parse(report).getroot().iter("testcase")
                     if case.get("classname", "").endswith(".AiPictureGpuTest"))
    require(any(case.get("name") == AI_METHOD for case in cases),
            "Le test GPU neuronal attendu n'a pas été exécuté.")
    require(not any(case.find(tag) is not None for case in cases
                    for tag in ("failure", "error", "skipped")),
            "Le test GPU neuronal a échoué, a été interrompu ou ignoré.")
    folder = output / "ai-picture"
    proof = json.loads((folder / "measurements.json").read_text())
    require(proof.get("schemaVersion") == 1, "Contrat de preuve IA inconnu.")
    for field in REQUIRED_PROOFS:
        require(proof.get(field) is True, f"Preuve IA absente ou échouée : {field}")
    require(type(proof.get("nativeRefusalsVerified")) is int and
            proof["nativeRefusalsVerified"] >= 3, "Les trois refus natifs ne sont pas prouvés.")
    for field in ("modelSha256", "pipelineSha256"):
        require(proof.get(field) == expected[field], f"La preuve IA vise un autre {field}.")
    # L'admission et l'horloge sont injectées pour tester un GPU d'émulateur.
    # Ces résultats prouvent le calcul/repli, jamais une cadence de box cliente.
    require(proof.get("testClockAndAdmissionInjected") is True and
            proof.get("performanceVerdict") == "NOT_MEASURED_ON_CLIENT_BOX",
            "La preuve doit distinguer l'essai fonctionnel d'un benchmark client.")
    for field, limit in (("referenceMaximumByteError", 4), ("referenceMeanByteError", 0.85)):
        value = proof.get(field)
        require(type(value) in (float, int) and math.isfinite(value) and 0 <= value <= limit,
                f"Pixels hors tolérance : {field}")
    for name, size in IMAGES.items():
        verify_png((folder / name).read_bytes(), size, name)
    return proof


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify-ai-picture-results.py <sorties-baseline>")
    assets = Path(__file__).resolve().parents[1] / "packages/native_video_player/android/src/main/assets/zuno_ai"
    expected = json.loads((assets / "manifest.json").read_text())
    proof = verify(Path(sys.argv[1]), expected)
    sys.stdout.write("Calcul neuronal GPU et replis natifs prouvés ; "
                     f"erreur max {proof['referenceMaximumByteError']}/255 ; "
                     "aucun verdict de performance sur une box cliente.\n")
