# Phase et canaux — le son « dans un trou »

Angle : est-ce que la voix disparaît à cause des voies (phase, ordre, downmix), sans qu'un passe-bas n'existe.

On n'a pas entendu les chaînes. On a mesuré des signaux fabriqués, et on a lu le chemin du lecteur. Le son par défaut n'est pas modifié. Aucun interrupteur nouveau : la fiche, quand la sonde est déjà allumée, écrit en plus le niveau `(G−D)/(G+D)`. Sonde coupée, rien ne change.

Branche de départ : `claude/zuno-mesures-audio`, commit `474969c2`.

## Ce que le lecteur fait vraiment aux voies

Lu dans Media3 1.5.1 et dans Zuno. Pas rejoué sur une box.

1. Le décodeur FFmpeg (`ffmpeg_jni.cc`) passe du flottant planaire au 16 bits entrelacé. Il garde la même fréquence et le même nombre de voies. Il n'inverse pas une voie.
2. `FfmpegAudioRenderer` ne donne pas de masque de canaux. `ChannelMappingAudioProcessor` reste alors inactif.
3. Le décodeur de la box ne pose un masque que pour un vieux Samsung (S6/S7, `OMX.SEC.aac.dec`, Android avant la version 7) ou pour Vorbis/Opus. Pas pour `c2.android.aac.decoder` sur un téléphone Android 16. Ce masque, quand il existe, **garde les premières voies et jette le reste**. Il ne mélange pas. Le centre d'un 5.1 (3e voie) n'est pas dans les deux premières.
4. Zuno n'ajoute pas de mélangeur. L'AudioTrack reçoit le nombre de voies du décodeur.
5. La sonde de phase lit la voie 1 et la voie 2. Le centre n'entre pas dans la corrélation.

Pour un AAC-LC annoncé 2 voies et décodé 2 voies (les fiches France 24), le chemin Zuno est une copie.

7 Motion (mpv) ne pose pas non plus de filtre de canaux dans `video_player_screen.dart`. Un flux stéréo en sort stéréo. Les deux lecteurs ont donc le même geste sur un AAC 2 voies : ils laissent le PCM du décodeur.

## PROUVÉ

Machine de test, 3 octobre 2026. FFmpeg 6.1.1 (le `.so` Jellyfin de la box est FFmpeg 6.0, lavc 60.3 : même famille, pas le même fichier). Signaux synthétiques. Aucun flux.

### Le chemin stéréo est une copie, et quels cas creusent la voix

Commande :

```text
gradle -p android-app/packages/native_video_player/logic-test test --rerun-tasks
```

Exécutée avec Gradle 8.11.1. **147 tests, 0 échec, 0 ignoré.**

Sortie du banc `ChannelPathTest` (voix synthétique, 48 kHz, 1 s) :

| Cas | Corrélation G/D | Niveau (G−D)/(G+D) | Voix gardée dans la somme | Creux 300 Hz – 3 kHz | Classe |
| --- | --- | --- | --- | --- | --- |
| Stéréo en phase, copie Zuno | +1,0000 | 0,0000 | 1,0000 | 0,0000 | pas un trou |
| Voies inversées (G = −D) | −1,0000 | infini | 0,0000 | 1,0000 | **trou de phase** |
| Droite en retard de 2 ms | −0,1664 | 1,1829 | 0,5682 | 0,1556 | **trou creux** |
| Droite en retard d'une trame AAC (1 024 échantillons, 21 ms) | −0,0595 | 1,0614 | 0,2907 | 0,1778 | **trou creux** |
| Retard d'un seul échantillon | +0,9968 | 0,0401 | 0,9970 | 0,0000 | pas un trou |
| Mono copié sur les deux voies | +1,0000 | 0,0000 | 1,0000 | 0,0000 | pas un trou |
| Mono seulement à gauche | illisible | 1,0000 | 0,2500 | 0,0000 | pas un trou (juste moins fort) |
| Deux voix différentes, une par voie | +0,0012 | 0,9988 | 0,5567 | 0,0000 | **deux programmes** |
| Milieu et écart joués comme gauche et droite | +0,0148 | 0,9853 | 0,4506 | 0,4138 | **trou creux** |
| Le même creux déjà copié sur les deux voies | +1,0000 | 0,0000 | 1,0000 | 0,0000 | la corrélation ne voit rien |
| 5.1, on ne garde que L et R | +1,0000 | 0,0000 | — | 0,0000 | la corrélation ne voit rien |
| Planaire lu comme de l'entrelacé | +0,9968 | 0,0401 | 0,9985 | 0,0000 | pas un trou |

