#!/usr/bin/env python3
# Banc hors ligne — qualité du son « vieille radio ».
#
# Le pourcentage d'énergie au-dessus de 4 kHz ne juge pas la parole :
# une voix naturelle et un filtre téléphone tombent tous les deux
# dans la zone basse. Ce script calcule d'autres indicateurs, sur
# des signaux dont le défaut est connu, et dit lesquels séparent
# vraiment les cas.
#
# Entrées acceptées :
#   • WAV (lu par ffmpeg, donc pas seulement le PCM 16 bits) ;
#   • PCM s16le entrelacé, le format que copie la sonde ;
#   • --valider : fabrique les signaux, applique les défauts avec
#     ffmpeg, et écrit les chiffres.
#
# Aucune URL, aucun mot de passe. Le son du lecteur n'est pas touché.

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy import signal

# Même coupure que AudioSpectrum.SPLIT_HZ, même filtre (ordre 2).
SPLIT_HZ = 4000.0
WARMUP = 512

# Bandes utilisées par la version embarquée. Les bords sont choisis
# pour qu'un passe-bande 300–3400 Hz (téléphone) vide les deux bandes
# extérieures, alors qu'une parole seulement « sourde » (passe-bas)
# garde le grave.
GRAVE_LO = 80.0
GRAVE_HI = 280.0
MILIEU_LO = 300.0
MILIEU_HI = 3400.0
AIGU_LO = 3500.0
AIGU_HI = 7000.0

# Centres 1/3 d'octave (Hz), de 50 à 16 000. IEC 61260, série usuelle.
TIERS = [
    50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
    800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300,
    8000, 10000, 12500, 16000,
]


def passe_haut_4k(x, sr):
    """Énergie du passe-haut 4 kHz / énergie totale.

    Copie exacte du biquad de AudioSpectrum.kt (Butterworth ordre 2,
    forme directe I). On ne compte pas les 512 premières trames.
    """
    q = math.sqrt(0.5)
    w0 = 2.0 * math.pi * SPLIT_HZ / sr
    c = math.cos(w0)
    alpha = math.sin(w0) / (2.0 * q)
    a0 = 1.0 + alpha
    b0 = ((1.0 + c) / 2.0) / a0
    b1 = (-(1.0 + c)) / a0
    b2 = ((1.0 + c) / 2.0) / a0
    a1 = (-2.0 * c) / a0
    a2 = (1.0 - alpha) / a0
    x1 = x2 = y1 = y2 = 0.0
    somme = 0.0
    somme_haut = 0.0
    for i, sample in enumerate(x):
        y = b0 * sample + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, sample
        y2, y1 = y1, y
        if i >= WARMUP:
            somme += sample * sample
            somme_haut += y * y
    if somme <= 0.0:
        return 0.0
    return somme_haut / somme


def _resonateur(x, sr, freq, bw):
    """Résonateur à deux pôles (un formant). Le gain global est remis
    à l'échelle par l'appelant : ici on évite seulement l'explosion."""
    r = math.exp(-math.pi * bw / sr)
    theta = 2.0 * math.pi * freq / sr
    b = [1.0 - r]
    a = [1.0, -2.0 * r * math.cos(theta), r * r]
    return signal.lfilter(b, a, x)


def _train_impulsions(n, sr, f0, rng):
    """Impulsions glottiques. La fréquence fondamentale bouge un peu
    (intonation), sinon le spectre est une grille trop parfaite."""
    t = np.arange(n, dtype=np.float64) / sr
    contour = f0 * (
        1.0
        + 0.05 * np.sin(2.0 * math.pi * 0.27 * t)
        + 0.025 * np.sin(2.0 * math.pi * 0.11 * t + 0.7)
    )
    phase = np.cumsum(contour / sr)
    changements = np.flatnonzero(np.diff(np.floor(phase))) + 1
    pulses = np.zeros(n, dtype=np.float64)
    if changements.size:
        pulses[changements] = 1.0
    # Légère gigue : on ne déplace pas les impulsions (ça casserait
    # le formant), on varie leur force.
    pulses[changements] *= 0.85 + 0.3 * rng.random(changements.size)
    return pulses


def _enveloppe_syllabes(n, sr, rng):
    """Bosses de 90 à 160 ms, puis un court silence. Rythme de parole."""
    env = np.zeros(n, dtype=np.float64)
    pos = int(0.04 * sr)
    while pos < n:
        duree = int(rng.uniform(0.09, 0.16) * sr)
        trou = int(rng.uniform(0.05, 0.11) * sr)
        long = min(duree, n - pos)
        if long > 4:
            env[pos:pos + long] = np.maximum(env[pos:pos + long], np.hanning(long))
        pos += duree + trou
    return env


def _ajouter_souffle(y, sr, rng, niveau):
    """« s » courts, au-dessus de 3 kHz, bien plus faibles que les voyelles.

    On normalise D'ABORD les voyelles. Sinon le souffle, très large,
    prend le pic et la voyelle disparaît : le premier essai donnait
    93 % d'énergie au-dessus de 4 kHz, ce qui n'est pas de la parole.
    """
    pic = np.max(np.abs(y))
    if pic < 1e-12:
        raise RuntimeError("synthèse muette")
    y = y / pic
    if niveau <= 0.0:
        return y * 0.45
    n = y.size
    bruit = rng.normal(0.0, 1.0, n)
    b_hp, a_hp = signal.butter(4, min(3000.0, sr * 0.45) / (sr / 2.0), btype="high")
    souffle = signal.lfilter(b_hp, a_hp, bruit)
    souffle /= np.max(np.abs(souffle)) + 1e-12
    porte = np.zeros(n, dtype=np.float64)
    pos = int(0.07 * sr)
    while pos < n - int(0.05 * sr):
        if rng.random() < 0.5:
            long = min(int(0.04 * sr), n - pos)
            porte[pos:pos + long] = np.hanning(long)
        pos += int(rng.uniform(0.22, 0.38) * sr)
    y = y + niveau * souffle * porte
    pic = np.max(np.abs(y))
    return (y / pic) * 0.45


