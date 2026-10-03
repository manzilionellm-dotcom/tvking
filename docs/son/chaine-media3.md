# Chaîne Media3 — revue ligne par ligne

Angle : ce que Zuno met entre le décodeur audio et l’AudioTrack, comparé à un Media3 1.5.1 non modifié. Rien n’a été entendu. Le son par défaut n’est pas changé.

Branche : `claude/son-09-chaine-media3`, à partir de `claude/zuno-mesures-audio` (`474969c2`).

## PROUVÉ

Commandes exécutées le 3 octobre 2026, sur cette machine. Pas de box, pas de téléphone, pas de flux IPTV.

### Tests du projet

`/tmp/gradle-8.10.2/bin/gradle -p android-app/packages/native_video_player/logic-test test`

Sortie : **BUILD SUCCESSFUL**. 20 fichiers de résultats, **140 tests, 0 échec, 0 ignoré**. Les 7 tests nouveaux sont dans `Media3ChainTest` (défaut = fabrique Zuno, étages actifs vides au repos, l’essai ignore sondes / voix claire / Sonic, Sonic inactif à vitesse 1 et actif à 0,97).

Le test déjà là `AudioSpectrumTest.chaineParDefautNeCoupePasLesAigus` a réimprimé :

```
CHAINE avant=0.8194908451579801 copie=0.8194908451579801 gain=0.8194908451579801 passe-bas=0.07888762097263485
```

Une copie et un gain 1 ne fabriquent pas un son « radio » à partir d’un bruit large. Un passe-bas, oui (0,079).

### Copie, entier 16 bits, et bande « appel »

Script Python (filtre maison, ordre 2, pas le filtre de l’app), bruit blanc 48 kHz, 48 000 échantillons, amplitude 0,4. Rapport = énergie au-dessus de 4 kHz / énergie totale.

```
white 0.8192188940110994
copy 0.8192188940110994
s16 0.8192187716966899
phone 0.09083385161070318
copy_identical True
s16_max_abs_delta 1.5258755217906206e-05
```

La copie est identique. Le passage en entier 16 bits ne change le rapport qu’à la 7e décimale. Un coupe-bande façon appel (grave sous 300 Hz, aigu au-dessus de 3,4 kHz, passe-bas appliqué deux fois) tombe à **0,091**, sous le seuil « bas » de l’app (0,12). Si un étage Zuno faisait ça, les quatre sondes ne seraient pas égales : la sonde d’après serait plus basse. Les fiches déjà prises disaient le contraire (0,9 % à 3,6 %, les quatre pareilles).

### Ce que le code Media3 1.5.1 fait vraiment

Sources lues (dépôt `androidx/media`, étiquette `1.5.1`), pas exécutées sur une box.

Ordre réel quand le décodeur sort du PCM, dans `DefaultAudioSink.configure` :

1. `ToInt16PcmAudioProcessor` — inactif si c’est déjà du 16 bits (`onConfigure` renvoie `NOT_SET`).
2. `ChannelMappingAudioProcessor` — inactif si aucune table de canaux (`setChannelMap(null)` → `NOT_SET`). Ce n’est pas un mélange : ça recopie des voies.
3. `TrimmingAudioProcessor` — inactif si délai et bourrage d’encodeur valent 0 (`NOT_SET`).
4. La chaîne de l’app, puis seulement les étages dont `isActive()` est vrai.
5. Si aucun étage n’est actif, `processBuffers` écrit le tampon du décodeur **tel quel** dans l’AudioTrack (`if (!audioProcessingPipeline.isOperational()) setOutputBuffer(inputBuffer)`).

`AudioOffload` : le constructeur de `DefaultAudioSink` force `offloadMode = OFFLOAD_MODE_DISABLED`. Zuno n’appelle pas `setOffloadMode`. Le sélecteur de pistes laisse `AUDIO_OFFLOAD_MODE_DISABLED` (le défaut). L’offload n’est pas allumé.

### Étages que Zuno enregistre

`ZunoAudioChain`, dans cet ordre :

| Étage | Actif quand | Sinon |
| --- | --- | --- |
| Sonde décodeur | Spectre allumé | `NOT_SET`, hors chaîne |
| `ClearVoiceProcessor` | voix claire allumée | `NOT_SET` |
| Sonde voix claire | Spectre allumé | `NOT_SET` |
| `SilenceSkippingAudioProcessor` | `skipSilenceEnabled` vrai | `isActive()` faux (`enabled` faux) |
| Sonde silence | Spectre allumé | `NOT_SET` |
| `SonicAudioProcessor` | vitesse ou hauteur éloignée de 1 de plus de 0,0001, ou fréquence changée | inactif, les échantillons n’y entrent pas |
| Sonde AudioTrack | Spectre allumé | `NOT_SET` |

