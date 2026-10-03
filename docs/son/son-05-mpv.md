# Angle 05 — 7 Motion / libmpv

Je n'ai pas entendu le son. Rien n'est « réparé ». Le son par défaut ne change pas : l'essai de sortie est **coupé**.

7 Motion (téléphone) joue avec **media_kit / libmpv**. Zuno sur la box et « Zuno essai » jouent avec **Media3 / AudioTrack**. Les deux peuvent sonner mal sur les mêmes chaînes. Ce qui compte, c'est ce qu'ils ont **en commun**, et ce que seul mpv ajoute.

## PROUVÉ

### 1. L'app ne règle pas le son mpv

Lu dans `android-app/lib/features/player/presentation/video_player_screen.dart`, fonction `_applyMpvOptions`, avant cet essai.

Elle écrit : `hwdec`, `cache`, `cache-secs`, `stream-lavf-o`, tailles du demuxer, `network-timeout`, `keep-open`, `user-agent`, `force-seekable`.

Elle n'écrit **pas** : `ao`, `audio-channels`, `audio-samplerate`, `audio-format`, `af`, `volume-max`, `audio-normalize-downmix`, `audio-buffer`.

`hwdec=auto-safe` (ou `no`) concerne l'image. Le décodeur AAC de ce libmpv est celui de FFmpeg (`aac`, `aac_latm`, `aac_fixed`). Il n'y a pas de décodeur AAC MediaCodec dans le `.so` (pas de `aac_mediacodec` ; les décodeurs MediaCodec présents sont h264, hevc, mpeg2, av1).

Aucun `af=` n'est posé. Le filtre `equalizer` est **compilé** dans le `.so` (`ff_af_equalizer`, option `--enable-filter=equalizer`) mais personne ne l'allume. Un filtre compilé et non branché ne coupe pas les aigus.

### 2. media_kit force OpenSL ES

Lu dans le source actuel de media_kit (`media_kit/lib/src/player/native/player/real.dart`, dépôt media-kit, branche main) :

- téléphone réel, ou API > 25 : `ao = opensles`
- émulateur ancien (API ≤ 25) : `ao = null` (pas de son)

`pubspec.yaml` demande `media_kit: ^1.1.11` et `media_kit_libs_android_video: ^1.3.6`. Il n'y a pas de `pubspec.lock` ici : la version exacte résolue au prochain `flutter pub get` n'a pas été rejouée. Les issues media-kit 445 et 1061 disent la même chose depuis 2023 : le défaut est OpenSL ES, et des gens ont trouvé qu'AudioTrack « sonnait mieux ». Ce n'est pas une mesure à nous.

Notre code, essai coupé, **n'écrit pas** `ao`. OpenSL ES reste celui de media_kit. C'est le son d'aujourd'hui.

### 3. Le libmpv embarqué (binaire, pas une doc)

Commande :

```text
curl -fsSL -o /tmp/mpv-arm64.jar \
  https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.7/default-arm64-v8a.jar
unzip -o -q /tmp/mpv-arm64.jar -d /tmp/mpvjar
strings /tmp/mpvjar/lib/arm64-v8a/libmpv.so | grep -E 'audio output$'
strings /tmp/mpvjar/lib/arm64-v8a/libmpv.so | grep -c -i aaudio
```

Le paquet `media_kit_libs_android_video` 1.3.x télécharge ce jar `v1.1.7` (lu dans son `build.gradle`). Taille reçue : **5 729 978** octets. `libmpv.so` : **12 369 680** octets.

Sorties audio trouvées dans le `.so` :

```text
Android AudioTrack audio output
Null audio output
OpenSL ES audio output
RAW PCM/WAVE file writer audio output
```

`grep -c -i aaudio` → **0**.

AAudio n'existe pas dans ce binaire. L'essai « AAudio » ne peut pas l'inventer : mpv n'a pas le pilote. Le son peut se taire. On revient en coupant l'essai et en zappant.

Le script de build `v1.1.7` (`buildscripts/include/depinfo.sh`) nomme FFmpeg **6.0** et mpv au commit `78d43740`. La ligne `Configuration:` lue dans le `.so` reprend les options meson de `mpv.sh` (`-Dlibmpv=true`, pas de lua, pas de vulkan). La ligne ffmpeg du même `.so` contient `--enable-decoder=aac*` et `--disable-filters` puis seulement `overlay` et `equalizer`.