Le cas « creux déjà copié » garde 0,568 de la voix **par rapport à l'original**, mais les deux voies sont identiques : la sonde G/D dit « tout va bien ».

5.1 dont la voix est seulement au centre, ordre FFmpeg (L, R, C, caisson, surrounds) :

- Garder les deux premières voies : énergie de voix 1,937×10⁹.
- Downmix qui garde le centre (formule ITU, témoin, **pas** le chemin Zuno) : 3,311×10¹⁰.
- Rapport : **0,058**. Le centre est perdu. La corrélation G/D, elle, vaut +1, parce que L et R étaient le même aigu, sans la voix.

Centre et caisson échangés, puis downmix qui jette le caisson : voix restante 9,89×10⁸ contre 1,66×10¹⁰ si l'ordre est le bon. Rapport **0,060**. La voix part avec le caisson.

Ordre des éléments AAC 5.1 (C, L, R, Ls, Rs, caisson) lu comme l'ordre FFmpeg : la voix se retrouve sur la première voie, plus sur le centre. Mesuré : l'énergie de voix de la voie 0 du tampon faux est égale à celle du centre du tampon juste (3,119×10¹⁰).

### L'AAC-LC ne fabrique pas le trou, et ne l'enlève pas

Commande :

```text
python3 android-app/tools/son/phase_canaux.py
```

Code de sortie 0. Encodeur AAC natif de FFmpeg, profil LC, 48 kHz, 128 kb/s. Joint stéréo = réglage d'usine (`aac_ms` auto, intensity allumé).

| Cas | Corrélation après décodage | Niveau | Creux | Voix gardée |
| --- | --- | --- | --- | --- |
| En phase, joint stéréo | +1,0000 | 0,0004 | 0,0000 | 1,0000 |
| Hors phase, joint stéréo | −1,0000 | 2751 | 1,0000 | 0,0000 |
| Hors phase, M/S forcé | −1,0000 | 1917 | 1,0000 | 0,0000 |
| Hors phase, voies indépendantes | −0,9993 | 53,37 | 1,0000 | 0,0000 |
| Retard 2 ms, joint stéréo | −0,1640 | 1,1800 | 0,0870 | 0,5700 |
| Deux voix, joint stéréo | +0,0014 | 0,9986 | 0,0533 | 0,5425 |
| Milieu/écart comme G/D, sans joint | +0,0256 | 0,9747 | 0,1541 | 0,4706 |

Un signal en phase reste en phase. Un signal hors phase reste hors phase : le joint stéréo ne répare pas le trou, et il ne le crée pas à partir d'un signal sain. Le retard de 2 ms survit (la somme ne garde que 0,57 de la voix de la gauche).

### Un 5.1 dont on ne garde que L et R perd la voix

Même script. AAC-LC 5.1, 320 kb/s, voix seulement au centre. Décodeur : 6 voies. Énergie de voix du centre 3,183×10¹⁴, des voies L+R 1,379×10⁷.

- Stéréo « deux premières voies » (`pan=stereo|c0=c0|c1=c1`) : voix 1,379×10⁷.
- Stéréo du downmix FFmpeg (`-ac 2`, il garde le centre) : voix 5,461×10¹³.
- Rapport : **0,0000** (moins de 0,0001).

C'est le geste du masque Media3 « on jette, on ne mélange pas ». Zuno ne le fait pas sur le chemin FFmpeg. Un lecteur qui ne garde que L et R d'un 5.1 « voix au centre » sort un stéréo sans la voix.

