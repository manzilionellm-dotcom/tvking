# Flux source — le son est-il déjà mauvais dans les octets ?

Angle : la chaîne qu'on reçoit (profil AAC réel, SBR, débit, ADTS ou LATM, fréquence, sauts d'horloge).
Branche : `claude/son-04-source`, à partir de `claude/zuno-mesures-audio` (commit `474969c2`).

On n'a pas les adresses des chaînes du client. On n'en a demandé aucune. Tout ce qui suit vient de fichiers générés ici (ffmpeg 6.1.1, fdkaac 1.0.0) et de petits fichiers de test publics déjà étiquetés HE-AAC. Aucun de ces fichiers n'est dans le dépôt.

Le son par défaut de l'app n'est pas modifié. La fiche lit des octets que le lecteur avait déjà, et elle compte les sauts d'horloge. Rien n'est réécrit, aucun filtre n'est ajouté, aucun interrupteur nouveau : il n'y a pas de nouveau comportement à couper.

On n'a pas entendu les chaînes. On n'a pas « réparé » le son.

## Ce que la fiche terrain disait déjà

AAC-LC, 48 kHz, stéréo, à l'entrée et à la sortie, décodeur FFmpeg et décodeur de la box pareils, énergie au-dessus de 4 kHz entre 0,9 % et 3,6 %. Quatre sondes identiques. Une autre app, sur les mêmes chaînes, sonne bien. 7 Motion (mpv) a le même défaut.

## PROUVÉ

Machine : ffmpeg 6.1.1, décodeurs `aac` et `aac_fixed` (les deux font le SBR : les chiffres ci-dessous sont identiques pour les deux, au dix-millième près). Le passe-haut est le même que la sonde de l'app (Butterworth ordre 2, 4 kHz). Le bruit blanc de contrôle donne **0,8195**, comme la sonde (0,819).

`logic-test` : `gradle test` dans `android-app/packages/native_video_player/logic-test` — **146 tests, 0 échec** (les 13 nouveaux lisent les octets ci-dessous).

### 1. Le pourcentage au-dessus de 4 kHz ne sépare pas une parole d'un flux écrasé

Voix synthétique (harmoniques jusqu'à 8 kHz), avant tout encodage :

| Signal | > 4 kHz | 95 % de l'énergie sous |
| --- | --- | --- |
| Voix, PCM | **0,86 %** | 1 400 Hz |
| La même, passe-bas 300–3 400 Hz (téléphone) | **0,59 %** | 1 400 Hz |
| La même, passe-bas 7 kHz | **0,73 %** | 1 400 Hz |
| Voix encodée AAC-LC 128, 64, 48, 32 ou 24 kb/s puis décodée | **0,44 % à 0,90 %** | 1 400 Hz |

La voix n'a presque rien au-dessus de 4 kHz. Le codeur ne peut pas « enlever » des aigus qui ne sont pas là. **0,9 % à 3,6 % sur une chaîne parlée est le chiffre d'une parole, même avec un AAC large.** Le téléphone (coupé à 3,4 kHz) donne le même ordre de grandeur. La sonde à 4 kHz ne peut pas dire « c'est la parole » ou « c'est un bug ».

Dès qu'on mélange la voix avec du bruit (il y a vraiment des aigus : 95 % de l'énergie jusqu'à 20 kHz, > 4 kHz = **26,9 %**), le débit se voit :

| AAC-LC 48 kHz, les deux décodeurs | > 4 kHz | 95 % de l'énergie sous | Classe de la sonde |
| --- | --- | --- | --- |
| 128 kb/s | 17,0 % | 13 410 Hz | milieu |
| 64 kb/s | **8,5 %** | 6 166 Hz | basse (≤ 12 %) |
| 32 kb/s | **1,1 %** | 2 200 Hz | basse, bande du téléphone |
| 24 kb/s | **0,8 %** | 1 932 Hz | basse |

Commande du mélange, puis de l'encodage (rien n'est une adresse de chaîne) :

```text
ffmpeg -i voix.wav -i noise48.wav -filter_complex \
  "[0:a][1:a]amix=inputs=2:normalize=0:duration=first,volume=0.7" mix.wav
ffmpeg -i mix.wav -c:a aac -b:a 32k -f adts mix_32000.aac
```