### 4. Ce qu'OpenSL ES fait dans ce commit mpv

Lu dans `audio/out/ao_opensles.c` du commit `78d43740` (celui cité par le script de build). Pas désassemblé octet par octet dans le `.so`. Les options `buffer-size-in-ms` et `frames-per-enqueue` sont bien des chaînes du `.so`.

- Le pilote **force 2 voies** (`mp_chmap_from_channels(&ao->channels, 2)`). Un AAC stéréo 48 kHz n'est pas mélangé. Un 5.1 le serait, par mpv, avant OpenSL.
- Il ne pose **pas** le type de flux Android (`SL_ANDROID_KEY_STREAM_TYPE` absent du fichier). Le défaut Android d'OpenSL, quand on ne le pose pas, est le flux média. Je ne l'ai pas revu dans le code Android de l'appareil.
- Tampon demandé : **250 ms** (`buffer_size_in_ms = 250`). C'est un délai, pas un filtre.
- Fréquence gardée entre 8 kHz et 192 kHz. 48 kHz passe.

Le pilote AudioTrack du même commit (`ao_audiotrack.c`) ouvre un AudioTrack avec **USAGE_MEDIA** et, sauf rôle « musique », **CONTENT_TYPE_MOVIE**. C'est le même couple que Zuno (`movieAudioAttributes()` dans `NativeVideoView.kt` : `USAGE_MEDIA` + `CONTENT_TYPE_MOVIE`, ou `SPEECH` seulement si « voix claire »).

