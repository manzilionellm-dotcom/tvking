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
- Les sondes, une fois allumées, ajoutent une copie de tampon PCM chacune (quatre copies). On n'a pas mesuré la latence ajoutée sur une box. Coupées, `onConfigure` renvoie `NOT_SET` : Media3 ne les insère pas, comme la voix claire coupée. Voix claire coupée, silences non sautés, Sonic inactif : la chaîne active est vide, le PCM va à l'AudioTrack comme avant.

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
| FFmpeg, AAC, sortie ≥ 32 kHz, spectre bas sur toutes les voies | `ffmpeg_essai_box` | INCERTAINE | Parole, ou FFmpeg sans les aigus que la box aurait | `AudioFixes.ffmpegForAac` : liste MediaCodec AAC normale. Défaut inchangé (FFmpeg) | `zuno.audio.fix.platform` (défaut coupé) |
| Mélange bas, une voie ≥ 0,40 | `spectre_annulation` | HAUTE (info) | Les aigus s'annulent dans le mélange | `AudioSpectrum.effectiveBand`. Ne pas changer le décodeur | aucun |
| Sonde décodeur LARGE, une sonde suivante BASSE ou MILIEU | `etage_coupe` | HAUTE | Le processeur entre ces deux sondes a baissé la bande | `AudioStages.firstDrop`. Voix claire : la couper à la main et remesurer. Silence : `skipSilenceEnabled` est déjà faux. AudioTrack : Sonic, vitesse déjà 1,0. On ne change pas le décodeur | aucun |
| Les sondes disent la même bande basse | `etages_pareils` | INCERTAINE (info) | Le PCM du décodeur est déjà bas. Les processeurs d'après ne l'ont pas baissé | `AudioStages.sameBand`. Ne pas changer le défaut. L'essai box reste `zuno.audio.fix.platform` | aucun |
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
- `NativeVideoView.kt` — quatre sondes inactives par défaut dans `ZunoAudioChain` (`setAudioProcessorChain`), lecture de `AudioFixes` au `setUrl` / `openCurrent`, rapport ajouté au texte déjà envoyé. `preferFfmpegFor` n'est pas modifié.

Pas de publication, pas de push sur `main`, pas de Worker, pas de release `zuno-tv` / `zuno-tv-test`, pas de signature, pas de 4K Player.

## Fiche France 24 (box de Lionel, 1er octobre 2026)

AAC-LC, 48 kHz, 2 voies, décodeur `ffmpegLavc60.3.100-aac`, sortie PCM 16 bits 48 kHz stéréo, énergie > 4 kHz = **2,0 %** (`spectre_bas`). Quatre chaînes sonnent « vieille radio » dans Zuno et bien dans une autre app, même source. Le défaut n'est donc pas « le fournisseur n'a pas d'aigus » au sens où l'autre app les rend. La fiche ne dit pas encore **quelle étape** de Zuno les enlève.

### Ce que la chaîne fait vraiment

Ordre Media3 1.5.1 (`DefaultAudioSink.configure`), PCM :

1. Décodeur. Pour l'AAC, `preferFfmpegFor` vide la liste `MediaCodec` : FFmpeg (`org.jellyfin.media3:media3-ffmpeg-decoder:1.5.0+1`, lavc 60.3 / FFmpeg 6.0) décode. Une app ExoPlayer par défaut laisse le décodeur de la box. C'est la seule différence de décodeur.
2. `ToInt16PcmAudioProcessor` si le décodeur sort du flottant. Ici la sortie annoncée est déjà du 16 bits (`enableFloatOutput` faux, `FfmpegAudioRenderer.shouldOutputFloat` préfère le 16 bits).
3. `ChannelMappingAudioProcessor` (remap, pas un filtre) puis `TrimmingAudioProcessor`.
4. Chaîne de l'app, `ZunoAudioChain` (même ordre que `DefaultAudioProcessorChain`, plus les sondes). Chaque sonde renvoie `NOT_SET` tant que `zuno.audio.diag.probe` est coupé : Media3 ne l'active pas.
   - sonde `decodeur` — premier PCM que l'app peut mesurer ;
   - `ClearVoiceProcessor` (`NOT_SET` si coupé, le défaut) ;
   - sonde `voix_claire` ;
   - `SilenceSkippingAudioProcessor` (`skipSilenceEnabled = false`, inactif) ;
   - sonde `silence` ;
   - `SonicAudioProcessor` (inactif si vitesse 1,0, hauteur 1,0 et même fréquence ; le direct est figé à 1,0) ;
   - sonde `audiotrack` — dernier PCM avant l'écriture dans l'AudioTrack.
