#!/usr/bin/env python3
# Mesure : un filtre « téléphone » (300–3400 Hz) change-t-il le chiffre
# « énergie au-dessus de 4 kHz » que les sondes de Zuno publient ?
#
# Les sondes copient le PCM AVANT l'AudioTrack. Le mode communication
# d'Android, s'il filtre, le fait dans le mélangeur, APRÈS. Cette
# commande ne lit aucun flux, aucun mot de passe. Signaux synthétiques.
#
# Le passe-haut 4 kHz est le même Butterworth ordre 2 que AudioSpectrum.kt.

import math
import struct
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

SR = 48000
SPLIT = 4000.0
WARMUP = 512
N = SR  # 1 seconde


def butterworth_high_ratio(x: np.ndarray, sr: int = SR, split: float = SPLIT) -> float:
    """Même filtre que AudioSpectrum.start / push (une voie, flottant -1..1)."""
    q = math.sqrt(0.5)
    w0 = 2.0 * math.pi * split / sr
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
    sum_high = 0.0
    for i, sample in enumerate(x):
        y = b0 * sample + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, sample
        y2, y1 = y1, y
        if i + 1 > WARMUP:
            sum_sq += sample * sample
            sum_high += y * y
    if sum_sq <= 0.0:
        return 0.0
    return sum_high / sum_sq


def fft_band(x: np.ndarray, sr: int, lo: float, hi: float) -> float:
    """Part de l'énergie entre lo et hi (Hz), énergie totale hors continu."""
    spec = np.fft.rfft(x)
    power = np.abs(spec) ** 2
    freqs = np.fft.rfftfreq(x.size, 1.0 / sr)
    total = power[1:].sum()
    if total <= 0:
        return 0.0
    mask = (freqs >= lo) & (freqs < hi)
    return float(power[mask].sum() / total)


def speech_like(n: int = N, sr: int = SR) -> np.ndarray:
    """Harmoniques de voix jusqu'à 3,2 kHz, plus un grave à 120 Hz."""
    t = np.arange(n) / sr
    partials = [
        (120, 0.35),
        (180, 0.25),
        (240, 0.55),
        (360, 0.40),
        (480, 0.30),
        (700, 0.22),
        (1100, 0.16),
        (1600, 0.10),
        (2200, 0.07),
        (2800, 0.04),
        (3200, 0.03),
    ]
    x = np.zeros(n, dtype=np.float64)
    for freq, amp in partials:
        x += amp * np.sin(2 * math.pi * freq * t)
    # Un souffle très faible au-dessus de 4 kHz, comme une voix réelle.
    rng = np.random.default_rng(1)
    noise = rng.normal(0, 1, n)
    # Passe-haut grossier du souffle : différence d'échantillons.
    hf = np.diff(noise, prepend=noise[0])
    x += 0.02 * hf
    peak = np.max(np.abs(x))
    return (0.4 * x / peak).astype(np.float64)


def white(n: int = N) -> np.ndarray:
    rng = np.random.default_rng(2)
    return (0.4 * rng.uniform(-1, 1, n)).astype(np.float64)


def write_wav(path: Path, x: np.ndarray, sr: int = SR) -> None:
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16)
    with wave.open(str(path), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path), "r") as w:
        raw = w.readframes(w.getnframes())
        n = w.getnframes()
        ch = w.getnchannels()
    samples = np.array(struct.unpack("<" + "h" * (len(raw) // 2), raw), dtype=np.float64)
    if ch > 1:
        samples = samples.reshape(-1, ch).mean(axis=1)
    return samples[:n] / 32768.0


def ffmpeg_af(src: Path, dst: Path, af: str) -> None:
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-i", str(src),
        "-af", af,
        str(dst),
    ]
    subprocess.run(cmd, check=True)


def report(name: str, x: np.ndarray) -> None:
    high = butterworth_high_ratio(x)
    below300 = fft_band(x, SR, 0.0, 300.0)
    mid = fft_band(x, SR, 300.0, 3400.0)
    above4 = fft_band(x, SR, 4000.0, SR / 2)
    print(
        f"{name}\tbutterworth>4kHz={high:.6f}\t"
        f"fft<300Hz={below300:.6f}\tfft_300_3400={mid:.6f}\tfft>4kHz={above4:.6f}"
    )


def main() -> int:
    tmp = Path("/tmp/zuno-mode-audio")
    tmp.mkdir(parents=True, exist_ok=True)
    voice = speech_like()
    noise = white()
    write_wav(tmp / "voix.wav", voice)
    write_wav(tmp / "bruit.wav", noise)
    ffmpeg_af(tmp / "voix.wav", tmp / "voix_tel.wav", "highpass=f=300,lowpass=f=3400")
    ffmpeg_af(tmp / "bruit.wav", tmp / "bruit_tel.wav", "highpass=f=300,lowpass=f=3400")
    # Bluetooth d'appel étroit : on descend à 8 kHz puis on remonte à 48 kHz.
    ffmpeg_af(tmp / "voix.wav", tmp / "voix_8k.wav", "aresample=8000,aresample=48000")
    ffmpeg_af(tmp / "bruit.wav", tmp / "bruit_8k.wav", "aresample=8000,aresample=48000")
    voice_tel = read_wav(tmp / "voix_tel.wav")
    noise_tel = read_wav(tmp / "bruit_tel.wav")
    voice_8 = read_wav(tmp / "voix_8k.wav")
    noise_8 = read_wav(tmp / "bruit_8k.wav")

    def align(a: np.ndarray, b: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        n = min(a.size, b.size)
        return a[:n], b[:n]

    voice, voice_tel = align(voice, voice_tel)
    noise, noise_tel = align(noise, noise_tel)
    _, voice_8 = align(voice, voice_8)
    _, noise_8 = align(noise, noise_8)
    print(f"echantillons voix {voice.size} bruit {noise.size} sr {SR}")
    report("voix", voice)
    report("voix_telephone_300_3400", voice_tel)
    report("voix_8kHz_remontee_48k", voice_8)
    report("bruit_blanc", noise)
    report("bruit_telephone_300_3400", noise_tel)
    report("bruit_8kHz_remontee_48k", noise_8)
    return 0


if __name__ == "__main__":
    sys.exit(main())
