#!/usr/bin/env python3
# =========================================================
#  make_goal_sound.py — Le « wouaaah » de la foule sur un but
# =========================================================
#  POURQUOI CE FICHIER EXISTE (23/08/2026).
#
#  Demande du propriétaire : « si le but entre, il faut un petit son,
#  comme les gens qui disent wouaouh ». Deux façons de le faire :
#
#    1. télécharger un enregistrement de foule ;
#    2. le SYNTHÉTISER.
#
#  On a choisi (2), et ce n'est pas un caprice technique. Un
#  enregistrement embarqué dans une application publiée sur le Play
#  Store engage la licence de son auteur — et « trouvé sur internet »
#  n'est pas une licence. Un son fabriqué par ce script n'appartient à
#  personne d'autre que nous : aucune réclamation possible, jamais.
#
#  Et le .wav du dépôt n'est pas un binaire mystère : il se refabrique
#  d'une commande, se règle, se rejoue.
#
#  ---------------------------------------------------------
#  DEUXIÈME VERSION — « je veux un son plus réel »
#  ---------------------------------------------------------
#  La première version filtrait du bruit blanc pour imiter une voyelle.
#  Verdict du propriétaire à l'écoute : pas assez réel. Il avait raison,
#  et voici POURQUOI, parce que la raison dicte le correctif.
#
#  Du bruit filtré n'a pas de HAUTEUR. Or une foule qui crie, ce sont
#  des centaines de voix qui ont chacune une note. Ce que l'oreille
#  reconnaît instantanément comme « des gens », c'est l'empilement de
#  ces notes proches mais jamais identiques — ce léger désaccord qui
#  fait le grain d'un chœur.
#
#  Deuxième manque, au moins aussi important : la première version
#  était SÈCHE. Un stade est un volume énorme et réverbérant. Un cri
#  de foule sans queue de réverbération sonne comme enregistré dans un
#  placard, et le cerveau le rejette immédiatement.
#
#  D'où cinq couches, cette fois :
#
#   1. LA FOULE — 260 voix synthétisées UNE PAR UNE. Chacune a sa
#      note, ses harmoniques, son vibrato, son instant de départ.
#   2. LE GLISSEMENT « OU » → « A » — obtenu SANS filtre glissant :
#      les voix qui partent tôt disent « ou » (la surprise), celles qui
#      partent tard disent « a » (la joie). Comme les départs sont
#      étalés, la foule entière glisse d'elle-même. C'est exactement ce
#      qui se passe dans un vrai stade.
#   3. LES SIFFLETS — quelques sifflements aigus. Très caractéristiques
#      d'un stade, et l'oreille les repère tout de suite.
#   4. LES APPLAUDISSEMENTS — des centaines de claquements brefs,
#      irréguliers, qui montent après le cri.
#   5. LA RÉVERBÉRATION — une vraie convolution avec une queue de
#      0,9 s. C'est elle qui met la foule DANS un stade.
#
#  ---------------------------------------------------------
#  Utilisation :
#      python3 tools/make_goal_sound.py
#  Écrit android/app/src/main/res/raw/goal_roar.wav
# =========================================================
import os
import wave

import numpy as np

#  22 050 Hz : la première version était à 16 kHz, ce qui coupe tout
#  au-dessus de 8 kHz. On y perdait l'air des applaudissements et le
#  haut des sifflets — deux choses que l'oreille utilise pour juger si
#  un son est « vrai ». Le fichier reste petit.
SR = 22050
DUR = 3.0
OUT = os.path.join('android', 'app', 'src', 'main', 'res', 'raw',
                   'goal_roar.wav')

rng = np.random.default_rng(20260823)   # graine FIXE = son reproductible
n = int(SR * DUR)
t = np.arange(n) / SR

# ---------------------------------------------------------
#  Les deux voyelles, par leurs formants
# ---------------------------------------------------------
#  Un formant est une bosse de résonance du conduit vocal. Leur
#  position dit QUELLE voyelle on entend — c'est toute la différence
#  entre « ou » et « a ». Valeurs classiques de la phonétique :
VOYELLE_OU = [(320, 1.0), (800, 0.55), (2500, 0.10)]
VOYELLE_A = [(700, 1.0), (1200, 0.85), (2600, 0.22)]


def enveloppe_formants(freqs, formants):
    """Gain à appliquer à chaque harmonique pour entendre la voyelle.

    Chaque formant est une résonance en cloche autour de sa fréquence.
    On évalue simplement cette cloche à la fréquence de l'harmonique :
    c'est de la synthèse par formants, et ça coûte trois lignes.
    """
    g = np.zeros_like(freqs)
    for fc, amp in formants:
        # Largeur proportionnelle à la fréquence : les formants hauts
        # sont naturellement plus larges que les formants graves.
        bw = fc * 0.45
        g += amp / (1.0 + ((freqs - fc) / bw) ** 2)
    return g


