#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Banc PHASE ET CANAUX.

Fabrique des AAC-LC 48 kHz (aucun flux, aucun mot de passe) et mesure
ce que le décodeur FFmpeg en rend : corrélation gauche/droite, niveau
RMS(G−D)/RMS(G+D), part de la bande 300 Hz – 3 kHz annulée dans la
somme (G+D)/2.

Le décodeur ici est FFmpeg 6.1.1 (le paquet de la machine). Le .so
Jellyfin de la box est lavc 60.3 (FFmpeg 6.0) : même famille, pas le
même binaire. On ne prétend pas avoir entendu le résultat.

Usage :
  python3 android-app/tools/son/phase_canaux.py
"""

from __future__ import annotations

import math
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

RATE = 48_000
DUREE = 1.0
N = int(RATE * DUREE)
VOIX_BAS = 300.0
VOIX_HAUT = 3_000.0
FFT = 8192
SEUIL = 0.25  # −12 dB, le même que ChannelPath


def voix(n: int, f0: float, phase: float = 0.0) -> np.ndarray:
    """Harmoniques façon voyelle, bande surtout sous 3,6 kHz."""
    i = np.arange(n, dtype=np.float64)
    env = 0.65 + 0.35 * np.sin(2 * math.pi * 3.0 * i / RATE)
    s = np.zeros(n, dtype=np.float64)
    h = 1
    f = f0
    while f < 3600 and h <= 24:
        if 500 <= f <= 900:
            form = 2.2
        elif 1000 <= f <= 1600:
            form = 1.6
        else:
            form = 1.0
        s += (form / h) * np.sin(2 * math.pi * f * i / RATE + phase * h)
        h += 1
        f = f0 * h
    return s * env * 1800.0


def vers_s16(x: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(x), -32768, 32767).astype(np.int16)


def ecrire_wav(chemin: Path, voies: np.ndarray) -> None:
    """voies : forme (trames, canaux), int16."""
    canaux = voies.shape[1]
    with wave.open(str(chemin), "wb") as w:
        w.setnchannels(canaux)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(voies.astype("<i2").tobytes())


def ffmpeg(args: list[str]) -> None:
    r = subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", *args],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        raise SystemExit(f"ffmpeg a échoué : {' '.join(args[:6])}")


def decoder_wav(aac: Path, wav: Path, extra: list[str] | None = None) -> None:
    ffmpeg(["-y", "-i", str(aac), *(extra or []), str(wav)])


def lire_wav(chemin: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(chemin), "rb") as w:
        canaux = w.getnchannels()
        brut = w.readframes(w.getnframes())
    pcm = np.frombuffer(brut, dtype="<i2").astype(np.float64)
    if canaux == 0:
        return pcm.reshape(0, 1), 1
    trames = pcm.reshape(-1, canaux)
    return trames, canaux


def ffprobe_canaux(chemin: Path) -> str:
    r = subprocess.run(
        [
            "ffprobe", "-hide_banner", "-loglevel", "error",
            "-show_entries", "stream=codec_name,profile,channels,channel_layout,sample_rate",
            "-of", "default=nw=1", str(chemin),
        ],
        capture_output=True, text=True,
    )
    return " ".join(line.strip() for line in r.stdout.splitlines() if line.strip())


def correlation(g: np.ndarray, d: np.ndarray) -> float:
    if g.size < 1000 or d.size < 1000:
        return float("nan")
    g = g - g.mean()
    d = d - d.mean()
    vg = float(np.dot(g, g))
    vd = float(np.dot(d, d))
    if vg <= 1e-6 or vd <= 1e-6:
        return float("nan")
    return float(np.dot(g, d) / math.sqrt(vg * vd))


def niveau(g: np.ndarray, d: np.ndarray) -> float:
    side = g - d
    mid = g + d
    es = float(np.dot(side, side))
    em = float(np.dot(mid, mid))
    if em <= 1e-6 and es <= 1e-6:
        return 0.0
    if em <= 1e-6:
        return float("inf")
    return math.sqrt(es / em)


def creux_inter(g: np.ndarray, d: np.ndarray) -> float:
    n = min(g.size, d.size)
    if n < FFT:
        return float("nan")
    start = (n - FFT) // 2
    fen = np.hanning(FFT)
    gg = g[start:start + FFT] * fen
    dd = d[start:start + FFT] * fen
    ss = (gg + dd) / 2.0
    mag_g = np.abs(np.fft.rfft(gg))
    mag_d = np.abs(np.fft.rfft(dd))
    mag_s = np.abs(np.fft.rfft(ss))
    bin_bas = max(1, int(VOIX_BAS * FFT / RATE))
    bin_haut = min(int(VOIX_HAUT * FFT / RATE), mag_g.size - 1)
    ref = (mag_g[bin_bas:bin_haut] + mag_d[bin_bas:bin_haut]) / 2.0
    somme = mag_s[bin_bas:bin_haut]
    pic = float(ref.max()) if ref.size else 0.0
    if pic <= 1e-9:
        return 0.0
    utiles = ref >= 0.02 * pic
    if not np.any(utiles):
        return 0.0
    annules = utiles & (somme < SEUIL * ref)
    return float(np.count_nonzero(annules) / np.count_nonzero(utiles))


def energie_voix(x: np.ndarray) -> float:
    """Énergie FFT dans 300–3000 Hz. Pas le filtre du Kotlin : un ordre de grandeur."""
    if x.size < 1024:
        return 0.0
    spec = np.abs(np.fft.rfft(x * np.hanning(x.size))) ** 2
    freqs = np.fft.rfftfreq(x.size, 1.0 / RATE)
    masque = (freqs >= VOIX_BAS) & (freqs <= VOIX_HAUT)
    return float(spec[masque].sum())


def mesurer(trames: np.ndarray) -> dict[str, float]:
    g = trames[:, 0]
    d = trames[:, 1] if trames.shape[1] > 1 else np.zeros_like(g)
    return {
        "corr": correlation(g, d),
        "niveau": niveau(g, d),
        "creux": creux_inter(g, d),
        "voix_g": energie_voix(g),
        "voix_d": energie_voix(d),
        "voix_somme": energie_voix((g + d) / 2.0),
    }


def fmt(v: float) -> str:
    if math.isnan(v):
        return "     illisible"
    if math.isinf(v):
        return "       infini"
    return f"{v:14.4f}"


def ligne(nom: str, m: dict[str, float], note: str = "") -> None:
    garde = float("nan")
    if m["voix_g"] > 1e-6:
        garde = m["voix_somme"] / m["voix_g"]
    print(
        f"{nom:<42} corr {fmt(m['corr'])}  niveau {fmt(m['niveau'])}  "
        f"creux {fmt(m['creux'])}  garde {fmt(garde)}  {note}"
    )


def encoder(wav: Path, aac: Path, extra: list[str]) -> None:
    ffmpeg([
        "-y", "-i", str(wav),
        "-c:a", "aac", "-profile:a", "aac_low", "-b:a", "128k",
        "-ar", "48000",
        *extra,
        "-f", "adts", str(aac),
    ])


def roundtrip(nom: str, voies: np.ndarray, extra: list[str], note: str) -> dict[str, float]:
    with tempfile.TemporaryDirectory(prefix="zuno-phase-") as tmp:
        tmp_path = Path(tmp)
        wav = tmp_path / "in.wav"
        aac = tmp_path / "out.aac"
        back = tmp_path / "back.wav"
        ecrire_wav(wav, vers_s16(voies))
        encoder(wav, aac, extra)
        probe = ffprobe_canaux(aac)
        decoder_wav(aac, back)
        trames, _ = lire_wav(back)
        # Le décodeur ajoute le délai d'encodeur : on aligne grossièrement
        # en jetant le début, la mesure est sur la fenêtre du milieu.
        m = mesurer(trames)
        ligne(nom, m, note + " | " + probe)
        return m


def patch_config_canal(aac: Path, dest: Path, config: int) -> None:
    """
    Change les 3 bits channel_configuration de chaque en-tête ADTS.
    Bits 23..25 du flux : bit 0 de l'octet 2, bits 7 et 6 de l'octet 3.
    """
    data = bytearray(aac.read_bytes())
    i = 0
    n = 0
    while i + 7 < len(data):
        if data[i] != 0xFF or (data[i + 1] & 0xF0) != 0xF0:
            i += 1
            continue
        # protection_absent = bit 0 de l'octet 1. En-tête 7 octets, ou 9 si CRC.
        protection_absent = data[i + 1] & 0x01
        header = 7 if protection_absent else 9
        # longueur de trame : bits 30..42, soit 13 bits.
        longueur = ((data[i + 3] & 0x03) << 11) | (data[i + 4] << 3) | ((data[i + 5] & 0xE0) >> 5)
        if longueur < header or i + longueur > len(data):
            break
        # bit 23 = LSB de l'octet 2. bits 24-25 = les deux bits de poids fort de l'octet 3.
        data[i + 2] = (data[i + 2] & 0xFE) | ((config >> 2) & 0x01)
        data[i + 3] = (data[i + 3] & 0x3F) | ((config & 0x03) << 6)
        n += 1
        i += longueur
    dest.write_bytes(data)
    print(f"  en-têtes ADTS réécrits : {n}, channel_configuration forcé à {config}")


def cinq_un() -> np.ndarray:
    i = np.arange(N, dtype=np.float64)
    l = np.sin(2 * math.pi * 6000 * i / RATE) * 4000
    r = l.copy()
    c = voix(N, 140.0)
    lfe = np.sin(2 * math.pi * 80 * i / RATE) * 8000
    ls = np.sin(2 * math.pi * 8000 * i / RATE) * 800
    rs = np.sin(2 * math.pi * 9000 * i / RATE) * 800
    return np.stack([l, r, c, lfe, ls, rs], axis=1)


def main() -> None:
    print("Banc phase / canaux — signaux synthétiques, AAC-LC 48 kHz, FFmpeg")
    print("corr = corrélation G/D ; niveau = RMS(G−D)/RMS(G+D) ;")
    print("creux = part des bins 300–3000 Hz annulés dans (G+D)/2 ;")
    print("garde = énergie de voix de la somme / énergie de voix de la gauche")
    print()

    i = np.arange(N)
    v = voix(N, 140.0)
    v180 = voix(N, 180.0)
    autre = voix(N, 230.0, phase=1.3)
    retard = np.concatenate([np.zeros(96), v180[:-96]])
    retard_aac = np.concatenate([np.zeros(1024), v180[:-1024]])

    cas = [
        ("PCM en phase (avant AAC)", np.stack([v, v], 1), None, "témoin"),
        ("PCM hors phase", np.stack([v, -v], 1), None, "trou de phase"),
        ("PCM retard 2 ms", np.stack([v180, retard], 1), None, "peigne"),
        ("PCM retard 1024", np.stack([v180, retard_aac], 1), None, "peigne trame"),
        ("PCM deux voix", np.stack([v, autre], 1), None, "deux programmes"),
        ("PCM mono dupliqué", np.stack([v, v], 1), None, "pas un trou"),
    ]
    for nom, voies, _, note in cas:
        ligne(nom, mesurer(voies), note)

    print()
    print("--- aller-retour AAC-LC 128 kb/s ---")
    roundtrip("AAC défaut, en phase", np.stack([v, v], 1), [], "M/S auto + intensity")
    roundtrip("AAC défaut, hors phase", np.stack([v, -v], 1), [], "M/S auto + intensity")
    roundtrip("AAC M/S forcé, hors phase", np.stack([v, -v], 1), ["-aac_ms", "1"], "aac_ms=1")
    roundtrip(
        "AAC sans M/S ni intensity, hors phase",
        np.stack([v, -v], 1),
        ["-aac_ms", "0", "-aac_is", "0"],
        "voies indépendantes",
    )
    roundtrip("AAC défaut, retard 2 ms", np.stack([v180, retard], 1), [], "le retard survit-il ?")
    roundtrip("AAC défaut, deux voix", np.stack([v, autre], 1), [], "deux programmes")
    roundtrip(
        "AAC sans joint, deux voix",
        np.stack([v, autre], 1),
        ["-aac_ms", "0", "-aac_is", "0"],
        "indépendant",
    )

    # Milieu / écart stockés comme gauche / droite, sans que l'encodeur
    # les retransforme (voies indépendantes).
    a = v
    b = autre
    mid = (a + b) / 2
    side = (a - b) / 2
    roundtrip(
        "AAC sans joint, M et S comme G et D",
        np.stack([mid, side], 1),
        ["-aac_ms", "0", "-aac_is", "0"],
        "couple non décodé",
    )

    print()
    print("--- 5.1, voix seulement au centre ---")
    mix = cinq_un()
    with tempfile.TemporaryDirectory(prefix="zuno-51-") as tmp:
        tmp_path = Path(tmp)
        brut = tmp_path / "51.pcm"
        wav = tmp_path / "51.wav"
        aac = tmp_path / "51.aac"
        faux = tmp_path / "51-config2.aac"
        brut.write_bytes(vers_s16(mix).astype("<i2").tobytes())
        ffmpeg([
            "-y", "-f", "s16le", "-ar", "48000", "-ac", "6",
            "-channel_layout", "5.1", "-i", str(brut), str(wav),
        ])
        ffmpeg([
            "-y", "-i", str(wav),
            "-c:a", "aac", "-profile:a", "aac_low", "-b:a", "320k",
            "-ar", "48000", "-f", "adts", str(aac),
        ])
        print("  5.1 déclaré juste :", ffprobe_canaux(aac))

        def voix_stereo(chemin: Path) -> float:
            trames, canaux = lire_wav(chemin)
            if canaux < 2:
                return energie_voix(trames[:, 0])
            return energie_voix(trames[:, 0]) + energie_voix(trames[:, 1])

        # Décodeur tel quel (6 voies).
        entier = tmp_path / "entier.wav"
        decoder_wav(aac, entier)
        trames, canaux = lire_wav(entier)
        print(f"  décodé : {canaux} voies, trames {trames.shape[0]}")
        voix_centre = energie_voix(trames[:, 2]) if canaux >= 3 else float("nan")
        voix_lr = energie_voix(trames[:, 0]) + energie_voix(trames[:, 1])
        print(f"  voix centre décodé {voix_centre:.3e}   voix L+R {voix_lr:.3e}")

        # Premières voies seulement : le masque Media3 qui jette au lieu de mélanger.
        premieres = tmp_path / "premieres.wav"
        ffmpeg([
            "-y", "-i", str(aac),
            "-af", "pan=stereo|c0=c0|c1=c1",
            str(premieres),
        ])
        # Downmix FFmpeg (-ac 2) : il garde le centre.
        melange = tmp_path / "melange.wav"
        ffmpeg(["-y", "-i", str(aac), "-ac", "2", str(melange)])
        v_pre = voix_stereo(premieres)
        v_mix = voix_stereo(melange)
        print(f"  voix stéréo « deux premières voies » {v_pre:.3e}")
        print(f"  voix stéréo downmix ffmpeg -ac 2     {v_mix:.3e}")
        if v_mix > 0:
            print(f"  rapport premières / downmix = {v_pre / v_mix:.4f}")

        # 5.1 en LC dont l'en-tête ADTS dit « 2 voies ».
        patch_config_canal(aac, faux, 2)
        print("  5.1 en-tête forcé à 2 :", ffprobe_canaux(faux))
        mal = tmp_path / "mal.wav"
        r = subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "warning", "-y", "-i", str(faux), str(mal)],
            capture_output=True, text=True,
        )
        if r.returncode != 0 or not mal.exists():
            print("  le décodeur a refusé le 5.1 déclaré 2 voies")
            print("\n".join(r.stderr.splitlines()[:8]))
        else:
            trames_mal, canaux_mal = lire_wav(mal)
            print(f"  décodé malgré l'en-tête : {canaux_mal} voies, trames {trames_mal.shape[0]}")
            if canaux_mal >= 3:
                print(f"  voix centre {energie_voix(trames_mal[:, 2]):.3e}  voix L+R "
                      f"{energie_voix(trames_mal[:, 0]) + energie_voix(trames_mal[:, 1]):.3e}")
            elif canaux_mal == 2:
                m = mesurer(trames_mal)
                ligne("  5.1 lu comme stéréo", m, "en-tête ADTS = 2")
            elif canaux_mal == 1:
                print(f"  une seule voie, voix {energie_voix(trames_mal[:, 0]):.3e}")

        # L'inverse : stéréo dont l'en-tête dit 5.1.
        stereo_aac = tmp_path / "stereo.aac"
        stereo_wav = tmp_path / "stereo.wav"
        ecrire_wav(stereo_wav, vers_s16(np.stack([v, v], 1)))
        encoder(stereo_wav, stereo_aac, [])
        stereo_faux = tmp_path / "stereo-config6.aac"
        patch_config_canal(stereo_aac, stereo_faux, 6)
        print("  stéréo en-tête forcé à 6 :", ffprobe_canaux(stereo_faux))
        mal2 = tmp_path / "mal2.wav"
        r2 = subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "warning", "-y", "-i", str(stereo_faux), str(mal2)],
            capture_output=True, text=True,
        )
        if r2.returncode != 0 or not mal2.exists():
            print("  le décodeur a refusé la stéréo déclarée 5.1")
            print("\n".join(r2.stderr.splitlines()[:8]))
        else:
            trames2, c2 = lire_wav(mal2)
            print(f"  décodé : {c2} voies")
            if c2 >= 2:
                ligne("  stéréo déclarée 5.1", mesurer(trames2), f"{c2} voies")


if __name__ == "__main__":
    main()