Donc : OpenSL (7 Motion, aujourd'hui) et AudioTrack (Zuno) **ne sont pas le même tuyau**. L'essai AudioTrack aligne le téléphone sur le tuyau de la box.

### 5. Ce que les deux lecteurs ont en commun — et ce qu'ils n'ont pas

| Élément | 7 Motion (mpv) | Zuno box / Zuno essai (Media3) |
| --- | --- | --- |
| Décodeur AAC | FFmpeg du libmpv (6.0 dans ce build) | FFmpeg Jellyfin **ou** décodeur de la puce. Les deux ont déjà sonné pareil sur la box |
| Sortie | OpenSL ES, forcé par media_kit | AudioTrack, `USAGE_MEDIA` + film |
| Focus audio | **pas demandé**. Aucun `AudioManager` dans le lecteur téléphone, ni dans `MediaKitAndroidHelper.java` | demandé par Zuno, volume lecteur 1,0 (déjà mesuré) |
| User-Agent | `VLC/3.0.18 LibVLC/3.0.18` par défaut (`PlayerSettings`) | `VLC/3.0.20 LibVLC/3.0.20` en dur (`NativeVideoView.kt`) |
| Relais local | **oui**, tout le direct passe par `LocalStreamRelay` | **non**, sauf pendant un enregistrement |
| `af` / égaliseur branché | non | non |
| `setMode` communication, annuleur d'écho, suppresseur de bruit | aucun appel dans le dépôt | aucun appel dans le dépôt |
| Permission micro | pas de `RECORD_AUDIO` dans les manifestes | pareil |
| Plugins partagés | `zuno_voice` ouvre la reconnaissance du système, sans micro en continu. `tvking_device` ne fait que monter/baisser le volume musique. Le service « Écouteurs » ne crée pas un second lecteur : il garde le processus éveillé, et seulement si on a tapé Écouteurs | le service Écouteurs n'est pas le lecteur de la box |

Le relais téléphone **recopie les octets** (`_fanout`). Il ne ré-encode pas, il ne filtre pas. Il n'explique pas la box, qui n'y passe pas en lecture normale.

Le point commun le plus net, avant les deux décodeurs : **les deux se présentent comme VLC**. Un fournisseur qui sert un flux différent selon le lecteur enverrait la même famille de flux aux deux, et un autre flux à l'autre application. Ce n'est pas prouvé sur un vrai serveur : aucun flux n'a été ouvert ici.

Ce qui n'est **pas** commun : la sortie (OpenSL contre AudioTrack) et le focus. Si le défaut est vraiment le même aux trois endroits (box, Samsung avec Zuno essai, 7 Motion), OpenSL seul ne peut pas en être la cause. Il peut quand même rendre **7 Motion** pire, ou différent. L'essai sert à le départager.

### 6. Ce qu'un mauvais réglage mpv ferait au chiffre « énergie > 4 kHz »

Même passe-haut que la sonde de la box (Butterworth ordre 2, 4 kHz, 512 échantillons de chauffe). Signaux fabriqués, 48 kHz, 1 seconde. Aucun flux.

Commande : `python3 android-app/tool/son_05_mpv_probe.py`

FFmpeg utilisé pour l'AAC : `ffmpeg version 6.1.1-3ubuntu5`.

```text
bruit_blanc                          0.819769   LARGE
bruit_passe_bas_3k4_deux_fois        0.078739   BASSE
voix_harmoniques_jusqu_a_3k2         0.066711   BASSE
bruit_bande_telephone_300_3400       0.089552   BASSE
peigne_2ms_sur_bruit                 0.818835   LARGE
peigne_20ms_sur_voix                 0.066715   BASSE
melange_voies_inversees              0.000000   SILENCE
correlation_voies_inversees         -1.0000
voie_gauche_seule_de_l_inverse       0.066711   BASSE
downmix_6_voies_bruit_vers_stereo    0.820870   LARGE
aac_lc_128k_bruit                    0.795845   LARGE
aac_lc_64k_bruit                     0.704026   LARGE
aac_lc_128k_voix                     0.066922   BASSE
```

Lecture, sans prétendre que c'est le flux de Lionel :

- Un passe-bas à 3,4 kHz, ou une bande téléphone 300–3400 Hz, sur du **bruit** tombe à ~8–9 % (BASSE). La sonde verrait ça.
- Une voix sans rien au-dessus de 3,2 kHz est déjà à **6,7 %**, sans aucun filtre. L'AAC-LC 128 kb/s ne change presque pas ce chiffre (6,7 %). Les 0,9 à 3,6 % déjà mesurés sur la box sont dans la zone d'une parole, ou d'un signal encore plus coupé. Cette machine ne les sépare pas.
- Un **peigne** (le son mélangé avec une copie décalée de 2 ms, « dans un trou » / « guerre entre deux sons ») sur du bruit reste **LARGE (82 %)**. La sonde des 4 kHz ne le voit pas.
- Le même peigne sur la voix reste à 6,7 % : la voix était déjà basse, l'écho n'ajoute rien au chiffre.
- Deux voies inversées : corrélation **−1**, le mélange est du silence. Chaque voie, seule, garde 6,7 %. La sonde de mélange ne dit pas « passe-bas » ; elle dit silence. La corrélation gauche/droite, elle, le voit. 7 Motion **n'a pas** cette sonde.
- Mélanger 6 bruits vers la stéréo ne coupe pas les aigus (82 %). Forcer 2 voies ne fabrique pas une « vieille radio » si le contenu est large.
- AAC-LC 64 kb/s de **bruit**, avec cet encodeur, reste LARGE (70 %). Un débit bas ne suffit pas, ici, à fabriquer un 1 %.

`volume-max` n'est pas posé (défaut mpv : 100). Le volume du lecteur media_kit part à 100. Ce n'est pas un filtre. Un volume au-dessus de 100 écrêterait : on ne le fait pas.

`audio-samplerate` forcé à 8 000 Hz rendrait le son lent et sourd, et la ligne `audio-out-params` le montrerait. On ne le force pas.

## HYPOTHÈSE

| # | Idée | Confiance | Pourquoi pas plus |
| --- | --- | --- | --- |
| 1 | Les deux apps envoient un User-Agent VLC, l'autre app en envoie un autre, et le fournisseur ne sert pas le même flux | 45 % | C'est le seul geste commun **avant** les deux décodeurs. Pas vérifié sur un serveur. Les 0,9–3,6 % collent à de la parole, donc France 24 / France Info / France 2 peuvent être « normales » et quand même jugées mauvaises. BEIN (foule) dans la même zone serait un vrai indice que le flux est coupé : la fiche de BEIN n'est pas dans ce dépôt |
| 2 | OpenSL ES rend 7 Motion moins bon qu'AudioTrack, sans être la cause de la box | 40 % pour le téléphone seul, **15 %** comme cause commune | Le binaire a les deux pilotes, media_kit choisit OpenSL, la box est déjà sur AudioTrack. Des utilisateurs media-kit ont préféré AudioTrack. Personne ici ne l'a écouté |
| 3 | OpenSL force 2 voies et abîme un flux qui n'est pas stéréo (BEIN, parfois 5.1) | 30 % pour un flux multi-voies, **5 %** pour un AAC-LC stéréo annoncé | France 24 est décrit stéréo 48 kHz. Le downmix de bruit, lui, ne coupe pas les aigus |
| 4 | 7 Motion ne prend pas le focus : un autre son se mélange (« guerre ») ou Android baisse le nôtre (« comme un appel ») | 25 % pour le téléphone, **faible** comme cause commune | Sur Zuno le volume lecteur est déjà 1,0 et le focus est tenu. Ça a été écarté là-bas |
| 5 | Le « dans un trou » est un peigne ou des voies qui se battent, invisible aux 4 kHz | 25 % | Prouvé que la sonde ne voit pas un peigne de 2 ms. Pas prouvé qu'il y en a un dans le flux. La box a déjà une corrélation gauche/droite : si elle est proche de +1, cette idée tombe pour la box |
| 6 | Un mode « appel » Android (annuleur d'écho) est allumé par l'app | **5 %**, plutôt écarté | Aucun `setMode`, aucun annuleur d'écho, aucun `RECORD_AUDIO` dans les manifestes. Ça peut encore venir du système, pas de notre code |

## À VÉRIFIER SUR L'APPAREIL

L'essai est dans **7 Motion** (le téléphone, lecteur mpv), pas dans Zuno TV. Pendant la lecture : réglages du lecteur (la feuille qui a déjà la vitesse et le tampon). En bas : **Essai de sortie audio**.

Il est sur **Coupé**. Coupé, l'app n'écrit pas `ao`. Le son doit rester celui d'aujourd'hui.

1. Ouvrir une chaîne qui sonne mal (et, si possible, une qui sonne bien). Ouvrir la feuille. Lire le bloc sous les puces. Noter au moins `ao`, `audio-params`, `audio-out-params`, `af`, `volume`, `audio-channels`.
   - `ao` doit être `opensles` sans qu'on l'ait choisi.
   - `af` vide = pas de filtre.
   - `audio-params` et `audio-out-params` disent la fréquence et le nombre de voies **avant** et **après** la sortie. 6 voies puis 2 voies = mélange. 48000 des deux côtés = pas de changement de fréquence.
2. Choisir **AudioTrack**. Le message dit de zapper. Zapper. Réécouter la même chaîne, puis relire le bloc : `ao` doit être `audiotrack`.
   - Mieux qu'OpenSL, et la box toujours mauvaise → OpenSL ne concerne que 7 Motion. On ne le met pas par défaut.
   - Pareil que la box → la sortie n'est pas la cause commune. Revenir sur **Coupé** et zapper (on remet OpenSL ES).
3. **AAudio** : ce libmpv ne l'a pas. Si le son se tait ou si `ao` ne devient pas `aaudio`, c'est le résultat attendu. Recouper, zapper.
4. Sur le téléphone, Réglages → Lecteur a déjà le choix du User-Agent (défaut VLC). Le passer sur **TiviMate**, rouvrir la chaîne, sans toucher à l'essai de sortie (laissé coupé). Si le son devient celui de l'autre app, le flux servi n'était pas le même. Remettre VLC après. La box, elle, a VLC/3.0.20 en dur : ce geste-là ne la change pas. On ne l'a pas ajouté, pour ne pas changer son son.
5. Pendant la chaîne, faire sonner une notification. Si la chaîne baisse ou se mélange, le téléphone ne tient pas le focus. Zuno, sur la box, écrit déjà la ligne « Focus audio ».

Ne pas publier. Ne pas installer ceci à la place de `phone-latest`.

## Fichiers

- `android-app/lib/features/player/domain/mpv_audio_output.dart` — quelles valeurs d'essai sont autorisées. Tout le reste, y compris `ao=null`, est refusé.
- `android-app/lib/features/player/data/player_settings.dart` — clé `player.mpv_ao_trial`, vide par défaut.
- `android-app/lib/features/player/presentation/video_player_screen.dart` — n'écrit `ao` que si l'essai est allumé. Affiche les propriétés, sans les modifier.
- `android-app/lib/features/player/presentation/widgets/player_settings_sheet.dart` — les quatre puces.
- `android-app/test/features/player/mpv_audio_output_test.dart`
- `android-app/tool/son_05_mpv_probe.py` — la mesure du tableau ci-dessus.

`flutter test` n'a pas été lancé : le SDK Flutter n'est pas installé sur cette machine.