def synthese_harmoniques(sr, secondes, f0, graine, f_max=7600.0, souffle=0.12):
    """Somme d'harmoniques en 1/k, puis des syllabes.

    L'amplitude en 1/k est une pente d'environ −6 dB par octave
    (puissance en 1/k²). L'essentiel de l'ÉNERGIE est dans les
    premières harmoniques, sous 300 Hz. Au-dessus de 4 kHz il reste
    peu : c'est le cas « 1 à 4 % », celui des fiches réelles, pas
    un bruit blanc.

    [f_max] coupe la série. 7600 Hz = parole complète. 3200 Hz =
    parole déjà sourde SANS filtre téléphone (le grave reste).
    """
    rng = np.random.default_rng(graine)
    n = int(sr * secondes)
    t = np.arange(n, dtype=np.float64) / sr
    # L'intonation fait glisser la fondamentale. La phase est
    # l'intégrale : les harmoniques restent des multiples.
    f_inst = f0 * (1.0 + 0.04 * np.sin(2.0 * math.pi * 0.23 * t))
    phase = np.cumsum(f_inst / sr)
    y = np.zeros(n, dtype=np.float64)
    k = 1
    while f0 * k < f_max and k < 80:
        y += (1.0 / k) * np.sin(2.0 * math.pi * k * phase + float(rng.uniform(0.0, 2.0 * math.pi)))
        k += 1
    y *= _enveloppe_syllabes(n, sr, rng)
    return _ajouter_souffle(y, sr, rng, souffle)


def synthese_parole(sr, secondes, f0, graine, fricatives=True):
    """Autre témoin : impulsions, trois formants, syllabes.

    Indépendant de la série harmonique. Si les deux témoins donnent
    le même classement, le seuil ne dépend pas d'un seul modèle.
    """
    rng = np.random.default_rng(graine)
    n = int(sr * secondes)
    source = _train_impulsions(n, sr, f0, rng)
    source = np.diff(source, prepend=0.0)
    voyelles = [
        (730.0, 1090.0, 2440.0),
        (270.0, 2290.0, 3010.0),
        (300.0, 870.0, 2240.0),
        (530.0, 1840.0, 2480.0),
    ]
    bloc = int(0.18 * sr)
    y = np.zeros(n, dtype=np.float64)
    pos = 0
    k = 0
    while pos < n:
        fin = min(n, pos + bloc)
        f1, f2, f3 = voyelles[k % len(voyelles)]
        morceau = source[pos:fin]
        for freq, bw in ((f1, 80.0), (f2, 100.0), (f3, 140.0)):
            morceau = _resonateur(morceau, sr, freq, bw)
        fondu = min(int(0.01 * sr), max(1, morceau.size // 2))
        if fondu > 0 and pos > 0:
            r = np.linspace(0.0, 1.0, fondu)
            morceau = morceau.copy()
            morceau[:fondu] *= r
            y[pos:pos + fondu] *= (1.0 - r)
        y[pos:fin] += morceau
        pos = fin
        k += 1
    y *= _enveloppe_syllabes(n, sr, rng)
    return _ajouter_souffle(y, sr, rng, 0.12 if fricatives else 0.0)


def ecrire_pcm(path, x, sr):
    """PCM s16le mono. On écrête à la conversion, comme un vrai fichier."""
    entier = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    entier.tofile(path)
    return entier


def lire_pcm(path, canaux):
    brut = np.fromfile(path, dtype="<i2")
    if canaux > 1:
        brut = brut[: brut.size - (brut.size % canaux)]
        brut = brut.reshape(-1, canaux)
    return brut.astype(np.float64) / 32768.0


def ffmpeg_filtre(src, dst, af, sr, canaux):
    """Applique un filtre ffmpeg. Le défaut est fabriqué ICI, pas par
    le détecteur : les deux codes ne partagent pas de filtre."""
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-f", "s16le", "-ar", str(sr), "-ac", str(canaux), "-i", src,
        "-af", af,
        "-f", "s16le", "-ar", str(sr), "-ac", str(canaux), dst,
    ]
    subprocess.run(cmd, check=True)
    return cmd


def ffmpeg_melange_retard(src, dst, sr, retard_ms):
    """x + copie retardée. C'est le cas « deux fois le même son »."""
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-f", "s16le", "-ar", str(sr), "-ac", "1", "-i", src,
        "-filter_complex",
        f"[0:a]asplit=2[a][b];[b]adelay={retard_ms}:all=1[d];"
        "[a][d]amix=inputs=2:normalize=0:duration=first,volume=0.5",
        "-f", "s16le", "-ar", str(sr), "-ac", "1", dst,
    ]
    subprocess.run(cmd, check=True)
    return cmd


def vers_mono(x):
    """Mélange des voies. Si elles s'annulent (G ≈ −D), le mélange
    est un silence et le spectre ne veut plus rien dire : on mesure
    alors la voie gauche, et la corrélation dit l'annulation à part."""
    if x.ndim == 1:
        return x
    mix = np.mean(x, axis=1)
    energie_mix = float(np.mean(mix ** 2))
    energie_g = float(np.mean(x[:, 0] ** 2))
    if energie_mix < 1e-4 * (energie_g + 1e-30):
        return np.array(x[:, 0], copy=True)
    return mix


