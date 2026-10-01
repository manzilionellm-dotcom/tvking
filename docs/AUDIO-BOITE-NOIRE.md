# Boîte noire audio — son « vieille radio »

Diagnostic du son de la chaîne en cours. Il **étend** `AudioDiagnosis` (Zuno 105, commit `fb784ab9`, déjà dans la 106). Il ne remplace pas `describe()` ni `verdicts()`.

Le chemin audio par défaut ne change pas. Les deux interrupteurs nouveaux sont **coupés** :

| Réglage | Clé | Défaut | Effet quand on l'allume |
| --- | --- | --- | --- |
| Mesurer le spectre | `zuno.audio.diag.probe` | coupé | la sonde PCM copie les échantillons **sans les modifier** |
| Réessayer FFmpeg | `zuno.audio.fix.ffmpeg` | coupé | au `setUrl` suivant, `forceBoxAacDecoder` repart à faux. Le filet des 8 s (`requestBoxAudioFallback`) reste |

Rien n'est envoyé au panel. Le heartbeat (`SubscriptionBackend.heartbeat`) n'a pas de champ diagnostic audio. On n'en a pas inventé.

Le rapport est local : `audio-diag.json`, une fiche par chaîne, 20 fiches, 48 Ko, corps tronqué à 4 000 caractères. Les URL et les mots de passe sont retirés.

## PROUVÉ (machine de test, signaux synthétiques)

Commandes réellement exécutées le 1er octobre 2026 :

- `flutter analyze --no-fatal-infos --no-fatal-warnings` — code de sortie **0** (254 remarques déjà présentes, aucune `error •`).
- `flutter test` — **342** tests passés, **2** ignorés, **0** échec.
- `gradle test` dans `android-app/packages/native_video_player/logic-test` — **77** tests, **0** échec.

### Spectre (passe-haut Butterworth ordre 2 à 4 kHz)

Énergie du passe-haut / énergie totale, PCM 16 bits, 48 000 échantillons (24 000 à 24 kHz). Seuils : large si ≥ **0,40**, bas si ≤ **0,12**, milieu sinon.

| Signal | Rapport mesuré | Classe |
| --- | --- | --- |
| Bruit blanc 48 kHz, amplitude 0,4 | **0,8194908451579801** | LARGE |
| Le même bruit, passe-bas 3,4 kHz appliqué deux fois | **0,07888762097263485** | BASSE |
| 1 kHz + 8 kHz | **0,47960864174293155** | LARGE |
| 8 kHz seul | **0,9556384601245715** | LARGE |
| 3 kHz seul | **0,2329493007397243** | MILIEU (ne tranche pas) |
| Bruit blanc 24 kHz | **0,6597358275523765** | LARGE |
| Ce bruit passé deux fois à 3,4 kHz, à 24 kHz | **0,06755364228786838** | BASSE |

Écart large bande − passe-bas à 48 kHz : **0,7406032241853453**. Le large bande n'est jamais classé BASSE. Une fenêtre trop courte, le silence, ou une fréquence sous 12 kHz ne concluent pas.

Une énergie basse **seule** ne désigne pas le décodeur. Une voix naturelle est pauvre au-dessus de 4 kHz et tomberait dans la même zone. Le rapport dit alors **cause incertaine** et ne propose pas de changer FFmpeg. C'est testé : snapshot FFmpeg 48 kHz + spectre bas → confiance `INCERTAINE`, aucun réglage, `sureCauses` vide.

Un spectre LARGE sur un HE-AAC décodé par la box **déjà à 48 kHz** retire l'hypothèse « SBR peut-être raté ». Testé.

### Saturation

| Signal | Part des échantillons \|s\| ≥ 32 760 | Lecture |
| --- | --- | --- |
| Bruit à amplitude 0,4 | **0,0** | pas de saturation |
| Le même bruit multiplié par 8 puis écrêté | **0,6898958333333334** (pic 32 768) | saturation **sûre** (seuil 0,10) |
| Sinus 1 kHz à pleine échelle | **0,041666666666666664** | **pas** sûr (sous 0,10, au-dessus du gris 0,02 → incertain) |

Le diagnostic n'allume pas « voix claire » tout seul.

### Règles de métadonnées (sans PCM)

Déjà là en 105, gardées, et doublées d'un correctif nommé :

- AAC + décodeur de box + sortie ≤ 24 kHz → cause **sûre** `decodeur_sans_sbr`. Correctif : `NativeVideoView.preferFfmpegFor` + `FfmpegAudioRenderer`. Réglage `zuno.audio.fix.ffmpeg`, défaut coupé.
- AAC + box + entrée ≥ 2 voies + sortie mono → cause **sûre** `stereo_perdue`. Même correctif, même réglage.
- FFmpeg qui sort à 48 kHz stéréo → **pas** accusé. Test de 105 toujours vert.
- `AudioFixes.forceBoxAfterOpen(false, true)` reste `true`. Le repli box ne bouge pas tant que le réglage est coupé.

