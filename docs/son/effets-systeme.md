# Effets système — son « vieille radio » / « comme un appel »

Angle : ce qui peut colorer le son **après** l'AudioTrack. Dolby Atmos, Adapt Sound, égaliseur, graves, virtualiseur, effets du mixage (session 0), effets collés à la session de Zuno, et la politique audio du fabricant.

Rien n'a été entendu ici. Rien n'est « réparé ». Le son par défaut ne change pas : l'app ne crée aucun effet, et il n'y a pas d'interrupteur nouveau. Lire le catalogue ne branche rien.

## PROUVÉ

### 1. Zuno demande un son « film », et n'attache aucun effet

Lu dans `NativeVideoView.movieAudioAttributes` : usage `USAGE_MEDIA`, contenu `CONTENT_TYPE_MOVIE`. Le contenu devient `CONTENT_TYPE_SPEECH` seulement si « voix claire » est allumée (réglage déjà là, coupé par défaut).

La fiche disait déjà : l'app n'a branché ni égaliseur, ni `DynamicsProcessing`, ni `LoudnessEnhancer`. Aucun `new Equalizer`, `BassBoost`, `Virtualizer` ou `LoudnessEnhancer` n'a été ajouté. Le constructeur Android **créerait** le moteur sur la session s'il n'existe pas. On ne l'appelle pas.

### 2. La mise en forme de la fiche

Commande exécutée le 3 octobre 2026, dans `android-app/packages/native_video_player/logic-test` :

```
/tmp/gradle-dist/gradle-8.10.2/bin/gradle test
```

Sortie : **BUILD SUCCESSFUL**. JUnit : **146 tests, 0 échec, 0 erreur**. Les 13 tests nouveaux sont `AudioSystemEffectsTest`. Ils vérifient les phrases, pas un appareil.

Ce que ces tests montrent, sur des chiffres fictifs :

| Chiffres donnés | Phrase | Suspect |
| --- | --- | --- |
| Égaliseur installé, mode normal, 48 kHz, micro muet, spatialiseur coupé | « Égaliseur », « Présent ne veut pas dire allumé » | non |
| Nom « Dolby Audio Processing », branchement « après le mixage » | « Effet fabricant » | non : présent ≠ allumé |
| Spatialiseur activé **et** « film stéréo spatialisable oui » | la ligne le dit | oui, indice seulement |
| Spatialiseur activé mais stéréo **non** spatialisable, 5.1 oui | les deux réponses | non |
| Mode communication + micro ouvert | « mode communication », « Micro : ouvert » | oui |
| Fréquence native 16 000 Hz ou 8 000 Hz | « fréquence de téléphonie » | oui |
| Drapeau SCO | « SCO appel » | oui |
| Deux lectures, la seconde pas à nous | « une autre application » | oui |
| Catalogue pas lu / lecture ratée / liste vide | trois phrases différentes | — |

Aucune de ces lignes ne commence par `Session audio`, `Annonces :` ou `AudioTrack ` : le carnet de fiches ne les prend donc pas pour un journal à part. Un secret du type `http://` ou `password=` dans un nom d'effet est retiré par le filet déjà en place.

Le test Dart du carnet (`audio_report_book_test.dart`, le bloc effets reste dans la fiche) n'a pas été lancé : Flutter n'est pas installé sur cette machine.

### 3. Ce que l'API publique permet, et ce qu'elle refuse

Sources :