5. `AudioTrack` PCM. Pas de `DynamicsProcessing`, pas d'`Equalizer`, pas de `LoudnessEnhancer` dans le code. Contenu audio `MOVIE` (ou `SPEECH` seulement si voix claire).

La fiche à 2,0 % a été prise par **une seule** sonde, placée après la voix claire et **avant** Sonic. Sonic n'explique donc pas ce 2,0 %. Avec les quatre sondes, la prochaine fiche dira si le chiffre est déjà là à `decodeur` ou s'il baisse plus loin.

`ClearVoiceGain` sous le seuil 0,40 rend un gain 1 : aucun échantillon ne change. Au-dessus, c'est un gain, pas un passe-bas.

### PROUVÉ (machine, 1er octobre 2026)

Même passe-haut que la sonde.

| Signal | Rapport | Lecture |
| --- | --- | --- |
| Bruit blanc 48 kHz, amplitude 0,4 | 0,8190706717706194 | LARGE |
| Le même, quantifié 16 bits | 0,8190705800818493 | LARGE (la conversion n'enlève rien) |
| Le même, gain « voix claire » au seuil (gain 1) | identique | LARGE |
| Le même encodé AAC-LC 128 kb/s puis décodé par FFmpeg 6.1.1 (`pcm_s16le`) | **0,7227955719029436** | LARGE |
| Le même encodé AAC-LC **64 kb/s** (le codeur coupe la bande) | 0,0016263204915718422 | BASSE — le codeur, pas un filtre Zuno. L'autre app entendrait la même chose |
| Harmoniques de voix, rien au-dessus de 3,2 kHz (logic-test) | 0,002921714190980977 | BASSE sans aucun filtre |
| Bruit 48 kHz, copie PCM puis gain 1 (logic-test, même échantillons) | 0,8194908451579801 avant, copie et gain identiques | LARGE. Le passe-bas 3,4 kHz du même bruit : 0,07888762097263485 |

Donc : **la chaîne PCM par défaut (copie, gain 1, entier 16 bits) ne fabrique pas un 2 % à partir d'un large bande.** FFmpeg AAC-LC à 128 kb/s non plus. Un 2 % est le chiffre d'une voix, ou d'un flux déjà coupé avant le décodeur, ou d'un décodeur qui n'a pas reconstruit le SBR. Ces trois-là donnent le même pourcentage. On ne les sépare pas sans un second décodeur sur la même chaîne.

L'encodeur AAC natif de cette machine ne fait pas le HE-AAC (`aac_he` refusé, pas de libfdk). On n'a pas rejoué le `.so` Jellyfin (ARM, lavc 60.3.100) : le FFmpeg du test est 6.1.1.

### PAS PROUVÉ

- Que le `.so` de la box rende un AAC-LC 48 kHz plus sourd que FFmpeg 6.1.1.
- Que ces quatre flux soient du HE-AAC étiqueté AAC-LC (SBR implicite). Le décodeur de la box (souvent Fraunhofer) le reconstruit ; FFmpeg 6.0 peut le rater quand la config dit 48 kHz. **C'est l'hypothèse, pas une preuve.**
- Que l'AudioTrack ou la TV n'ajoute pas un second traitement après la sonde. La fiche 2 % est **avant** cet étage.
- Qu'allumer le décodeur de la box répare France 24. Ça peut aussi rendre « radio » les chaînes que FFmpeg réparait (SBR ignoré par la puce). Le défaut ne change donc pas.

### Essai, coupé par défaut

`zuno.audio.fix.platform` (`AudioFixes.preferPlatformAac`, défaut faux). Allumé : au `setUrl` suivant, `AudioFixes.ffmpegForAac` laisse la liste MediaCodec AAC en place. Le MP2 reste sur FFmpeg. Si la box échoue (`onAudioCodecError` / `onAudioSinkError`), `platformAacGaveUp` revient à FFmpeg pour cette ouverture et ne renvoie pas la balle.

`ffmpegForAac(false, …)` reste vrai : le chemin v106 est inchangé tant que l'interrupteur est coupé.

### Deuxième fiche France 24 (même jour, Spectre coupé à l'affichage)

Même format : AAC-LC 48 kHz 2 voies, `ffmpegLavc60.3.100-aac`, PCM 16 bits 48 kHz 2 voies. Énergie > 4 kHz = **0,8 %** (le passage d'avant affichait 2,0 %). L'interrupteur Spectre était coupé : le 0,8 % est le chiffre **déjà enregistré**, pas une nouvelle fenêtre. France 2, fiche précédente : mêmes caractéristiques, mesure absente. La chaîne sonne bien dans une autre app.

0,8 % et 2,0 % sont tous les deux sous le seuil bas (12 %). L'ancienne sonde ne renvoyait un nouveau texte que quand la **classe** changeait : deux fois « basse », le 0,8 % pouvait rester invisible. Elle publie maintenant dès que le pourcentage arrondi change.

### Ce qui est avant ou entre le décodeur FFmpeg et l'ancienne sonde

Lu dans le code, pas rejoué sur le `.so` de la box.

- Options FFmpeg : `enableFloatOutput` est faux, donc `FfmpegAudioRenderer` demande du PCM 16 bits. Dans `ffmpeg_jni.cc` (Media3 1.5.1), le `SwrContext` de l'AAC garde **la même fréquence et le même nombre de voies** ; il ne fait que passer du flottant planaire au 16 bits entrelacé. Ce n'est pas un passe-bas à 4 kHz dans ce source. Le `.so` Jellyfin (lavc 60.3.100) n'a pas été exécuté ici.
- `ToInt16PcmAudioProcessor` : no-op si c'est déjà du 16 bits. Il est **avant** la première sonde. On ne peut pas mesurer avant lui sans remplacer `DefaultAudioSink`, ce qui changerait la lecture.
- `ChannelMappingAudioProcessor` : remap, pas un filtre. `TrimmingAudioProcessor` : enlève le délai d'encodeur, pas un passe-bas.
- Voix claire : avant l'ancienne sonde. Coupée, `NOT_SET`, absente de la chaîne active. Allumée, c'est un gain. Le test gain 1 ne change pas le rapport.
- Sonic et le saut de silence sont **après** l'ancienne sonde. Ils n'expliquent ni 2,0 % ni 0,8 %.
- Pas d'égaliseur, pas de `DynamicsProcessing`, pas de `LoudnessEnhancer`, pas d'effet Android global branché par l'app.

Donc un 0,8 % sur l'ancienne sonde est **déjà dans le PCM 16 bits du décodeur**, après ToInt16 / mapping / trim. Ça ne prouve pas encore si c'est la parole ou FFmpeg. Les quatre sondes servent à le vérifier sur la box : si les quatre pourcentages restent ~0,8 %, les processeurs après la sonde décodeur sont innocents.

### Ce que la prochaine fiche doit montrer

Le rapport écrit un pourcentage par sonde (`decodeur`, `voix_claire`, `silence`, `audiotrack`), plus les voies de la sonde décodeur. Sans les quatre chiffres, on ne tranche pas.

Pour trancher, Lionel : **allumer Spectre**, rouvrir France 24 (le chiffre du passage d'avant est effacé à l'ouverture), lire les quatre pourcentages. Puis, si les quatre sont bas, allumer **Box AAC**, zapper, rouvrir, noter le nouveau décodeur et les quatre pourcentages.

| Prochaine fiche | Conclusion |
| --- | --- |
| Les quatre sondes ~0,8 %, FFmpeg et box pareils | le contenu (parole), ou un traitement après l'AudioTrack (TV / HAL), qu'on ne mesure pas. On ne change pas le décodeur |
| `decodeur` large, une sonde plus tard basse | `etage_coupe` : l'étage nommé (voix claire, silence ou Sonic). Le décodeur n'est pas le coupable |
| FFmpeg ~0,8 % aux quatre sondes, box large (une voie ≥ 40 %) | FFmpeg n'a pas les aigus sur cette chaîne. L'essai box reste coupé par défaut |
| Mélange bas mais une voie large | `spectre_annulation`. On ne change pas le décodeur |
| Box à ≤ 24 kHz | la règle déjà sûre `decodeur_sans_sbr` : revenir à FFmpeg |

## Défaut d'état entre deux chaînes : repli AAC par chaîne (1er octobre 2026, soir)

**Indice terrain** : le son « vieille radio / mélangé » n'apparaît pas à la première ouverture ; il apparaît après beaucoup de zapping, au retour sur des chaînes déjà vues.

**Cause trouvée dans le code** (`NativeVideoView.kt`, v103 → v106) : `forceBoxAacDecoder` était un seul booléen pour tout le processus (`companion object`), mis à vrai **pour toujours** par :

1. le filet des 8 s : `ffmpegAudioActive && player.playbackState != STATE_READY` à la 8e seconde après `setUrl` — donc aussi un simple **re-tamponnage réseau** à cet instant, pas seulement « FFmpeg n'a jamais démarré » ;
2. une erreur du rendu FFmpeg (`ExoPlaybackException` TYPE_RENDERER, ex. paquet TS abîmé après une reconnexion) ;
3. une erreur de sortie son ou de décodeur pendant que FFmpeg décode.

Une fois vrai, **toutes** les chaînes AAC repassaient par le décodeur de la box : le chemin de la v98, celui qui faisait le son « vieille radio » sur cette box. Les chaînes entendues bonnes au début (FFmpeg) devenaient mauvaises au retour (box). Rien ne le disait dans la fiche. Seul « FFmpeg : réessayer » le défaisait.

**Correctif (le plus petit)** :

- `logic/AacRoute.kt` : la mémoire de repli est **par chaîne** (`url.hashCode()`, 32 entrées max, aucune adresse gardée). Une chaîne où FFmpeg a vraiment échoué reste sur la box sans attendre 8 s au retour ; les autres gardent FFmpeg.
- Le filet des 8 s ne se déclenche que si le lecteur n'a **jamais** été prêt dans la session (`readyThisSession`), plus sur un re-tamponnage.
- Chaque repli écrit une ligne « Repli : … » dans la boîte noire, avec la cause (délai de 8 s / erreur du moteur FFmpeg / erreur de la sortie son / erreur du décodeur) et le numéro du zap.
- **Interrupteur de repli** : `zuno.audio.fix.session_fallback` (Réglages → Diagnostic du son → « Repli : par chaîne / session entière »). Vrai = exactement l'ancien comportement. Faux par défaut.
- Rien d'autre ne change : chemin audio, FFmpeg par défaut pour l'AAC, sondes et essais coupés par défaut.

**Fiche** : nouvelle ligne `Cycle : zap n°… · chaîne déjà ouverte avant (…e fois) · lecteurs vivants … · décodeurs audio vivants … · AudioTrack vivants … · repli box : …` (`logic/PlayerCensus.kt`, alimenté par `onAudioDecoderInitialized/Released`, `onAudioTrackInitialized/Released`, création / `release()` du lecteur). Plus d'un vivant → « ⚠ plus d'un actif » et verdict `CHEVAUCHEMENT`.

**Cycle de vie vérifié en lecture de code** : une seule vue plein écran = un seul `ExoPlayer`, réutilisé au zap (`stop()` + `clearMediaItems()` + `setMediaItem()` + `prepare()`), libéré une fois (`released`, `release()` idempotent). Le `stop()` rend le décodeur audio et l'AudioTrack (événements Media3 comptés). Pas de cache de lecteurs ni de chaîne préchargée côté Dart. Le second lecteur légitime est la sonde de l'écran Diagnostic réseau. Les reprises (`openCurrent`) sont gardées par le jeton de session ; un seul `prepare()` à la fois (`ReconnectGate.retryPending`).

### PROUVÉ (tests exécutés, `logic-test`, 100 tests, 0 échec)

- `AacRouteTest.cinquanteZapsUnePanneSeuleLaChaineEnPanneVaSurLaBox` : 50 zaps sur 12 chaînes, une panne (délai 8 s) sur la chaîne 7 au zap 20 → au retour, la chaîne 0 reste **FFmpeg**, la chaîne 7 est **box** (cause, zap 20), **2** ouvertures en mode box seulement (les deux retours sur la 7), 1 chaîne mémorisée.
- `AacRouteTest.modeSessionEntiereReproduitLeDefautDAvant` : même scénario avec l'interrupteur « session entière » → la chaîne 0 passe à la **box** : c'est le défaut observé, reproduit.
- `PlayerCensusTest.cinquanteZapsEntreFormatsLaissentUnSeulDeChaque` : 50 zaps entre AAC-LC 48 kHz stéréo, MP2 44,1 kHz, AAC 5.1, HE-AAC 24 kHz, retour à la première → lecteurs 1, décodeurs 1, AudioTrack 1, 14e ouverture ; le test **échoue** s'il reste plus d'un vivant.
- `PlayerCensusTest.unDecodeurNonRenduEstSignale` : une fuite simulée (ancien décodeur non rendu) → « plus d'un actif ».
- `AudioDiagnosisTest.leRapportDitLeRepliBoxEtLeCycle` : la fiche affiche `REPLI : … depuis le zap n°7 (délai de 8 s)` et la ligne `Cycle`.

### PAS PROUVÉ (seulement sur la box)

- Que le repli process-wide était bien **la** cause entendue : la fiche de la version précédente ne notait pas le repli. La nouvelle version le note : si le son redevient « radio », la fiche doit montrer `repli box : ACTIF` ou `décodé par : box`. Si elle montre `FFmpeg` et `aucun` repli pendant un son mauvais, la cause est ailleurs.
- La **comparaison PCM** « sortie identique avant / après 50 zaps » demande le vrai lecteur Android : non exécutée ici.
- Les compteurs vivants sur une vraie box (les événements `onAudioTrackReleased` / `onAudioDecoderReleased` doivent bien arriver à chaque zap).

## Son « dans un trou » (comme la musique pendant un appel) : focus audio et lecture hors de l'app (1er octobre 2026, soir)

**Indice terrain** : après avoir quitté l'app (Home) puis être revenu, la voix change et sonne lointaine, « derrière une porte ». Même symptôme dans 7 MOTION téléphone (lecteur mpv, pas Media3) → la cause est dans ce que les deux ont en commun : le **focus audio Android**.

**Cause** : Media3 avec `handleAudioFocus = true` applique tout seul la « baisse » (`AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK`) demandée par une autre app ou un bip : notre son passe à **20 %** (`AudioFocusManager.VOLUME_MULTIPLIER_DUCK = 0.2`) — en aval des sondes, donc invisible dans « Points de mesure » — et ne remonte que si le système renvoie `AUDIOFOCUS_GAIN`, ce qui n'arrive pas toujours sur ces box. Le son reste à 20 % jusqu'au zap suivant (`openCurrent` redemande le focus). En arrière-plan, l'ancienne **pause** gardait décodeur, AudioTrack et focus vivants pendant que la box faisait autre chose.

**Correctif** (`NativeVideoView.kt`, `logic/AudioFocusPolicy.kt`) :
- Zuno demande le focus lui-même (`AudioFocusRequest`, `setWillPauseWhenDucked(false)`) et applique `AudioFocusPolicy` : `CAN_DUCK` → **ignoré** (jamais de baisse) ; `LOSS_TRANSIENT` → pause, reprise au `GAIN` ; `LOSS` → pause ; `GAIN` → reprise seulement si c'est nous qui avions mis en pause.
- Arrière-plan (`suspend`) : **arrêt** (volume 0, `stop()`, `clearMediaItems()`, focus rendu) au lieu d'une pause ; retour (`resume` ou `play`) : réouverture comme un zap (direct au bord du direct, film à sa position).
- Fiche / boîte noire : chaque événement de focus est écrit (« Focus audio : … »), plus « Session audio Android n°… » et « Lectures audio actives sur la box : N (…) » (`AudioManager.registerAudioPlaybackCallback`, API 26+) qui compte les sons simultanés, les nôtres compris.
- Interrupteurs de repli : `zuno.audio.focus.android` (« Focus : Android » = Media3 gère, ancien comportement) et `zuno.player.bg_pause_only` (« Hors app : pause » = ancien comportement). Faux par défaut.

### PROUVÉ (tests exécutés, `logic-test`, 104 tests, 0 échec)

- `AudioFocusPolicyTest` : la baisse demandée est ignorée (son entier) ; perte passagère → pause puis reprise au GAIN ; un GAIN sans pause de notre fait ne relance pas ; perte définitive → pause.

### PAS PROUVÉ (seulement sur la box)

- Que le ducking Media3 était bien ce que Lionel entendait : la fiche de la version précédente ne notait pas le focus. La nouvelle note chaque événement : si le son sonne « dans un trou », la boîte noire doit contenir « Focus audio : … » ou « Lectures audio actives … → deux sons en même temps » juste avant.
- Qu'Android accorde le focus à notre demande sur cette box (sinon la ligne « demande REFUSÉE » apparaît).
- La réouverture au retour (Home → app) : à vérifier qu'elle ne laisse pas d'écran noir.

## Un seul AudioTrack au zap et au retour (1er octobre 2026, suite)

**Lu dans Media3 1.5.1** (`DefaultAudioSink.flush`, appelé par `stop()`), pas rejoué sur la box : l'AudioTrack n'est pas rendu dans `stop()`. `releaseAudioTrackAsync` le programme 20 ms plus tard sur un fil unique du processus, et `onAudioTrackReleased` n'est envoyé qu'après `AudioTrack.release()`. Un `prepare()` immédiat laisse donc deux pistes. Après beaucoup de zaps, la file s'allonge. `releasePlayer` retirait en plus l'écouteur **avant** `stop()` : le rendu n'était plus compté, et la fiche pouvait rester sur `CHEVAUCHEMENT`.

**Autre état qui survivait au retour** : `ffmpegAudioActive` n'était remis à faux que dans `setUrl`, pas dans le silence. Au retour (Home), le filet des 8 s voyait encore « FFmpeg actif » et « jamais prêt », et pouvait envoyer **cette** chaîne à la box pour toujours.

**Correctif** (`logic/AudioHandoff.kt`, branché dans `NativeVideoView`) :
- On n'appelle `prepare()` que lorsque `PlayerCensus.tracksAlive()` vaut 0 (la nôtre ou celle de l'aperçu / de la sonde). Délai max 1,5 s, puis on solde le compteur et on le dit.
- `dispose` répond à Dart seulement après le rendu (ou le délai) : l'aperçu ne laisse pas une piste vivante quand le plein écran s'ouvre.
- Le silence remet `ffmpegAudioActive` à faux. Le filet des 8 s ne voit que CETTE ouverture.
- Perte de focus pendant un zap (lecteur pas encore en lecture) : pause retenue, pas de son à 20 %. Volume de lecture toujours 1. Demande déjà tenue : pas de second appel. API &lt; 26 : mêmes codes.
- Sonde Diagnostic réseau : pas lancée si `ForegroundPlayback` est verrouillé. L'aperçu était déjà coupé avant le plein écran (`releaseActive` attendu, `_start` refuse si verrouillé).
- Enregistrement : Home arrête comme le direct ; le fichier est ouvert en « vod » pour reprendre à la position.
- Interrupteur de repli : `zuno.audio.handoff.immediate` (« Passage : tout de suite »). Faux par défaut.

Lignes de boîte noire ajoutées (les anciennes restent) : `Zap : n°…`, `Zap : on attend…` / `Zap : AudioTrack précédent rendu…`, `AudioTrack rendu. Pistes encore vivantes : N`, `Focus audio : obtenu.` / `abandonné.`, `Libération : …`, `Retour : film rouvert à … ms` ou `Retour : direct rouvert au bord du direct`.

### PROUVÉ (`logic-test`, 113 tests, 0 échec)

- `AudioHandoffTest.cinquanteZapsEtDixRetoursLaissentUnSeulDeChaque` : 50 zaps (AAC-LC 48 kHz, MP2, AAC 5.1, HE-AAC 24 kHz) + 10 sorties/retours. Max 1 piste, max 1 décodeur, 1 lecteur. Volume 1,0 même si une baisse est demandée. Une panne sur la 3e chaîne ne change pas la première.
- `AudioHandoffTest.lePassageImmediatLaisseDeuxPistesCestLeReglageDeRepli` : l'interrupteur allumé reproduit le chevauchement (2 pistes).
- `AudioHandoffTest.leFiletDes8sNeVoitPasLeFfmpegDeLaChaineDavant` : drapeau remis à faux → pas de repli ; drapeau vrai et jamais prêt → repli.
- `AudioFocusPolicyTest` : demande refusée, demande en double, API ancienne = mêmes codes, GAIN qui n'arrive pas après une baisse → volume 1, perte pendant un zap → pause retenue.

### PAS PROUVÉ (seulement sur la box)

- Que l'oreille entend la même chose après 50 zaps et après Home. La boîte noire doit montrer, dans l'ordre : `Zap : n°…`, `Zap : on attend…` puis `AudioTrack précédent rendu` (ou `pas rendu à temps`), `AudioTrack rendu. Pistes encore vivantes : 0` puis `1`, `Focus audio : obtenu`, et au retour `Retour : direct rouvert au bord du direct` (ou `film rouvert à … ms`). `Lectures audio actives` ne doit pas rester à 2. `repli box` doit rester `aucun` si FFmpeg n'a pas vraiment échoué.
- L'écran noir au retour, si aucune image n'avait été copiée.
- La signature de l'APK de test : elle se fait dans GitHub Actions (`build-zuno-tv.yml`, `test_box=true`, `publish=false`), pas sur cette machine.