## PAS PROUVÉ (vraie box, vraies chaînes)

Aucune box, aucune chaîne IPTV, aucun HDMI n'a été mesuré ici.

- On n'a pas entendu le son « dans une boîte » sur un flux réel, ni vérifié qu'un HE-AAC de fournisseur sort vraiment à 24 kHz sur une puce Amlogic (ou une autre).
- On n'a pas mesuré le décalage image/son. La règle existe (≥ 200 ms = sûr, ≤ 80 ms = ignoré, entre les deux = incertain) mais le lecteur **n'envoie pas** de chiffre : inventer un écart serait une fausse certitude. `setVideoChangeFrameRateStrategy(OFF)` et `skipSilenceEnabled = false` sont déjà en place et ne sont pas modifiés.
- On n'a pas prouvé que rallumer FFmpeg répare une chaîne réelle, ni qu'il ne la laisse pas muette. Le filet des 8 s reste justement pour ça.
- Le downmix 5.1 → stéréo est un **constat** (nombre de voies), pas une preuve que c'est lui qui fait le son radio. Aucun masque de canaux n'est changé.
- La sonde, une fois allumée, ajoute une copie de tampon PCM. On n'a pas mesuré la latence ajoutée sur une box. Coupée, `onConfigure` renvoie `NOT_SET` : Media3 ne l'insère pas, comme la voix claire coupée.

### Essai simple sur une box

1. Installer l'APK de **cette** branche (pas la release `zuno-tv`).
2. Réglages → Diagnostic du son. Les deux interrupteurs doivent être **coupés**.
3. Ouvrir une chaîne qui sonne « radio » et une qui sonne normal. Revenir au diagnostic.
4. Lire les deux fiches. Noter codec, décodeur, fréquences, et si une ligne commence par `[HAUTE · CAUSE]`.
5. Si la cause sûre est `decodeur_sans_sbr` ou `stereo_perdue` : allumer **FFmpeg : réessayer**, zapper, réécouter. Si la chaîne reste sur le logo plus de 8 s, le filet doit revenir à la box tout seul. Recouper le réglage.
6. Pour le spectre : allumer **Spectre : mesuré**, rouvrir la chaîne, attendre une seconde, relire la fiche. Un pourcentage ≥ 40 % veut dire « pas un passe-bas ». Un pourcentage ≤ 12 % est **compatible** avec un passe-bas mais n'est pas, à lui seul, une preuve de bug.
7. Vérifier que la fiche ne contient ni `http` ni mot de passe.

## Symptôme → cause → correctif exact

Confiance **HAUTE** = la règle est entière et le test négatif correspondant ne s'allume pas. **INCERTAINE** = on le dit, et on ne change pas le défaut.

