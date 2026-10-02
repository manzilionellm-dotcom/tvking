#!/usr/bin/env python3
# Génère assets/audio/son_temoin.m4a
#
# 10 secondes, AAC-LC, 48 kHz, stéréo, deux voies identiques (pas d'opposition) :
#   0–5 s  voix synthétique (harmoniques sous 3,2 kHz) → aigus bas
#   5–10 s bruit blanc, les deux voies pareilles → aigus hauts
#
# Aucune parole réelle, aucune adresse. Après encodage on redécode et on
# vérifie les deux moitiés. Si le bruit encodé n'est plus large, le fichier
# ne sert à rien : on s'arrête.

import math
import os
import struct
import subprocess
import sys

SR = 48_000
SECONDS = 10
SPLIT = 5
OUT = os.path.join(
    os.path.dirname(__file__), "..", "..", "assets", "audio", "son_temoin.m4a"
)


def voice(t: float) -> float:
    f0 = 140.0
    acc = 0.0
    h = 1
    while f0 * h < 3200.0:
        acc += math.sin(2.0 * math.pi * f0 * h * t) / h
        h += 1
    env = 0.35 + 0.65 * max(0.0, math.sin(2.0 * math.pi * 3.5 * t))
    return acc * env * 0.08


def main() -> None:
    n = SR * SECONDS
    # Bruit déterministe, identique à gauche et à droite.
    state = 0x12345678

    def rnd() -> float:
        nonlocal state
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        return (state / 0x7FFFFFFF) * 2.0 - 1.0

    pcm = bytearray()
    for i in range(n):
        t = i / SR
        if t < SPLIT:
            s = voice(t)
        else:
            s = rnd() * 0.35
        v = max(-1.0, min(1.0, s))
        sample = int(v * 32767.0)
        pcm += struct.pack("<hh", sample, sample)

    raw = OUT + ".s16le"
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(raw, "wb") as f:
        f.write(pcm)

    subprocess.check_call(
        [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", raw,
            "-c:a", "aac", "-b:a", "160k", "-ar", str(SR), "-ac", "2",
            OUT,
        ]
    )
    decoded = OUT + ".decoded.s16le"
    subprocess.check_call(
        [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-i", OUT, "-f", "s16le", "-ac", "2", "-ar", str(SR), decoded,
        ]
    )
    with open(decoded, "rb") as f:
        back = f.read()
    os.remove(raw)
    os.remove(decoded)

    def ratio(buf: bytes) -> float:
        # Passe-haut Butterworth ordre 2 à 4 kHz, même idée que AudioSpectrum.
        q = math.sqrt(0.5)
        w0 = 2.0 * math.pi * 4000.0 / SR
        c = math.cos(w0)
        alpha = math.sin(w0) / (2.0 * q)
        a0 = 1.0 + alpha
        b0 = ((1.0 + c) / 2.0) / a0
        b1 = (-(1.0 + c)) / a0
        b2 = ((1.0 + c) / 2.0) / a0
        a1 = (-2.0 * c) / a0
        a2 = (1.0 - alpha) / a0
        x1 = x2 = y1 = y2 = 0.0
        sum_sq = 0.0
        sum_hi = 0.0
        frames = 0
        count = len(buf) // 4
        for i in range(count):
            left, right = struct.unpack_from("<hh", buf, i * 4)
            x = ((left + right) / 2.0) / 32768.0
            y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, x, y1, y
            frames += 1
            if frames > 512:
                sum_sq += x * x
                sum_hi += y * y
        return 0.0 if sum_sq <= 0.0 else sum_hi / sum_sq

    half = SR * SPLIT * 4
    low = ratio(back[:half])
    high = ratio(back[half : half * 2])
    print(f"voix {low:.4f}  bruit {high:.4f}  octets {os.path.getsize(OUT)}")
    if not (low <= 0.12 and high >= 0.40):
        sys.exit(f"témoin hors seuils : voix {low} bruit {high}")


if __name__ == "__main__":
    main()
