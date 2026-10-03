# Attributs et AudioTrack — son « film » ou un autre chemin

Angle : ce que Zuno déclare à Android au moment de créer l'AudioTrack (usage, type de contenu, drapeaux, capture, spatialisation, session, performance, tunneling, offload, capacités, tampon), comparé au défaut de Media3 1.5.1, à ExoPlayer sans réglage, et à VLC 3.0.

Rien n'a été entendu. Le son par défaut n'est pas modifié. L'essai est coupé.

## PROUVÉ

### Ce que Zuno envoie aujourd'hui

Lu dans `NativeVideoView.movieAudioAttributes` (avant cet essai, et encore quand l'essai est coupé) :

- usage `USAGE_MEDIA` (1)
- contenu `CONTENT_TYPE_MOVIE` (3), ou `CONTENT_TYPE_SPEECH` (1) seulement si « voix claire » est allumée
- aucun drapeau, aucune politique de capture, aucune spatialisation posés à la main

Media3 complète alors avec les défauts de son `AudioAttributes.Builder` (source `androidx/media` tag `1.5.1`, fichier `AudioAttributes.java`, récupéré le 3 octobre 2026) :

- drapeaux `0`
- capture `ALLOW_CAPTURE_BY_ALL` (1)
- spatialisation `SPATIALIZATION_BEHAVIOR_AUTO` (0), posée sur Android 12 et plus

Le manifeste de l'app ne contient pas `allowAudioPlaybackCapture`. La politique de capture reste donc celle de la piste.

### Défaut Media3 / ExoPlayer sans réglage

Même fichier, et `ExoPlayer.java` du même tag :

- `AudioAttributes.DEFAULT` = `new Builder().build()`
- usage média, contenu **inconnu** (`CONTENT_TYPE_UNKNOWN` = 0), drapeaux 0, capture tous, spatialisation auto
- `ExoPlayer.Builder` part de ce défaut (`audioAttributes = AudioAttributes.DEFAULT`)
- Zuno appelle `setAudioAttributes` et **remplace** le contenu inconnu par « film »

L'écart chiffré, voix claire coupée, est **un seul nombre** : contenu 3 au lieu de 0. Usage, drapeaux, capture, spatialisation, offload et tunneling sont les mêmes.

### VLC 3.0

`modules/audio_output/audiotrack.c` de VLC 3.0.23 (page Fossies lue le 3 octobre 2026) crée l'AudioTrack avec l'ancien constructeur `STREAM_MUSIC`, pas avec un contenu « film ». La session vient de `audiotrack-session-id`.

Traduction Android 14 (`android-14.0.0_r75`) et Android 15 (`android-15.0.0_r1`), méthode `setInternalLegacyStreamType` : pour `STREAM_MUSIC`, le contenu **reste inconnu**. Le commentaire AOSP dit qu'ils refusent de deviner « musique » pour ce flux. L'usage retombe sur média si la stratégie produit ne l'a pas déjà mis.

Donc VLC 3.0, sur Android 14 et 15, arrive au même contenu que le défaut Media3 (inconnu), pas au « film » de Zuno.

### Tunneling, offload, performance, session, passthrough, tampon

Sources Media3 1.5.1 lues le même jour :

| Réglage | Défaut Media3 | Zuno | L'essai le change ? |
| --- | --- | --- | --- |
| Tunneling | `tunnelingEnabled = false` (`DefaultTrackSelector`) | `setTunnelingEnabled(false)` en plus | non |
| Si le tunneling était allumé | `DefaultAudioTrackProvider` **remplace** les attributs par contenu film + drapeau `FLAG_HW_AV_SYNC` + usage média | ce chemin n'est pas pris | non |
| Offload | `AUDIO_OFFLOAD_MODE_DISABLED` (0) dans `TrackSelectionParameters.AudioOffloadPreferences` et `RendererConfiguration` | jamais allumé | non |
| Performance | `DefaultAudioTrackProvider.customizeAudioTrackBuilder` renvoie le builder **sans** `setPerformanceMode` | pareil | non |
| Session | `ExoPlayerImpl` en génère une (`generateAudioSessionIdV21`). Le sink part de `AUDIO_SESSION_ID_UNSET` puis reçoit ce numéro | Zuno ne choisit pas un numéro. La fiche dit déjà « Session audio Android n°… » | non |
| Effet auxiliaire | `NO_AUX_EFFECT_ID` | aucun égaliseur, aucun `DynamicsProcessing`, aucun `LoudnessEnhancer` | non |
| Passthrough | AC-3, E-AC-3, DTS si la sortie les accepte | pareil. L'AAC-LC des chaînes citées est décodé en PCM (les sondes voient du PCM) | non |
| Tampon PCM | minimum × 4, borné entre 250 ms et 750 ms (`DefaultAudioTrackBufferSizeProvider`, facteur 4) | ce résultat, puis `AudioTrackBuffer.sized` : doublé, plafond +256 Ko, aligné sur la trame | non |

`DefaultAudioTrackProvider.java` du tag 1.5.1 fait 118 lignes. Il n'appelle pas `setPerformanceMode`. Le mode performance reste celui du constructeur Android (`PERFORMANCE_MODE_NONE`, valeur 0 dans la doc Android). Ce n'est pas un choix Zuno.

### Commande exécutée

Répertoire `android-app/packages/native_video_player/logic-test`, le 3 octobre 2026 :

```text
/tmp/gradle-8.11.1/bin/gradle test --no-daemon
```

Sortie : `BUILD SUCCESSFUL`. **142** tests, **0** ignoré, **0** échec (les 9 tests `AudioProfileTest` sont dedans).

Ce que ces tests verrouillent :

- essai absent, vide, ou texte inconnu → coupé
- coupé, sans voix claire → contenu film, drapeaux 0, capture tous, spatialisation auto, performance 0, tunneling coupé, offload coupé
- coupé, voix claire allumée → contenu parole (le comportement d'aujourd'hui)
- film / musique / parole / défaut Media3 ne changent **que** le contenu
- le défaut Media3 et la traduction VLC 3.0 ont le contenu inconnu
- la ligne de fiche ne contient ni `http` ni `password`, et n'ajoute pas de cause sûre
- rouvrir seulement si une lecture est en cours **et** que le mode change. Repousser « coupé » alors qu'on est déjà coupé ne rouvre pas

Le test Dart du bouton (`audio_attribute_trial_test.dart`) n'a pas été lancé : Flutter n'est pas installé sur cette machine. L'ordre des mots est le même que `AudioProfile.ORDER`, déjà testé en Kotlin.

## HYPOTHÈSE

Les sondes (0,9 à 3,6 % au-dessus de 4 kHz) sont **avant** l'AudioTrack. Un attribut ne remet pas des aigus dans ce PCM. Cet angle n'explique donc pas un manque d'aigus déjà mesuré dans l'app. Il peut expliquer une couleur ajoutée **après** : « dans un trou », « deux sons qui se battent », « comme pendant un appel ». La doc Android dit que le type de contenu sert à brancher des traitements (page Audio attributes, AOSP).

| Idée | Confiance | Pourquoi pas plus |
| --- | --- | --- |
| Le contenu « film » fait prendre à la box ou au Samsung un traitement cinéma (surround virtuel, Dolby, élargissement) que le contenu inconnu ou « musique » ne prend pas. Ça sonne creux ou comme deux sources, et les sondes ne le voient pas | 40 % | Le mécanisme est documenté par Android, et c'est le seul écart avec Media3 et VLC 3.0. On n'a pas le code Samsung ni celui de la box. On n'a pas écouté |
| « Parole » (voix claire, ou l'essai) fait prendre le chemin téléphone : bande étroite, compresseur d'appel | 15 % comme cause actuelle, 50 % comme effet de l'essai | Aujourd'hui, parole n'est envoyé que si la voix claire est allumée. Si elle est coupée, ce n'est pas le chemin en cours |
| Drapeaux, capture, session, performance, tunneling, offload ou passthrough expliquent le défaut sur l'AAC-LC | 5 % | Ils sont déjà ceux de Media3. L'AAC-LC ne part pas en passthrough : les sondes voient du PCM |
| Le tampon doublé (+256 Ko max) fait le son « radio » | 10 % | Un tampon plus long ajoute du retard ou évite un craquement. Il ne coupe pas la bande. L'essai ne le change pas, pour ne pas mélanger les causes |

7 Motion (téléphone, libmpv) a le même défaut à l'oreille, d'après le contexte. Le script de build `media_kit` (`libmpv-android-video-build`, `buildscripts/scripts/mpv.sh`) ne fixe ni `ao` ni `audio-set-media-role`. Dans mpv, `ao_audiotrack.c` met le contenu « film » **seulement** si le rôle média est demandé, et « musique » si le rôle est musique. Sinon le contenu reste celui du constructeur Android (inconnu) avec l'usage média. On n'a pas ouvert le `.so` du téléphone : on ne sait pas quel sort est réellement pris. Confiance 30 % que 7 Motion envoie aussi « film ». Si c'est le cas, film est un point commun. Si 7 Motion envoie « inconnu » et sonne pareil, le contenu n'est pas la cause commune.

## À VÉRIFIER SUR L'APPAREIL

L'essai est dans Réglages → Diagnostic du son → bouton **Attributs**. Coupé au départ. Clé `zuno.audio.profile`. Un appui avance : coupé → film → musique → parole → défaut Media3 → coupé.

Ça ne change pas le décodeur, le volume, le tampon, le tunneling ni l'offload. Si une chaîne (ou le son témoin) joue déjà, elle est rouverte pour que l'AudioTrack naisse avec le nouveau contenu. La fiche gagne une ligne `Attributs : …`. La ligne `Chemin : … flux …` dit ce qu'Android a **annoncé**. Les deux doivent nommer le même contenu.

7 Motion (mpv) n'a pas ce bouton. L'essai ne porte que sur le lecteur natif (la box, et « Zuno essai » seulement si cet écran Diagnostic du son y est).

### Expérience

1. Installer l'APK de **cette** branche. Pas la release `zuno-tv`. Ne rien publier.
2. Ouvrir Diagnostic du son. Le bouton doit dire **Attributs : coupé**.
3. Jouer le son témoin. Écouter les 5 secondes de **bruit** (la seconde moitié). Le bruit a des aigus dans le fichier : s'il sonne sourd ou « dans un trou », c'est l'appareil. S'il sonne clair, ce n'est pas l'appareil.
4. Appuyer jusqu'à **Attributs : musique**. Relancer le témoin si la lecture s'est arrêtée. Réécouter le bruit.
5. Pareil pour **défaut Media3**, puis **parole**, puis **film**.
6. Lire la fiche. Noter la ligne `Attributs` et la fin de la ligne `Chemin` (`flux …`).
7. Refaire 4 à 6 sur une chaîne qui sonne mal (France 24 ou une autre), sans changer les autres interrupteurs.
8. Remettre **Attributs : coupé** avant de quitter.

### Comment lire le résultat

| Ce qu'on entend | Lecture |
| --- | --- |
| Le bruit du témoin est sourd sur **film** et **coupé**, clair sur **musique** ou **défaut Media3** | le contenu « film » déclenche un traitement de l'appareil. Confiance haute **sur cet appareil**. On ne change pas le défaut tout seul |
| Les quatre essais sonnent pareil, témoin compris | les attributs ne sont pas la cause ici. Chercher ailleurs |
| Seule **parole** sonne « comme un appel » | le chemin parole existe, mais ce n'est pas le réglage actuel (sauf si la voix claire était allumée) |
| `Attributs` dit musique et `Chemin` dit encore film | Android a réécrit le contenu. Le noter : l'essai n'a pas atteint la sortie |
| Le témoin est clair partout, la chaîne reste sourde partout | le PCM de la chaîne est déjà comme ça (parole). Les attributs n'y sont pour rien |

Le bouton **film**, voix claire coupée, envoie les mêmes chiffres que **coupé**. Il sert à nommer l'essai dans la fiche. La comparaison utile est musique, parole, et défaut Media3, contre coupé.