| Symptôme | Règle (toutes vraies) | Confiance | Cause | Correctif dans le code | Réglage |
| --- | --- | --- | --- | --- | --- |
| Sortie ≤ 24 kHz, AAC, décodeur ≠ FFmpeg, pas de passthrough | `decodeur_sans_sbr` | HAUTE | Le décodeur AAC de la box n'a pas reconstruit le SBR | `NativeVideoView.preferFfmpegFor` rend la liste `MediaCodecSelector` vide pour `audio/mp4a-latm`. `buildAudioRenderers` ajoute `FfmpegAudioRenderer` après le rendu de la box. `AudioFixes.forceBoxAfterOpen` remet `forceBoxAacDecoder` à faux **seulement** si le réglage est allumé | `zuno.audio.fix.ffmpeg` (défaut coupé) |
| Entrée ≥ 2 voies, sortie mono, AAC, décodeur de la box | `stereo_perdue` | HAUTE | Stéréo paramétrique (PS) ignorée | Même endroit : `preferFfmpegFor` / `FfmpegAudioRenderer` | le même, défaut coupé |
| FFmpeg sort aussi à ≤ 24 kHz | `ffmpeg_sortie_basse` | INCERTAINE | Flux sans SBR, ou `.so` incomplet. On n'accuse pas la box | `NativeVideoView.ffmpegAac` / `FfmpegLibrary.supportsFormat(AUDIO_AAC)`. Ne pas changer `preferFfmpegFor` | aucun |
| HE-AAC décodé par la box, sortie ≥ 32 kHz, spectre pas LARGE | `heaac_box_freq_haute` | INCERTAINE | SBR fait, ou simple rééchantillonnage | Ne pas imposer FFmpeg | aucun |
| HE-AAC box à ≥ 32 kHz **et** spectre LARGE | (la règle ci-dessus ne s'allume pas) | HAUTE que ce n'est pas un passe-bas | Les aigus au-dessus de 4 kHz sont là | Aucun | aucun |
| Énergie > 4 kHz ≥ 0,40 | `spectre_large` | HAUTE (info) | Pas un son radio par coupure de bande | `AudioSpectrum.judge`. Aucun correctif | aucun |
| Énergie > 4 kHz ≤ 0,12 | `spectre_bas` | INCERTAINE | Passe-bas **ou** parole naturellement pauvre en aigus | `AudioSpectrum.judge` / `AudioProbeProcessor`. Ne pas filtrer le son, ne pas forcer FFmpeg sur ce seul chiffre | aucun |
| Entre 0,12 et 0,40 | `spectre_incertain` | INCERTAINE | Les seuils ne sont pas franchis | Ne rien changer | aucun |
| Pas de PCM | `spectre_absent` | info | Sonde coupée (le défaut) | `AudioProbeProcessor.onConfigure` → `NOT_SET` | `zuno.audio.diag.probe` |
| 6 voies (ou plus) → 1 ou 2, pas de passthrough | `downmix` | HAUTE comme constat, pas comme cause radio | `DefaultAudioSink` mélange vers l'AudioTrack | `NativeVideoView.buildAudioSink`. **Ne pas** changer le masque | aucun |
| Piste mono et une autre a plus de voies | `piste_plus_large` | INCERTAINE | Peut être un commentaire | `onTracksChanged` + `SpokenTrackChoice.pick`. Choix manuel `selectTrack`. Ne pas changer le choix automatique | aucun |
| Piste mono, rien de plus large | `source_mono` | HAUTE | Le flux est mono | Rien dans le décodeur | aucun |
| Débit annoncé &lt; 96 kb/s | `debit_faible` | HAUTE | Limite du fournisseur | `onAudioInputFormatChanged` lit `Format.bitrate`. Ne pas ré-encoder | aucun |
| Pas AAC, entrée &lt; 32 kHz | `source_basse_freq` | HAUTE | Aigus absents dès la source | `Format.sampleRate`. Ne pas inventer d'aigus | aucun |
| ≥ 10 % d'échantillons au plafond, voix claire coupée | `saturation` | HAUTE | Écrêtage | `ClearVoiceGain.target` / `ClearVoiceProcessor.queueInput`. Le réglage **existant** `zuno.player.clear_voice.v1` baisse les pics. Ce diagnostic ne l'allume pas | aucun (nouveau) |
| Sinus pleine échelle (~4,2 %) ou voix claire déjà allumée | `saturation` | INCERTAINE | Pic normal, ou compresseur déjà au plancher 0,45 | Ne pas compresser plus | aucun |
| Coupures AudioTrack | `coupures` | HAUTE | Tampon affamé, pas un passe-bas | `AudioTrackBuffer.sized` dans `buildAudioSink`. Ne pas l'agrandir sans mesure box | aucun |
| Passthrough AC-3 / E-AC-3 / DTS | `passthrough` | info | Pas de PCM dans l'app | Ne pas forcer le décodage PCM : on perdrait l'HDMI | aucun |
| Voix claire allumée | `voix_claire` | info | Compresseur, **pas** un passe-bas | `ClearVoiceProcessor`. Ne pas la coupler au diagnostic | le réglage déjà là |
| Écart image/son fourni ≥ 200 ms | `decalage` | HAUTE | Décalage | `setVideoChangeFrameRateStrategy(OFF)` et `skipSilenceEnabled = false` sont **déjà** le défaut. Aucune mesure réelle n'est branchée | aucun |
| Écart entre 81 et 199 ms | `decalage` | INCERTAINE | Pas assez net | Ne rien changer | aucun |
| Écart ≤ 80 ms ou non mesuré | (silence) | — | Pas un défaut / pas de chiffre | — | aucun |

Codecs nommés dans le rapport : AAC-LC (`mp4a.40.2`), HE-AAC/SBR (`mp4a.40.5`), HE-AAC v2 SBR+PS (`mp4a.40.29`), AC-3, E-AC-3, MP2 (`audio/mpeg-L2`), MP3 (`audio/mpeg`).

## Fichiers touchés hors du diagnostic (le strict nécessaire)

- `lib/main_tv.dart` — range le texte déjà émis (`audioDiag`) et charge les deux préférences (défaut faux).
- `lib/features/tv/presentation/tv_settings_screen.dart` — une carte « Diagnostic du son ».
- `packages/native_video_player/lib/native_video_player.dart` — envoie les deux drapeaux à la vue, avant l'URL.
- `NativeVideoView.kt` — sonde inactive par défaut dans `setAudioProcessors`, lecture de `AudioFixes` au `setUrl` / `openCurrent`, rapport ajouté au texte déjà envoyé. `preferFfmpegFor` n'est pas modifié.

Pas de publication, pas de push sur `main`, pas de Worker, pas de release `zuno-tv` / `zuno-tv-test`, pas de signature, pas de 4K Player.
