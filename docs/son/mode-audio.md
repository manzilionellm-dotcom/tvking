# Mode audio système — son « comme un appel »

Angle : est-ce qu’Android est resté en **mode communication / appel**, avec le haut-parleur d’appel ou le Bluetooth d’appel, et est-ce que ça explique le son « vieille radio », « dans un trou », « comme la musique quand on t’appelle », « guerre entre deux sons » ?

Personne n’a écouté ici. Rien n’est déclaré réparé. Le son par défaut n’est pas modifié : l’interrupteur nouveau est **coupé**.

Clé : `zuno.audio.mode.normal`. Défaut : faux.

## PROUVÉ

### 1. Notre code ne met pas Android en mode appel

Recherche dans le dépôt (`setMode`, `MODE_IN_COMMUNICATION`, `setSpeakerphoneOn`, `startBluetoothSco`, `setCommunicationDevice`, `AudioRecord`, `SpeechRecognizer.create`, `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, `USAGE_VOICE_COMMUNICATION`) avant cet ajout.

Ce qui existe vraiment :

| Endroit | Ce qu’il fait | Ce qu’il ne fait pas |
| --- | --- | --- |
| Lecteur TV (`NativeVideoView`) | Demande le focus `AUDIOFOCUS_GAIN` avec usage **musique** (`USAGE_MEDIA`) et contenu **film** (ou **parole** seulement si « voix claire » est déjà allumée, un autre réglage). Lit le mode, le haut-parleur d’appel et le Bluetooth d’appel pour la ligne « Chemin ». | N’appelle pas `setMode`, `setSpeakerphoneOn`, `startBluetoothSco`, `setCommunicationDevice`. |
| Téléphone, lecteur mpv (`video_player_screen.dart`) | Ouvre le flux. Ne règle pas `ao`. | Ne touche pas au mode Android. |
| `zuno_voice` | Au micro de la recherche : ouvre l’écran de reconnaissance **d’Android** (`RecognizerIntent`). `SpeechRecognizer` sert seulement à `isRecognitionAvailable` (une question « est-ce que ça existe ? »). | Ne crée pas de `SpeechRecognizer`, pas d’`AudioRecord`, pas de `RECORD_AUDIO`. |
| `VoiceRelayActivity` | Reçoit un texte déjà reconnu par la box, ramène Zuno, se ferme. | Pas de micro. |
| `tvking_device` | Monte ou baisse le volume **musique** d’un cran. | Pas de mode. |
| Manifestes du dépôt | Aucune permission `RECORD_AUDIO`. Aucune `MODIFY_AUDIO_SETTINGS` **avant** cet ajout. | Le micro n’est pas demandé au démarrage. |

`speech_to_text` et `audio_session` ne sont pas dans `android-app/pubspec.yaml`. Ils ne sont pas non plus dans les `pubspec.yaml` des paquets téléchargés ci-dessous.

Archives pub.dev lues le 3 octobre 2026, puis :

`rg -g '*.dart' -g '*.kt' -g '*.java' -g '*.xml' "setMode|MODE_IN_COMMUNICATION|setSpeakerphone|BluetoothSco|setCommunicationDevice|AudioRecord|SpeechRecognizer|RECORD_AUDIO|MODIFY_AUDIO|USAGE_VOICE|requestAudioFocus|opensles" /tmp/plugin-src`

Résultat : deux mentions. Aucune des deux ne change le mode audio.

- `media_kit` 1.1.11, `real.dart` vers la ligne 2548 : sur un vrai appareil (ou Android > 25), le lecteur pose **`ao = opensles`**.
- `flutter_local_notifications` 18.0.1 : des **noms** de constantes `USAGE_VOICE_COMMUNICATION`. Notre code de notifications ne les utilise pas.

Aussi lus, sans aucun de ces mots : `media_kit_video` 1.3.1, `media_kit_libs_android_video` 1.3.8, `wakelock_plus` 1.2.10, `local_auth` 2.3.0, `screen_brightness_android` 2.1.4.

mpv 0.36, `audio/out/ao_opensles.c` : le lecteur OpenSL **ne choisit pas** un type de flux (musique ou appel). Il lit seulement la latence. Ça ne prouve pas que le téléphone le mette en appel. Ça prouve qu’on ne le force pas vers la musique non plus.

### 2. Cycle de vie

| Qui | Quand ça s’ouvre | Quand ça se ferme | Si on quitte l’app |
| --- | --- | --- | --- |
| Micro de recherche | Seulement si on ouvre la recherche et que l’écoute part (`TvSearchScreen` → `VoiceCapture.listen`). Pas au démarrage. Au démarrage TV, `VoiceHotkey` branche un retour de **texte** et lit une phrase déjà là (`takePending`). Pas de micro. | La réponse de l’écran Android (`onActivityResult`) lâche notre attente. Si l’activité Zuno part, on répond « annulé ». On ne ferme pas l’écran de Google : ce n’est pas le nôtre. | L’écran de reconnaissance peut rester un moment. Nous, on n’a pas changé le mode, donc on n’a rien à remettre. |
| Focus du lecteur TV | À chaque ouverture de chaîne, si le réglage « Focus : Zuno » est le défaut. | Abandonné quand on quitte l’app (`suspend`) et à la destruction de la vue. | La lecture est **arrêtée** (volume 0, `stop`, focus rendu). Le mode Android n’est pas touché. |
| Lecteur mpv (7 Motion) | À l’ouverture d’une chaîne, d’une pub, d’un enregistrement. | `dispose` de l’écran. | `video_player_screen.dart` n’écoute pas le passage en arrière-plan. mpv peut continuer. Il ne met pas le mode communication. |
| Garde nouvelle | Seulement si l’interrupteur est **allumé**, avant de créer la sortie son. | On ne remet **pas** l’ancien mode en quittant : l’ancien mode peut être le mode communication qui fuit. On ne met jamais nous-mêmes le mode communication, donc il n’y a rien à refermer. | Le mode normal demandé reste. |

### 3. Les sondes « > 4 kHz » ne voient pas un filtre téléphone sur de la parole

Les quatre sondes copient le PCM **avant** l’AudioTrack. Un traitement du mélangeur Android (mode communication, Bluetooth d’appel, haut-parleur d’appel) est **après**. Il peut changer ce qu’on entend sans changer le pourcentage des sondes.

Commande exécutée :

`python3 android-app/ci/audio/mode_telephone.py`

Le passe-haut 4 kHz est le même Butterworth ordre 2 que `AudioSpectrum.kt`. Les filtres viennent de ffmpeg. Signaux synthétiques, 48 kHz, 1 seconde. Aucun flux.

Sortie :

```
echantillons voix 48000 bruit 48000 sr 48000
voix	butterworth>4kHz=0.003554	fft<300Hz=0.587010	fft_300_3400=0.411075	fft>4kHz=0.001910
voix_telephone_300_3400	butterworth>4kHz=0.002978	fft<300Hz=0.263679	fft_300_3400=0.736236	fft>4kHz=0.000067
voix_8kHz_remontee_48k	butterworth>4kHz=0.001662	fft<300Hz=0.588116	fft_300_3400=0.411856	fft>4kHz=0.000024
bruit_blanc	butterworth>4kHz=0.814657	fft<300Hz=0.012466	fft_300_3400=0.132948	fft>4kHz=0.828853
bruit_telephone_300_3400	butterworth>4kHz=0.189285	fft<300Hz=0.012143	fft_300_3400=0.768021	fft>4kHz=0.146515
bruit_8kHz_remontee_48k	butterworth>4kHz=0.102131	fft<300Hz=0.078830	fft_300_3400=0.839848	fft>4kHz=0.002036
```

Lecture :

- Une voix synthétique est déjà à **0,36 %** au-dessus de 4 kHz. Les fiches terrain (0,9 % à 3,6 %) sont dans la même zone. Ça ne désigne pas un bug.
- Le même son passé en bande téléphone (300–3400 Hz, ffmpeg) reste à **0,30 %**. La sonde ne change pas de classe. En revanche l’énergie **sous 300 Hz** passe de **58,7 % à 26,4 %**. C’est le creux, le son « dans un trou », et la sonde actuelle ne le mesure pas.
- La même voix ramenée de 8 kHz (Bluetooth d’appel étroit) reste à **0,17 %**. Toujours invisible pour la sonde.
- Un bruit blanc, lui, passe de **81,5 %** (large) à **10,2 %** (bas) après le 8 kHz. Le **son témoin** (moitié bruit) peut donc voir un goulot **s’il est avant la sonde**. S’il est dans le mélangeur, après la sonde, le témoin mesuré reste large pendant que le haut-parleur est sourd.

### 4. Tests de la garde

`gradle test` dans `android-app/packages/native_video_player/logic-test` : **142 tests, 0 échec**.

La garde coupée, même en mode communication, haut-parleur d’appel allumé et Bluetooth d’appel allumé : **aucune action**. Allumée : on demande le mode normal et on coupe le haut-parleur d’appel. Un vrai appel, une sonnerie ou un renvoi : on n’écrit pas. Le Bluetooth n’est jamais coupé par une action. Le cas « déjà normal, tout coupé, interrupteur coupé » ne produit pas de ligne (pour ne pas noyer les aperçus).

## HYPOTHÈSE

| Idée | Confiance | Ce qui la soutient | Ce qui la baisse |
| --- | --- | --- | --- |
| Le mélangeur Android traite le son **après** l’AudioTrack parce que le mode est communication, le haut-parleur d’appel est allumé, ou le Bluetooth d’appel est allumé. | **40 %** | Les mots du terrain collent à ce chemin. Le même défaut est sur la box (Media3), le Samsung (Android 16) et 7 Motion (mpv) : le point commun est Android, pas le décodeur. Une autre app sonne bien. Les sondes ne peuvent pas voir cet étage (prouvé ci-dessus sur un signal). | Notre code ne met **jamais** ce mode. Depuis Android 11 le mode est en principe **par application** : le mode d’une autre app ne devrait pas filtrer notre piste. Si la ligne « Chemin » dit déjà « mode normal », cette idée tombe beaucoup. |
| Sur **7 Motion seulement**, `ao=opensles` (posé par media_kit 1.1.11, pas par nous) sonne moins bien qu’AudioTrack. | **25 %** pour le téléphone, **8 %** comme cause commune avec la box | Le mainteneur de media_kit dit que le défaut est OpenSL, et que `--ao=audiotrack` change le rendu (issue 445). Notre lecteur téléphone ne remplace pas `ao`. | La box TV **n’utilise pas** mpv. Si la box a le même défaut, OpenSL n’est pas la cause commune. On ne change pas `ao` : ce n’est pas le défaut, et l’interrupteur de cette branche ne le touche pas. |
| L’écran micro laisse un mode communication après une recherche vocale. | **15 %** si le micro a été utilisé juste avant, **5 %** au froid | L’écran est celui d’Android, connu pour passer en communication le temps de l’écoute. On ne remet pas le mode nous-mêmes au retour. | On n’ouvre pas le micro au démarrage. Sans appui sur le micro, ce chemin ne part pas. |
| Notre demande de focus met le mode communication. | **5 %** | Le symptôme « pendant un appel » fait penser au focus. | Le focus demandé est musique / film, gain plein, pas un usage voix. Le volume lecteur est déjà mesuré à 1,0. |
| Bluetooth d’appel (SCO) resté allumé. | **20 %** s’il y a un casque appairé, **10 %** sinon | Le SCO est une bande étroite : exactement « vieille radio ». Les deux lecteurs passent par Android, donc les deux l’entendraient. Une autre app peut choisir un autre chemin. | On ne **démarre** jamais le SCO. On ne le coupe pas non plus (couper le casque de quelqu’un serait pire). La ligne « Chemin » le dit déjà. |

Rien de tout ça n’est tranché. La garde sert à **départager** la première idée, pas à la déclarer vraie.

## Garde-fou (coupé par défaut)

Allumé, **avant** de créer la sortie son :

- si le mode est communication (ou un mode inconnu qui n’est pas un appel) : `setMode(MODE_NORMAL)` ;
- si le haut-parleur d’appel est allumé et qu’on n’est pas en vrai appel : on le coupe ;
- on relit le mode juste après et on l’écrit.

On ne coupe pas : un vrai appel, une sonnerie, un renvoi système, le Bluetooth d’appel.

Pourquoi avant la piste : certaines puces choisissent le traitement au moment où l’AudioTrack naît. Changer le mode après ne suffit pas. Sur la box, allumer l’interrupteur pendant une chaîne **rouvre** cette chaîne. Sur le téléphone, c’est à la **prochaine** lecture (un zap).

`MODIFY_AUDIO_SETTINGS` est ajoutée au manifeste du plugin (permission normale, pas de question à l’écran). Elle ne change rien tant que l’interrupteur est coupé : le code n’appelle `setMode` que si la décision dit d’écrire.

Depuis Android 11, `setMode(MODE_NORMAL)` ne retire en principe que **notre** demande. Si un autre programme tient le mode, la ligne d’après dira « mode resté communication » ou « Android a refusé setMode ». Ça aussi est une réponse.

Ne pas allumer ça **pendant un appel WhatsApp / visio** : ce mode-là est justement « communication ». Sur une box sans appel, le risque est faible. Sur le Samsung, le faire seulement pour l’essai, puis recouper.

## À VÉRIFIER SUR L’APPAREIL

Installer l’APK de **cette** branche. Pas la release `zuno-tv`, pas `phone-latest`.

### D’abord sans allumer l’interrupteur

1. Ouvrir France 24 (ou France 2, France Info, BEIN), une chaîne qui sonne mal.
2. Lire Réglages → Boîte noire, les lignes `SON`, et la fiche Diagnostic du son.
3. Noter la ligne **« Chemin : »** (dans « Seconde 1 » … « Seconde 10 ») :
   - mode (normal / communication / appel) ;
   - haut-parleur d’appel ;
   - Bluetooth appel ;
   - flux (musique contenu film, ou appel).
4. Jouer le **son témoin** (Diagnostic du son), Spectre allumé. Noter le pourcentage de la moitié **bruit**.
   - Bruit ≥ 40 % dans la fiche, mais bruit **sourd** dans les haut-parleurs : le filtre est **après** la sonde (mélangeur, mode, TV). Cette piste reste ouverte.
   - Bruit ≤ 12 % dans la fiche : le goulot est **avant** la sonde. Le mode Android n’explique pas le chiffre. Chercher ailleurs.
5. Ne pas allumer « Mode : forcer normal » si la ligne dit déjà mode normal, haut-parleur d’appel coupé, Bluetooth appel coupé, flux musique. Dans ce cas la confiance de la piste « mode » tombe vers **10 %** (il resterait un traitement Samsung qui ne se voit pas dans `getMode()`, non mesuré ici).

S’il n’y a **pas** de ligne « Garde mode » : c’est normal. Coupée, et tout déjà normal, on se tait.

### Ensuite, seulement si l’étape 3 a montré un mode pas normal, un haut-parleur d’appel, ou pour l’essai volontaire

1. Box : Diagnostic du son → **Mode : forcer normal**. Téléphone 7 Motion : Réglages → Lecteur → **Mode audio : forcer normal**.
2. Zapper (ou rouvrir) la même chaîne. Rejouer le témoin.
3. Lire la ligne :
   - `Garde mode : allumée. on va demander le mode normal…`
   - puis `Garde mode : après écriture, mode « communication » → « normal »` **ou** `mode resté « communication »` **ou** `Android a refusé setMode`.
4. Sur le téléphone, la même phrase est dans logcat : `adb logcat | grep "Garde mode"`.
5. Comparer l’oreille **et** le témoin. On ne conclut pas sur l’oreille seule.
   - Le son devient clair **et** la ligne montre que le mode a vraiment changé : la piste monte au-dessus de **70 %**. Ce n’est toujours pas une preuve pour toutes les chaînes : refaire France 2 et le témoin.
   - La ligne dit que le mode a changé **mais** le son reste mauvais : le mode n’était pas la cause. Recouper l’interrupteur.
   - La ligne dit « resté » ou « refusé » : Android n’a pas laissé Zuno changer le mode. La piste n’est pas confirmée. Noter le mot exact.
6. Recouper l’interrupteur. Le défaut revient : on n’écrit plus.

Si la ligne « Chemin » dit **Bluetooth appel allumé**, ne pas le couper avec cette garde (elle ne le coupe pas). Le dire dans le retour : ce sera un essai à part, casque débranché, pour ne pas couper un vrai casque par erreur.
