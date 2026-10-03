#!/usr/bin/env python3
# Simulation : quels défauts de tampon / format donnent un spectre
# « vieille radio », et lesquels non.
#
# On ne prétend pas entendre. On mesure, sur des signaux fabriqués :
#   • part d'énergie au-dessus de 4 kHz (même idée que AudioSpectrum) ;
#   • part d'énergie entre 300 Hz et 3,4 kHz (bande téléphone) ;
#   • aplatissement spectral (un peigne creuse le spectre) ;
#   • kurtosis (des clics, des trous, un son haché) ;
#   • modulation de l'enveloppe (deux sons qui se battent, un « trou »).
#
# Seuils repris de l'app : large si > 4 kHz ≥ 0,40 ; bas si ≤ 0,12.
# Un glitch « fait vieille radio » SEULEMENT s'il fait passer un bruit
# large sous 0,12 sans devenir un train de clics (kurtosis < 20).

import math
import struct
import subprocess
import wave
from pathlib import Path

import numpy as np

SR = 48_000
N = SR * 2  # 2 secondes
RNG = np.random.default_rng(7)
WIDE_MIN = 0.40
LOW_MAX = 0.12


def biquad_low(x, sr, fc, q=0.7071):
    """Passe-bas biquad (RBJ). Une passe, pas un filtre de studio."""
    w0 = 2.0 * math.pi * fc / sr
    alpha = math.sin(w0) / (2.0 * q)
    cosw = math.cos(w0)
    b0 = (1.0 - cosw) / 2.0
    b1 = 1.0 - cosw
    b2 = b0
    a0 = 1.0 + alpha
    a1 = -2.0 * cosw
    a2 = 1.0 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = np.empty_like(x)
    z1 = 0.0
    z2 = 0.0
    for i, sample in enumerate(x):
        out = b0 * sample + z1
        z1 = b1 * sample - a1 * out + z2
        z2 = b2 * sample - a2 * out
        y[i] = out
    return y


def biquad_high(x, sr, fc, q=0.7071):
    w0 = 2.0 * math.pi * fc / sr
    alpha = math.sin(w0) / (2.0 * q)
    cosw = math.cos(w0)
    b0 = (1.0 + cosw) / 2.0
    b1 = -(1.0 + cosw)
    b2 = b0
    a0 = 1.0 + alpha
    a1 = -2.0 * cosw
    a2 = 1.0 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = np.empty_like(x)
    z1 = 0.0
    z2 = 0.0
    for i, sample in enumerate(x):
        out = b0 * sample + z1
        z1 = b1 * sample - a1 * out + z2
        z2 = b2 * sample - a2 * out
        y[i] = out
    return y


def bandpass_phone(x, sr):
    """300 Hz – 3,4 kHz, deux biquads de chaque côté. Le contrôle « radio »."""
    y = x
    for _ in range(2):
        y = biquad_high(y, sr, 300.0)
        y = biquad_low(y, sr, 3400.0)
    return y


def metrics(x, sr):
    x = np.asarray(x, dtype=np.float64)
    x = x - np.mean(x)
    spec = np.fft.rfft(x * np.hanning(len(x)))
    power = (spec.real ** 2) + (spec.imag ** 2)
    freqs = np.fft.rfftfreq(len(x), 1.0 / sr)
    total = float(np.sum(power)) + 1e-20
    high = float(np.sum(power[freqs >= 4000.0])) / total
    phone = float(np.sum(power[(freqs >= 300.0) & (freqs <= 3400.0)])) / total
    # Aplatissement : 1 = bruit plat, plus bas = spectre creusé (peigne, tonal).
    nz = power[power > 0]
    flat = float(np.exp(np.mean(np.log(nz))) / (np.mean(nz) + 1e-20))
    m2 = float(np.mean(x ** 2)) + 1e-20
    kurt = float(np.mean(x ** 4) / (m2 * m2))
    # Enveloppe : valeur absolue lissée sur 10 ms, puis son écart relatif.
    win = max(1, int(sr * 0.010))
    env = np.convolve(np.abs(x), np.ones(win) / win, mode="same")
    mod = float(np.std(env) / (np.mean(env) + 1e-12))
    # Trous numériques : des vrais zéros, pas une simple baisse de volume.
    zeros = float(np.mean(np.abs(x) < 1e-4))
    return {
        "high": high,
        "phone": phone,
        "flat": flat,
        "kurt": kurt,
        "mod": mod,
        "zeros": zeros,
    }


