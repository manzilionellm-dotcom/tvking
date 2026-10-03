# Format, rééchantillonnage et tampon

Angle : le son « vieille radio », « dans un trou », « comme la musique quand on t'appelle », « guerre entre deux sons », sur de l'AAC-LC 48 kHz stéréo (France 24, France 2, France Info, BEIN). Même plainte sur la box, sur le Samsung SM-S938B avec Zuno essai, et dans 7 Motion (lecteur mpv). Une autre app, sur les mêmes chaînes, sonne bien.

Ce texte ne dit pas que le son a été entendu, ni qu'il est réparé. Le son par défaut n'a pas été modifié. Les compteurs ajoutés à la fiche lisent l'AudioTrack ; ils n'écrivent rien dedans.

## PROUVÉ

### 1. Tests du texte de la fiche

Commande :

```text
/tmp/gradle-8.14.3/bin/gradle -p android-app/packages/native_video_player/logic-test test --console=plain
```

Sortie utile : `BUILD SUCCESSFUL`. 146 tests, 0 échec, 0 erreur (les 133 d'avant, plus 13 sur le tampon et le format).

Ce que ces tests verrouillent :

- Piste 48 kHz et mélangeur 48 kHz : la fiche dit « mêmes fréquences : AudioFlinger n'a pas à rééchantillonner ». Aucune phrase FORMAT en haut.
- Piste 48 kHz et mélangeur 44,1 kHz : la fiche dit « vers le bas ». La règle `reechantillonnage_android` est une info incertaine, pas une cause sûre, et elle n'a pas d'interrupteur.
- Piste 48 kHz et mélangeur 96 kHz : « vers le haut ».
- Une fréquence manquante : « rééchantillonnage Android inconnu ». On n'invente pas un zéro.
- `getUnderrunCount` à 4 et le rappel Media3 à 1 : la fiche cite les deux, et retient 4.
- Piste illisible : « underruns AudioTrack non lisibles », pas un 0 inventé.
- Vitesse 1,00 et Sonic inactif : pas de ligne RYTHME. Vitesse 1,03 et Sonic actif : une info, pas une cause sûre.
- Latence stable, en hausse, en baisse, ou qui oscille : quatre phrases distinctes.
- `getLatency` très au-dessus du tampon : la fiche rappelle que cette méthode compte souvent le tampon deux fois.
- Sans sonde : « Écrêtage : non mesuré », pas 0,00 %.
- Sans AudioTrack encore créé : « Tampon : pas encore lu ».

### 2. Simulation des glitches

Commande :

```text
python3 android-app/tools/son_glitch_sim.py
```

Sortie (Python 3, numpy 2.4.4, ffmpeg 6.1.1) :

```text
RÉFÉRENCES (avant glitch)
parole synthétique            BAS      >4kHz   0.16%  tél  10.49%  kurt     1.5  mod 0.099  zéros   0.0%  plat 0.000  NI RADIO NI HACHÉ
bruit large                   LARGE    >4kHz  83.29%  tél  13.12%  kurt     3.0  mod 0.039  zéros   0.0%  plat 0.563  NI RADIO NI HACHÉ
partiels jusqu'à 10 kHz       BAS      >4kHz   2.22%  tél  35.24%  kurt     5.3  mod 0.067  zéros   0.4%  plat 0.000  NI RADIO NI HACHÉ

GLITCH SUR DU BRUIT LARGE (le contrôle : on SAIT qu'il y a des aigus)
téléphone 300-3400 Hz         BAS      >4kHz   3.34%  tél  92.08%  kurt     3.0  mod 0.091  zéros   0.1%  plat 0.000  VIEILLE RADIO (spectre)
passe-bas 4 kHz x2            BAS      >4kHz   6.40%  tél  79.17%  kurt     3.0  mod 0.082  zéros   0.1%  plat 0.000  VIEILLE RADIO (spectre)
rééch. linéaire 48→8→48       BAS      >4kHz   4.99%  tél  79.56%  kurt     3.4  mod 0.144  zéros   0.1%  plat 0.003  VIEILLE RADIO (spectre)
rééch. linéaire 48→44.1→48    LARGE    >4kHz  68.34%  tél  24.99%  kurt     3.4  mod 0.045  zéros   0.1%  plat 0.463  NI RADIO NI HACHÉ
rééch. linéaire 48→96→48      LARGE    >4kHz  73.60%  tél  20.80%  kurt     3.1  mod 0.087  zéros   0.1%  plat 0.515  NI RADIO NI HACHÉ
vitesse 1,03 (linéaire)       LARGE    >4kHz  75.92%  tél  18.90%  kurt     3.2  mod 0.041  zéros   0.0%  plat 0.533  NI RADIO NI HACHÉ
vitesse 0,97 (linéaire)       LARGE    >4kHz  74.41%  tél  20.08%  kurt     3.2  mod 0.043  zéros   0.1%  plat 0.518  NI RADIO NI HACHÉ
retrait 1 % d'échantillons    LARGE    >4kHz  83.27%  tél  13.17%  kurt     3.0  mod 0.039  zéros   0.0%  plat 0.561  NI RADIO NI HACHÉ
trous 20 ms / 200 ms          LARGE    >4kHz  83.16%  tél  13.20%  kurt     3.3  mod 0.304  zéros  10.0%  plat 0.562  GUERRE
blocage 20 ms / 200 ms        LARGE    >4kHz  69.57%  tél  11.25%  kurt     3.2  mod 0.278  zéros   0.0%  plat 0.480  GUERRE
bégaiement 10 ms              LARGE    >4kHz  83.15%  tél  13.25%  kurt     3.0  mod 0.040  zéros   0.0%  plat 0.550  NI RADIO NI HACHÉ
échantillon tenu x8           MILIEU   >4kHz  13.02%  tél  72.98%  kurt     3.0  mod 0.100  zéros   0.0%  plat 0.070  NI RADIO NI HACHÉ
modulation en anneau 90 Hz    LARGE    >4kHz  83.13%  tél  13.20%  kurt     4.5  mod 0.066  zéros   0.2%  plat 0.564  NI RADIO NI HACHÉ
peigne 2 ms                   LARGE    >4kHz  83.27%  tél  13.01%  kurt     3.0  mod 0.045  zéros   0.1%  plat 0.336  CREUX
deux copies désaccordées 0,7 %  LARGE    >4kHz  79.94%  tél  15.85%  kurt     3.0  mod 0.041  zéros   0.1%  plat 0.555  NI RADIO NI HACHÉ
baisse de volume 4 Hz         LARGE    >4kHz  83.07%  tél  13.32%  kurt     4.6  mod 0.432  zéros   0.1%  plat 0.565  GUERRE
écrêtage x4                   LARGE    >4kHz  83.32%  tél  13.04%  kurt     1.8  mod 0.035  zéros   0.0%  plat 0.563  NI RADIO NI HACHÉ
quantification 16 bits        LARGE    >4kHz  83.29%  tél  13.12%  kurt     3.0  mod 0.039  zéros   0.0%  plat 0.563  NI RADIO NI HACHÉ
quantification 8 bits         LARGE    >4kHz  83.28%  tél  13.12%  kurt     3.0  mod 0.039  zéros   0.0%  plat 0.563  NI RADIO NI HACHÉ

GLITCH SUR LA PAROLE SYNTHÉTIQUE (harmoniques sous 3,8 kHz)
téléphone 300-3400 Hz         BAS      >4kHz   0.02%  tél  76.45%  kurt     5.8  mod 0.199  zéros   0.5%  plat 0.000  NI RADIO NI HACHÉ
trous 20 ms / 200 ms          BAS      >4kHz   0.17%  tél  10.94%  kurt     1.7  mod 0.309  zéros   0.0%  plat 0.000  NI RADIO NI HACHÉ
bégaiement 10 ms              BAS      >4kHz   0.23%  tél  12.14%  kurt     1.5  mod 0.101  zéros   0.0%  plat 0.000  NI RADIO NI HACHÉ
peigne 2 ms                   BAS      >4kHz   0.40%  tél  17.30%  kurt     2.1  mod 0.051  zéros   0.1%  plat 0.000  NI RADIO NI HACHÉ
deux copies désaccordées 0,7 %  BAS      >4kHz   0.13%  tél   9.19%  kurt     2.3  mod 0.312  zéros   0.1%  plat 0.000  NI RADIO NI HACHÉ
rééch. linéaire 48→44.1→48    BAS      >4kHz   0.13%  tél  10.45%  kurt     1.5  mod 0.099  zéros   0.0%  plat 0.000  NI RADIO NI HACHÉ
quantification 16 bits        BAS      >4kHz   0.16%  tél  10.49%  kurt     1.5  mod 0.099  zéros   0.0%  plat 0.000  NI RADIO NI HACHÉ
écrêtage x4                   BAS      >4kHz   0.16%  tél   9.05%  kurt     1.3  mod 0.080  zéros   0.0%  plat 0.000  NI RADIO NI HACHÉ
baisse de volume 4 Hz         BAS      >4kHz   0.16%  tél  10.49%  kurt     2.3  mod 0.437  zéros   0.0%  plat 0.000  NI RADIO NI HACHÉ

GLITCH SUR DES PARTIELS (jusqu'à 10 kHz, énergie > 4 kHz déjà à 2,22 %)
téléphone 300-3400 Hz         BAS      >4kHz   0.16%  tél  93.77%  kurt     4.9  mod 0.084  zéros   0.3%  plat 0.000  NI RADIO NI HACHÉ
deux copies désaccordées 0,7 %  BAS      >4kHz   2.11%  tél  35.44%  kurt     4.2  mod 0.329  zéros   0.3%  plat 0.000  NI RADIO NI HACHÉ
peigne 2 ms                   BAS      >4kHz   3.58%  tél  73.28%  kurt     4.5  mod 0.057  zéros   0.4%  plat 0.000  NI RADIO NI HACHÉ
trous 20 ms / 200 ms          BAS      >4kHz   2.21%  tél  34.89%  kurt     5.8  mod 0.307  zéros  10.4%  plat 0.000  NI RADIO NI HACHÉ
rééch. linéaire 48→44.1→48    BAS      >4kHz   1.76%  tél  35.20%  kurt     5.0  mod 0.067  zéros   0.3%  plat 0.000  NI RADIO NI HACHÉ
vitesse 1,03 (linéaire)       BAS      >4kHz   2.21%  tél  35.25%  kurt     5.2  mod 0.065  zéros   0.3%  plat 0.000  NI RADIO NI HACHÉ

FFMPEG aresample (swr), même bruit large, aller-retour vers 48 kHz
ffmpeg swr 48→44k→48          LARGE    >4kHz  80.31%  tél  15.46%  kurt     3.0  mod 0.042  zéros   0.0%  plat 0.413  CREUX
ffmpeg swr 48→8k→48           BAS      >4kHz   0.20%  tél  84.38%  kurt     3.0  mod 0.086  zéros   0.1%  plat 0.000  VIEILLE RADIO (spectre)
ffmpeg swr 48→96k→48          LARGE    >4kHz  81.93%  tél  14.18%  kurt     3.0  mod 0.041  zéros   0.0%  plat 0.528  NI RADIO NI HACHÉ
```

Règle du classement, fixée dans le script avant de juger un glitch : « vieille radio (spectre) » seulement si l'énergie au-dessus de 4 kHz tombe à 12 % ou moins ET qu'elle a perdu au moins 15 points ET que le kurtosis reste sous 20 (pas un train de clics). 12 % et 40 % sont les seuils déjà utilisés par `AudioSpectrum` (`LOW_MAX_RATIO`, `WIDE_MIN_RATIO`).

Lecture de ces chiffres :

- Le seul geste qui fabrique vraiment le spectre « vieille radio » à partir d'un bruit large, c'est un filtre étroit : téléphone 300–3 400 Hz (83 % → 3 %), passe-bas 4 kHz (→ 6 %), ou descente à 8 kHz puis retour (linéaire → 5 %, ffmpeg swr → 0,2 %).
- Un rééchantillonnage 48 ↔ 44,1 garde un bruit large : 68 % en linéaire, 80 % avec ffmpeg. 48 ↔ 96 aussi (74 % et 82 %).
- Une vitesse 0,97 ou 1,03, ou le retrait d'1 % des échantillons, laisse le bruit large (74 à 83 %).
- Des trous de 20 ms laissent 83 % au-dessus de 4 kHz. Ils montent la modulation d'enveloppe (0,039 → 0,304) et mettent 10 % d'échantillons à zéro. C'est un son haché, pas un son filtré.
- Une baisse de volume à 4 Hz (l'image « musique pendant un appel », côté volume) laisse 83 % au-dessus de 4 kHz et 0,1 % de zéros. L'enveloppe pompe (modulation 0,432). Le spectre ne bouge pas.
- Un peigne de 2 ms laisse 83 % au-dessus de 4 kHz et creuse le spectre (plat 0,563 → 0,336). Le mot « dans un trou » peut coller à ça. Le pourcentage au-dessus de 4 kHz, lui, ne le voit pas.
- Deux copies de bruit désaccordées de 0,7 % ne se battent pas : le bruit n'a pas de hauteur. Sur des partiels, la même opération laisse le pourcentage à 2,11 % (il était 2,22 %) et fait passer la modulation de 0,067 à 0,329. Le spectre « > 4 kHz » ne voit pas la guerre ; l'enveloppe, si.
- L'écrêtage et le passage en 16 bits (sans dither) ne bougent pas le pourcentage du bruit (83,32 % et 83,29 %).
- Tenir chaque échantillon 8 fois (un blocage continu, pas un trou de temps en temps) descend le bruit à 13 %, juste au-dessus du seuil « bas ». C'est le seul glitch de rythme qui s'approche d'un filtre, et il est continu.
- Le libellé CREUX sur ffmpeg 48 → 44,1 → 48 vient d'un aplatissement 0,563 → 0,413. L'énergie au-dessus de 4 kHz reste à 80 %. Ce n'est pas le spectre téléphone.
- Des partiels qui montent jusqu'à 10 kHz ne font quand même que 2,22 % d'énergie au-dessus de 4 kHz, parce que les graves portent l'énergie. C'est dans la fourchette 0,9–3,6 % déjà mesurée sur la parole. Un filtre téléphone sur ce signal ne fait bouger ce pourcentage que de 2,22 % à 0,16 %, mais il entasse 94 % de l'énergie entre 300 Hz et 3,4 kHz (c'était 35 %). La sonde actuelle, qui ne regarde que « > 4 kHz », classe les deux en « bas ».

ffmpeg est appelé par le script (`aresample`, rééchantillonneur `swr`). Les trois lignes FFMPEG ci-dessus sont sa sortie, relue en wav.

## LU DANS LE CODE

Ce n'est pas une commande, donc ce n'est pas dans PROUVÉ. C'est le chemin Media3 1.5.1 tel qu'il est branché.

- `DefaultAudioSink` crée l'AudioTrack à la fréquence du PCM, après la chaîne de processeurs. Il n'appelle pas `SonicAudioProcessor.setOutputSampleRateHz`. Si la vitesse est 1 et la hauteur est 1, Sonic se retire (`NOT_SET`). Le rééchantillonnage vers la fréquence du mélangeur, s'il a lieu, est celui d'Android, après le dernier PCM que l'app peut copier.
- Le direct fige `DefaultLivePlaybackSpeedControl` à min = max = 1. `setEnableAudioTrackPlaybackParams(false)` : un changement de vitesse passerait par Sonic, pas par `AudioTrack.setPlaybackParams`. Aujourd'hui la vitesse demandée est 1.
- `setEnableFloatOutput(false)`. `ToInt16PcmAudioProcessor` est inactif quand le décodeur est déjà en PCM 16 bits (c'est le cas habituel de l'AAC). Il n'ajoute pas de dither. S'il reçoit du flottant, il borne à [-1, 1] puis multiplie par 32 767, sans bruit de dither.
- Le tampon de sortie reste celui d'avant : le calcul Media3, doublé, plafonné à +256 Ko (`AudioTrackBuffer`). Le tampon réseau (5 s / 45 s) n'est pas touché.
- 7 Motion passe par libmpv (`video_player_screen.dart`, `PlayerConfiguration`), pas par cet AudioSink. Un défaut présent aussi dans 7 Motion a peu de chances de venir de Sonic ou du tampon Media3 seuls.

Les compteurs nouveaux sont dans la fiche, bloc « Tampon / Format / Rythme / Écrêtage » :

- underruns : `AudioTrack.getUnderrunCount` (API 24) à côté du rappel Media3 ;
- latence : `AudioTrack.getLatency` (méthode cachée, valeur brute) et durée du tampon (`bufferSizeInFrames`) ;
- fréquence de la piste, fréquence `PROPERTY_OUTPUT_SAMPLE_RATE`, période `PROPERTY_OUTPUT_FRAMES_PER_BUFFER` ;
- vitesse et hauteur du lecteur, min/max, nombre d'écarts hors de 1, Sonic actif ou non, vitesse lue par `getPlaybackParams` si Android répond ;
- pourcentage d'échantillons `|s| ≥ 32760`, sonde audiotrack si elle a parlé, sinon sonde décodeur, sinon « non mesuré ».

La piste est retenue par un fournisseur qui appelle le fournisseur par défaut de Media3 et garde la référence. Aucun paramètre du `AudioTrack.Builder` n'est ajouté. Aucun interrupteur nouveau : il n'y a pas de nouveau comportement à couper.

## HYPOTHÈSES

Confiance que ce mécanisme est la cause du son décrit. Ce n'est pas une somme à 100 %.

| # | Mécanisme | Confiance | Ce qui la tient |
| --- | --- | --- | --- |
| 1 | Un passe-bas dans l'app, avant l'AudioTrack (Sonic, float, 16 bits, dither, tampon qui « filtre ») | 10 % | Les quatre sondes étaient déjà identiques. La simulation : trous, vitesse ±3 %, 16 bits, écrêtage et 48↔44,1 ne font pas tomber un bruit large sous 12 %. |
| 2 | Rééchantillonnage Android 48 kHz vers 44,1 ou 96 kHz, après la sonde | 20 % | Possible seulement si la fiche montre deux fréquences différentes. La simulation (linéaire et ffmpeg) garde alors un bruit large. La confiance monte à 25 % si le mélangeur est vers 8–16 kHz, parce que là le spectre téléphone apparaît. Elle tombe vers 5 % si les deux fréquences sont 48 kHz. |
| 3 | Sous-alimentation du tampon (underruns) comme son continu « vieille radio » | 15 % | Les trous gardent 83 % d'énergie au-dessus de 4 kHz. Ils expliquent un son haché, avec des zéros. La fiche tranche : compteur qui reste à 0 pendant que le son est mauvais → cette hypothèse tombe. |
| 4 | Dérive d'horloge corrigée par une vitesse variable | 8 % | Le code fige la vitesse à 1. La simulation à ±3 % ne fait pas un spectre radio. 7 Motion n'utilise pas ce Sonic et la plainte y est la même. |
| 5 | Écrêtage, absence de dither, PCM flottant | 5 % | Float coupé dans le code. Quantification 16 bits : 83,29 % contre 83,29 %. Écrêtage : le pourcentage ne baisse pas. La fiche le dira en % si la sonde est allumée. |
| 6 | Deux copies légèrement désaccordées, ou un peigne (« trou », « guerre »), invisibles pour la sonde > 4 kHz | 35 % | Sur des partiels à 2,22 % (la zone déjà mesurée sur la parole), un désaccord de 0,7 % laisse le pourcentage à 2,11 % et triple presque la modulation. Un peigne de 2 ms laisse un bruit large. Le chevauchement de deux lecteurs a déjà été écarté par les essais précédents : s'il reste une guerre, elle est dans une seule piste, ou après l'app (mélangeur, HDMI, téléviseur). |
| 7 | Cause propre au AudioSink Media3, absente de mpv | 15 % | La plainte est aussi dans 7 Motion. Ce qui est commun pèse plus : le flux, ou le chemin Android après les deux lecteurs. |

L'hypothèse 6 est la plus haute de cet angle parce que les mots « trou » et « guerre » collent à des mesures que le pourcentage > 4 kHz ne voit pas, et que ce pourcentage, sur les chaînes en cause, est déjà celui d'une parole (0,9–3,6 %). Elle n'est pas démontrée sur l'appareil.

## À VÉRIFIER SUR L'APPAREIL

Build de cette branche seulement. Ne pas publier. Ne pas changer un réglage qui modifie le son : Spectre copie le PCM, il ne le filtre pas.

1. Box, ou Samsung avec Zuno essai (le lecteur natif, pas 7 Motion). Ouvrir Diagnostic du son. Allumer Spectre.
2. Lancer France 24, ou France 2. Ne pas zapper. Laisser tourner une minute (la fiche relit le tampon toutes les 5 s pendant 60 s).
3. Lire les quatre lignes Tampon, Format, Rythme, Écrêtage. Les noter telles quelles.

Lecture :

- `underruns AudioTrack 0` et `rappel Media3 0` pendant que le son est mauvais : les trous de tampon ne sont pas la cause de cette écoute. L'hypothèse 3 tombe pour cette séance.
- Le compteur monte (plusieurs fois dans la minute) : les trous sont réels. Ils expliquent un son haché. Ils n'expliquent pas, d'après la simulation, un spectre coupé à 4 kHz.
- `piste 48 kHz` et `mélangeur 48 kHz` : Android n'a pas à rééchantillonner. L'hypothèse 2 tombe pour cette sortie.
- `mélangeur 44,1 kHz` ou `96 kHz` : Android rééchantillonne après la sonde. Ce n'est pas encore la preuve du son radio (la simulation garde un bruit large). Le noter, et comparer si l'autre app, sur le même appareil, annonce la même fréquence.
- `mélangeur` vers 8 ou 16 kHz : là, la simulation dit que le spectre téléphone apparaît. Ce serait le cas le plus net de cet angle.
- `vitesse 1,00`, `0 écart(s)`, `Sonic inactif` : personne ne corrige le rythme. L'hypothèse 4 tombe pour cette séance.
- `Écrêtage` sous 2 % : pas de saturation. Au-dessus de 10 % : saturation réelle (seuil déjà dans `AudioSpectrum`). « non mesuré » : la sonde n'a pas encore une fenêtre, ou elle est coupée.
- `latence stable` : l'horloge ne dérive pas de façon visible. `latence en hausse` sans underrun : le tampon se remplit, le timbre ne devrait pas changer. `latence en baisse` avec underruns qui montent : la piste est sous-alimentée.
- `getLatency` « souvent le double du tampon » : lire le tampon en ms, pas le chiffre brut, pour la latence. `latence non lisible` : Android a refusé la méthode cachée. Ce n'est pas une latence de 0.

4. Bouton « Jouer le son témoin », déjà dans Diagnostic du son. Bruit sourd : la sortie de l'appareil (après l'app) avale les aigus, et la ligne Format dira si c'est un mélangeur à basse fréquence. Bruit clair, chaîne sourde : le sourd est dans le flux ou dans le décodeur, pas dans le rééchantillonnage de la sortie.
5. 7 Motion (mpv) n'a pas ces lignes. Si Zuno affiche 0 underrun, 48 kHz = 48 kHz, vitesse 1,00, écrêtage bas, et que 7 Motion sonne pareil sur la même chaîne, la cause n'est pas le tampon Media3 ni Sonic. Elle est dans ce que les deux lecteurs partagent (le flux, ou le chemin du téléphone / de la box après eux).

Rien dans cette branche ne doit être publié, ni envoyé sur les releases.
