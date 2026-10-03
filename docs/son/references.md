# Son — apps de référence (angle 12)

Branche `claude/son-12-references`, partie de `claude/zuno-mesures-audio` (`474969c2`).

Ce texte ne dit pas que le son a été entendu, ni qu'il est réparé. Il compare le code de Zuno aux lecteurs publics, et il classe des hypothèses. Chaque source a une adresse. Rien ici n'a été inventé pour combler un trou : si une date ou un réglage n'est pas dans la source, il n'est pas écrit.

Le son par défaut ne change pas. Un seul essai a été ajouté, **coupé**. Voir la fin.

## Ce que Zuno annonce aujourd'hui (lu dans le code, pas sur un appareil)

Lecteur box : Media3 1.5.1, `NativeVideoView.movieAudioAttributes`.

- Usage : média (`USAGE_MEDIA`).
- Type de contenu : **film** (`CONTENT_TYPE_MOVIE`). Parole seulement si « voix claire » est allumée.
- Pas de drapeau (pas de synchro HDMI matérielle, pas de basse latence).
- Pas de mode performance (`setPerformanceMode` n'est appelé nulle part).
- Pas de délestage (`setOffloadedPlayback` n'est pas allumé).
- PCM 16 bits forcé (`setEnableFloatOutput(false)`).
- Vitesse AudioTrack figée (`setEnableAudioTrackPlaybackParams(false)`), direct à 1,0.
- Tunnel audio/vidéo coupé.
- Focus : Zuno le demande lui-même (`AUDIOFOCUS_GAIN`, `setWillPauseWhenDucked(false)`, `setAcceptsDelayedFocusGain(false)`). Media3 ne le gère pas tant que l'interrupteur « Focus : Android » est coupé.
- Tampon de sortie : deux fois le minimum d'Android, plafonné à +256 Ko (`AudioTrackBuffer.sized`).
- Numéro de session : celui que Media3 crée. Zuno n'en impose pas.
- Pas d'égaliseur, pas de `DynamicsProcessing`, pas de `LoudnessEnhancer`, pas de `LoudnessCodecController`.

Téléphone 7 Motion : `lib/main.dart` démarre media_kit (libmpv). Le lecteur téléphone ne règle pas `ao`. media-kit dit lui-même qu'il utilise OpenSL (`--ao=opensles`), pas AudioTrack.

## 1. Comment les apps de référence règlent la sortie

### Media3 / ExoPlayer 1.5.1 (la référence du lecteur box)

Fichier de la version que Zuno embarque :

- https://github.com/androidx/media/blob/1.5.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/audio/DefaultAudioTrackProvider.java
- https://github.com/androidx/media/blob/1.5.1/libraries/common/src/main/java/androidx/media3/common/AudioAttributes.java
- https://github.com/androidx/media/blob/1.5.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/ExoPlayer.java

Lu le 3 octobre 2026 sur l'étiquette `1.5.1`.

`DefaultAudioTrackProvider` (API 23+) construit l'AudioTrack ainsi :

- attributs passés par l'app, sauf en tunnel : là, le fournisseur force film + média + drapeau `FLAG_HW_AV_SYNC` ;
- format (fréquence, voies, encodage) ;
- `MODE_STREAM` ;
- taille de tampon demandée ;
- numéro de session ;
- à partir d'Android 10, `setOffloadedPlayback` seulement si le délestage est demandé.

Il n'appelle pas `setPerformanceMode`. Il ne met pas `FLAG_LOW_LATENCY`.

Le lecteur ExoPlayer, si on ne touche à rien, part de `AudioAttributes.DEFAULT` : type **inconnu**, usage **média**, aucun drapeau, politique de capture « tout le monde », spatialisation **AUTO**. Le booléen `handleAudioFocus` du constructeur n'est pas mis à vrai : le champ Java vaut faux. Un ExoPlayer de démo ne demande donc pas le focus tout seul, et il annonce « inconnu », pas « film ».

Zuno, lui, appelle `setAudioAttributes` avec **film**. C'est la différence nette avec le Media3 de référence. L'usage média, l'absence de drapeaux et la spatialisation AUTO sont les mêmes.

### VLC

Deux sorties, lues le 3 octobre 2026 sur `master` :

- AudioTrack : https://raw.githubusercontent.com/videolan/vlc/master/modules/audio_output/android/audiotrack.c
- AAudio : https://raw.githubusercontent.com/videolan/vlc/master/modules/audio_output/android/aaudio.c
- Choix de l'app Android : https://raw.githubusercontent.com/videolan/vlc-android/master/application/resources/src/main/java/org/videolan/resources/VLCOptions.kt
- Effet de volume : https://raw.githubusercontent.com/videolan/vlc/master/modules/audio_output/android/dynamicsprocessing_jni.c

L'app VLC Android (`VLCOptions.getAout`) : OpenSL si on le choisit, AudioTrack si on le choisit, **sinon AAudio** (le commentaire du source dit « aaudio is the default »). Le wiki VLC dit qu'AAudio ne fait pas le passthrough : dans ce cas VLC repasse à AudioTrack. https://code.videolan.org/videolan/vlc-android/-/wikis/Audio-Output

AudioTrack de VLC, quand il est vraiment utilisé :

- usage média ;
- type **film** si le rôle VLC est une vidéo, **musique** sinon ;
- `MODE_STREAM` ;
- session : l'option `audiotrack-session-id`. L'app Android en génère une (`generateAudioSessionId`) et la passe ;
- le PCM flottant est **commenté** dans le source (« Don't use Float for now since 5.1/7.1 Float is down sampled to Stereo Float »). La voie AudioTrack reste en 16 bits ;
- pas de `setPerformanceMode` dans ce fichier.

`DynamicsProcessing` est créé sur la session, mais le source ne l'allume que si le gain demandé n'est pas 1,0. À volume normal il est désactivé. Le commentaire dit aussi de ne pas l'utiliser avant Android 12 (plantage aléatoire, vlc-android#2221). Ce n'est pas un égaliseur de timbre au volume 1.

AAudio de VLC (la sortie par défaut de l'app) :

- usage : média si le rôle est `video`, `music`, `production` ou `test`. Le rôle `communication` passerait en appel. Sans rôle, le source laisse le défaut AAudio, qu'il commente comme média ;
- format : 16 bits si le décodeur sort déjà du S16, **flottant** sinon (il demande la conversion) ;
- session allouée par AAudio si `audiotrack-session-id` vaut 0 ;
- mode basse latence **seulement** si l'option VLC `low-delay` est vraie, ou pour de l'ambisonique. Le défaut de `low-delay` n'est pas dans ce fichier : il n'est pas affirmé ici.

AAudio n'a pas de « type de contenu » film/musique. Il a un usage.

### Kodi

https://github.com/xbmc/xbmc/blob/master/xbmc/cores/AudioEngine/Sinks/AESinkAUDIOTRACK.cpp

Lu le 3 octobre 2026 (`master`).

`CreateAudioTrack` :

- usage média ;
- type **musique** (pas film), même pour une vidéo ;
- `MODE_STREAM` ;
- session `AUDIO_SESSION_ID_GENERATE` (Android en crée une) ;
- PCM flottant si le sink dit qu'il le supporte (le fichier le vérifie et le choisit).

Pas de `setPerformanceMode` dans la création lue.

### mpv, et donc 7 Motion

AudioTrack de mpv : https://github.com/mpv-player/mpv/blob/master/audio/out/ao_audiotrack.c (le fichier lu correspond au contenu public de `ao_audiotrack.c`, défaut `cfg_pcm_float = 1`).

- usage média, toujours ;
- type de contenu **seulement si** mpv a un « media role » : musique si le rôle est musique, film sinon. Sans rôle, `setContentType` n'est pas appelé. Le constructeur Android part alors d'**inconnu** ;
- `MODE_STREAM` ;
- session : option `audiotrack-session-id`, 0 par défaut (Android en génère une) ;
- PCM flottant **allumé par défaut** (`priv_defaults` : `cfg_pcm_float = 1`) ;
- tampon : deux fois le minimum du pilote, serré entre **75 ms et 150 ms**.

L'app mpv-android demande le focus à part, en se faisant passer pour de la **musique** : https://github.com/mpv-android/mpv-android/blob/master/app/src/main/java/is/xyz/mpv/MPVActivity.kt (`USAGE_MEDIA` + `CONTENT_TYPE_MUSIC`, `AUDIOFOCUS_GAIN`). Le commentaire du source dit que libmpv peut utiliser d'autres valeurs dans `ao_audiotrack`, mais que la demande de focus, elle, dit toujours « musique ».

7 Motion ne pose pas `ao` et ne pose pas de media role. media-kit documente sa sortie Android comme OpenSL, pas AudioTrack :

- https://github.com/media-kit/media-kit/issues/445 (le mainteneur : « Currently, we use --ao=opensles »)
- https://github.com/media-kit/media-kit/pull/453 (commit du 13 septembre 2023 qui passe à AudioTrack, puis retour à OpenSL le 15 septembre 2023)
- https://github.com/media-kit/media-kit/issues/1061 (AudioTrack « improves the sound quality » pour un utilisateur ; le mainteneur dit qu'il n'est pas le défaut à cause de plantages JNI)

OpenSL ne règle pas un `AudioAttributes` « film ». Il tombe sur le flux musique ancien.

## 2. Problèmes publics « métallique / en boîte / voix de téléphone »

Aucun ticket public trouvé ne dit : « France 24 en AAC-LC 48 kHz sonne comme une vieille radio dans ExoPlayer et dans mpv, et bien dans une autre app ». Ce qui suit est ce qui existe, avec les dates lues. Ce n'est pas la preuve que c'est le cas de Lionel.

| Quoi | Date lue | Lien | Rapport avec Zuno |
| --- | --- | --- | --- |
| WAV flottant déformé sur Galaxy S25, Android 15. Le même fichier est bon avec MediaPlayer. Corrigé après Media3 1.7.1, prévu pour 1.8.0-beta01. Pas dans 1.5.1. | ouvert le 31 mai 2025, mis à jour le 3 août 2025 | https://github.com/androidx/media/issues/2490 | Zuno force le 16 bits, pas le flottant. Le ticket ne décrit pas de l'AAC-LC. Il montre seulement qu'un S25 peut rendre un PCM flottant mal, et un 16 bits (MediaPlayer) bien. |
| MIDI « mince, sans richesse » sur le même S25 Android 15. Classé demande, pas bug de décodeur AAC. | ouvert le 31 mai 2025 | https://github.com/androidx/media/issues/2489 | Autre format. Utile seulement comme témoin : sur ce téléphone, deux lecteurs du même fichier ne sonnent pas pareil. |
| Le mode `MODE_IN_COMMUNICATION` ne reste pas. L'équipe Android dit qu'un garde-fou remet `NORMAL` si l'app ne garde pas une lecture ou une capture en usage **appel**. Laisser le mode appel « abîme le comportement de la plateforme ». | page Issue Tracker, pas de date de création dans l'extrait lu | https://issuetracker.google.com/issues/209493718 | Le chemin d'appel (bande étroite, anti-écho) est exactement le timbre « musique pendant un appel ». Le garde-fou existe côté AOSP. Un constructeur peut ne pas l'appliquer. Zuno ne met pas ce mode : il le **lit** seulement. |
| Galaxy S25 Ultra : après WeChat ou WhatsApp, le Bluetooth reste « en appel ». La musique ne revient qu'en forçant l'arrêt de l'app d'appel. | sujet ouvert le 11 avril 2025 | https://r2.community.samsung.com/t5/Galaxy-S/Bluetooth-Stuck-in-In-Call-Mode-After-apps-Calls-on-Galaxy-S25/td-p/18900791 | Même phrase que le terrain, **sur Bluetooth**, après un appel. Pas un bug ExoPlayer. |
| Galaxy S24 Ultra, One UI 8.0, Android 16, logiciel `S928U1UES4CYL1` : après un appel, la musique reprend « comme encore en appel » (bande étroite). Couper « Appels » sur l'oreillette rend le média normal et coupe les appels. | sujet ouvert le 4 janvier 2026 | https://r2.community.samsung.com/t5/Galaxy-S/Bluetooth-call-audio-routing-issue-with-Sony-WF-1000XM5-on/td-p/21343187 | One UI 8 + Android 16, timbre d'appel qui reste. Le modèle cité est SM-S928U1, pas le SM-S938B. Même famille, pas la même preuve. |
| Notes Galaxy plus anciennes : après un appel, le média Bluetooth « presque radio AM », ou « forcé dans le canal d'appel, mauvaise qualité ». | fil de 2023, messages jusqu'en 2024 | https://r1.community.samsung.com/t5/galaxy-note/bluetooth-audio-issue-after-phone-call/td-p/20047730 | Antérieur à Android 16. Montre que le symptôme Samsung est connu hors Zuno. |
| mpv : AudioTrack ne fait pas de mode exclusif, donc Android rééchantillonne. Discussion AAudio, pas fusionnée comme sortie par défaut de mpv-android (l'app reste en API 21 ; AAudio est API 26). | discussion de la demande, 2023 et après | https://github.com/mpv-player/mpv/pull/12261 | Piste « qualité » publique, pas un timbre de téléphone mesuré. |

Recherche faite aussi sur « tinny / telephone / muffled / underwater » pour Media3, ExoPlayer, mpv, Samsung, Android 14–16. Les pages Samsung grand public sur un son étouffé (eau, pression, équilibre gauche/droite) ne décrivent pas une app IPTV. Elles ne sont pas retenues comme cause.

## 3. Android 15 et 16 — ce qui peut toucher une app

Sources officielles, pages relues le 3 octobre 2026 (mention « Last updated 2026-10-01 UTC » sur les pages Android 15).

**Le type de contenu choisit des traitements.** Android dit que le type (film, musique, parole, inconnu) sert à brancher ou non des blocs de post-traitement. Ce n'est pas le décodeur. C'est après l'écriture du PCM.

- https://source.android.com/docs/core/audio/attributes
- https://developer.android.com/reference/android/media/AudioAttributes

Le type film est décrit comme « dialogue, musique et effets » d'un film ou d'une émission. Le type inconnu est le défaut du constructeur.

**Android 15, toutes les apps.** Une piste **directe** ou **délestée** (audio compressé, souvent HDMI ou DSP) peut faire fermer une autre piste directe ou délestée si la limite matérielle est atteinte. Avant, la nouvelle piste échouait. Zuno, pour l'AAC-LC, écrit du PCM : ce n'est pas ce chemin, sauf passthrough AC-3 / DTS qui n'est pas le cas France 24.

- https://developer.android.com/about/versions/15/behavior-changes-all

**Android 15, apps qui ciblent l'API 35.** Demander le focus audio exige d'être l'app au premier plan, ou un service de premier plan lié au son. Sinon la demande revient refusée.

- https://developer.android.com/about/versions/15/behavior-changes-15
- https://developer.android.com/reference/android/media/AudioFocusRequest

Zuno, si le focus est refusé, le dit et joue quand même à plein volume. Un refus ne baisse pas le son. Ça peut expliquer un mélange avec une autre app, pas à lui seul un timbre de téléphone. La cible SDK réelle du build Flutter n'a pas été relue dans un APK ici.

**Android 15, loudness (CTA-2075).** `LoudnessCodecController` ajuste le décodeur AAC selon les métadonnées de loudness et l'appareil (haut-parleur, casque, TV). C'est **opt-in** : il faut créer le contrôleur avec le numéro de session. Zuno ne le fait pas. Media3 1.5.1 non plus dans les fichiers lus. Ne pas l'avoir n'ajoute pas un filtre tout seul, d'après cette page.

- https://developer.android.com/about/versions/15/features
- https://developer.android.com/reference/android/media/LoudnessCodecController
- résumé : https://developer.android.com/about/versions/15/summary

**Android 15, spatialisation.** `Virtualizer` est déprécié. Le remplacement est `Spatializer`, et le comportement se règle sur les attributs (`SPATIALIZATION_BEHAVIOR_AUTO` ou `NEVER`). Le défaut Media3 1.5.1, et donc Zuno qui ne le règle pas, est **AUTO**.

- https://developer.android.com/about/versions/15/summary

**Android 15, focus et parole.** Depuis Android 8, une lecture marquée **parole** n'est pas baissée automatiquement : le système prévient l'app pour qu'elle se mette en pause. Film et inconnu, eux, peuvent être baissés. Zuno ignore déjà la baisse. La doc :

- https://developer.android.com/reference/android/media/AudioFocusRequest

**Android 16, pages de comportement.** Les pages « apps qui ciblent Android 16 » et « toutes les apps » lues ne décrivent pas un nouveau filtre AudioTrack, ni un nouveau `MODE_IN_COMMUNICATION`.

- https://developer.android.com/about/versions/16/behavior-changes-16
- https://developer.android.com/about/versions/16/behavior-changes-all

**Android 16, ajouts audio (pas un durcissement forcé).** QPR2 bêta 1 (20 août 2025) ajoute, entre autres : décodage IAMF, « Personal Audio Sharing » dans le sélecteur de sortie, nouvelles API AAudio, curseur HDR/SDR. La page dit que ces changements sont surtout des ajouts.

- https://developer.android.com/about/versions/16/qpr2/release-notes
- https://developer.android.com/about/versions/16/features (qualité image/son des TV via `MediaQuality`, aides auditives LE Audio)

Le partage audio (Auracast / LE Audio) est un choix de l'utilisateur dans le sélecteur de sortie. Il n'est pas branché par le type « film » dans le code de Zuno. Aucune source officielle lue ne dit qu'il dégrade l'AAC d'une app qui ne le demande pas.

**Mode appel.** `MODE_IN_COMMUNICATION` reste le mode d'une communication VoIP en cours. L'Issue Tracker cité plus haut dit qu'AOSP le remet à `NORMAL` si l'app ne maintient pas une activité audio d'appel. Ce n'est pas un changement nouveau d'Android 15 ou 16 dans les pages lues.

## PROUVÉ

Commandes et lectures réellement faites le 3 octobre 2026.

1. Le dépôt est sur `474969c2` au départ (`git log -1`). Le code de `movieAudioAttributes` annonce film + média. C'est lu dans `NativeVideoView.kt`, pas supposé.
2. Media3 **1.5.1**, fichier brut téléchargé : `AudioAttributes.DEFAULT` = type inconnu, usage média, spatialisation AUTO, aucun drapeau. `DefaultAudioTrackProvider` ne met pas de mode performance. Le tunnel seul ajoute `FLAG_HW_AV_SYNC`.
3. VLC `audiotrack.c` (master, téléchargé) : film si rôle vidéo, musique sinon, usage média, `MODE_STREAM`, flottant commenté. `VLCOptions.kt` : AAudio est le défaut de l'app.
4. Kodi `AESinkAUDIOTRACK.cpp` (master, téléchargé) : média + **musique** + `AUDIO_SESSION_ID_GENERATE`.
5. mpv `ao_audiotrack.c` : type de contenu seulement avec un media role ; flottant par défaut ; tampon 75–150 ms.
6. Test unitaire ajouté, exécuté (Gradle 8.14.3, téléchargé pour l'occasion ; un premier essai `--offline` a échoué parce que le plugin Kotlin n'était pas en cache) :

```
/tmp/gradle-8.14.3/bin/gradle -p android-app/packages/native_video_player/logic-test test --tests '*AudioFixesTest'
```

Puis la suite entière du même dossier, sans filtre :

```
/tmp/gradle-8.14.3/bin/gradle -p android-app/packages/native_video_player/logic-test test
```

`AudioFixesTest` : 6 tests passés, dont `leTypeAnnonceResteFilmSaufEssai`. Le défaut (essai coupé, voix claire coupée) reste le type **film** (3). L'essai allumé donne **inconnu** (0). Voix claire + essai reste **parole** (1). La suite `logic-test` entière finit par `BUILD SUCCESSFUL` (seconde exécution, 1 s, tâches déjà compilées).

Aucune chaîne IPTV n'a été jouée. Aucun spectre nouveau n'a été calculé : les mesures PCM déjà dans `docs/AUDIO-BOITE-NOIRE.md` disent que le PCM avant l'AudioTrack est celui d'une parole (0,9 à 3,6 % au-dessus de 4 kHz). Ce rapport ne les refait pas.

## HYPOTHÈSE

Classées. La confiance est la chance que **cette** différence explique le timbre entendu sur les trois appareils (box, SM-S938B, 7 Motion), pas la chance que la différence de code existe. Les différences de code, elles, sont dans le tableau plus bas : elles sont lues, pas devinées.

1. **Traitement après l'AudioTrack, choisi par le type de contenu** — **35 %**. Android le documente. Zuno dit « film », un ExoPlayer nu dit « inconnu », Kodi dit « musique ». Ça peut creuser la voix (film / spatialisation / profil « cinéma » du téléviseur ou de Dolby). Confiance pas plus haute : 7 Motion ne dit pas « film » (OpenSL, pas de media role) et sonne mal aussi, d'après le terrain. Si les deux sonnent pareil, le type « film » n'est pas la cause **commune**. L'essai sert à le séparer sur la box.
2. **Chemin d'appel resté collé (mode communication, ou Bluetooth HFP)** — **40 % sur le téléphone si la fiche dit « chemin d'appel » ou si le son n'est mauvais qu'en Bluetooth ; 15 % sur la box.** Les fils Samsung (2025 et janvier 2026, One UI 8 / Android 16) décrivent exactement « la musique comme encore en appel ». Ça touche toutes les apps qui passent par ce chemin. Ça n'explique la box que si la ligne « Chemin » y dit la même chose. Zuno ne met pas ce mode.
3. **Deux voix dans le flux (commentaire + piste, ou gauche ≠ droite)** — **30 % pour « guerre entre deux sons ».** Les sondes de spectre ne voient pas ça : chaque voie peut être une parole normale. La corrélation gauche/droite est déjà mesurée par la branche de départ, pas encore lue sur l'appareil de Lionel. VLC et Kodi laissent choisir la piste ; ils ne réparent pas un flux déjà mélangé par la chaîne.
4. **Sortie différente : AudioTrack (Zuno) contre OpenSL (7 Motion) contre AAudio (VLC par défaut)** — **25 % comme cause commune.** Les trois chemins existent dans les sources. Ils expliquent qu'une app sonne autrement. Ils expliquent mal que Zuno **et** 7 Motion sonnent **pareil** et mal, sauf si le mal est avant la sortie (le flux) ou après, dans un traitement commun de l'appareil (hypothèses 1 et 2).
5. **PCM flottant** — **10 % pour Zuno.** Zuno et l'essai « décodeur de la box » sont en 16 bits. Le ticket S25 concerne le flottant. mpv, si on le forçait en AudioTrack, serait en flottant par défaut : ça peut compter pour 7 Motion **seulement** le jour où `ao=audiotrack` est allumé. Aujourd'hui 7 Motion est en OpenSL.
6. **Loudness Android 15 non branché** — **10 %.** C'est opt-in. Ne pas l'avoir n'ajoute pas un filtre, d'après la doc. Une autre app qui l'allume peut sonner plus « présente ». Ce n'est pas prouvé pour l'app qui sonne bien : on ne sait pas laquelle.
7. **Focus et baisse de volume** — **5 %.** Déjà écarté sur le terrain (volume lecteur 1,0, focus tenu). Le code de repli « Focus : Android » remettrait la baisse à 20 %, pas un filtre téléphone.
8. **Taille du tampon** — **5 % pour le timbre.** Un tampon change les coupures et le retard, pas la bande passante. Zuno est plus grand que mpv (75–150 ms). Les deux sonnent mal : le tampon n'est pas le point commun du timbre.

## Différences concrètes, classées

| # | Zuno | Référence qui sonne souvent « juste » | Expérience pour trancher |
| --- | --- | --- | --- |
| 1 | Type **film** | Media3 nu : **inconnu**. Kodi : **musique**. mpv sans rôle : pas de type (inconnu). VLC AudioTrack : film **si** rôle vidéo, musique sinon. VLC AAudio : usage média, pas de type film. | Sur la box : Diagnostic du son → **Contenu : inconnu**, zapper la chaîne mauvaise, puis le témoin. Couper l'essai ensuite. Lire la ligne « Type de contenu annoncé » et la ligne de chemin (elle doit dire « inconnu », plus « film »). |
| 2 | AudioTrack via Media3 | VLC Android : **AAudio** par défaut. 7 Motion : **OpenSL**. | Même chaîne, même appareil, trois lectures : Zuno, 7 Motion, VLC (sans changer ses réglages audio). Noter si VLC est bon et les deux autres mauvais. Ça départage « le flux » et « la sortie ». |
| 3 | PCM **16 bits** forcé | mpv AudioTrack : flottant par défaut. Kodi : flottant si le sink le peut. VLC AudioTrack : 16 bits. VLC AAudio : flottant sauf S16 déjà là. | Déjà tranché pour Zuno : le 16 bits sonne comme le décodeur de la box. Ne pas rallumer le flottant. Sur 7 Motion, ne passer `ao=audiotrack` que pour un essai court : media-kit signale des plantages JNI. |
| 4 | Focus demandé par Zuno, sans baisse, gain plein | ExoPlayer nu : ne demande pas le focus. mpv-android : focus en se déclarant **musique**. | Déjà en place : la fiche dit « Focus audio ». Si elle dit « demande REFUSÉE » (Android 15, app pas au premier plan), le noter. Ne pas allumer « Focus : Android » pour chercher le timbre : ça remet la baisse à 20 %. |
| 5 | Spatialisation **AUTO** (Zuno ne la règle pas ; Media3 non plus) | Aucune des sources lues ne met `SPATIALIZATION_BEHAVIOR_NEVER` | Sur le téléphone : réglages son, couper Dolby / Atmos / son spatial, rejouer la chaîne **sans** changer Zuno. Sur la box : le mode audio du téléviseur (film, standard, jeu). Si le timbre change, le traitement est **après** Zuno. |
| 6 | Pas de mode performance | Media3 1.5.1 non plus. VLC AAudio : basse latence seulement si `low-delay` | Pas d'essai dans Zuno : ce n'est pas une différence avec Media3. Le chercher serait inventer un réglage que les références n'utilisent pas pour de la télé. |
| 7 | Tampon ≈ 2× le minimum, +256 Ko max | mpv : 75–150 ms | Ne pas y toucher pour le timbre. Si le son « se bat » seulement après beaucoup de zaps, la fiche « pistes encore vivantes » reste le juge, pas la taille. |
| 8 | Session choisie par Media3, aucun effet dessus | VLC crée un `DynamicsProcessing` **éteint** à gain 1. Kodi et mpv laissent Android créer la session | Pas d'effet à ajouter. À volume 1, VLC n'en met pas un non plus. |
| 9 | Pas de délestage, pas de direct, pour l'AAC PCM | Une app qui envoie le bitstream HDMI saute le mélangeur Android | France 24 est de l'AAC-LC décodé en PCM des deux côtés (FFmpeg et décodeur de la box, déjà essayés). Le passthrough n'explique pas ces chaînes. Le vérifier : la fiche ne doit pas dire passthrough. |
| 10 | Pas de `LoudnessCodecController` | Android 15 le propose, personne dans les sources lues ne l'allume par défaut | Ne pas l'allumer. Si l'app qui sonne bien est connue, regarder si elle le documente. Sinon on ne lui attribue pas le mérite. |

## À VÉRIFIER SUR L'APPAREIL

Installer l'APK de **cette** branche (pas une release). Les essais restent coupés au premier lancement.

### A. Type de contenu (l'interrupteur nouveau)

1. Ouvrir une chaîne qui sonne mal (haut-parleur du téléphone, ou HDMI de la box : le noter).
2. Réglages → Diagnostic du son. **Contenu** doit afficher « film ».
3. Allumer **Contenu : inconnu**. La boîte noire doit écrire `Type de contenu annoncé : inconnu (essai).`
4. Zapper la chaîne (ou la rouvrir). La ligne de chemin doit montrer le contenu **inconnu**, plus **film**.
5. Écouter 15 secondes, puis le bouton **Jouer le son témoin**.
   - La chaîne et le témoin changent ensemble → l'appareil traite « film » autrement qu'« inconnu ».
   - La chaîne reste mauvaise et le témoin (moitié bruit) est clair → le flux, pas l'étiquette.
   - Rien ne change → cette hypothèse tombe pour cet appareil. Recouper l'essai.
6. Recouper : le libellé redevient « Contenu : film », et la ligne doit redire « film (défaut) ».

La voix claire allumée gagne : le type reste « parole ». Couper la voix claire avant cet essai.

### B. Chemin d'appel (déjà mesuré, pas encore lu sur l'appareil)

Sans nouvel interrupteur. Même chaîne.

1. Lire la ligne **Chemin**. Si elle contient « chemin d'appel », « communication », « Bluetooth d'appel » ou le haut-parleur d'oreille : c'est l'hypothèse 2, pas le décodeur.
2. Sur le SM-S938B : écouter au haut-parleur du téléphone, **sans** oreillette. Puis avec l'oreillette. Si seul le Bluetooth est « téléphone », c'est le fil Samsung (profil d'appel resté collé), pas Zuno. Forcer l'arrêt des apps d'appel, ou couper « Appels » sur l'oreillette, comme dans les sujets cités, et réécouter.
3. Sur la box : la même ligne. HDMI + mode normal écarte le chemin d'appel.

### C. Les trois lecteurs, même chaîne, même branchement

1. Zuno (cet APK), essai contenu **coupé**.
2. 7 Motion, sans changer `ao`.
3. VLC, sortie laissée par défaut (AAudio, sauf si le réglage de l'appareil dit autre chose).
4. Noter bon / mauvais pour chacun, et la sortie (HP, HDMI, Bluetooth).

Lecture : les trois mauvais → le flux ou l'appareil, pas l'étiquette « film ». Zuno et 7 Motion mauvais, VLC bon → la sortie (AudioTrack/OpenSL contre AAudio) ou un traitement que VLC ne déclenche pas. Zuno seul mauvais → le type « film » ou un autre réglage propre à Media3 (l'essai A doit déjà avoir répondu).

### D. Spatialisation / profil du téléviseur

Sans changer Zuno : couper le son spatial ou Dolby du téléphone, et passer le téléviseur de « film » à « standard ». Réécouter la même chaîne. Si ça suffit, Zuno n'a pas à changer son PCM.

### E. Ce qu'il ne faut pas conclure

- Un pourcentage au-dessus de 4 kHz qui reste bas sur les quatre sondes est compatible avec de la parole. Il ne dit pas que l'AudioTrack est innocent : il est **après** les sondes.
- Ne pas publier, ne pas pousser `main`, ne pas toucher aux releases.

## Code ajouté (coupé par défaut)

| Réglage | Clé | Défaut | Quand on l'allume |
| --- | --- | --- | --- |
| Contenu : inconnu | `zuno.audio.ref.content_unknown` | coupé | le type annoncé passe de film (3) à inconnu (0). Usage média inchangé. PCM inchangé. La voix claire reste parole. |

Endroit : Diagnostic du son, à côté de « Passage ». Pris en compte tout de suite sur l'AudioTrack déjà ouvert (`setAudioAttributes`), et à la prochaine ouverture. 7 Motion (mpv) n'a pas cet interrupteur : il n'annonce pas « film ».