# ---------------------------------------------------------
#  1. LA FOULE — 260 voix, une par une
# ---------------------------------------------------------
N_VOIX = 260
foule = np.zeros(n)

for i in range(N_VOIX):
    # Hauteur de la voix. Deux tiers de voix graves (hommes), un tiers
    # d'aiguës : c'est ce mélange qui fait qu'une foule n'est ni un
    # grondement, ni un cri d'enfants.
    if rng.random() < 0.65:
        f0 = rng.normal(135.0, 22.0)      # voix graves
    else:
        f0 = rng.normal(225.0, 35.0)      # voix aiguës
    f0 = float(np.clip(f0, 80.0, 330.0))

    # Instant de départ. PERSONNE ne réagit exactement en même temps :
    # c'est cet étalement qui donne la vague, au lieu d'un « bloc » qui
    # sonnerait comme un effet sonore de dessin animé.
    depart = float(rng.uniform(0.0, 0.55))
    d0 = int(depart * SR)
    if d0 >= n - 100:
        continue

    # Les voix qui partent TÔT disent « ou » (la surprise), celles qui
    # partent TARD disent « a » (la joie). D'où le « wouaaah » global,
    # sans aucun filtre glissant.
    p = depart / 0.55
    formants = [
        (a[0] + (b[0] - a[0]) * p, a[1] + (b[1] - a[1]) * p)
        for a, b in zip(VOYELLE_OU, VOYELLE_A)
    ]

    m = n - d0
    tv = np.arange(m) / SR

    # Montée de hauteur (~1,5 demi-ton) : une voix qui crie monte.
    # Plus le vibrato, léger et propre à chaque voix.
    glide = 1.0 + 0.09 * np.minimum(1.0, tv / 0.6)
    vib = 1.0 + rng.uniform(0.004, 0.014) * np.sin(
        2 * np.pi * rng.uniform(4.0, 7.0) * tv + rng.uniform(0, 6.28))
    f_inst = f0 * glide * vib
    phase = 2 * np.pi * np.cumsum(f_inst) / SR

    # Harmoniques. Une voix criée est RICHE : on en garde beaucoup, et
    # on module leur amplitude par la voyelle.
    nh = int(min(24, (SR / 2.2) // f0))
    h_idx = np.arange(1, nh + 1)
    gains = enveloppe_formants(f0 * h_idx, formants) / (h_idx ** 0.7)

    voix = np.zeros(m)
    for k, g in zip(h_idx, gains):
        if g < 0.012:
            continue
        voix += g * np.sin(k * phase + rng.uniform(0, 6.28))

    # Enveloppe propre à cette voix : attaque vive, tenue courte,
    # extinction. Chacun crie sa propre durée.
    att = int(rng.uniform(0.05, 0.16) * SR)
    tenue = int(rng.uniform(0.25, 0.75) * SR)
    env = np.ones(m)
    a_end = min(att, m)
    env[:a_end] = np.linspace(0, 1, a_end) ** 0.6
    if att + tenue < m:
        rest = m - att - tenue
        env[att + tenue:] = np.exp(-np.linspace(0, rng.uniform(2.5, 5.0), rest))
    foule[d0:] += voix * env * rng.uniform(0.5, 1.0)

foule /= np.sqrt(np.mean(foule ** 2)) + 1e-9

# ---------------------------------------------------------
#  2. LE SOUFFLE — l'air de milliers de poitrines
# ---------------------------------------------------------
#  Les voix seules sonnent encore « synthé ». Un peu de bruit filtré
#  par-dessus apporte l'air que l'additif ne produit pas.
souffle = rng.standard_normal(n)
souffle = np.convolve(souffle, np.ones(9) / 9.0, mode='same')
souffle /= np.sqrt(np.mean(souffle ** 2)) + 1e-9

env_g = np.ones(n)
a = int(0.14 * SR)
env_g[:a] = np.linspace(0, 1, a) ** 0.6
d = int(0.70 * SR)
env_g[d:] = np.exp(-np.linspace(0, 3.0, n - d))

# ---------------------------------------------------------
#  3. LES SIFFLETS
# ---------------------------------------------------------
#  Rares mais décisifs : c'est un marqueur sonore que le cerveau
#  associe immédiatement à un stade. Trop nombreux, ça devient un
#  arbitre ; on en met une poignée, en retrait.
sifflets = np.zeros(n)
for _ in range(5):
    d0 = int(rng.uniform(0.25, 1.6) * SR)
    dur = int(rng.uniform(0.20, 0.45) * SR)
    if d0 + dur >= n:
        continue
    tv = np.arange(dur) / SR
    f = rng.uniform(1900, 3100) * (
        1.0 + 0.02 * np.sin(2 * np.pi * rng.uniform(5, 9) * tv))
    s = np.sin(2 * np.pi * np.cumsum(f) / SR)
    e = np.minimum(1.0, tv / 0.05) * np.exp(-tv * 4.0)
    sifflets[d0:d0 + dur] += s * e * rng.uniform(0.25, 0.5)

# ---------------------------------------------------------
#  4. LES APPLAUDISSEMENTS
# ---------------------------------------------------------
#  Un clap = un claquement très bref et large bande. Des centaines,
#  répartis irrégulièrement, et de plus en plus denses APRÈS le cri —
#  parce qu'on crie d'abord, on applaudit ensuite.
claps = np.zeros(n)
for _ in range(650):
    ct = rng.uniform(0.15, DUR - 0.1)
    # Densité croissante : plus on avance, plus il y a de claps.
    if rng.random() > min(1.0, 0.25 + ct / 1.6):
        continue
    d0 = int(ct * SR)
    dur = int(rng.uniform(0.006, 0.016) * SR)
    if d0 + dur >= n:
        continue
    b = rng.standard_normal(dur) * np.exp(-np.linspace(0, 7, dur))
    claps[d0:d0 + dur] += b * rng.uniform(0.4, 1.0)
claps /= np.max(np.abs(claps)) + 1e-9

# ---------------------------------------------------------
#  MÉLANGE
# ---------------------------------------------------------
#  ⚠ LEÇON DE LA PREMIÈRE VERSION : des coefficients de mélange ne
#  veulent rien dire tant que les couches n'ont pas été ramenées au
#  même niveau efficace (RMS). Un filtre résonant atténue énormément,
#  du bruit large bande non — écrire « 0.5 » devant chacun donne alors
#  tout le poids au second.
sec = (foule * env_g * 1.00
       + souffle * env_g * 0.30
       + sifflets * 0.35
       + claps * 0.45)

# ---------------------------------------------------------
#  5. LA RÉVERBÉRATION — mettre la foule DANS un stade
# ---------------------------------------------------------
#  C'est le manque le plus grave de la première version. Une vraie
#  convolution : on fabrique une réponse impulsionnelle (du bruit qui
#  décroît exponentiellement, la forme d'une queue de réverbération) et
#  on convolue. Sans ça, aucun réglage des autres couches ne rendra le
#  son crédible — l'oreille entend « petit local », pas « stade ».
ir_len = int(0.9 * SR)
ir = rng.standard_normal(ir_len) * np.exp(-np.linspace(0, 5.0, ir_len))
ir[0] = 1.0                       # le son direct
ir /= np.sqrt(np.sum(ir ** 2))
mouille = np.convolve(sec, ir, mode='full')[:n]

#  35 % de réverbération : assez pour le volume, pas au point de
#  transformer le cri en bouillie.
mix = 0.65 * sec + 0.35 * (mouille / (np.max(np.abs(mouille)) + 1e-9)
                           * np.max(np.abs(sec)))

#  Compression douce : une foule réelle est dense, sans crêtes isolées.
#  `tanh` arrondit les pointes et rapproche le niveau moyen du maximum,
#  ce qui rend le son plus « plein » sur un haut-parleur de téléphone.
mix = np.tanh(mix * 1.6 / (np.max(np.abs(mix)) + 1e-9))

#  Normalisation à -3 dBFS. On ne monte PAS à 0 : un son de
#  notification à fond est agressif, et le client règle son volume.
mix = mix / (np.max(np.abs(mix)) + 1e-9) * 0.70

#  Fondus : sans eux, la troncature nette crée un « clac » audible.
f_in = int(0.005 * SR)
mix[:f_in] *= np.linspace(0, 1, f_in)
f_out = int(0.12 * SR)
mix[-f_out:] *= np.linspace(1, 0, f_out)

pcm = np.clip(mix * 32767.0, -32768, 32767).astype('<i2')

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with wave.open(OUT, 'wb') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())

size = os.path.getsize(OUT)
print(f'écrit : {OUT}')
print(f'  durée   : {DUR:.2f} s   ({SR} Hz mono 16 bits)')
print(f'  poids   : {size / 1024:.0f} Ko')
print(f'  voix    : {N_VOIX}')
print(f'  crête   : {np.max(np.abs(mix)):.3f}   (-3 dBFS visé)')
