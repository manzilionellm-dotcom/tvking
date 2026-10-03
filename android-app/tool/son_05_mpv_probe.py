#!/usr/bin/env python3
# Mesure le même passe-haut que AudioSpectrum.kt (Butterworth ordre 2, 4 kHz)
# sur des signaux synthétiques. Aucun flux, aucun secret.
# Sert à voir ce qu'un mauvais réglage mpv ferait au chiffre « énergie > 4 kHz »,
# et ce que ce chiffre ne voit pas (peigne, voies inversées).

import math
import struct
import subprocess
import tempfile
import os

RATE = 48000
SPLIT = 4000.0
WARMUP = 512
N = 48000  # 1 seconde
WIDE = 0.40
LOW = 0.12


def biquad_highpass(rate, fc):
    q = math.sqrt(0.5)
    w0 = 2.0 * math.pi * fc / rate
    c = math.cos(w0)
    alpha = math.sin(w0) / (2.0 * q)
    a0 = 1.0 + alpha
    return (
        ((1.0 + c) / 2.0) / a0,
        (-(1.0 + c)) / a0,
        ((1.0 + c) / 2.0) / a0,
        (-2.0 * c) / a0,
        (1.0 - alpha) / a0,
    )


def biquad_lowpass(rate, fc):
    q = math.sqrt(0.5)
    w0 = 2.0 * math.pi * fc / rate
    c = math.cos(w0)
    alpha = math.sin(w0) / (2.0 * q)
    a0 = 1.0 + alpha
    return (
        ((1.0 - c) / 2.0) / a0,
        (1.0 - c) / a0,
        ((1.0 - c) / 2.0) / a0,
        (-2.0 * c) / a0,
        (1.0 - alpha) / a0,
    )


def apply_biquad(xs, coef):
    b0, b1, b2, a1, a2 = coef
    y = [0.0] * len(xs)
    x1 = x2 = y1 = y2 = 0.0
    for i, x in enumerate(xs):
        v = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, v
        y[i] = v
    return y


def ratio(xs):
    coef = biquad_highpass(RATE, SPLIT)
    b0, b1, b2, a1, a2 = coef
    sum_sq = 0.0
    sum_high = 0.0
    x1 = x2 = y1 = y2 = 0.0
    frames = 0
    for x in xs:
        v = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, v
        frames += 1
        if frames > WARMUP:
            sum_sq += x * x
            sum_high += v * v
    useful = max(0, frames - WARMUP)
    r = 0.0 if sum_sq <= 0 else sum_high / sum_sq
    mean_sq = 0.0 if useful <= 0 else sum_sq / useful
    if useful < 8192:
        band = "SHORT"
    elif mean_sq < 1e-8:
        band = "SILENCE"
    elif r >= WIDE:
        band = "LARGE"
    elif r <= LOW:
        band = "BASSE"
    else:
        band = "MILIEU"
    return r, band


def to_s16(xs):
    out = []
    for x in xs:
        s = int(max(-1.0, min(1.0, x)) * 32767.0)
        out.append(s)
    return out


def from_s16(samples):
    return [s / 32768.0 for s in samples]


def noise(seed, amp, n=N):
    # LCG, reproductible, pas de numpy obligatoire pour le bruit.
    x = seed & 0xFFFFFFFF
    out = []
    for _ in range(n):
        x = (1664525 * x + 1013904223) & 0xFFFFFFFF
        u = (x / 4294967296.0) * 2.0 - 1.0
        out.append(u * amp)
    return out


def speech():
    # Harmoniques de voix, rien au-dessus de 3,2 kHz.
    freqs = (150, 300, 600, 1200, 2400, 3200)
    out = []
    for i in range(N):
        t = i / RATE
        s = 0.0
        for f in freqs:
            s += math.sin(2 * math.pi * f * t)
        out.append(0.15 * s / len(freqs))
    return out


def delay_mix(xs, ms, gain):
    d = int(RATE * ms / 1000.0)
    out = []
    for i, x in enumerate(xs):
        y = x
        if i >= d:
            y += gain * xs[i - d]
        out.append(y * 0.5)
    return out


def pearson(a, b):
    n = min(len(a), len(b))
    ma = sum(a[:n]) / n
    mb = sum(b[:n]) / n
    num = den_a = den_b = 0.0
    for i in range(n):
        da = a[i] - ma
        db = b[i] - mb
        num += da * db
        den_a += da * da
        den_b += db * db
    if den_a <= 0 or den_b <= 0:
        return float("nan")
    return num / math.sqrt(den_a * den_b)


def aac_roundtrip(xs, bitrate):
    pcm = b"".join(struct.pack("<h", s) for s in to_s16(xs))
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "in.pcm")
        aac = os.path.join(d, "out.aac")
        dst = os.path.join(d, "back.pcm")
        open(src, "wb").write(pcm)
        subprocess.check_call(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error",
                "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", src,
                "-c:a", "aac", "-profile:a", "aac_low", "-b:a", bitrate,
                "-ar", str(RATE), "-y", aac,
            ],
            stdout=subprocess.DEVNULL,
        )
        subprocess.check_call(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error",
                "-i", aac, "-f", "s16le", "-ac", "1", "-ar", str(RATE), "-y", dst,
            ],
            stdout=subprocess.DEVNULL,
        )
        raw = open(dst, "rb").read()
    samples = [struct.unpack_from("<h", raw, i)[0] for i in range(0, len(raw) - 1, 2)]
    return from_s16(samples)


def show(name, xs):
    r, band = ratio(xs)
    print(f"{name}\t{r:.6f}\t{band}")


def main():
    blanc = noise(1, 0.4)
    show("bruit_blanc", blanc)
    lp = biquad_lowpass(RATE, 3400)
    bas = apply_biquad(apply_biquad(blanc, lp), lp)
    show("bruit_passe_bas_3k4_deux_fois", bas)
    voix = speech()
    show("voix_harmoniques_jusqu_a_3k2", voix)
    hp = biquad_highpass(RATE, 300)
    tel = apply_biquad(apply_biquad(blanc, hp), lp)
    tel = apply_biquad(tel, lp)
    show("bruit_bande_telephone_300_3400", tel)
    show("peigne_2ms_sur_bruit", delay_mix(blanc, 2.0, 0.8))
    show("peigne_20ms_sur_voix", delay_mix(voix, 20.0, 0.8))
    # Voies inversées : le mélange (G+D)/2 que fait la sonde tombe à ~0.
    gauche = voix
    droite = [-x for x in voix]
    mix = [(a + b) / 2.0 for a, b in zip(gauche, droite)]
    show("melange_voies_inversees", mix)
    rg = pearson(gauche, droite)
    print(f"correlation_voies_inversees\t{rg:.4f}")
    show("voie_gauche_seule_de_l_inverse", gauche)
    # Downmix « 5.1 » naïf vers stéréo : L, R, C, LFE, Ls, Rs tous du bruit
    # indépendant. Ce n'est pas un passe-bas.
    chans = [noise(10 + i, 0.3) for i in range(6)]
    stereo_l = []
    for i in range(N):
        L, R, C, lfe, Ls, Rs = (chans[k][i] for k in range(6))
        stereo_l.append(0.5 * L + 0.35 * C + 0.25 * Ls + 0.15 * lfe)
    show("downmix_6_voies_bruit_vers_stereo", stereo_l)
    show("aac_lc_128k_bruit", aac_roundtrip(blanc, "128k"))
    show("aac_lc_64k_bruit", aac_roundtrip(blanc, "64k"))
    show("aac_lc_128k_voix", aac_roundtrip(voix, "128k"))


if __name__ == "__main__":
    main()