def band_name(high):
    if high >= WIDE_MIN:
        return "LARGE"
    if high <= LOW_MAX:
        return "BAS"
    return "MILIEU"


def speechish(n, sr):
    """Harmoniques de voix sous 3,8 kHz, plus un filet de bruit. Pas un locuteur."""
    t = np.arange(n) / sr
    y = np.zeros(n)
    f0 = 140.0
    k = 1
    while f0 * k < 3800.0:
        y += (1.0 / (k ** 1.3)) * np.sin(2.0 * math.pi * f0 * k * t)
        k += 1
    y *= 0.35 / (np.max(np.abs(y)) + 1e-12)
    # Un peu d'air au-dessus de 4 kHz, pour viser le 1 à 4 % mesuré sur une voix.
    t = np.arange(n) / sr
    y += 0.012 * np.sin(2.0 * math.pi * 5500.0 * t)
    y += 0.006 * np.sin(2.0 * math.pi * 7500.0 * t)
    y += RNG.normal(0.0, 0.002, n)
    return y


def tonal(n, sr):
    """Partiels jusqu'à 10 kHz : une « musique » simple, pour le désaccord."""
    t = np.arange(n) / sr
    y = np.zeros(n)
    freq = 200.0
    k = 1
    while freq < 10_000.0:
        y += (1.0 / k) * np.sin(2.0 * math.pi * freq * t)
        freq += 250.0
        k += 1
    return y * (0.3 / (np.max(np.abs(y)) + 1e-12))


def wide_noise(n):
    return RNG.normal(0.0, 0.2, n)


def resample_linear(x, sr_in, sr_out):
    n_out = int(round(len(x) * sr_out / sr_in))
    if n_out < 2:
        return x.copy()
    pos = np.linspace(0.0, len(x) - 1.0, n_out)
    i0 = np.floor(pos).astype(np.int64)
    i1 = np.minimum(i0 + 1, len(x) - 1)
    frac = pos - i0
    return x[i0] * (1.0 - frac) + x[i1] * frac


def dropouts(x, sr, gap_ms=20, every_ms=200):
    y = x.copy()
    gap = int(sr * gap_ms / 1000)
    every = int(sr * every_ms / 1000)
    for i in range(0, len(y), every):
        y[i : i + gap] = 0.0
    return y


def hold_gaps(x, sr, gap_ms=20, every_ms=200):
    """Pendant le trou, on répète le dernier échantillon (blocage)."""
    y = x.copy()
    gap = int(sr * gap_ms / 1000)
    every = int(sr * every_ms / 1000)
    for i in range(1, len(y), every):
        end = min(len(y), i + gap)
        y[i:end] = y[i - 1]
    return y


def stutter(x, sr, chunk_ms=10, every_ms=80):
    y = x.copy()
    chunk = int(sr * chunk_ms / 1000)
    every = int(sr * every_ms / 1000)
    i = every
    while i + chunk < len(y):
        y[i : i + chunk] = y[i - chunk : i]
        i += every
    return y


def drop_one_percent(x):
    """Retire 1 échantillon sur 100 : horloge trop vite, sans filtre."""
    keep = np.ones(len(x), dtype=bool)
    keep[::100] = False
    return x[keep]


def clip_hard(x, gain=4.0):
    return np.clip(x * gain, -1.0, 1.0)


def quantize_int16(x):
    """Arrondi vers l'entier 16 bits, sans dither. Comme ToInt16 sur un float déjà dans [-1, 1]."""
    q = np.clip(np.round(x * 32767.0), -32768, 32767) / 32767.0
    return q


def quantize_8bit(x):
    return np.clip(np.round(x * 127.0), -128, 127) / 127.0


def comb(x, sr, delay_ms=2.0, mix=0.45):
    d = int(sr * delay_ms / 1000.0)
    y = x.copy()
    y[d:] = (1.0 - mix) * x[d:] + mix * x[:-d]
    return y


