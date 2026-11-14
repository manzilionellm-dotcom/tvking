#!/usr/bin/env python3
"""Mire « film hybride » : un petit HEVC local qui porte, comme les films 4K
récents, DEUX jeux de réglages d'image dans le même flux.

  - un message HDR10+ devant chaque image (unité SEI de type 39, message 4,
    signature B5 00 3C 00 01 04, contenu ST 2094-40 valide) ;
  - une unité Dolby Vision à la fin de chaque image (unité NAL de type 62).

C'est ce mélange que les clés Amazon à puce MT8696 ne savent pas afficher
(écran d'une seule couleur, le son continue). Le test instrumenté
NativeHybridHdrTest joue cette mire dans le VRAI lecteur et vérifie que le
filtre retire les deux jeux avant le décodeur, sans casser la lecture.

Aucun film, aucun téléchargement, aucun flux fournisseur : l'image est une
mire ffmpeg, les unités ajoutées sont fabriquées ici. L'unité Dolby Vision
ne contient pas de vrais réglages : seul son type compte pour le filtre, et
un décodeur ordinaire ignore ce type.
"""

import json
from pathlib import Path
import subprocess
import tempfile

APP = Path(__file__).resolve().parents[1]
OUTPUT = APP / "packages/native_video_player/android/src/androidTest/assets/hybrid_hdr.mkv"

WIDTH, HEIGHT, RATE, SECONDS = 256, 144, 15, 40

NAL_AUD = 35
NAL_PREFIX_SEI = 39
NAL_DOLBY_RPU = 62
HDR10_PLUS_SIGNATURE = bytes([0xB5, 0x00, 0x3C, 0x00, 0x01, 0x04])
START_CODE = b"\x00\x00\x00\x01"


def split_nals(stream: bytes) -> list[bytes]:
    """Découpe un flux Annex B en unités NAL (sans leur code de départ)."""
    nals = []
    position = stream.find(b"\x00\x00\x01")
    while position >= 0:
        begin = position + 3
        following = stream.find(b"\x00\x00\x01", begin)
        end = len(stream) if following < 0 else following
        # Les zéros devant un code de départ lui appartiennent.
        while end > begin and stream[end - 1] == 0:
            end -= 1
        nals.append(stream[begin:end])
        position = following
    return nals


def nal_type(nal: bytes) -> int:
    return (nal[0] >> 1) & 0x3F


def escape(rbsp: bytes) -> bytes:
    """Ajoute l'octet 03 après deux zéros quand l'octet suivant vaut 0 à 3."""
    out = bytearray()
    zeros = 0
    for value in rbsp:
        if zeros >= 2 and value <= 3:
            out.append(3)
            zeros = 0
        out.append(value)
        zeros = zeros + 1 if value == 0 else 0
    return bytes(out)


def unescape(nal: bytes) -> bytes:
    out = bytearray()
    zeros = 0
    for value in nal:
        if zeros >= 2 and value == 3:
            zeros = 0
            continue
        out.append(value)
        zeros = zeros + 1 if value == 0 else 0
    return bytes(out)


def nal(kind: int, rbsp: bytes) -> bytes:
    return bytes([kind << 1, 0x01]) + escape(rbsp)