- [AudioEffect](https://developer.android.com/reference/android/media/audiofx/AudioEffect) : pour coller un effet à **une** piste, on donne l'identifiant de session de cette piste. `queryEffects()` « Query all effects available on the platform » : le **catalogue** des moteurs installés, pas ceux qui tournent. Coller un effet insert (égaliseur, graves, virtualiseur) au mixage global avec la session 0 est **déprécié**. Un effet auxiliaire, lui, se crée sur la session 0, puis il faut y envoyer la piste exprès.
- Code AOSP `AudioEffect` : créer l'objet crée le moteur dans la session s'il n'y en a pas déjà un. C'est pour ça que la fiche ne le fait pas.
- Il n'existe pas d'appel public « liste les effets déjà allumés sur la session N ». `queryPreProcessings` est caché et concerne le **micro**, pas la piste qu'on écoute. On ne s'en sert pas.

La fiche écrit donc deux choses distinctes :

1. Le numéro de session de Zuno, et la phrase : on ne liste pas les effets déjà collés, parce que les créer changerait le son.
2. Le catalogue `queryEffects` : nom, famille (égaliseur, graves, virtualiseur, annulation d'écho, Dolby si le nom le dit), branchement (dans la piste / auxiliaire / avant le micro / après le mixage), éditeur. Huit lignes maximum.

### 4. Quels effets peuvent s'appliquer à USAGE_MEDIA + contenu film

Sources AOSP :

- [audio_effects.xml](https://android.googlesource.com/platform/frameworks/av/+/d9a58d33c3/media/libeffects/data/audio_effects.xml) : le **post-traitement** se déclare par type de flux. Types valides : `music`, `ring`, `alarm`, `notification`, `voice_call`. L'exemple colle `music_post_proc` au flux `music` et `voice_post_proc` au flux `voice_call`.
- `USAGE_MEDIA` correspond au flux musique (`STREAM_MUSIC`). `USAGE_VOICE_COMMUNICATION` correspond à l'appel. Le contenu (`MOVIE`, `MUSIC`, `SPEECH`) **ne change pas** ce flux dans AOSP. La doc `AudioAttributes` dit seulement que le contenu « may be used by the audio framework » pour choisir un traitement. Un fabricant **peut** s'en servir. AOSP, lui, ne met pas un film sur le flux `voice_call`.
- [Configurer les prétraitements](https://source.android.com/docs/core/audio/implement-pre-processing) : l'annulation d'écho et la réduction de bruit se déclarent sur la **capture** `voice_communication` (le micro), pas sur la musique. Le fichier d'exemple les applique tout seul dès que quelqu'un ouvre ce micro.
- [Effets audio](https://source.android.com/docs/core/audio/audio-effects) (Android 11) : le fabricant peut coller et **allumer** un effet dès qu'une sortie ou une entrée est choisie (`deviceEffects` dans `audio_effects.xml`). Ça vise surtout l'auto, mais le même fichier existe sur un téléphone et sur une box. L'app ne voit pas ce fichier.

Donc, sur une piste Zuno (média, film, PCM stéréo) :

| Effet | Peut-il toucher cette piste sans que Zuno le demande ? |
| --- | --- |
| Post-traitement du flux `music` (souvent dynamique, volume perçu, parfois un virtualiseur ou un Dolby) | Oui, si le fabricant l'a écrit dans `audio_effects.xml`. Toutes les apps qui passent par le mélangeur musique l'ont aussi. |
| Effet collé à la **sortie** (haut-parleur, HDMI, Bluetooth) | Oui, même mécanisme `deviceEffects`. |
| Égaliseur / graves / virtualiseur en session 0 | Déprécié, mais un vieux lecteur de musique ou le réglage « effets sonores » peut encore l'avoir fait. On ne peut pas le lire sans en créer un. |
| Prétraitement micro (écho, bruit, gain auto) | Sur le micro, pas sur la musique, tant que le mode n'est pas un mode d'appel. |
| Post-traitement `voice_call` | Sur le flux appel, pas sur `USAGE_MEDIA`, **sauf** si le mode Android est passé en appel / communication et que le circuit du fabricant fait tout passer par là. |
| Spatialiseur Android (API 32) | Seulement si quatre choses sont vraies : l'appareil en a un, il est disponible pour la sortie actuelle, il est activé, et `canBeSpatialized` dit oui pour **ces** attributs et **ce** format. L'usage doit être média ou jeu. Le stéréo n'est pas toujours accepté. |

La fiche lit, sans les modifier : niveau du spatialiseur, activé oui/non, disponible oui/non, suivi de tête, « film stéréo spatialisable », « film 5.1 spatialisable ». Doc : [Spatial Audio](https://developer.android.com/media/grow/spatial-audio), [Spatializer](https://developer.android.com/reference/android/media/Spatializer).

### 5. Samsung One UI 8 / Android 16 (SM-S938B) — pages Samsung

Pages officielles lues (le libellé exact varie selon la version, Samsung le dit) :

- [Dolby Atmos ne s'applique pas](https://www.samsung.com/us/support/troubleshoot/TSG10007481/) : Réglages → Sons et vibration → Qualité et effets sonores. Dolby Atmos vaut pour le haut-parleur, l'écouteur filaire et le Bluetooth, **sauf** les Galaxy Buds : là, le menu Dolby est remplacé par **360 Audio**. Modes : **Auto** (s'ajuste selon le contenu), **Movie** (cinéma), **Music**, **Voice** (« focused on clear voice audio »).
- [Qu'est-ce que Dolby Atmos](https://www.samsung.com/ph/support/mobile-devices/what-is-dolby-atmos/) : Movie = films, séries, vidéos. Voice = rendre les voix fortes et claires. Auto = optimiser selon ce qui joue.
- [Réglages audio avancés](https://www.samsung.com/us/support/answer/ANS10003294/) et [Adapt Sound](https://www.samsung.com/latin_en/support/mobile-devices/how-to-customize-the-adapt-sound/) : Adapt Sound est un profil d'oreille (âge, ou test d'audition, de préférence au casque). [Égaliseur](https://www.samsung.com/us/support/answer/ANS10002953/) : Normal, Pop, Classic, Jazz, Rock, Custom, au même endroit. Une note de cette page limite **une** option aux Galaxy Buds branchés : on ne conclut pas que l'égaliseur du haut-parleur est toujours là, ni jamais là.

Comment un effet « voix / appel » s'allume, d'après ces pages et AOSP, sans inventer un bouton caché :

1. Quelqu'un met Dolby sur **Voice**, ou sur **Auto** (Samsung dit que Auto suit le contenu). Movie vise les films et les vidéos : Zuno se déclare justement « film ».
2. Adapt Sound est enregistré : c'est un égaliseur personnel sur le son du téléphone.
3. Le mode Android n'est plus « normal » (appel, communication). Le circuit peut alors traiter **toute** la sortie comme un appel : bande étroite, écho, réduction de bruit. La fiche « Chemin » le disait déjà. On y ajoute le micro (ouvert ou muet) et le drapeau SCO s'il est lisible.
4. Une autre app tient le micro en `VOICE_COMMUNICATION` : AOSP allume alors écho + bruit **sur le micro**. Ça ne filtre la musique que si le fabricant mélange les deux chemins. On ne le voit pas dans le catalogue : le catalogue dit seulement que le moteur existe.

One UI 8 n'a pas d'API publique lue ici qui dirait « Dolby Voice est allumé ». Le nom peut apparaître dans `queryEffects` (« Dolby », « Atmos », « SoundAlive », « Adapt Sound », « UHQ »). **Présent dans la liste ne veut pas dire allumé.**

### 6. Box Android TV

Même cadre AOSP : le post-traitement du flux `music` et les effets de sortie (HDMI) s'appliquent à toute piste `USAGE_MEDIA`, Zuno compris, **si** le fichier du fabricant les déclare. Beaucoup de box n'ont pas le menu Dolby du Galaxy. Elles ont souvent un réglage du fabricant (son surround, mode nuit, renforcement des dialogues) ou alors c'est la **TV** qui le fait sur le HDMI.

Une TV qui traite tout le PCM HDMI le ferait pour **toutes** les apps qui envoient le même PCM. Si une autre app sonne bien sur la **même** box et la **même** TV, le traitement commun de la TV n'explique pas la différence, sauf si l'autre app n'envoie pas le même signal (débit binaire Dolby au lieu de PCM, autre fréquence, piste « directe » qui saute le mélangeur).

### 7. 7 Motion (mpv) peut viser le même usage

Source publique [mpv `ao_audiotrack.c`](https://github.com/mpv-player/mpv/blob/06f4ce75/audio/out/ao_audiotrack.c) : l'AudioTrack est créé en `USAGE_MEDIA`. Le contenu est `CONTENT_TYPE_MOVIE`, ou `CONTENT_TYPE_MUSIC` si le rôle musique est posé. Zuno TV (Media3) et cette sortie mpv demandent donc le même usage, et souvent le même contenu « film ». Un post-traitement du flux musique les prend tous les deux.

On n'a pas exécuté le `.so` de 7 Motion. La sortie par défaut de media_kit a longtemps été OpenSL, pas AudioTrack (discussion media_kit, les plantages JNI). On ne sait pas laquelle tourne dans l'APK téléphone.

### 8. Ce que la fiche ajoute, sans changer le son

À chaque rapport, bloc « Effets système (lecture seule, aucun effet créé par l'app) » :

- session de Zuno (numéro, ou « pas encore connue ») ;
- catalogue `queryEffects` ;
- `AudioManager.getProperty` : `OUTPUT_SAMPLE_RATE` et `OUTPUT_FRAMES_PER_BUFFER`. La doc Android dit que ce sont la fréquence et le tampon du **chemin rapide**, pas forcément la piste média. Un 48 000 Hz ici ne prouve pas que la piste est à 48 kHz (la fiche de décodeur le dit déjà). Un 8 000 ou 16 000 Hz est marqué « fréquence de téléphonie » ;
- micro muet ou ouvert (`isMicrophoneMute`) ;
- spatialiseur, questions seulement ;
- chaque `AudioPlaybackConfiguration` : usage, contenu, drapeaux, appareil. `getAllFlags` est tenté (le bit SCO est caché). Si Android 16 le refuse, comme `getClientUid`, la fiche dit « publics seulement » ;
- « cette app », « une autre application », ou « appartenance inconnue ».

Une ligne `[INCERTAINE · INFO] effet_systeme` n'apparaît que pour un indice **lisible** : mode d'appel, 8 ou 16 kHz, spatialiseur activé qui accepte le stéréo, drapeau SCO, micro ouvert en mode d'appel, autre app en lecture. Un Dolby seulement présent dans le catalogue **ne** déclenche **pas** cette ligne. Aucun réglage n'est proposé. `sureCauses` reste vide sur ce seul indice : la conclusion ne change pas le chemin.

## HYPOTHÈSE

Classées pour **ce** symptôme (AAC-LC 48 kHz stéréo, sondes déjà d'accord, 0,9 à 3,6 % au-dessus de 4 kHz, même plainte sur la box, le Galaxy et 7 Motion, une autre app correcte). Confiance = chance que **cet** angle soit la cause, pas une note de documentation.

| # | Hypothèse | Confiance | Ce qui la soutient | Ce qui la freine |
| --- | --- | --- | --- | --- |
| 1 | Un post-traitement du flux musique (dynamique, virtualiseur, « dialogues ») est allumé sur l'appareil, après l'AudioTrack. Zuno et mpv y passent. L'autre app sort autrement (piste directe, autre usage, bitstream). | 35 % | AOSP colle ce traitement à `music` sans demander à l'app. Les sondes s'arrêtent avant. « Dans un trou » et « guerre entre deux sons » collent à un virtualiseur ou à deux traitements (Dolby + Adapt Sound) qui se superposent. | Le fichier du fabricant n'a pas été lu. Présent ≠ allumé. Sur deux appareils très différents, il faudrait le même genre de traitement des deux côtés. |
| 2 | Sur le Galaxy seulement : Dolby **Voice** ou **Auto**, ou Adapt Sound, pousse la voix et creuse le reste. Movie vise les vidéos, et Zuno dit « film ». | 40 % pour le téléphone, 5 % pour la box | Les pages Samsung décrivent Voice et Auto avec ces mots. Le symptôme « comme la musique pendant un appel » est celui d'un profil voix. | Aucune API ne dit le mode Dolby. Ça n'explique pas la box, sauf si la box a un réglage analogue (hypothèse 1). |
| 3 | Le mode Android est resté en communication, ou la fréquence native est 8 ou 16 kHz, ou un drapeau SCO est posé. | 20 % | C'est le mécanisme officiel le plus proche de « quand on t'appelle ». La fiche le nomme. | Le focus et le volume ont déjà été écartés. Si la ligne « Chemin » est « mode normal » et la fréquence 48 kHz, cette hypothèse tombe. |
| 4 | Le spatialiseur Android spatialise le stéréo et crée un creux / deux sons. | 15 % tant que la fiche n'a pas dit « activé oui » et « film stéréo spatialisable oui » | Doc : un média peut être spatialisé. | Le stéréo est souvent refusé. Le Dolby Samsung n'est pas forcément ce spatialiseur-là. |
| 5 | Une autre app joue en même temps. | 10 % | « Guerre entre deux sons ». La fiche compte les lectures. | Déjà cherché : le chevauchement de **nos** pistes a été écarté. Reste une app étrangère. |
| 6 | Pas un effet système. Le PCM est déjà celui d'une parole (les sondes l'ont dit). L'autre app **ajoute** de l'aigu, Zuno joue le signal sec. | 30 % | 0,9 à 3,6 % au-dessus de 4 kHz est normal pour de la parole, **avant** tout effet. | N'explique pas « dans un trou » si l'autre app joue le même flux sans traitement non plus. |

La 1 et la 6 peuvent être vraies ensemble : parole sèche **plus** un effet après la piste. On ne les sépare pas sans la fiche d'un vrai appareil, Dolby coupé puis rallumé.

## À VÉRIFIER SUR L'APPAREIL

APK de **cette** branche, pas une release. Le son ne change pas tout seul. Réglages → Diagnostic du son, ouvrir la chaîne qui sonne mal (France 24 ou France Info), attendre une seconde, lire le bloc « Effets système ».

Noter, mot pour mot :

1. `Session de Zuno n°…`
2. Chaque ligne du catalogue (surtout Égaliseur, Virtualiseur, Dynamique, Volume perçu, Effet fabricant, Annulation d'écho).
3. `Sortie native : … Hz` et le nombre de trames.
4. `Micro : …`
5. La ligne `Spatialiseur : …` entière.
6. `Lectures annoncées` : une seule « cette app », ou une « autre application ».
7. S'il y a une ligne `effet_systeme`.

Puis, **sans réinstaller**, dans cet ordre. Même chaîne, même volume, cinq secondes chacune. Après chaque étape, dire si le creux a disparu, et recopier seulement la ligne Spatialiseur et la ligne Micro si elles ont changé.

### Galaxy SM-S938B

1. Branchement de départ noté : haut-parleur, ou casque, ou Bluetooth. Les Buds remplacent Dolby par 360 Audio : le dire.
2. Réglages → Sons et vibration → Qualité et effets sonores.
3. Dolby Atmos **coupé**. Réécouter. Puis **Music**. Réécouter. Puis **Movie**. Réécouter. Puis **Voice**. Réécouter. Remettre le mode d'origine.
4. Adapt Sound **coupé** (s'il est là). Réécouter. Le remettre.
5. Égaliseur sur **Normal**, si le menu s'ouvre. Réécouter.
6. Laisser une autre app qui sonne bien ouverte **en silence** (pause), puis la fermer vraiment. Regarder si « Lectures annoncées » passe à 2.

Si le son devient normal **seulement** Dolby coupé ou sur Music, l'hypothèse 2 est la bonne **sur ce téléphone**. Si rien ne change, elle tombe pour cet appareil.

### Box Android TV

1. Noter HDMI, barre de son, ou haut-parleur de la box. La ligne « sortie » de la fiche doit dire la même chose.
2. Dans les réglages **de la box** : son, surround, mode nuit, dialogues, « Dolby ». Tout couper ou passer en « stéréo / PCM / aucun ». Réécouter.
3. Même chose dans les réglages **de la TV** (mode nuit, clarté des voix). Si la TV change le son de Zuno **et** celui de l'autre app de la même façon, la TV n'est pas la différence.
4. Ouvrir l'autre app sur la même chaîne, revenir à Zuno, lire « Lectures annoncées ».

### Les deux

- Si `effet_systeme` parle de mode communication, de 8 ou 16 kHz, ou de SCO : quitter toute app d'appel ou d'assistant, vérifier que « Chemin » repasse à « mode normal », réécouter.
- Si le catalogue est vide **et** le spatialiseur est « niveau aucun, activé non » **et** le mode est normal **et** il n'y a qu'une lecture : cet angle n'a rien trouvé sur cet appareil. On ne coupe rien dans Zuno pour autant.

Ne pas coller d'adresse de flux ni de mot de passe dans un retour : la fiche ne doit déjà plus en contenir.