### Un 5.1 mal déclaré en stéréo ne sort pas un son creux : FFmpeg refuse

48 en-têtes ADTS réécrits, `channel_configuration` passé de 6 à 2. ffprobe annonce alors `channels=2` et `sample_rate=0`. Le décodeur répond `channel element 1.0 is not allocated` et n'écrit aucun échantillon. L'inverse (stéréo déclarée 5.1) donne la même erreur. Sur ce FFmpeg, un mauvais nombre de voies dans l'en-tête ADTS fait un échec, pas un trou.

### Le passage planaire → entrelacé n'insère pas de trou entre les trames

`ffmpeg_jni.cc` avance le tampon du nombre d'octets prévu, et il passe ce nombre d'octets à `swr_convert` qui attend un nombre d'échantillons. On a rejoué exactement la conversion du décodeur (flottant planaire → 16 bits entrelacé, 48 kHz, stéréo, même disposition) avec libswresample 6.1.1.

Commande :

```text
gcc -O2 -o /tmp/swr_gap android-app/tools/son/swr_gap.c -lswresample -lavutil
/tmp/swr_gap
```

Sortie, pour chaque trame de 1 024 échantillons (une trame AAC) :

```text
borne 1024  obtenus 1024  octets_jni 4096  octets_reels 4096  ech_en_trop 0  restants 0
```

Huit trames : **0 échantillon en trop**. Pour cette conversion, l'avance tombe juste. Ce n'est pas un peigne ajouté par le décodeur.

## Quels cas reproduisent « dans un trou »

| Ce qu'on entendrait | Cas qui le fabrique | La corrélation G/D le voit ? |
| --- | --- | --- |
| La voix disparaît, il reste un souffle, « dans un trou », surtout au haut-parleur du téléphone ou si la TV additionne | G = −D. La somme est vide. L'AAC-LC garde ça tel quel. | Oui. Corrélation ≤ −0,70, niveau très grand. |
| Son creux, un peu « deux sons qui se battent », sans inversion totale | Un retard de 2 ms à 21 ms entre les voies. Ou le milieu et l'écart joués comme gauche et droite. | Oui, en partie. Corrélation proche de 0, niveau autour de 1, creux > 0,12 sur le PCM brut. |
| Deux langues ou deux commentaires en même temps | Une voix différente sur chaque voie. La somme les garde toutes les deux : ce n'est pas un trou, c'est une bagarre. | Oui. Corrélation ≈ 0, creux ≈ 0. |
| La voix manque, la musique d'ambiance reste, et les deux voies ont l'air d'accord | 5.1, voix au centre, on n'a gardé que L et R. Ou centre échangé avec le caisson puis caisson jeté. | **Non.** Corrélation +1 sur L/R. Il faut comparer l'énergie de voix au downmix qui garde le centre. |
| Son déjà creux, pareil des deux côtés | Le peigne est déjà dans le signal, copié à l'identique. | **Non.** Corrélation +1. |
| Mono copié, mono d'un seul côté, mauvais assemblage planaire, joint stéréo d'un signal sain | — | Non. Ça ne fait pas le trou. |

## HYPOTHÈSE