def bits(*fields: tuple[int, int]) -> bytes:
    """Colle des champs (valeur, nombre de bits), complète à l'octet par des 0."""
    text = "".join(format(value, f"0{width}b") for value, width in fields)
    text += "0" * (-len(text) % 8)
    return int(text, 2).to_bytes(len(text) // 8, "big")


def hdr10_plus_sei(frame: int) -> bytes:
    """Message HDR10+ complet (SMPTE ST 2094-40), une fenêtre, sans courbe."""
    metadata = bits(
        (1, 8),                      # application_version
        (1, 2),                      # num_windows
        (4000, 27),                  # luminance maximale visée
        (0, 1),                      # pas de tableau de luminance réelle
        (30000 + frame % 500, 17),   # maxscl rouge (change à chaque image)
        (30000, 17),                 # maxscl vert
        (30000, 17),                 # maxscl bleu
        (12000, 17),                 # moyenne
        (0, 4),                      # aucun centile
        (10, 10),                    # part de pixels clairs
        (0, 1),                      # pas de luminance de mastering
        (0, 1),                      # pas de courbe de tons
        (0, 1),                      # pas de saturation
    )
    payload = HDR10_PLUS_SIGNATURE + metadata
    assert len(payload) < 255
    message = bytes([4, len(payload)]) + payload
    return nal(NAL_PREFIX_SEI, message + b"\x80")


def dolby_rpu(frame: int) -> bytes:
    """Unité de type 62. Contenu de remplissage, jamais nul en fin d'unité."""
    body = bytes([0x19]) + bytes((0x21 + (frame * 7 + i * 13) % 0xC0) for i in range(120))
    return nal(NAL_DOLBY_RPU, body + b"\x80")


def access_units(nals: list[bytes]) -> list[list[bytes]]:
    """x265 est lancé avec aud=1 : chaque image commence par une unité AUD."""
    units: list[list[bytes]] = []
    for item in nals:
        if nal_type(item) == NAL_AUD or not units:
            units.append([])
        units[-1].append(item)
    return units


def inject(stream: bytes) -> tuple[bytes, int]:
    out = bytearray()
    units = access_units(split_nals(stream))
    for frame, unit in enumerate(units):
        first_picture = next(i for i, item in enumerate(unit) if nal_type(item) < 32)
        hybrid = unit[:first_picture] + [hdr10_plus_sei(frame)] + unit[first_picture:] + [dolby_rpu(frame)]
        for item in hybrid:
            out += START_CODE + item
    return bytes(out), len(units)


def carries_hdr10_plus(item: bytes) -> bool:
    if nal_type(item) != NAL_PREFIX_SEI:
        return False
    rbsp = unescape(item[2:])
    return rbsp[0] == 4 and rbsp[2:2 + len(HDR10_PLUS_SIGNATURE)] == HDR10_PLUS_SIGNATURE


def ffmpeg(*arguments: str) -> None:
    subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", *arguments], check=True)


def build() -> dict:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    frames = RATE * SECONDS
    with tempfile.TemporaryDirectory() as folder:
        plain = Path(folder) / "plain.h265"
        hybrid = Path(folder) / "hybrid.h265"
        back = Path(folder) / "back.h265"
        # Mire qui bouge (les images diffèrent), une image clé par seconde,
        # pas d'image B : l'ordre de décodage est l'ordre d'affichage.
        ffmpeg(
            "-f", "lavfi", "-i", f"testsrc2=s={WIDTH}x{HEIGHT}:r={RATE}:d={SECONDS}",
            "-an", "-c:v", "libx265", "-preset", "veryfast", "-pix_fmt", "yuv420p",
            "-x265-params",
            f"keyint={RATE}:min-keyint={RATE}:scenecut=0:bframes=0:repeat-headers=1:aud=1:info=0:log-level=error",
            "-fflags", "+bitexact", "-flags:v", "+bitexact", "-f", "hevc", str(plain),
        )
        stream, count = inject(plain.read_bytes())
        assert count == frames, f"{count} images encodées, {frames} attendues"
        hybrid.write_bytes(stream)
        # Conteneur Matroska, comme les films : le lecteur le relit en Annex B.
        ffmpeg(
            "-fflags", "+genpts", "-framerate", str(RATE), "-f", "hevc", "-i", str(hybrid),
            "-c", "copy", "-fflags", "+bitexact", "-f", "matroska", str(OUTPUT),
        )
        # Contre-vérification : ce que le conteneur rend au lecteur porte
        # bien les deux jeux, sur CHAQUE image.
        ffmpeg("-i", str(OUTPUT), "-c", "copy", "-bsf:v", "hevc_mp4toannexb", "-f", "hevc", str(back))
        stored = split_nals(back.read_bytes())
        pictures = sum(1 for item in stored if nal_type(item) < 32)
        dolby = sum(1 for item in stored if nal_type(item) == NAL_DOLBY_RPU)
        hdr = sum(1 for item in stored if carries_hdr10_plus(item))
        assert pictures == frames, f"{pictures} images dans le conteneur, {frames} attendues"
        assert dolby == frames, f"{dolby} unités Dolby Vision pour {frames} images"
        assert hdr == frames, f"{hdr} messages HDR10+ pour {frames} images"
    probe = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-of", "json", str(OUTPUT),
    ], text=True))
    assert len(probe["streams"]) == 1, "La mire doit être muette."
    video = probe["streams"][0]
    assert video["codec_name"] == "hevc"
    assert (video["width"], video["height"]) == (WIDTH, HEIGHT)
    return {
        "fixture": str(OUTPUT), "bytes": OUTPUT.stat().st_size, "width": WIDTH, "height": HEIGHT,
        "frames": frames, "hdr10_plus_messages": hdr, "dolby_vision_units": dolby, "audio": False,
    }


if __name__ == "__main__":
    print(json.dumps(build()))
