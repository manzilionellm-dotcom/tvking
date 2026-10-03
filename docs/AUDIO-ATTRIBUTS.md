# Le mot dit à Android : film, musique ou parole

Zuno dit au téléphone et à la box : « c'est un film ». Ce mot ne filtre pas les aigus dans l'application. Il peut servir au téléphone ou à la box pour choisir un traitement **après** notre lecteur (Dolby, son « cinéma », voix). On n'a pas les oreilles de Lionel : ce fichier sépare ce qui est lu dans le code, ce qui est lu dans les documents publics, et ce qu'il faut réécouter sur l'appareil.

L'interrupteur est **coupé**. Coupé, le son part comme avant.

## PROUVÉ — le code de Zuno (cette branche)

Confiance haute : c'est écrit dans les fichiers, et le test machine le vérifie pour la règle « coupé = comme avant ».

| Ce qu'on envoie | Où | Coupé |
| --- | --- | --- |
| Usage « musique » (`USAGE_MEDIA`, le volume musique) | `NativeVideoView.kt` lignes 1034-1036 | oui, toujours |
| Contenu « film » | mêmes lignes, et `AudioContentChoice.kt` `declared` | oui, si la voix claire est coupée |
| Contenu « parole » | la même fonction | seulement si la voix claire est **déjà** allumée (réglage d'avant, pas celui-ci) |
| Aucun drapeau (pas de synchro image forcée, pas de son obligatoire) | le builder n'appelle pas `setFlags` (lignes 1034-1037) | oui |
| Délestage (offload) coupé | on n'appelle pas `setEnableAudioOffload`. Media3 1.5.1 démarre le sink à `OFFLOAD_MODE_DISABLED` (`DefaultAudioSink.java` ligne 598) | oui |
| Tunnel audio/vidéo coupé | `NativeVideoView.kt` ligne 992, `.setTunnelingEnabled(false)` | oui |
| `setAudioAttributes` à la construction et à chaque ouverture | lignes 1003 et 1783 | oui |
| La même paire usage + type sur la demande de focus | lignes 536-541 | oui |
| Numéro de session noté, aucun égaliseur branché par l'app | ligne 2343. Pas de `Equalizer`, `DynamicsProcessing` ni `LoudnessEnhancer` dans ce lecteur | oui |
| Sortie flottante coupée, vitesse AudioTrack coupée | lignes 883-884 | oui |
| Focus géré par Zuno, pas la baisse à 20 % de Media3 | ligne 1785, interrupteur « Focus : Android » coupé | oui |

La ligne de boîte noire, à chaque ouverture : `Type déclaré : film (interrupteur coupé). Usage musique, drapeaux 0, délestage coupé, tunnel coupé.`

Les échantillons ne passent pas par cette fonction. Elle ne fait que choisir le mot.

## PROUVÉ — sources publiques (pas l'appareil)

Confiance haute sur le texte lu. Ça ne dit pas ce que l'oreille de Lionel entend.

**Android, le mode d'emploi officiel** ([Audio attributes](https://source.android.com/docs/core/audio/attributes)). L'usage décide du volume et du chemin. Le type de contenu (film, musique, parole, inconnu) **peut** servir à brancher un traitement d'après. Ce n'est pas obligatoire pour le constructeur.

**Android 16, constructeur ancien « flux musique »** (`AudioAttributes.java`, `setInternalLegacyStreamType`, lignes 1233-1235). `STREAM_MUSIC` **laisse le type à « inconnu »**. Il ne le met pas sur « musique ». L'usage, lui, devient média (ligne 1659).

**VLC 3.0.21** (`modules/audio_output/audiotrack.c`, `AudioTrack_New`, lignes 855-864). Il ouvre l'AudioTrack avec l'ancien constructeur `STREAM_MUSIC`. Il ne pose pas `CONTENT_TYPE_MOVIE`. Sur Android 16, le cadre en fait donc un type **inconnu**, usage média. VLC ne branche `DynamicsProcessing` que pour un volume au-dessus de 1 ; à volume 1 il le coupe (lignes 2093-2100).

**mpv 0.38.0** (`audio/out/ao_audiotrack.c`, lignes 302-306). Usage média. Type **film** s'il y a une image, **musique** s'il n'y a pas de piste vidéo (`player/audio.c`, lignes 448-449). Pas de drapeau dans ce builder. Numéro de session : option, 0 = Android en choisit un.

**Media3 1.5.1, si l'app ne dit rien** (`AudioAttributes.DEFAULT`). Type **inconnu**, usage média, drapeaux à 0, spatialisation en automatique. Zuno, lui, **dit film** (ligne 1036). En mode tunnel, Media3 ignore un changement d'attributs (`DefaultAudioSink.java` lignes 1402-1404). Zuno n'est pas en tunnel.

**YouTube.** Le programme de l'application YouTube n'est pas public. On ne peut pas citer la ligne. On ne devine pas.

**7 Motion (téléphone, libmpv).** `video_player_screen.dart` ne règle ni `ao`, ni `audio-media-role`, ni `audio-set-media-role`. Le `.so` embarqué par `media_kit_libs_android_video` n'a pas été ouvert ici : la version exacte de mpv dedans n'est pas prouvée. Les versions récentes de mpv ont en plus un interrupteur `--audio-set-media-role`, **coupé dans mpv**. S'il est coupé, le type peut rester « inconnu » au lieu de « film ». Les deux textes existent. On ne tranche pas sans le `.so`.

**Samsung, pages officielles.**

- Dolby Atmos ([TSG10007481](https://www.samsung.com/us/support/troubleshoot/TSG10007481/)) : modes Auto, Film, Musique, Voix. Auto « ajuste selon le contenu ». Un message du support Samsung (communauté) précise que Auto est prévu pour un **contenu déjà encodé Dolby Atmos**, pas pour n'importe quelle chaîne. Notre flux est de l'AAC-LC stéréo, pas de l'Atmos.
- Adapt Sound ([ANS10003294](https://www.samsung.com/us/support/answer/ANS10003294/)) : profil d'oreille. Samsung écrit qu'un casque doit être branché pour s'en servir. Ce n'est pas décrit comme un choix film / musique / parole.
- Auracast, appelé « Audio Broadcast » à partir de One UI 8.5 ([ANS10001042](https://www.samsung.com/us/support/answer/ANS10001042/)) : on **lance** une diffusion Bluetooth vers des écouteurs compatibles. Ce n'est pas un filtre du haut-parleur, et ce n'est pas lié au mot « film ».

**Android TV / box.** Le mot « film » est lu par la **box** (sa puce), pas par le téléviseur au bout du câble HDMI. Le téléviseur reçoit du PCM stéréo et applique son propre mode image/son. Changer le mot dans Zuno peut donc changer le son **dans la box**, et ne rien changer au traitement de la télé.

## NON PROUVÉ — il faut l'appareil de Lionel

Confiance : on ne l'a pas exécuté ici. Aucune box, aucun Samsung SM-S938B, aucune oreille.

- Que « film » sonne creux et que « musique » ou « inconnu » sonne clair, sur ce téléphone ou sur cette box.
- Le type réel annoncé par 7 Motion (le `.so` mpv).
- Le type réel annoncé par YouTube ou par l'autre application qui sonne bien.
- Qu'un mode Dolby « Voix » ou « Film » soit allumé dans les réglages du Samsung.
- Qu'Auracast ou Adapt Sound soient en route au moment de l'écoute.
- Que la puce de la box lise le type. Beaucoup de puces l'ignorent.

## HYPOTHÈSE

| Idée | Confiance | Pourquoi ce n'est pas une preuve |
| --- | --- | --- |
| Le mot « film » fait choisir à Samsung un rendu cinéma (creux, « dans un trou ») | moyenne | Samsung documente des modes Film / Musique / Voix, mais ne dit pas qu'il lit notre `CONTENT_TYPE_MOVIE` pour de l'AAC-LC. Auto parle surtout de l'Atmos encodé |
| Le mot « parole » (voix claire, ou l'essai) rapproche du son « comme un appel » | moyenne | Android autorise un traitement « parole ». Le chemin d'appel (mode communication) est **déjà** une autre mesure, dans `AudioRouteState` |
| VLC sonne mieux parce qu'il dit « inconnu » et Zuno dit « film » | moyenne | Vrai dans les sources VLC 3.0.21 et Zuno. Pas réécouté |
| mpv dit la même chose que Zuno (« film ») dès qu'il y a une image, donc le mot n'explique pas que **les deux** sonnent mal | moyenne, et seulement pour mpv 0.38 | Le `.so` de 7 Motion peut être plus récent et dire « inconnu » |
| Adapt Sound ou Auracast expliquent le son sur la box **et** le haut-parleur | basse | Samsung : Adapt Sound demande un casque ; Auracast est une diffusion qu'on démarre. Ni l'un ni l'autre n'est le chemin HDMI d'une box |
| Passer le bouton sur « musique » répare l'oreille | nulle tant que Lionel n'a pas écouté | C'est l'essai. Le défaut ne change pas |

Si les trois positions (film, musique, parole) sonnent pareil, le mot est éliminé, comme le décodeur l'a été. On le dira sur la fiche : la ligne `Type déclaré` change, le son non.

## Le bouton

Réglages → Diagnostic du son → **Type : coupé**.

Chaque appui avance : coupé → film → musique → parole → coupé.

- **Coupé** : film, ou parole si la voix claire est déjà allumée. Rien d'autre ne bouge.
- **Film, musique, parole** : on rouvre la chaîne. Les échantillons restent ceux du décodeur. Seul le mot dit à Android change. La voix claire (le compresseur) ne suit pas ce bouton : sinon on mélangerait les deux essais.

Clé : `zuno.audio.diag.content_type`. Valeur absente ou inconnue = `off`.

La fiche doit montrer `Type déclaré : …` et, sur la ligne Chemin, `flux musique (contenu film)` ou musique ou parole. Les deux phrases parlent du même choix.

À faire sur l'appareil, dans l'ordre :

1. Installer l'APK de **cette** branche. Pas une release `zuno-tv`.
2. Vérifier que le bouton est sur **Type : coupé**.
3. Ouvrir une chaîne qui sonne « vieille radio ». Lire la ligne `Type déclaré`.
4. Passer à **musique**, réécouter. Puis **parole**. Puis revenir à **coupé**.
5. Noter si l'oreille change. Si elle ne change pas, le mot n'est pas la cause.
6. Sur le Samsung : regarder Réglages → Qualité et effets sonores → Dolby Atmos (Auto, Film, Musique ou Voix) et si un casque ou Auracast est actif. Le dire avec la fiche.

## Test machine

`AudioContentChoiceTest` : coupé + voix claire coupée = film ; coupé + voix claire = parole ; l'essai « musique » gagne même si la voix claire est allumée ; le bouton fait le tour ; la ligne ne contient pas `http`.

Commande : `gradle test --offline -q` dans `android-app/packages/native_video_player/logic-test`.