def detune_mix(x, sr, ratio=1.007):
    other = resample_linear(x, sr, int(round(sr * ratio)))
    n = min(len(x), len(other))
    return 0.5 * x[:n] + 0.5 * other[:n]


def duck(x, sr, hz=4.0, floor=0.25):
    t = np.arange(len(x)) / sr
    gain = floor + (1.0 - floor) * (0.5 + 0.5 * np.sin(2.0 * math.pi * hz * t))
    return x * gain


def sample_hold(x, hold=8):
    idx = np.arange(len(x))
    return x[(idx // hold) * hold]


def ring(x, sr, hz=90.0):
    t = np.arange(len(x)) / sr
    return x * np.sin(2.0 * math.pi * hz * t)


def write_wav(path, x, sr):
    y = np.clip(x, -1.0, 1.0)
    pcm = (y * 32767.0).astype(np.int16)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sr)
        handle.writeframes(pcm.tobytes())


def read_wav(path):
    with wave.open(str(path), "rb") as handle:
        sr = handle.getframerate()
        frames = handle.readframes(handle.getnframes())
        channels = handle.getnchannels()
    pcm = np.frombuffer(frames, dtype=np.int16).astype(np.float64) / 32767.0
    if channels > 1:
        pcm = pcm[::channels]
    return pcm, sr


def ffmpeg_roundtrip(src_wav, dst_wav, rate):
    """48 kHz → rate → 48 kHz avec le rééchantillonneur d'ffmpeg (swr)."""
    mid = dst_wav.with_suffix(".mid.wav")
    subprocess.run(
        [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-i", str(src_wav),
            "-af", f"aresample={rate}:resampler=swr",
            str(mid),
        ],
        check=True,
    )
    subprocess.run(
        [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-i", str(mid),
            "-af", "aresample=48000:resampler=swr",
            str(dst_wav),
        ],
        check=True,
    )
    return read_wav(dst_wav)


def classify(base, after):
    """
    Règles fixées avant de lire les chiffres d'un glitch particulier.
    BAS + kurtosis modéré = la signature spectrale « vieille radio ».
    Kurtosis très haut = haché / clics, même si la bande bouge.
    Modulation qui monte fort, bande qui reste large = « guerre » / creux.
    """
    high_drop = base["high"] - after["high"]
    radio = after["high"] <= LOW_MAX and after["kurt"] < 20.0 and high_drop > 0.15
    clicks = after["kurt"] >= 20.0 or (after["kurt"] > base["kurt"] * 3.0 and after["kurt"] > 8.0)
    war = (not radio) and after["high"] >= 0.25 and (after["mod"] - base["mod"]) > 0.08
    hollow = (not radio) and after["flat"] < base["flat"] * 0.75 and after["high"] >= 0.20
    if radio:
        return "VIEILLE RADIO (spectre)"
    bits = []
    if clicks:
        bits.append("HACHÉ")
    if war:
        bits.append("GUERRE")
    if hollow:
        bits.append("CREUX")
    if not bits:
        return "NI RADIO NI HACHÉ"
    return " + ".join(bits)


def row(name, base, after):
    label = classify(base, after)
    return (
        f"{name:28}  {band_name(after['high']):7}  "
        f">4kHz {after['high']*100:6.2f}%  "
        f"tél {after['phone']*100:6.2f}%  "
        f"kurt {after['kurt']:7.1f}  "
        f"mod {after['mod']:.3f}  "
        f"zéros {after['zeros']*100:5.1f}%  "
        f"plat {after['flat']:.3f}  "
        f"{label}"
    )


def main():
    speech = speechish(N, SR)
    noise = wide_noise(N)
    music = tonal(N, SR)
    speech_m = metrics(speech, SR)
    noise_m = metrics(noise, SR)
    music_m = metrics(music, SR)

    print("RÉFÉRENCES (avant glitch)")
    print(row("parole synthétique", speech_m, speech_m))
    print(row("bruit large", noise_m, noise_m))
    print(row("partiels jusqu'à 10 kHz", music_m, music_m))
    print()
    print("GLITCH SUR DU BRUIT LARGE (le contrôle : on SAIT qu'il y a des aigus)")
    print(f"{'glitch':28}  {'bande':7}  énergie")

    cases = [
        ("téléphone 300-3400 Hz", bandpass_phone(noise, SR)),
        ("passe-bas 4 kHz x2", biquad_low(biquad_low(noise, SR, 4000.0), SR, 4000.0)),
        ("rééch. linéaire 48→8→48", resample_linear(resample_linear(noise, SR, 8000), 8000, SR)),
        ("rééch. linéaire 48→44.1→48", resample_linear(resample_linear(noise, SR, 44100), 44100, SR)),
        ("rééch. linéaire 48→96→48", resample_linear(resample_linear(noise, SR, 96000), 96000, SR)),
        ("vitesse 1,03 (linéaire)", resample_linear(noise, SR, int(SR / 1.03))),
        ("vitesse 0,97 (linéaire)", resample_linear(noise, SR, int(SR / 0.97))),
        ("retrait 1 % d'échantillons", drop_one_percent(noise)),
        ("trous 20 ms / 200 ms", dropouts(noise, SR)),
        ("blocage 20 ms / 200 ms", hold_gaps(noise, SR)),
        ("bégaiement 10 ms", stutter(noise, SR)),
        ("échantillon tenu x8", sample_hold(noise, 8)),
        ("modulation en anneau 90 Hz", ring(noise, SR, 90.0)),
        ("peigne 2 ms", comb(noise, SR, 2.0, 0.45)),
        ("deux copies désaccordées 0,7 %", detune_mix(noise, SR, 1.007)),
        ("baisse de volume 4 Hz", duck(noise, SR)),
        ("écrêtage x4", clip_hard(noise, 4.0)),
        ("quantification 16 bits", quantize_int16(noise)),
        ("quantification 8 bits", quantize_8bit(noise)),
    ]
    for name, signal in cases:
        print(row(name, noise_m, metrics(signal, SR)))

    print()
    print("GLITCH SUR LA PAROLE SYNTHÉTIQUE (déjà pauvre au-dessus de 4 kHz)")
    speech_cases = [
        ("téléphone 300-3400 Hz", bandpass_phone(speech, SR)),
        ("trous 20 ms / 200 ms", dropouts(speech, SR)),
        ("bégaiement 10 ms", stutter(speech, SR)),
        ("peigne 2 ms", comb(speech, SR, 2.0, 0.45)),
        ("deux copies désaccordées 0,7 %", detune_mix(speech, SR, 1.007)),
        ("rééch. linéaire 48→44.1→48", resample_linear(resample_linear(speech, SR, 44100), 44100, SR)),
        ("quantification 16 bits", quantize_int16(speech)),
        ("écrêtage x4", clip_hard(speech, 4.0)),
        ("baisse de volume 4 Hz", duck(speech, SR)),
    ]
    for name, signal in speech_cases:
        print(row(name, speech_m, metrics(signal, SR)))

    print()
    print("GLITCH SUR DES PARTIELS (musique simple, aigus présents)")
    music_cases = [
        ("téléphone 300-3400 Hz", bandpass_phone(music, SR)),
        ("deux copies désaccordées 0,7 %", detune_mix(music, SR, 1.007)),
        ("peigne 2 ms", comb(music, SR, 2.0, 0.45)),
        ("trous 20 ms / 200 ms", dropouts(music, SR)),
        ("rééch. linéaire 48→44.1→48", resample_linear(resample_linear(music, SR, 44100), 44100, SR)),
        ("vitesse 1,03 (linéaire)", resample_linear(music, SR, int(SR / 1.03))),
    ]
    for name, signal in music_cases:
        print(row(name, music_m, metrics(signal, SR)))

    tmp = Path("/tmp/son-glitch")
    tmp.mkdir(parents=True, exist_ok=True)
    src = tmp / "bruit.wav"
    write_wav(src, noise, SR)
    print()
    print("FFMPEG aresample (swr), même bruit large, aller-retour vers 48 kHz")
    try:
        for rate in (44100, 8000, 96000):
            dst = tmp / f"swr-{rate}.wav"
            pcm, sr = ffmpeg_roundtrip(src, dst, rate)
            print(row(f"ffmpeg swr 48→{rate // 1000}k→48", noise_m, metrics(pcm, sr)))
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        print(f"ffmpeg indisponible ou en erreur : {exc}")


if __name__ == "__main__":
    main()