def _bins_bande(n_fft, sr, lo, hi):
    # k * sr / n_fft dans [lo, hi). On ignore le continu (k = 0).
    k0 = max(1, int(math.ceil(lo * n_fft / sr)))
    k1 = int(math.floor((hi - 1e-9) * n_fft / sr))
    k1 = min(k1, n_fft // 2)
    if k1 < k0:
        return k0, k0
    return k0, k1 + 1


def spectre_puissance(mono, sr, n_fft):
    """Fenêtre de Hann, puissance par bin (rfft). On prend le milieu
    du signal : le début porte encore la mise en route des filtres."""
    if mono.size < n_fft:
        padded = np.zeros(n_fft, dtype=np.float64)
        padded[: mono.size] = mono
        morceau = padded
    else:
        depart = (mono.size - n_fft) // 2
        morceau = mono[depart:depart + n_fft]
        # Le milieu d'un fichier peut être un silence (pause). On prend
        # alors le début, où il y a encore du son. Les témoins continus
        # ne changent pas : leur milieu n'est pas muet.
        if float(np.mean(morceau ** 2)) < 1e-8:
            morceau = mono[:n_fft]
    fenetre = np.hanning(n_fft)
    # La fenêtre de Hann vaut 0 aux bords : on compense pour que
    # l'énergie ne dépende pas de sa forme.
    spec = np.fft.rfft(morceau * fenetre)
    puissance = (spec.real ** 2 + spec.imag ** 2) / (np.sum(fenetre ** 2) + 1e-30)
    return puissance


def energie_bande(puissance, sr, lo, hi):
    n_fft = (puissance.size - 1) * 2
    k0, k1 = _bins_bande(n_fft, sr, lo, hi)
    if k1 <= k0:
        return 0.0
    return float(np.sum(puissance[k0:k1]))


def tiers_octave(puissance, sr):
    """Niveau de chaque bande 1/3 d'octave, en dB par rapport à la
    bande la plus forte entre 100 Hz et 4 kHz (le milieu de la parole).
    Une bande vide (au-dessus de Nyquist) vaut NaN."""
    n_fft = (puissance.size - 1) * 2
    niveaux = []
    brut = []
    for fc in TIERS:
        if fc >= sr / 2.0:
            niveaux.append(float("nan"))
            brut.append(0.0)
            continue
        lo = fc / (2.0 ** (1.0 / 6.0))
        hi = fc * (2.0 ** (1.0 / 6.0))
        e = energie_bande(puissance, sr, lo, hi)
        brut.append(e)
        niveaux.append(e)
    # Référence : max des bandes dont le centre est dans 100–4000 Hz.
    ref = 0.0
    for fc, e in zip(TIERS, brut):
        if 100.0 <= fc <= 4000.0 and e > ref:
            ref = e
    if ref <= 0.0:
        nan = float("nan")
        return [nan] * len(TIERS), nan, nan, nan, nan
    db = []
    for e in brut:
        if e <= 0.0:
            db.append(-180.0)
        else:
            db.append(10.0 * math.log10(e / ref))

    def bords(seuil):
        # Centre le plus grave et le plus aigu encore au-dessus du seuil.
        f_bas = float("nan")
        f_haut = float("nan")
        for fc, niveau in zip(TIERS, db):
            if fc >= sr / 2.0:
                continue
            if niveau >= seuil:
                if math.isnan(f_bas):
                    f_bas = float(fc)
                f_haut = float(fc)
        return f_bas, f_haut

    f_bas, f_haut = bords(-40.0)
    f_bas_20, f_haut_20 = bords(-20.0)
    return db, f_bas, f_haut, f_bas_20, f_haut_20


def facteur_crete(mono):
    pic = float(np.max(np.abs(mono)))
    rms = math.sqrt(float(np.mean(mono ** 2)) + 1e-30)
    if rms <= 0.0 or pic <= 0.0:
        return float("nan"), 0.0, float("nan")
    crete = 20.0 * math.log10(pic / rms)
    # Même seuil que la sonde : |échantillon| ≥ 32 760 en 16 bits.
    # Ici le signal est en [-1, 1] : 32760/32768 ≈ 0,99976.
    frac = float(np.mean(np.abs(mono) >= (32760.0 / 32768.0)))
    return crete, frac, 20.0 * math.log10(rms + 1e-30)


def plancher_bruit(mono, sr):
    """10e centile des niveaux courts (20 ms), en dBFS.

    Sur une parole synthétique, les silences entre syllabes sont
    numériques : le plancher tombe très bas. Un vrai souffle de
    micro, ou un bruit ajouté, le remonte. Ce n'est pas un juge
    du filtre téléphone.
    """
    long = max(8, int(0.020 * sr))
    saut = max(4, long // 2)
    if mono.size < long:
        return float("nan"), float("nan")
    rms = []
    for i in range(0, mono.size - long + 1, saut):
        morceau = mono[i:i + long]
        rms.append(math.sqrt(float(np.mean(morceau ** 2)) + 1e-30))
    rms = np.asarray(rms)
    p10 = float(np.percentile(rms, 10))
    p90 = float(np.percentile(rms, 90))
    return 20.0 * math.log10(p10 + 1e-30), 20.0 * math.log10(p90 + 1e-30)


def chute_niveau(mono, sr):
    """Écart, en dB, entre la seconde la plus forte et la plus faible.

    Pour chaque seconde : 90e centile des niveaux courts (20 ms).
    On ignore ainsi les silences entre syllabes. Une baisse tenue
    (gain × 0,2 pendant un appel) écarte les secondes d'environ 14 dB.
    Une parole stable reste dans quelques dB.
    """
    long = max(8, int(0.020 * sr))
    sec = int(sr)
    if mono.size < 2 * sec:
        return float("nan")
    niveaux = []
    for s0 in range(0, mono.size - sec + 1, sec):
        frames = []
        i = s0
        fin = s0 + sec - long
        pas = max(1, long // 2)
        while i <= fin:
            morceau = mono[i:i + long]
            frames.append(math.sqrt(float(np.mean(morceau ** 2)) + 1e-30))
            i += pas
        p90 = float(np.percentile(frames, 90))
        niveaux.append(20.0 * math.log10(p90 + 1e-30))
    # Une seconde de silence (pause entre deux phrases) tombe très bas.
    # Ce n'est pas une baisse de type « appel » : on ne la compte pas.
    # 20 dB sous la seconde la plus forte. Un gain × 0,2 fait −14 dB,
    # donc il reste compté. Un trou numérique (−60 dB et plus) sort.
    pic = max(niveaux)
    gardes = [v for v in niveaux if v >= pic - 20.0]
    if len(gardes) < 2:
        return 0.0
    return max(gardes) - min(gardes)


def pompage(mono, sr):
    """Rapport d'énergie de l'enveloppe : 0,3–2 Hz / 3–8 Hz.

    3–8 Hz, c'est le rythme des syllabes. 0,3–2 Hz, c'est une baisse
    lente (musique pendant un appel, compresseur qui respire).
    Il faut plusieurs secondes : une fenêtre d'une seconde ne voit
    pas un cycle de 0,5 Hz.
    """
    if mono.size < int(sr * 2):
        return float("nan")
    # Enveloppe : valeur absolue, puis passe-bas ~30 Hz.
    env = np.abs(mono)
    b, a = signal.butter(2, 30.0 / (sr / 2.0), btype="low")
    env = signal.lfilter(b, a, env)
    env = env - float(np.mean(env))
    # On décime à 200 Hz : les deux bandes sont très en dessous.
    pas = max(1, sr // 200)
    env = env[::pas]
    sr_e = sr / pas
    n = 1 << int(math.floor(math.log2(env.size)))
    if n < 256:
        return float("nan")
    spec = np.fft.rfft(env[:n] * np.hanning(n))
    p = spec.real ** 2 + spec.imag ** 2
    freqs = np.fft.rfftfreq(n, d=1.0 / sr_e)

    def bande(lo, hi):
        m = (freqs >= lo) & (freqs < hi)
        if not np.any(m):
            return 0.0
        return float(np.sum(p[m]))

    syllabes = bande(3.0, 8.0)
    lent = bande(0.3, 2.0)
    if syllabes <= 0.0:
        return float("nan")
    return lent / syllabes


def correlation_gd(x):
    """Pearson entre la voie 1 et la voie 2. Mono → NaN."""
    if x.ndim != 2 or x.shape[1] < 2:
        return float("nan")
    g = x[:, 0]
    d = x[:, 1]
    g = g - np.mean(g)
    d = d - np.mean(d)
    den = math.sqrt(float(np.sum(g * g) * np.sum(d * d))) + 1e-30
    return float(np.sum(g * d) / den)


def score_echo(puissance, sr):
    """Pic du cepstre entre 18 et 40 ms, divisé par la médiane.

    La fondamentale (2,5–12 ms) et ses multiples (2e, 3e… harmonique
    du cepstre) sont retirés : une voix à 120 Hz a un pic vers 25 ms
    et 33 ms, et ce n'est pas un écho. Un second son à 30 ms ne tombe
    pas exactement sur ces multiples : il reste dans la fenêtre.
    """
    amp = np.sqrt(np.maximum(puissance, 0.0))
    log_amp = np.log(amp + 1e-12)
    cep = np.fft.irfft(log_amp)
    n = cep.size
    p0 = max(1, int(round(0.0025 * sr)))
    p1 = min(n // 2, int(round(0.012 * sr)))
    i0 = max(1, int(round(0.018 * sr)))
    i1 = min(n // 2, int(round(0.040 * sr)))
    if i1 <= i0 + 2 or p1 <= p0:
        return float("nan"), float("nan")
    pitch_i = p0 + int(np.argmax(cep[p0:p1]))
    zone = cep[i0:i1].copy()
    for k in range(2, 7):
        centre = k * pitch_i
        tol = int(round(0.05 * centre))
        a = max(i0, centre - tol)
        b = min(i1, centre + tol + 1)
        if b > a:
            zone[a - i0:b - i0] = 0.0
    med = float(np.median(np.abs(cep[i0:i1]))) + 1e-12
    pic = float(np.max(zone))
    if pic <= 0.0:
        return 0.0, float("nan")
    retard_ms = (i0 + int(np.argmax(zone))) * 1000.0 / sr
    return pic / med, retard_ms


def distance_reference(db, reference):
    """Écart quadratique moyen des bandes 80 Hz–8 kHz, en dB.

    [reference] est le profil moyen d'une parole propre (même échelle :
    0 dB = bande la plus forte du milieu). Plus c'est grand, plus la
    forme s'éloigne de cette parole.
    """
    ecarts = []
    for fc, niveau, ref in zip(TIERS, db, reference):
        if fc < 80.0 or fc > 8000.0:
            continue
        if math.isnan(niveau) or math.isnan(ref):
            continue
        ecarts.append((niveau - ref) ** 2)
    if not ecarts:
        return float("nan")
    return math.sqrt(sum(ecarts) / len(ecarts))


def mesurer(x, sr):
    """Tous les indicateurs pour un tampon float [-1, 1].

    Mono ou stéréo entrelacé en colonnes. Le mélange sert au spectre ;
    la corrélation garde les deux voies.
    """
    mono = vers_mono(x)
    n_fft = 32768 if mono.size >= 32768 else 1 << int(math.floor(math.log2(max(256, mono.size))))
    puissance = spectre_puissance(mono, sr, n_fft)
    grave = energie_bande(puissance, sr, GRAVE_LO, GRAVE_HI)
    milieu = energie_bande(puissance, sr, MILIEU_LO, MILIEU_HI)
    aigu = energie_bande(puissance, sr, AIGU_LO, AIGU_HI)
    db, f_bas, f_haut, f_bas_20, f_haut_20 = tiers_octave(puissance, sr)
    # Bande plus étroite, loin sous la coupure 300 Hz : le filtre
    # téléphone l'atténue plus que la bande 80–280, qui touche la pente.
    grave_etroit = energie_bande(puissance, sr, 70.0, 180.0)
    milieu_parole = energie_bande(puissance, sr, 400.0, 2500.0)
    crete, ecretage, rms_db = facteur_crete(mono)
    plancher, fort = plancher_bruit(mono, sr)
    echo, echo_ms = score_echo(puissance, sr)
    return {
        "haut_4k": passe_haut_4k(mono, sr),
        "grave_sur_milieu": grave / milieu if milieu > 0.0 else float("nan"),
        "aigu_sur_milieu": aigu / milieu if milieu > 0.0 else float("nan"),
        "grave_etroit": grave_etroit / milieu_parole if milieu_parole > 0.0 else float("nan"),
        "f_bas_hz": f_bas,
        "f_haut_hz": f_haut,
        "f_bas_20_hz": f_bas_20,
        "f_haut_20_hz": f_haut_20,
        "crete_db": crete,
        "ecretage": ecretage,
        "rms_dbfs": rms_db,
        "plancher_dbfs": plancher,
        "fort_dbfs": fort,
        "pompage": pompage(mono, sr),
        "chute_db": chute_niveau(mono, sr),
        "correlation_gd": correlation_gd(x),
        "echo": echo,
        "echo_ms": echo_ms,
        "tiers_db": db,
        "n_fft": n_fft,
        "secondes": mono.size / sr,
    }


def _arrondi(v):
    if isinstance(v, float):
        if math.isnan(v) or math.isinf(v):
            return None
        return round(v, 6)
    return v


def resumer(m):
    return {k: _arrondi(v) if k != "tiers_db" else [_arrondi(x) for x in v] for k, v in m.items()}


def preparer_signaux(dossier, sr=48000):
    """Fabrique les témoins. Les filtres viennent de ffmpeg.

    Retourne (liste de (nom, groupe, tampon float), commandes).
    groupe sert à dire qui doit être séparé de qui.
    """
    commandes = []
    # Deux familles. « harm » = harmoniques 1/k. « formant » = voyelles.
    # « harm_sourde » s'arrête à 3,2 kHz dès la synthèse : le grave
    # n'a pas été filtré. C'est le piège du pourcentage > 4 kHz.
    propres = {
        "harm_homme": synthese_harmoniques(sr, 8.0, 120.0, 11, f_max=7600.0, souffle=0.12),
        "harm_femme": synthese_harmoniques(sr, 8.0, 210.0, 29, f_max=7600.0, souffle=0.12),
        "harm_sourde": synthese_harmoniques(sr, 8.0, 120.0, 11, f_max=3200.0, souffle=0.0),
        "formant_homme": synthese_parole(sr, 8.0, 120.0, 11, fricatives=True),
        "formant_sans_souffle": synthese_parole(sr, 8.0, 120.0, 11, fricatives=False),
    }
    # La version sans souffle est renormalisée : retirer le souffle
    # ne doit pas changer le niveau des voyelles, déjà normalisées
    # avant l'ajout. synthese_parole normalise à la fin, donc les
    # voyelles sont un peu plus fortes sans souffle. C'est voulu :
    # on compare des formes, pas des niveaux absolus.

    fichiers = {}
    for nom, sig in propres.items():
        chemin = os.path.join(dossier, nom + ".pcm")
        ecrire_pcm(chemin, sig, sr)
        fichiers[nom] = chemin

    def filtre(nom_src, nom, af):
        src = fichiers[nom_src]
        dst = os.path.join(dossier, nom + ".pcm")
        cmd = ffmpeg_filtre(src, dst, af, sr, 1)
        commandes.append(cmd)
        fichiers[nom] = dst

    # Téléphone : 300–3400 Hz, deux fois (pente plus raide, comme un
    # codec parole). ffmpeg, pas scipy.
    tel = "highpass=f=300:poles=2,lowpass=f=3400:poles=2,highpass=f=300:poles=2,lowpass=f=3400:poles=2"
    filtre("harm_homme", "telephone_harm", tel)
    filtre("harm_femme", "telephone_femme", tel)
    filtre("formant_homme", "telephone_formant", tel)
    # Passe-bas seul : le grave reste. C'est le cas qui trompe « > 4 kHz ».
    filtre("harm_homme", "passe_bas_harm", "lowpass=f=3400:poles=2,lowpass=f=3400:poles=2")
    filtre("formant_homme", "passe_bas_formant", "lowpass=f=3400:poles=2,lowpass=f=3400:poles=2")
    # Passe-haut seul : les aigus restent, le grave part.
    filtre("harm_homme", "passe_haut_harm", "highpass=f=300:poles=2,highpass=f=300:poles=2")
    # Rumble à 80 Hz : une parole de radio, PAS un téléphone.
    filtre("harm_homme", "rumble_80", "highpass=f=80:poles=2")
    # Compression : détection de crête, sinon le seuil ne voit que
    # le silence entre les syllabes et le compresseur ne fait rien.
    filtre(
        "harm_homme",
        "compresse",
        "acompressor=threshold=-20dB:ratio=8:attack=5:release=300:makeup=4dB:detection=peak",
    )
    # Écrêtage : on pousse, la conversion s16le coupe les pics.
    filtre("harm_homme", "ecrete", "volume=28dB")
    # Deux fois le même son, 30 ms plus tard.
    dst_echo = os.path.join(dossier, "echo_30ms.pcm")
    commandes.append(ffmpeg_melange_retard(fichiers["harm_homme"], dst_echo, sr, 30))
    fichiers["echo_30ms"] = dst_echo

    # Bruit de fond ajouté à −50 dBFS : le plancher doit monter.
    # Le téléphone, lui, ne le fait pas.
    bruit = np.random.default_rng(3).normal(0.0, 10 ** (-50.0 / 20.0), propres["harm_homme"].size)
    bruite = propres["harm_homme"] + bruit
    ecrire_pcm(os.path.join(dossier, "bruit_50.pcm"), bruite, sr)
    fichiers["bruit_50"] = os.path.join(dossier, "bruit_50.pcm")

    # Baisse tenue × 0,2 (musique pendant un appel). Courbe de gain
    # numpy : ce n'est pas un filtre. ffmpeg a déjà fait les filtres.
    duck = propres["harm_homme"].copy()
    i0, i1 = int(3.0 * sr), int(5.5 * sr)
    rampe = int(0.03 * sr)
    gain = np.ones(duck.size, dtype=np.float64)
    gain[i0:i1] = 0.2
    if rampe > 0:
        r = np.linspace(1.0, 0.2, rampe)
        gain[i0:i0 + rampe] = r
        gain[i1 - rampe:i1] = r[::-1]
    duck *= gain
    ecrire_pcm(os.path.join(dossier, "duck.pcm"), duck, sr)
    fichiers["duck"] = os.path.join(dossier, "duck.pcm")

    # Pause franche de 2 s au milieu. Sans le rejet des secondes
    # muettes, la chute de niveau vaudrait des dizaines de dB et
    # accuserait à tort un « appel ». Avec le rejet, elle doit
    # rester du même ordre que la parole continue.
    pause = propres["harm_homme"].copy()
    pause[int(3.0 * sr):int(5.0 * sr)] = 0.0
    ecrire_pcm(os.path.join(dossier, "pause.pcm"), pause, sr)
    fichiers["pause"] = os.path.join(dossier, "pause.pcm")

    # Deux paroles différentes additionnées (pas un simple écho).
    autre = synthese_harmoniques(sr, 8.0, 165.0, 47, f_max=7600.0, souffle=0.12)
    mix = 0.55 * propres["harm_homme"] + 0.45 * autre[: propres["harm_homme"].size]
    pic = np.max(np.abs(mix))
    mix = mix / pic * 0.45
    ecrire_pcm(os.path.join(dossier, "deux_paroles.pcm"), mix, sr)
    fichiers["deux_paroles"] = os.path.join(dossier, "deux_paroles.pcm")

    # Stéréo : voies identiques, et voies opposées. La corrélation
    # se mesure là. Le spectre des voies opposées est pris sur la
    # gauche, parce que le mélange s'annule.
    gauche = propres["harm_homme"]
    identiques = np.column_stack([gauche, gauche])
    oppose = np.column_stack([gauche, -gauche])

    groupes = {
        "harm_homme": "propre",
        "harm_femme": "propre",
        "harm_sourde": "sourd",
        "formant_homme": "propre",
        "formant_sans_souffle": "sourd",
        "rumble_80": "propre",
        "telephone_harm": "telephone",
        "telephone_femme": "telephone",
        "telephone_formant": "telephone",
        "passe_bas_harm": "sourd",
        "passe_bas_formant": "sourd",
        "passe_haut_harm": "maigre",
        "compresse": "compresse",
        "ecrete": "ecrete",
        "echo_30ms": "echo",
        "bruit_50": "bruit",
        "duck": "duck",
        "pause": "pause",
        "deux_paroles": "deux",
    }
    signaux = []
    for nom, groupe in groupes.items():
        sig = lire_pcm(fichiers[nom], 1)
        signaux.append((nom, groupe, sig))
    signaux.append(("voies_identiques", "propre", identiques))
    signaux.append(("voies_opposees", "oppose", oppose))
    return signaux, commandes


def intervalle(mesures, noms):
    vals = []
    for nom in noms:
        v = mesures[nom]
        if v is None or (isinstance(v, float) and math.isnan(v)):
            continue
        vals.append(v)
    if not vals:
        return None
    return min(vals), max(vals)


def separe(mesures, groupe_haut, groupe_bas):
    """Vrai s'il existe un seuil : tout le groupe haut est au-dessus
    de tout le groupe bas. Renvoie aussi le milieu du trou."""
    haut = intervalle(mesures, groupe_haut)
    bas = intervalle(mesures, groupe_bas)
    if haut is None or bas is None:
        return {"separe": False, "raison": "valeur manquante"}
    if haut[0] > bas[1]:
        seuil = math.sqrt(max(haut[0], 1e-12) * max(bas[1], 1e-12)) if bas[1] > 0 and haut[0] > 0 else (haut[0] + bas[1]) / 2.0
        return {
            "separe": True,
            "sens": "haut > bas",
            "min_haut": haut[0],
            "max_haut": haut[1],
            "min_bas": bas[0],
            "max_bas": bas[1],
            "seuil_geom": seuil,
            "trou": haut[0] - bas[1],
        }
    if bas[0] > haut[1]:
        seuil = (bas[0] + haut[1]) / 2.0
        return {
            "separe": True,
            "sens": "bas > haut",
            "min_haut": haut[0],
            "max_haut": haut[1],
            "min_bas": bas[0],
            "max_bas": bas[1],
            "seuil_geom": seuil,
            "trou": bas[0] - haut[1],
        }
    return {
        "separe": False,
        "raison": "chevauchement",
        "min_haut": haut[0],
        "max_haut": haut[1],
        "min_bas": bas[0],
        "max_bas": bas[1],
    }


def charger(path, sr, canaux):
    if path.lower().endswith(".wav"):
        # ffmpeg décode n'importe quel WAV vers le PCM que la sonde copie.
        with tempfile.TemporaryDirectory() as tmp:
            dst = os.path.join(tmp, "out.pcm")
            cmd = [
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-i", path,
                "-f", "s16le", "-ac", str(canaux), "-ar", str(sr), dst,
            ]
            subprocess.run(cmd, check=True)
            return lire_pcm(dst, canaux)
    return lire_pcm(path, canaux)


def formater_ligne(nom, m):
    def f(cle, fmt):
        v = m[cle]
        if v is None or (isinstance(v, float) and (math.isnan(v) or math.isinf(v))):
            return "—"
        return format(v, fmt)

    return (
        f"{nom:22}  >4k {f('haut_4k', '7.4f')}  "
        f"grave/mil {f('grave_sur_milieu', '7.4f')}  "
        f"aigu/mil {f('aigu_sur_milieu', '7.4f')}  "
        f"f−40 {f('f_bas_hz', '6.0f')}–{f('f_haut_hz', '6.0f')}  "
        f"f−20 {f('f_bas_20_hz', '6.0f')}–{f('f_haut_20_hz', '6.0f')}  "
        f"g70 {f('grave_etroit', '7.4f')}  "
        f"crête {f('crete_db', '5.1f')} dB  "
        f"écrêt {f('ecretage', '6.4f')}  "
        f"plancher {f('plancher_dbfs', '7.1f')}  "
        f"pompage {f('pompage', '6.3f')}  "
        f"chute {f('chute_db', '5.1f')} dB  "
        f"écho {f('echo', '6.2f')}  "
        f"G/D {f('correlation_gd', '6.2f')}"
    )


def _echo_syllabique(sr):
    """Même témoin que le test Kotlin : harmoniques 1/k, syllabes,
    copie ajoutée 30 ms plus tard. Renvoie (score propre, score copie)."""
    n = sr
    f0 = 120.0
    on = int(0.12 * sr)
    periode = int(0.20 * sr)
    y = np.zeros(n, dtype=np.float64)
    for i in range(n):
        pos = i % periode
        env = 0.0 if pos >= on else 0.5 - 0.5 * math.cos(2.0 * math.pi * pos / (on - 1))
        s = 0.0
        k = 1
        while f0 * k < 7600.0 and k <= 64:
            s += (1.0 / k) * math.sin(2.0 * math.pi * f0 * k * i / sr)
            k += 1
        y[i] = s * env
    pic = np.max(np.abs(y))
    y *= 0.45 / pic
    d = int(0.030 * sr)
    z = y.copy()
    z[d:] += 0.8 * y[:-d]
    z *= 0.45 / (np.max(np.abs(z)) + 1e-12)

    def quant(a):
        return np.clip(np.round(a * 32767.0), -32768, 32767).astype(np.float64) / 32768.0

    return mesurer(quant(y), sr)["echo"], mesurer(quant(z), sr)["echo"]


def main():
    p = argparse.ArgumentParser(description="Indicateurs objectifs de qualité audio.")
    p.add_argument("fichier", nargs="?", help="WAV ou PCM s16le à mesurer")
    p.add_argument("--valider", action="store_true", help="fabrique les témoins et compare")
    p.add_argument("--rate", type=int, default=48000)
    p.add_argument("--canaux", type=int, default=1)
    p.add_argument("--json", default="", help="où écrire le JSON des chiffres")
    args = p.parse_args()

    if args.fichier:
        x = charger(args.fichier, args.rate, args.canaux)
        m = mesurer(x, args.rate)
        print(formater_ligne(os.path.basename(args.fichier), m))
        if args.json:
            with open(args.json, "w", encoding="utf-8") as f:
                json.dump(resumer(m), f, ensure_ascii=False, indent=2)
        return 0

    if not args.valider:
        p.print_help()
        return 2

    with tempfile.TemporaryDirectory(prefix="son-lab-") as tmp:
        signaux, commandes = preparer_signaux(tmp, args.rate)
        resultats = []
        ref_bands = []
        for nom, groupe, sig in signaux:
            m = mesurer(sig, args.rate)
            m["nom"] = nom
            m["groupe"] = groupe
            resultats.append(m)
            if nom in ("harm_homme", "harm_femme", "formant_homme"):
                ref_bands.append(m["tiers_db"])
        # Profil de référence : moyenne des deux paroles propres.
        reference = []
        for i in range(len(TIERS)):
            vals = [b[i] for b in ref_bands if not math.isnan(b[i])]
            reference.append(sum(vals) / len(vals) if vals else float("nan"))
        for m in resultats:
            m["distance_ref_db"] = distance_reference(m["tiers_db"], reference)

        print("COMMANDES FFMPEG")
        for cmd in commandes:
            print(" ", " ".join(cmd))
        print()
        print("MESURES")
        for m in resultats:
            print(formater_ligne(m["nom"], m), "  LSD", format(m["distance_ref_db"], ".2f"), "dB")

        # Aller-retour WAV : le lecteur de fichiers ne doit pas changer
        # les indicateurs du témoin propre.
        src = None
        # On refait le pcm propre depuis le résultat déjà en mémoire.
        propre = next(s for s in signaux if s[0] == "harm_homme")[2]
        pcm_path = os.path.join(tmp, "rt.pcm")
        wav_path = os.path.join(tmp, "rt.wav")
        back_path = os.path.join(tmp, "rt-back.pcm")
        ecrire_pcm(pcm_path, propre, args.rate)
        subprocess.run(
            ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
             "-f", "s16le", "-ar", str(args.rate), "-ac", "1", "-i", pcm_path,
             "-c:a", "pcm_s16le", wav_path],
            check=True,
        )
        subprocess.run(
            ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
             "-i", wav_path, "-f", "s16le", "-ac", "1", "-ar", str(args.rate), back_path],
            check=True,
        )
        retour = mesurer(lire_pcm(back_path, 1), args.rate)
        direct = next(m for m in resultats if m["nom"] == "harm_homme")
        print()
        print(
            "ALLER-RETOUR WAV grave/milieu direct",
            format(direct["grave_sur_milieu"], ".6f"),
            "relu",
            format(retour["grave_sur_milieu"], ".6f"),
        )

        par_nom = {m["nom"]: m for m in resultats}

        def col(cle):
            return {nom: m[cle] for nom, m in par_nom.items()}

        propres = ["harm_homme", "harm_femme", "formant_homme", "rumble_80", "voies_identiques"]
        telephones = ["telephone_harm", "telephone_femme", "telephone_formant"]
        sourds = ["passe_bas_harm", "passe_bas_formant", "harm_sourde", "formant_sans_souffle"]
        maigres = ["passe_haut_harm"]

        separations = {
            "haut_4k_telephone_vs_propre": separe(col("haut_4k"), propres, telephones),
            "haut_4k_telephone_vs_sourd": separe(col("haut_4k"), sourds, telephones),
            "grave_telephone_vs_propre": separe(col("grave_sur_milieu"), propres, telephones),
            "grave_telephone_vs_sourd": separe(col("grave_sur_milieu"), sourds, telephones),
            "grave_telephone_vs_maigre": separe(col("grave_sur_milieu"), maigres, telephones),
            "aigu_telephone_vs_propre": separe(col("aigu_sur_milieu"), propres, telephones),
            "aigu_sourd_vs_propre": separe(col("aigu_sur_milieu"), propres, sourds),
            "aigu_maigre_vs_telephone": separe(col("aigu_sur_milieu"), maigres, telephones),
            "fhaut_telephone_vs_propre": separe(col("f_haut_hz"), propres, telephones),
            "fbas_telephone_vs_sourd": separe(col("f_bas_hz"), telephones, sourds),
            "echo_vs_propre": separe(col("echo"), ["echo_30ms"], propres),
            "echo_vs_deux_paroles": separe(col("echo"), ["echo_30ms"], ["deux_paroles"]),
            "pompage_duck_vs_propre": separe(col("pompage"), ["duck"], propres),
            "pompage_compresse_vs_propre": separe(col("pompage"), ["compresse"], propres),
            "chute_duck_vs_propre": separe(col("chute_db"), ["duck"], propres + ["pause"]),
            "chute_compresse_vs_propre": separe(col("chute_db"), ["compresse"], propres),
            "plancher_bruit_vs_propre": separe(col("plancher_dbfs"), ["bruit_50"], propres),
            "ecretage_vs_propre": separe(col("ecretage"), ["ecrete"], propres),
            "crete_ecrete_vs_propre": separe(col("crete_db"), propres, ["ecrete"]),
            "plancher_telephone_vs_propre": separe(col("plancher_dbfs"), telephones, propres),
            "lsd_telephone_vs_propre": separe(col("distance_ref_db"), telephones, propres),
            "lsd_sourd_vs_telephone": separe(col("distance_ref_db"), telephones, sourds),
            "grave_etroit_tel_vs_propre": separe(col("grave_etroit"), propres, telephones),
            "grave_etroit_tel_vs_sourd": separe(col("grave_etroit"), sourds, telephones),
            "fbas20_tel_vs_sourd": separe(col("f_bas_20_hz"), telephones, sourds),
            "fhaut20_tel_vs_propre": separe(col("f_haut_20_hz"), propres, telephones),
            "correlation_oppose_vs_identique": separe(
                col("correlation_gd"),
                ["voies_identiques"],
                ["voies_opposees"],
            ),
        }
        print()
        print("SEPARATIONS")
        for nom, s in separations.items():
            print(f"  {nom}: {json.dumps(s, ensure_ascii=False)}")

        payload = {
            "rate": args.rate,
            "tiers_hz": TIERS,
            "reference_db": [_arrondi(v) for v in reference],
            "signaux": [
                {
                    "nom": m["nom"],
                    "groupe": m["groupe"],
                    **{k: _arrondi(m[k]) for k in (
                        "haut_4k", "grave_sur_milieu", "aigu_sur_milieu", "grave_etroit",
                        "f_bas_hz", "f_haut_hz", "f_bas_20_hz", "f_haut_20_hz", "crete_db", "ecretage",
                        "rms_dbfs", "plancher_dbfs", "fort_dbfs", "pompage", "chute_db",
                        "correlation_gd", "echo", "echo_ms", "distance_ref_db",
                        "n_fft", "secondes",
                    )},
                    "tiers_db": [_arrondi(v) for v in m["tiers_db"]],
                }
                for m in resultats
            ],
            "separations": separations,
            "aller_retour_wav": {
                "grave_direct": _arrondi(direct["grave_sur_milieu"]),
                "grave_relu": _arrondi(retour["grave_sur_milieu"]),
                "haut_4k_direct": _arrondi(direct["haut_4k"]),
                "haut_4k_relu": _arrondi(retour["haut_4k"]),
            },
            "commandes": [" ".join(c) for c in commandes],
        }
        if args.json:
            with open(args.json, "w", encoding="utf-8") as f:
                json.dump(payload, f, ensure_ascii=False, indent=2)
        print()
        print("JSON", args.json)

        # Ce que le banc a le droit d'affirmer. Si un jour un témoin
        # ne se sépare plus, la commande échoue : on ne garde pas
        # un seuil qui ne tient plus.
        doit = [
            "grave_telephone_vs_propre",
            "grave_telephone_vs_sourd",
            "aigu_maigre_vs_telephone",
            "echo_vs_propre",
            "echo_vs_deux_paroles",
            "chute_duck_vs_propre",
            "ecretage_vs_propre",
            "plancher_bruit_vs_propre",
            "correlation_oppose_vs_identique",
        ]
        ne_doit_pas = [
            "haut_4k_telephone_vs_propre",
            "plancher_telephone_vs_propre",
            "grave_telephone_vs_maigre",
            "fbas_telephone_vs_sourd",
            "pompage_compresse_vs_propre",
        ]
        for nom in doit:
            if not separations[nom]["separe"]:
                print("ECHEC attendu séparé:", nom)
                return 1
        for nom in ne_doit_pas:
            if separations[nom]["separe"]:
                print("ECHEC attendu NON séparé:", nom)
                return 1
        # Seuils embarqués : ils doivent rester dans le trou mesuré.
        g = separations["grave_telephone_vs_propre"]
        if not (g["max_bas"] < 0.10 < g["min_haut"]):
            print("ECHEC seuil grave 0,10 hors du trou", g)
            return 1
        a = separations["aigu_maigre_vs_telephone"]
        if not (a["max_bas"] < 0.015 < a["min_haut"]):
            print("ECHEC seuil aigu 0,015 hors du trou", a)
            return 1
        e = separations["echo_vs_deux_paroles"]
        if not (e["max_bas"] < 18.0 < e["min_haut"]):
            print("ECHEC seuil écho 18 hors du trou large", e)
            return 1
        # Écho le plus faible qu'on revendique : parole à syllabes,
        # copie à 30 ms, une seconde. Le seuil 18 doit être en dessous.
        syllabique = _echo_syllabique(args.rate)
        print(
            "ECHO SYLLABIQUE propre",
            format(syllabique[0], ".2f"),
            "copie",
            format(syllabique[1], ".2f"),
        )
        if not (syllabique[0] < 18.0 < syllabique[1]):
            print("ECHEC seuil écho 18 hors du trou syllabique", syllabique)
            return 1
        c = separations["chute_duck_vs_propre"]
        if not (c["max_bas"] < 8.0 < c["min_haut"]):
            print("ECHEC seuil chute 8 dB hors du trou", c)
            return 1
        print("SEUILS EMBARQUES dans les trous mesures : grave 0,10 · aigu 0,015 · echo 18 · chute 8 dB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