Bruit blanc seul, même codeur, même lecture :

| Débit | > 4 kHz | > 12 kHz | 95 % sous |
| --- | --- | --- | --- |
| 130 kb/s | 71,7 % | 30,4 % | 16 279 Hz |
| 66 kb/s | 50,1 % | 6,8 % | 10 937 Hz |
| 50 kb/s | 32,0 % | 1,1 % | 7 057 Hz |
| 34 kb/s | **10,5 %** | 0,1 % | **3 538 Hz** |
| 26 kb/s | **5,9 %** | 0,0 % | **2 927 Hz** |

À 34 kb/s et en dessous, un son qui avait des aigus sort « vieille radio », étiqueté AAC-LC 48 kHz stéréo. Les deux décodeurs donnent les mêmes chiffres. Une autre app qui reçoit **les mêmes octets** entend la même chose.

### 2. Un HE-AAC bien décodé peut quand même être « bas » à 4 kHz

Fichier de test public, HE-AAC explicite, 44,1 kHz, stéréo, environ 64 kb/s. Décodé par `aac` et par `aac_fixed` :

- sortie **44 100 Hz, stéréo** (le SBR a remonté la fréquence) ;
- énergie > 4 kHz = **6,32 %** (la sonde dirait « basse ») ;
- énergie au-dessus de 11 kHz = **0,44 %**.

`aac_fixed` journalise deux saturations internes du filtre SBR (`sbr_qmf_analysis: value … too large`) mais le pourcentage reste **6,32 %**, identique à `aac`.

Donc : **un HE-AAC dont le SBR a marché peut afficher moins de 12 % au-dessus de 4 kHz.** Ce chiffre seul n'accuse pas le décodeur.

### 3. HE-AAC implicite : l'en-tête dit LC, souvent 22 kHz, souvent mono