Réglages au repos (ceux du commit de départ) : Spectre coupé, voix claire coupée, `skipSilenceEnabled = false` (posé dans `attachToSurface`, et c’est aussi le défaut ExoPlayer), vitesse du direct figée à 1,0. Les sept étages sont donc inactifs. Le PCM va droit à l’AudioTrack, comme un `DefaultAudioProcessorChain` au repos (silence + Sonic, eux aussi inactifs).

La chaîne utilisateur par défaut de Media3 est exactement silence puis Sonic, sans sonde et sans voix claire. Au repos, la liste **active** est vide des deux côtés. C’est ce que `Media3ChainTest.zunoAuReposEtMedia3AuReposEcriventLePcmTelQuel` vérifie.

### Options du décodeur FFmpeg (Jellyfin `media3-ffmpeg-decoder` 1.5.0+1, API Media3 1.5.1)

Construit par `FfmpegAudioRenderer(handler, listener, audioSink)`. Aucun `AudioProcessor` passé au constructeur : le sink est celui de Zuno.

- **Sortie flottante** : `shouldOutputFloat` ne demande du float que si le sink refuse le 16 bits, ou s’il accepte le float **en direct**. `enableFloatOutput` est faux (deux fois : fabrique et sink, et c’est le défaut Media3). Le sink ne prend le float en direct que si ce drapeau est vrai. Donc FFmpeg demande `AV_SAMPLE_FMT_S16`.
- **`SwrContext`** (`ffmpeg_jni.cc`) : même disposition de canaux en entrée et en sortie, même fréquence. Il ne change que le format (flottant planaire → 16 bits entrelacé). Pas de matrice de downmix, pas de fréquence imposée.
- **Nombre de voies** : `ffmpegGetChannelCount` lit `ch_layout.nb_channels` **après** décodage. L’app ne force pas la stéréo.
- **Pas d’option AAC** (cutoff, SBR, float) posée par Zuno. `err_recognition = AV_EF_IGNORE_ERR` : des paquets abîmés sont ignorés, ce n’est pas un filtre.
- Le `.so` Jellyfin (lavc 60.3.100) n’a pas été exécuté ici. Le fichier JNI lu est celui de Media3 1.5.1, pas un dump du `.so`.

Détail du JNI : `swr_convert` reçoit en `out_count` une taille en **octets** (`bufferOutSize`), alors que FFmpeg attend un nombre d’échantillons. Pour une conversion 1:1, le nombre d’échantillons écrits tient dans le tampon, et l’avance se fait de la taille prévue. Ce n’est pas un passe-bas à 4 kHz. Un décalage de délai du rééchantillonneur ferait plutôt une erreur de décodage. Non rejoué sur le `.so`.

### Réglages du sink et du lecteur

| Réglage | Media3 1.5.1 nu | Zuno au repos | Effet audible possible |
| --- | --- | --- | --- |
| `enableFloatOutput` | faux | faux (forcé) | aucun au repos. L’allumer peut sonner plus « large » ou crachoter sur une box qui gère mal le float |
| `enableAudioTrackPlaybackParams` | faux | faux (forcé) | aucun à vitesse 1. Vrai : la vitesse passerait par l’AudioTrack, pas par Sonic |
| Audio offload | désactivé | désactivé | aucun |
| `skipSilence` | faux | faux | aucun. Vrai : des trous dans la voix, pas une bande coupée |
| Vitesse / hauteur | le direct peut aller de 0,97 à 1,03 (`DefaultLivePlaybackSpeedControl`) | figée à 1,0 / 1,0 | à 0,97–1,03 Sonic est **actif** (étirement). Zuno le laisse **inactif**. Un étirement de 3 % ne coupe pas à 4 kHz. Zuno en fait moins que Media3 nu |
| Volume lecteur | 1 | 1 pendant la lecture, 0 seulement le temps du zap | une baisse durable ferait un son faible, pas « vieille radio ». Déjà écarté sur l’appareil |
| Voix claire (gain) | n’existe pas | coupée (`NOT_SET`) | allumée : les pics baissent (plancher 0,45). Ce n’est pas un passe-bas. Le rapport d’énergie au-dessus de 4 kHz ne bouge pas à gain constant |
| Sondes | n’existent pas | coupées | allumées : copie, quatre fois. Le test de copie ci-dessus ne change pas le rapport |
| Tampon AudioTrack | minimum Media3 | doublé, plafond +256 Ko (`AudioTrackBuffer.sized`) | latence un peu plus grande, moins de craquements. La taille d’un tampon ne coupe pas les aigus |
| Décodeur AAC | celui de la box (`MediaCodecAudioRenderer` seul, mode extension OFF) | liste MediaCodec AAC vidée, puis `FfmpegAudioRenderer` ajouté après | deux décodeurs peuvent sonner différemment. Sur l’appareil, les deux ont déjà été jugés pareils (ce n’est pas rejoué ici) |
| `setEnableDecoderFallback` | faux | vrai | si le premier codec plante, on essaie le suivant. Pas un filtre |
| Attributs audio | `USAGE_MEDIA` + contenu **inconnu** | `USAGE_MEDIA` + contenu **film** (parole seulement si voix claire) | sur certaines puces, le type « film » ou « parole » déclenche un traitement dans Android, **après** l’AudioTrack. Les sondes ne le voient pas |
| Focus | Media3 ne le prend pas | Zuno le prend, sans baisser à 20 % | déjà traité ailleurs. Pas un étage entre décodeur et piste |
| `handleAudioBecomingNoisy` | faux | vrai | pause si on débranche un casque. Pas un changement de timbre |
| Rôle audio | aucun drapeau | `ROLE_FLAG_MAIN` | peut choisir une autre piste si le flux en a plusieurs. Les chaînes citées sortent déjà en AAC-LC 48 kHz stéréo : la piste jouée n’est pas un commentaire mono |