| Idée | Confiance | Pourquoi |
| --- | --- | --- |
| Sur les fiches à 2 voies en entrée et 2 voies en sortie, Zuno n'inverse pas, ne jette pas un centre, et ne crée pas le trou tout seul. Le PCM du décodeur est recopié. | 90 % | Le code Media3 1.5.1 et le test d'identité. Reste 10 % : un comportement du `.so` ARM ou de l'AudioTrack qu'on n'a pas exécuté. |
| Si la fiche montre une corrélation ≤ −0,70, le trou vient de voies opposées **déjà dans le PCM**. Le haut-parleur qui additionne (téléphone, certaines TV) efface la voix. Une autre app qui ne joue qu'une voie, ou une autre piste, sonnerait bien. | 80 % que ce mécanisme fait ce symptôme. **Pas** 80 % que ce soit le cas de France 24 : la fiche ne l'a pas encore mesuré. | Le banc : garde-voix 0, creux 100 %, et l'AAC ne répare pas. |
| Si la corrélation est autour de 0 et le niveau autour de 1, soit deux programmes se battent, soit un retard creuse la voix. | 70 % | Les deux cas du banc se ressemblent après l'encodeur AAC (creux 0,09 contre 0,05). La fiche seule ne les sépare pas complètement. |
| Le joint stéréo AAC, le mono dupliqué, ou le planaire mal lu sont la cause. | 10 % | Le banc les innocente sur des signaux sains. |
| Un 5.1 mal étiqueté « stéréo » dans l'ADTS sort un son creux avec FFmpeg. | 10 % | FFmpeg refuse le fichier. Il ne sort pas de PCM creux. Le décodeur de la box peut faire autrement : non mesuré ici. |
| La voix au centre jetée explique les fiches France 24 (2 voies → 2 voies). | 15 % | Ce geste existe dans Media3, mais pas sur ce chemin, et la fiche dit déjà 2 et 2. Il expliquerait un flux vraiment 5.1 dont on ne garderait que L et R. |
| Le passage `swr_convert` ajoute un peigne entre les trames AAC. | 15 % | 0 échantillon en trop sur libswresample 6.1.1, conversion identité. Le `.so` 6.0 de la box n'a pas été chargé. |
| Le trou est déjà dans chaque voie (les deux pareilles, déjà creuses). Les deux lecteurs le rendent, une autre app fait autre chose (autre piste, autre traitement). | 35 % | Le banc montre que la corrélation ne le voit pas. Rien ne prouve que les chaînes de Lionel sont dans ce cas. |

## À VÉRIFIER SUR L'APPAREIL

Installer l'APK de **cette** branche. Pas la release `zuno-tv`, pas `phone-latest`. Ne rien publier.

La sonde reste le seul moyen de lire la phase. L'allumer ne change pas les échantillons : elle copie.

1. Réglages → Diagnostic du son → allumer **Spectre**. Laisser les autres interrupteurs coupés.
2. Jouer le **son témoin** (voix puis bruit, voies ensemble). Attendre deux secondes. Lire la ligne « Corrélation gauche/droite ».
3. Ouvrir France 24, France 2, France Info, BEIN, et une chaîne qui sonne bien. Pour chacune, attendre deux secondes et noter :
   - voies en entrée et en sortie ;
   - corrélation ;
   - niveau `(G−D)/(G+D)` ;
   - énergie `(G−D)²/(G+D)²`.
4. Refaire France 24 au casque, puis au haut-parleur.

Lecture, sans conclure à l'oreille seule :

| Témoin | Chaîne | Ce que ça voudrait dire |
| --- | --- | --- |
| corrélation > +0,90 et niveau < 0,20 | pareil | Les voies ne s'opposent pas. Le trou **n'est pas** une inversion gauche/droite. Chercher ailleurs (le creux est peut-être déjà dans le signal, les deux voies d'accord). |
| témoin > +0,90 | chaîne ≤ −0,70, niveau grand | Le PCM de la chaîne a les voies à l'envers. Zuno ne les a pas retournées : c'est le flux, ou le décodeur. Au haut-parleur la voix doit s'effacer, au casque elle doit sonner « à côté de la tête ». |
| témoin > +0,90 | chaîne entre −0,30 et +0,30, niveau autour de 1 | Deux sons, ou un retard entre les voies. Écouter si ce sont deux langues, ou une seule voix creuse. |
| témoin lui aussi ≤ −0,70 | — | L'appareil retourne une voie **après** la sonde (ou la sonde se trompe). Le flux n'est pas le coupable. |
| entrée 6 voies, sortie 2 | — | Là, le centre a pu être jeté. La corrélation G/D ne le dit pas. Ce n'est pas le cas des fiches déjà vues (2 et 2). |

Le son témoin sert de contrôle : on sait qu'il est en phase. S'il mesure en phase et la chaîne aussi, cette piste (phase entre les voies) est innocente pour cette chaîne.