Quatre fichiers de test du même paquet, même contenu, signalisation différente. Les deux décodeurs ffmpeg sortent **exactement** les mêmes chiffres (44 100 Hz, stéréo, > 4 kHz = 15,57 %). Le contenu de ce paquet est très grave (95 % de l'énergie sous 466 Hz) : il ne sert pas à mesurer les aigus, il sert à voir ce que l'en-tête dit.

| Octets | Ce que dit l'en-tête | Ce que ffmpeg 6.1 en sort |
| --- | --- | --- |
| `13 88` (2 octets) | AAC-LC, **22 050 Hz, mono**. Pas de SBR écrit. | 44 100 Hz, **stéréo**. SBR et stéréo paramétrique trouvés dans les trames. |
| `13 88 56 e5 a0` | LC, puis extension `0x2b7` : SBR présent, extension **44 100 Hz** | pareil |
| `eb 8a 08 00` | type **29** (HE-AAC v2) dès le premier champ, cœur 22 050 Hz, extension 44 100 Hz | pareil |
| en-tête ADTS `fff95c4011420c` | profil **LC** (2 bits), **22 050 Hz, mono**, trame 138 octets → **23 kb/s** | 44 100 Hz, stéréo (le fichier `.aacp` ; quelques trames sont invalides, le son qui sort est quand même à 44,1 kHz stéréo) |

L'ADTS ne peut pas écrire « HE-AAC » : son profil tient sur 2 bits (Main, LC, SSR, LTP). Media3, pour le nom `mp4a.40.2`, ne lit pas l'extension `0x2b7`. Il peut donc afficher **AAC-LC** alors que les octets d'après disent le SBR.

Dans le code de FFmpeg 6.1 (`mpeg4audio.c`, `aacdec_template.c`), le drapeau SBR vaut −1 (« on ne sait pas ») tant que l'extension ne le met pas à 0. Dans ce cas, **même au-dessus de 24 kHz**, ffmpeg applique le SBR s'il le trouve dans les premières trames. Il ne l'ignore que si l'extension dit « SBR absent » (`sbr == 0`), avec le journal `SBR signaled to be not-present but was found in the bitstream`.

Essai : les mêmes octets `13 88`, plus l'extension qui met le bit SBR à 0 (`13 88 56 e5 00`). ffprobe dit alors `profile=LC`, `sample_rate=22050`, `channels=1`. Le décodage ne donne **pas** un son sourd mais valide : le fichier wav fait 172 octets (vide) et ffmpeg écrit :

```text
channel element 2.4 is not allocated
Number of bands (24) exceeds limit (20)
Decode error rate 1 exceeds maximum 0.666667
Output file is empty
```

Forcer « LC seul » sur ce HE-AAC v2 casse la lecture. Ça ne fabrique pas le son « radio » qu'on entend quand même.

**Conséquence pour la fiche terrain.** Un HE-AAC implicite classique s'annonce à **22 ou 24 kHz** (souvent mono) à l'entrée, et à 44,1 ou 48 kHz en sortie si le décodeur a fait le SBR. La fiche déjà lue dit **48 kHz à l'entrée et 48 kHz à la sortie**. Ce n'est pas cette signature. L'entrée, c'est le format *avant* décodage (`onAudioInputFormatChanged`), pas la fréquence après SBR.

### 4. LATM et ADTS ne se jouent pas avec le même décodeur

`fdkaac -p 2 -b 64000 -f 10` écrit un LOAS (les octets commencent par `56 e0`).

- `ffmpeg -c:a aac` : erreur `Invalid data`, pas de son.
- `ffmpeg -c:a aac_latm` : son valide, > 4 kHz = **56,64 %**, comme le même LC en ADTS (**56,63 %**).

Un LATM laissé tel quel au décodeur AAC ne donne pas un son sourd : il ne donne pas de son. Media3 retire le LATM avant FFmpeg et avant le décodeur de la box. Le type MIME `audio/mp4a-latm` est le nom que Media3 donne **aussi à l'ADTS**. Le mot « latm » dans ce nom ne prouve pas le transport.

Le paquet Ubuntu de libfdk-aac (2.0.2) refuse le HE-AAC : `fdkaac -p 5` → `ERROR: unsupported profile`. On n'a pas pu fabriquer nous-mêmes un HE-AAC. Les fichiers HE viennent des tests publics décrits plus haut.

### 5. Une copie décalée (« deux sons ») ne change pas le pourcentage à 4 kHz

Bruit blanc, et le même bruit mélangé avec une copie retardée de 4 ms :

| | > 4 kHz | corrélation à 4 ms |
| --- | --- | --- |
| Bruit | 0,8195 | **0,005** |
| Bruit + copie à 4 ms | **0,8190** | **0,505** |

La sonde à 4 kHz ne voit rien. La corrélation gauche/droite non plus, si les deux voies sont retardées ensemble : elles restent d'accord entre elles. Le creux « dans un trou » d'un son doublé est un autre chiffre, qu'on n'a pas mis sur le fil audio (ça coûterait du calcul à chaque échantillon). On le laisse comme essai sur l'appareil, pas comme un filtre.

### 6. Un saut d'horloge se mesure

Deux bouts MPEG-TS collés, le second décalé de 8 s (`-output_ts_offset 8`). `ffprobe` sur les paquets audio :

```text
écarts autour de la jointure : 21,3 ms, 21,3 ms, 21,3 ms, 5973,3 ms, 21,3 ms
sauts au-dessus de 80 ms : 5973,3
```

21,3 ms est la durée normale d'une trame AAC à 48 kHz (1024 / 48000). Le saut de **5 973 ms** est l'horloge qui saute. La fiche le comptera si Media3 envoie une discontinuité de raison « interne » (pas un zap, pas une recherche). Au-dessus d'environ 200 ms, Media3 vide déjà le tampon. On ne recale pas l'horloge, et on ne change pas la vitesse (elle reste 1,0).

Jouer du 24 kHz comme si c'était du 48 kHz (`asetrate`) double la hauteur : la voix passe de « 95 % sous 1 400 Hz » à « 95 % sous 2 800 Hz », et > 4 kHz monte de 0,86 % à 3,2 %. C'est un son plus aigu, pas un son de téléphone.

### 7. Transcodage en cascade

Le HE-AAC de test (64 kb/s, SBR fait, > 4 kHz = 6,4 % sur la première seconde, 95 % sous 9,0 kHz), puis :

| Étape | > 4 kHz | 95 % sous |
| --- | --- | --- |
| HE décodé | 6,4 % | 9,0 kHz |
| ré-encodé AAC-LC 64 kb/s, 48 kHz | 5,3 % | 6,4 kHz |
| coupé à 8 kHz, puis AAC-LC 48 kb/s | **3,5 %** | **4,5 kHz** |

Un maillon qui jette le SBR (ou coupe à 8 kHz) puis ré-encode en « AAC-LC 48 kHz » laisse un fichier que **tous** les décodeurs rendront sourd. L'étiquette reste AAC-LC 48 kHz stéréo. C'est compatible avec « FFmpeg, la box et mpv sonnent pareil ».

## HYPOTHÈSE

Confiance que **ça** explique le son entendu sur les chaînes parlées, pas confiance dans les mesures du dessus (celles-là sont faites).

| Idée | Confiance | Pourquoi ce niveau |
| --- | --- | --- |
| Le 0,9–3,6 % est la parole, et la sonde ne peut pas dire si le son est « radio » | **40 %** | La voix synthétique est à 0,4–0,9 % sans aucun filtre. Un HE-AAC correct est à 6 %. Le téléphone est à 0,6 %. Trois causes, un seul chiffre. |
| Le flux est déjà un AAC-LC 48 kHz trop bas, ou un transcodage qui a jeté les aigus | **35 %** | Ça explique que FFmpeg, la box et mpv soient d'accord, et qu'une autre app sonne mieux **si elle ne reçoit pas les mêmes octets**. La fiche terrain ne montrait pas le débit (souvent 0 en .ts). |
| Deux copies dans la piste, ou un saut d'horloge (« guerre entre deux sons ») | **30 %** | Une copie à 4 ms ne bouge pas le pourcentage à 4 kHz (prouvé) et ne se voit pas gauche/droite si les deux voies bougent ensemble. Pas mesuré sur les chaînes. |
| HE-AAC implicite que le décodeur n'a pas reconstruit | **15 %** | La signature, c'est une **entrée ≤ 24 kHz** (souvent mono) et une sortie qui ne double pas. La fiche dit 48 kHz des deux côtés. FFmpeg 6.1 cherche encore le SBR quand le drapeau vaut −1. |
| HE-AAC écrit comme du LC à 48 kHz (SBR « downsampled » ou en-tête réécrit) | **20 %** | Possible en théorie. On n'a pas pu l'encoder (fdkaac refuse le profil 5). Forcer « SBR absent » sur un vrai HE-AAC v2 a vidé le fichier, ça n'a pas fait un son sourd. |
| LATM passé au mauvais décodeur | **10 %** | Ça coupe le son (erreur), ça ne le rend pas sourd. Le son des chaînes sort. |
| Fréquence lue à la mauvaise vitesse (24 kHz joué en 48, ou 44,1 pris pour 48) | **10 %** | Ça change la hauteur. Le symptôme décrit n'est pas une voix accélérée. |

Rien de tout cela n'est « la cause ». L'expérience sur l'appareil, plus bas, départage les trois premières.

## Ce que la fiche ajoute

Lecture seule, dans `AacSource` (testé) et branché dans `onAudioInputFormatChanged`. Une ligne **Signalisation** :

- profil lu dans les octets (pas seulement `mp4a.40.2`) : LC, HE-AAC, HE-AAC v2 ;
- fréquence du cœur et fréquence d'extension ;
- SBR explicite, SBR « à chercher » (LC et ≤ 24 kHz), ou SBR non demandé (> 24 kHz) ;
- transport : ADTS, ASC, ou LOAS (`56 E0`) ;
- débit annoncé, débit moyen, débit de crête, et débit **mesuré** quand l'en-tête ADTS est encore là (taille de trame × 8 × fréquence / 1024) ;
- si le format du lecteur et les octets ne disent pas la même fréquence ou le même nombre de voies, la ligne le dit.

En plus, sans toucher au son :

- **Pistes audio annoncées** dès qu'il y en a deux (une seule est jouée) ;
- **Horloge du direct** : nombre de sauts internes et le plus grand, en millisecondes. Un zap ne compte pas.

Si l'en-tête est mono **et** que c'est un candidat SBR / HE-AAC, la fiche ne dit plus « mono d'origine » comme une certitude. Si la sortie est stéréo, elle dit que la stéréo paramétrique a été reconstruite.

Le débit mesuré n'est là que si les octets ADTS arrivent encore jusqu'à la fiche. En direct, Media3 les retire avant le décodeur : la ligne dira alors « débit mesuré : pas disponible ». C'est honnête. Le débit annoncé reste celui du format, souvent inconnu en `.ts`.

## À VÉRIFIER SUR L'APPAREIL

APK de **cette** branche. Pas la release `zuno-tv`. Tous les interrupteurs du Diagnostic du son restent **coupés**. Ouvrir une chaîne qui sonne mal, attendre dix secondes, ouvrir Diagnostic du son. Recommencer avec une chaîne qui sonne bien. Comparer les deux fiches. Ne pas copier d'adresse dans un message.

Lire, pour chacune :

1. La ligne **Entrée** (fréquence, voies) et la ligne **Sortie**.
2. La ligne **Signalisation** : type d'objet, SBR explicite ou non, transport, débit annoncé, débit mesuré.
3. **Pistes audio** : 1 ou plus.
4. **Horloge du direct** : absente, ou des sauts.
5. Le pourcentage > 4 kHz, seulement comme rappel : il ne tranche pas.

| Ce que la fiche montre | Lecture |
| --- | --- |
| Entrée **et** sortie à 48 kHz, AAC-LC, « SBR non demandé », débit annoncé ou mesuré **sous 48 kb/s** | Le codeur a déjà coupé. FFmpeg, la box et mpv feront le même son. L'autre app entend mieux seulement si elle reçoit un autre flux. On ne change pas le décodeur. |
| Pareil, mais débit **inconnu** | On ne peut pas encore séparer la parole d'un débit bas. Il manque la taille des trames ADTS. Ne pas conclure. |
| Entrée **≤ 24 kHz** (souvent mono), sortie **48 kHz** et 2 voies, « SBR implicite à chercher » | Le décodeur a reconstruit. Le défaut n'est pas un SBR oublié. |
| Entrée ≤ 24 kHz **et** sortie ≤ 24 kHz | Le SBR n'a pas été fait, ou il n'y en avait pas. C'est le cas déjà prévu (`decodeur_sans_sbr` si c'est la box). |
| « SBR explicite : oui », sortie égale à la fréquence d'extension | Le SBR est écrit et la fréquence a suivi. Un pourcentage bas ne le contredit pas. |
| Horloge : un saut de plus de 200 ms au moment où « deux sons » se battent | L'horloge du flux saute. Ce n'est pas un filtre. Noter l'heure du saut et si ça colle au symptôme. |
| Deux pistes audio, et la piste jouée n'est pas celle qu'on croit | Choisir l'autre piste à la main. Ne pas les mixer. |
| Les deux chaînes (bonne et mauvaise) ont la **même** signalisation et le même débit | Le flux source ne les sépare pas. La cause est ailleurs (après l'AudioTrack, ou un traitement que la sonde ne voit pas). |

Essai en plus, si la chaîne mauvaise a un jingle ou un applaudissement (pas seulement une voix) : le pourcentage > 4 kHz **pendant ce passage** (ligne « Dernière seconde », sonde allumée — elle copie, elle ne filtre pas). Un jingle qui reste sous 12 % alors que la chaîne « bonne » passe au-dessus de 40 % sur un passage comparable, c'est le flux qui n'a pas les aigus. Un jingle qui passe au-dessus de 40 % sur la chaîne « mauvaise », le flux a les aigus : le son « radio » n'est pas une coupure au-dessus de 4 kHz.

On n'allume pas « Box AAC » ni « FFmpeg : réessayer » pour cet essai. Le décodeur a déjà été écarté.

## Ce qui n'est pas prouvé

- Le débit réel des chaînes de Lionel. La fiche le dira seulement si le conteneur ou l'en-tête ADTS le porte encore.
- Qu'un HE-AAC « downsampled » à 48 kHz existe sur ces chaînes. L'encodeur de cette machine ne sait pas le fabriquer.
- Qu'un saut d'horloge arrive sur ces directs. Le compteur est prêt, il n'a pas tourné sur une box.
- Le creux d'une copie décalée de quelques millisecondes. La fiche ne le mesure pas, pour ne pas charger le fil audio.