Pas d’égaliseur, pas de `DynamicsProcessing`, pas de `LoudnessEnhancer`, pas de `ChannelMixingAudioProcessor` dans le code Zuno.

## Différences qui restent quand tout est coupé

Pour un AAC-LC 16 bits, 48 kHz, stéréo, vitesse 1, silence non sauté :

1. **Qui décode** — FFmpeg au lieu de la box. Les sondes voient déjà le PCM de ce décodeur. Elles étaient basses et égales : le creux est **dans** ce PCM, ou c’est de la parole. L’autre app qui sonne bien peut décoder autrement. L’essai « Box AAC » (déjà là, coupé) garde la chaîne Zuno et change seulement le décodeur.
2. **Tampon AudioTrack plus grand** — pas un filtre.
3. **Type de contenu « film »** au lieu de « inconnu » — hors des sondes. Risque réel seulement si la puce traite le « film » (renfort de voix, compression). Pas prouvé.
4. **Vitesse bloquée à 1** — Sonic moins souvent actif que chez Media3 nu. Ça ne peut pas, à soi seul, rendre Zuno **pire** qu’un Media3 nu sur le timbre.

7 Motion (téléphone) joue avec libmpv, pas avec cette chaîne. Un étage qui n’existe que dans Media3 ne peut pas être la seule cause d’un défaut entendu aussi dans mpv. Ça n’empêche pas la box Media3 d’avoir, en plus, un défaut à elle.

## HYPOTHÈSE

| Idée | Confiance | Pourquoi | Ce qui la départage |
| --- | --- | --- | --- |
| Au repos, aucun étage Zuno ne filtre. Le PCM du décodeur est écrit tel quel | 85 % | Lu dans Media3 1.5.1 et dans `ZunoAudioChain`. Testé en logique (liste active vide). Les quatre sondes égales sur l’appareil vont dans le même sens. Les 15 % : un bug de « inactif » qu’on n’a pas exécuté sur la puce | Essai « Chaîne Media3 » ci-dessous. S’il sonne pareil que « Box AAC », le sink Zuno n’est pas en cause |
| Le tampon agrandi n’est pas le son « radio » | 90 % | Une taille de tampon ne retire pas les aigus. Elle change la latence et les coupures | Le même essai : s’il sonne mieux, ce n’est pas une preuve que le tampon était coupable (l’essai change aussi le décodeur) |
| Sonic / saut de silence / float / offload ne sont pas le défaut actuel | 85 % | Tous inactifs ou égaux au défaut Media3, et la vitesse Zuno est plus calme | La fiche doit montrer `vitesse 1,00` et `silences non sautés`. Si une fiche montre autre chose, cette ligne est fausse sur l’appareil |
| Le type « film » (ou « parole » si voix claire) est traité par la puce après l’AudioTrack | 20 % | Possible sur un téléphone ou une TV, invisible pour les sondes. Le défaut aussi présent dans mpv affaiblit l’idée « seulement Media3 » | L’essai ne change **pas** ce type. S’il sonne toujours faux, l’idée reste ouverte. Il faudrait un second essai, pas fait ici |
| Le `SwrContext` FFmpeg (octets passés à la place d’échantillons, ou le `.so` Jellyfin) coupe la bande | 20 % | Le source JNI ne demande pas un passe-bas. Le décodeur de la box a été jugé pareil sur l’appareil, donc FFmpeg seul n’explique pas tout | Déjà en partie fait (« Box AAC »). À refaire sur **cette** version, même chaîne, et noter le nom du décodeur dans la fiche |
| Deux sons se battent encore (« guerre entre deux sons ») | 15 % pour la chaîne | Le passage « un seul AudioTrack » est déjà en place et coupé au sens « ne pas revenir à l’ancien ». Cette revue ne le rouvre pas | La fiche : `AudioTrack vivants` doit rester 1, `Lectures` ne doit pas rester à 2 |

