# Laboratoire — la forme du son, pas seulement « au-dessus de 4 kHz »

Personne n'a écouté. Les chiffres viennent de signaux fabriqués, dont le défaut est connu, puis mesurés par un programme.

Le pourcentage d'énergie au-dessus de 4 kHz n'est pas un juge de la parole. Une voix a presque toute son énergie dans le grave. Un filtre « téléphone » (300–3400 Hz, le son d'un appel) enlève ce grave. Le pourcentage au-dessus de 4 kHz, lui, ne bouge presque pas : on a retiré le gros du signal, donc le peu qui reste au-dessus de 4 kHz pèse toujours à peu près le même poids.

## PROUVÉ

Commande, le 3 octobre 2026, sur cette machine (Python 3, numpy 2.4.4, scipy 1.18.1, ffmpeg 6.1.1) :

```
python3 android-app/tools/audio_lab/mesure.py --valider
```

Code de sortie **0**. Le script échoue tout seul si un seuil sort du trou mesuré.

Les filtres (téléphone, passe-bas, passe-haut, compresseur, écrêtage, écho 30 ms) sont faits par **ffmpeg**, pas par le détecteur. La parole est simulée : harmoniques en 1/k (pente d'une voix) et, à part, des voyelles à formants. Deux familles, pour ne pas dépendre d'un seul modèle.

| Signal | > 4 kHz | grave/milieu | aigu/milieu | chute | écho |
| --- | ---: | ---: | ---: | ---: | ---: |
| Parole homme, propre | 0,0112 | 3,47 | 0,048 | 0,6 dB | 7 |
| Parole femme, propre | 0,0196 | 1,71 | 0,051 | 0,4 dB | 6 |
| La même, filtre téléphone ffmpeg 300–3400 Hz | 0,0123 | 0,076 | 0,0046 | 0,7 dB | 4 |
| Femme, même filtre | 0,0124 | 0,075 | 0,0048 | 0,6 dB | 5 |
| Voyelles, filtre téléphone | 0,0050 | 0,015 | ~0 | 2,1 dB | 3 |
| Passe-bas seul (le grave reste) | 0,0022 | 3,61 | 0,0034 | 0,6 dB | 4 |
| Parole déjà coupée à 3,2 kHz, sans filtre | 0,0026 | 3,50 | ~0 | 0,5 dB | 4 |
| Passe-haut seul (l'aigu reste) | 0,0572 | 0,072 | 0,063 | 0,6 dB | 7 |
| Copie du même son, 30 ms plus tard | 0,0148 | 2,27 | 0,053 | 1,5 dB | 173 |
| Deux paroles différentes additionnées | 0,0134 | 2,40 | 0,046 | 1,3 dB | 12 |
| Gain × 0,2 pendant 2,5 s | 0,0112 | 3,47 | 0,048 | 14,4 dB | 7 |
| 2 s de silence au milieu | 0,0112 | 3,49 | 0,049 | 0,6 dB | 5 |
| Bruit ajouté à −50 dBFS | 0,0123 | 3,46 | 0,048 | 0,6 dB | 4 |
| Écrêtage (volume +28 dB) | 0,0192 | 3,26 | 0,056 | 0,0 dB | 6 |
| Voies identiques / voies inversées | | | | | G/D +1,00 / −1,00 |

Lecture de la première ligne et de la ligne téléphone : **> 4 kHz passe de 1,12 % à 1,23 %**. Le filtre téléphone ne se voit pas. Le grave, lui, passe de 3,47 à 0,076.

Le même calcul, refait en Kotlin sur une parole harmonique d'une seconde (test `AudioQualityTest`, logique pure, pas le téléphone) :

- propre : grave 3,47, aigu 0,047, > 4 kHz = 1,09 %, classe LARGE, et l'ancien mètre dit BASSE
- téléphone : grave 0,083, aigu 0,004, > 4 kHz = 1,23 %, classe TÉLÉPHONE, et l'ancien mètre dit encore BASSE
- passe-bas seul : grave 3,62, classe SOURD
- passe-haut seul : grave 0,079, aigu 0,061, classe MAIGRE

`gradle test` dans `android-app/packages/native_video_player/logic-test` : **BUILD SUCCESSFUL**, 0 échec (toute la suite, y compris les 6 tests nouveaux).

Aller-retour WAV (ffmpeg écrit un WAV PCM 16 bits puis le relit) : grave/milieu 3,468810 des deux côtés.

### Seuils embarqués, pris dans les trous

| Indicateur | Trou mesuré | Seuil |
| --- | --- | --- |
| grave/milieu | téléphone ≤ 0,0756, parole ou passe-bas ≥ 0,144 | **0,10** (milieu géométrique mesuré 0,104) |
| aigu/milieu | téléphone ≤ 0,0048, passe-haut = 0,063 | **0,015** (milieu géométrique mesuré 0,017) |
| écho | deux paroles = 11,8 ; copie syllabique à 30 ms = 28 ; témoin long = 173 | **18** (milieu du trou étroit 11,8 … 28) |
| chute | parole ≤ 2,3 dB, y compris 2 s de silence ; gain × 0,2 = 14,4 dB | **8 dB** (milieu du trou) |

La forme se lit à deux chiffres, pas à un seul :

- grave bas **et** aigu bas → téléphone (passe-bande 300–3400 Hz)
- grave bas **et** aigu présent → maigre (passe-haut seulement)
- grave présent **et** aigu bas → sourd (parole sans souffle, ou passe-bas seul). L'ancien mètre met ce cas dans la même case que le téléphone. Celui-ci non.
- les deux présents → large

Le grave seul ne sépare pas le téléphone du passe-haut : les deux coupent le grave (0,072 et 0,076 se chevauchent). C'est pour ça qu'il faut l'aigu avec.

### Ce qui a été mesuré et qui ne sépare pas

- **Bords à −40 dB et à −20 dB** (bandes 1/3 d'octave). Un passe-haut à 300 Hz de cette pente laisse encore la bande 100 Hz dans les 40 dB. Les bords se chevauchent. On ne s'en sert pas comme juge.
- **Plancher de bruit contre le téléphone.** Les deux sont à −300 dB (silence numérique entre les syllabes). Le plancher ne dit pas « radio ». Il sait lire un vrai bruit : −50 dBFS ajouté → plancher −50,1 dB.
- **Pompage du compresseur ffmpeg** (`acompressor` seuil −20 dB, ratio 8, détection de crête, relâchement 300 ms). Le rapport d'enveloppe reste celui de la parole (0,008 contre 0,007). Cette compression-là ne se voit pas. La baisse tenue × 0,2, elle, se voit à la chute (14,4 dB), pas à ce rapport.
- **Distance à un profil moyen de parole.** Les deux familles de synthèse sont trop différentes entre elles : les distances se chevauchent. Pas un juge.
- **Deux paroles différentes** (pas une copie décalée). L'écho reste à 12, sous le seuil 18. On ne les détecte pas.
- **Série harmonique fixe, sans syllabes, plus une copie à 30 ms.** Score 7. Le pic se confond avec la fondamentale. La parole à syllabes, elle, passe à 28.

L'écrêtage fort se voit déjà avec l'ancien compteur : 32,6 % des échantillons au plafond (seuil sûr 10 %), facteur de crête 4,2 dB contre 14 dB. Rien de nouveau à embarquer pour ça.

## Ce qui est dans l'application

Trois indicateurs, dans `AudioQuality.kt`, appelés par la sonde qui **copie** le PCM. Aucun échantillon n'est modifié. La sonde reste coupée par défaut (`zuno.audio.diag.probe`). Coupée, ces calculs ne tournent pas. Pas de nouvel interrupteur : allumer Spectre allume déjà la copie. On n'a pas changé le son par défaut.

La fiche, quand Spectre est allumé et qu'une seconde est passée, gagne une ligne « Forme », une ligne « Écho », et au bout de 4 secondes une ligne « Chute ». Un profil téléphone, un écho ou une chute au-dessus du seuil est une info, **pas une cause sûre** : la conclusion reste « on ne change pas le chemin par défaut ».

## HYPOTHÈSES

Rien de ceci n'a été mesuré sur une chaîne réelle. Les pourcentages disent à quel point l'hypothèse colle avec ce qu'on sait déjà, pas une certitude.

1. **Le PCM décodé a déjà la forme téléphone** (grave/milieu < 0,10 et aigu/milieu < 0,015), et c'est pour ça que « > 4 kHz » restait à 1–3 % sans rien dire. Confiance **40 %**. Ça colle avec le symptôme « vieille radio / comme un appel », et avec le fait que 1 % au-dessus de 4 kHz est exactement le chiffre d'une parole propre **et** d'une parole filtrée téléphone. Ça colle moins avec « une autre application sonne bien sur la même chaîne » : si le flux est bon, le PCM de Zuno ne devrait être téléphone que si Zuno filtre. Les quatre sondes diront si c'est déjà vrai à la sortie du décodeur.

2. **Le PCM est une parole normale** (grave/milieu au-dessus de 0,14, comme 1,7 à 3,5 sur les témoins) et le mauvais son est **après** la sonde : AudioTrack, Android, haut-parleur ou TV. Confiance **45 %**. Les fiches déjà lues (0,9 % à 3,6 % au-dessus de 4 kHz) sont le chiffre de la parole propre du banc (1,1 % et 2,0 %), pas d'un passe-bas de bruit. L'autre application joue la même source. Si le grave est là dans Zuno, le décodeur n'a pas fait un téléphone.

3. **Deux fois le même son, décalé de 20 à 40 ms** (« guerre entre deux sons »). Confiance **20 %**. L'écho le verrait (score ≥ 18). Deux programmes différents, non (score 12). Les essais précédents ont déjà écarté un simple chevauchement de lecteurs ; ça ne prouve pas qu'il n'y a pas une copie dans le PCM.

4. **Une baisse tenue dans le PCM** (« musique pendant un appel »), alors que le volume du lecteur reste 1,0. Confiance **15 %**. La chute ≥ 8 dB le dirait. Une pause entre deux phrases ne le dit pas (mesuré 0,6 dB avec 2 s de silence). Le volume lecteur à 1,0 n'empêche pas le PCM, lui, d'être bas.

## À VÉRIFIER SUR L'APPAREIL

APK de **cette** branche. Pas la release `zuno-tv`, pas une publication.

1. Réglages → Diagnostic du son. Spectre **éteint** au départ. Ouvrir une chaîne : le son doit être celui d'avant. La fiche ne doit pas avoir de ligne « Forme ».
2. Allumer **Spectre : mesuré**. Rouvrir une chaîne qui sonne mal (France 24, France 2, France Info ou BEIN) et une qui sonne bien. Attendre huit secondes.
3. Lire, sur chaque fiche, les quatre sondes et la ligne « Forme » :
   - grave/milieu **< 0,10** et aigu/milieu **< 0,015**, aux quatre sondes → le PCM du décodeur a déjà la forme téléphone. Noter le décodeur (FFmpeg ou box). Ne pas changer le réglage tout de suite : la ligne le dit, elle ne répare pas.
   - grave/milieu **> 0,14** → ce n'est pas un téléphone dans le PCM. Le mauvais son, s'il est toujours là, est après la sonde (sortie, TV, haut-parleur).
   - grave bas mais aigu **> 0,015** → passe-haut (« maigre »), pas un téléphone.
   - grave haut et aigu bas → parole sourde ou passe-bas seul. L'ancien « > 4 kHz bas » disait la même chose, à tort, d'un téléphone.
   - écho **≥ 18** → une copie décalée est dans le PCM. Regarder en même temps « lectures vivantes ».
   - chute **≥ 8 dB** alors que la ligne de volume reste 1,0 → la baisse est dans le PCM, pas dans le focus.
4. Bouton **Jouer le son témoin**, Spectre allumé. S'il est « large » et que la chaîne est « téléphone », l'appareil ne filtre pas tout : c'est le PCM de la chaîne. S'il est « téléphone » lui aussi, le chemin commun (après le décodeur, ou le décodeur sur tout) est en cause.
5. La fiche ne doit contenir ni `http` ni mot de passe.

7 Motion (lecteur mpv) n'a pas cette sonde. Le banc sait lire un WAV ou un PCM s16le (`python3 android-app/tools/audio_lab/mesure.py fichier.wav`), si un jour on en capture un. Cette branche n'ajoute pas d'enregistrement.

Entre 0,08 et 0,14 de grave/milieu, on est dans le trou le plus étroit du banc (0,076 contre 0,144). Lire le chiffre brut, pas seulement le mot « téléphone » ou « large ».