Je ne conclus pas que la cause est trouvée.

## Essai ajouté (coupé par défaut)

Réglages → Diagnostic du son → **Chaîne Media3 : Zuno**.

- Clé : `zuno.audio.chain.stock`. Absente ou illisible = faux.
- Faux : le lecteur d’avant. FFmpeg pour l’AAC, tampon agrandi, sondes inactives.
- Vrai : `DefaultRenderersFactory` sans aucun appel en plus. Décodeur de la box, sink Media3, pas de sonde, pas de voix claire, tampon d’origine. La vitesse reste à 1,0. Le focus et le volume ne changent pas.

Allumer reconstruit le lecteur (les rendus sont figés à la construction) et rouvre la chaîne en cours. Recouper revient au son habituel.

Ce que l’essai change **en même temps** (à ne pas mélanger) :

- le décodeur AAC (box au lieu de FFmpeg) ;
- le tampon ;
- le repli de décodeur (faux, comme Media3) ;
- le temps de raccord vidéo HLS (5 s, le défaut, au lieu de 0).

Le MP2 n’a plus FFmpeg pendant l’essai : une chaîne MP2 peut rester muette. Les chaînes citées sont de l’AAC.

L’essai « Box AAC » déjà présent ne change **que** le décodeur, et garde le sink Zuno. Les deux ensemble séparent « décodeur » et « reste de la chaîne ».

La fiche gagne une ligne `Chaîne : Zuno (défaut)` ou `Chaîne : essai Media3 par défaut`. En essai, la sonde dit qu’elle n’est pas branchée : normal, il n’y a plus d’étage Zuno.

7 Motion et le lecteur mpv du téléphone ne lisent pas cet interrupteur.

## À VÉRIFIER SUR L’APPAREIL

Sur la box (lecteur Media3), pas sur une release, pas avec `publish=true`.

1. Installer l’APK de **cette** branche. Réglages → Diagnostic du son. Lire « Chaîne Media3 : **Zuno** ». Ne pas allumer Spectre pour la première écoute.
2. Ouvrir France 24 (puis France 2, France Info, une chaîne qui sonne bien). La boîte noire doit contenir `Chaîne : Zuno (défaut)`.
3. Sans couper l’image : allumer **Box AAC : essai**, zapper, réécouter la même chaîne 20 secondes. Noter le nom du décodeur sur la fiche (`box (…)` ou `FFmpeg`). Recouper Box AAC.
4. Allumer **Chaîne Media3 : essai**. La chaîne doit se rouvrir seule. La fiche doit dire `Chaîne : essai Media3 par défaut` et `décodé par : box`. Réécouter 20 secondes.
5. Recouper **Chaîne Media3**. La fiche doit revenir à `Chaîne : Zuno (défaut)`. Réécouter : le son doit être celui d’avant l’essai.
6. Tableau à remplir, une ligne par chaîne :

| Chaîne | Zuno (FFmpeg) | Box AAC (sink Zuno) | Chaîne Media3 (sink nu) |
| --- | --- | --- | --- |
| France 24 | | | |
| France 2 | | | |
| France Info | | | |
| BEIN | | | |
| une chaîne qui sonne bien | | | |

7. Lecture des trois cases :
   - les trois pareilles et mauvaises → la chaîne Media3 de Zuno n’est pas la cause sur cette box. Chercher après l’AudioTrack (TV, HDMI, type de contenu) ou dans le flux, pas dans les processeurs ;
   - Box AAC mauvaise, Chaîne Media3 bonne → quelque chose du sink Zuno (tampon ou étage qu’on croit inactif) change le son. Le décodeur n’est pas la différence entre ces deux cases ;
   - Zuno mauvaise, Box AAC bonne → le décodeur FFmpeg. L’essai « chaîne nue » n’apporte alors rien de plus ;
   - une seule chaîne change → noter son codec sur la fiche, ne pas généraliser.
8. Vérifier qu’aucune ligne ne contient `http` ni un mot de passe.

Le téléphone Samsung et 7 Motion : cet interrupteur ne s’y applique que si l’APK installé est celui de la box (Media3). Le lecteur mpv ne passe pas par `ZunoAudioChain`.
