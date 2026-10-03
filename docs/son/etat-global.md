# Son 10 — état global et fuites

Angle : tout ce qui **reste en mémoire** après un zap ou un retour de Home, et qui pourrait encore faire du son (ou changer le mode audio de l'appareil) à côté de la chaîne.

On n'a pas entendu la chaîne. On n'a pas « réparé » le son. Le chemin audio par défaut **ne change pas** : aucun interrupteur nouveau, aucun volume, aucun décodeur, aucun arrêt de plus au Home. Les compteurs lisent seulement.

Branche `claude/son-10-etat-global`, partie de `claude/zuno-mesures-audio` (`474969c2`).

## Ce que le compteur ajoute

Chaque source de l'app a une case, même à zéro. La ligne est collée sur la fiche Diagnostic (TV) et écrite à part sous le nom de chaîne `(sources)` (TV et téléphone). La boîte noire reçoit la même ligne, étiquette `SON`.

Sources comptées : plein écran, aperçu, film, enregistrement TV, sonde réseau, son témoin, téléphone (mpv), pub de démarrage, enregistrement téléphone, service de fond, service d'enregistrement, voix (micro).

Présences : son, ouvert (son coupé), piste gardée (pause), micro, verrou (service, pas de PCM). Un verrou **ne compte pas** comme un second son. Deux cases « son » ou « piste gardée » donnent `⚠ plusieurs sons`.

La ligne Cycle du lecteur natif ajoute `registre natif N` (vues Kotlin encore inscrites). Si N est plus de 1 : `⚠ plusieurs lecteurs inscrits`. Si on ne passe pas le nombre, la ligne d'avant ne change pas.

`codeStopsOnHome` est une table lue dans les écrans. Le compteur **ne s'en sert pas pour couper** qui que ce soit. L'observateur de Home ne fait qu'une photo.

## PROUVÉ

Commandes exécutées le 3 octobre 2026 sur cette machine. Aucune box, aucun téléphone, aucun flux.

### Tests

```
cd android-app && flutter test \
  test/features/player/audio_sources_test.dart \
  test/features/player/audio_report_book_test.dart \
  test/features/player/single_player_audio_test.dart \
  test/features/player/playback_lease_test.dart
```

Sortie : `All tests passed!` — **24** tests, **0** échec. Les 12 du compteur couvrent : la table Home, 50 zaps avec une seule source en son, l'aperçu encore en son au Home pendant que le plein écran est coupé, le téléphone non coupé par le code, la pause qui garde la piste, aperçu + plein écran = plusieurs sons, le témoin laissé ouvert, la pub encore ouverte avec le téléphone, le service de fond comme verrou, le micro encore ouvert, la fiche qui reçoit la ligne (un journal non), un silence de passage qui ne compte plus.

```
gradle -p android-app/packages/native_video_player/logic-test test
```

Les résultats XML (`logic-test/build/test-results/test/TEST-*.xml`, horodatage `2026-10-03T08:52:27`) : **20** suites, **141** tests, **0** échec, **0** ignoré. `GlobalAudioStateTest` : **8** tests, **0** échec. Ligne imprimée par le test des 50 zaps :

```
SOURCES home=[apercu] zap=50 sons=[apercu]
```

Un second passage `gradle … test --offline` a répondu `BUILD SUCCESSFUL` (`test UP-TO-DATE`) : les XML n'ont pas été recalculés.

### Ce qui n'existe pas dans le code de l'app

```
rg -n --glob '!**/build/**' \
  'MediaSession|SoundPool|TextToSpeech|ToneGenerator|audio_session|AudioEffect|DynamicsProcessing|LoudnessEnhancer|android.media.MediaPlayer' \
  android-app
```

Seules sorties : un document iOS (`docs/ios-app-store-playbook.md`) qui **propose** d'ajouter plus tard le package `audio_session` (il n'est pas dans les dépendances utilisées ici), et la phrase déjà écrite dans `AudioDiagnosis.kt` : « Pas d'égaliseur, pas de DynamicsProcessing, pas de LoudnessEnhancer. »

```
rg -n 'AudioManager.*(setMode|setSpeakerphoneOn)|setSpeakerphoneOn' android-app
```

Aucune sortie. L'app n'appelle pas `AudioManager.setMode` ni le haut-parleur forcé.

`tv_hub_screen.dart` : aucune vue `NativeVideo` ni `Player(`. L'écran d'accueil TV n'a pas de vidéo de fond. La pub de démarrage n'est montée que dans `lib/main.dart` (téléphone / 7 Motion). `lib/main_tv.dart` n'initialise pas libmpv.

Les clics d'interface passent par `HapticFeedback` (recherche, code admin). Pas de `SystemSound`, pas de `SoundPool`, pas de bip MediaPlayer.

`RecordingForegroundService` écrit le fichier avec `HttpURLConnection`. Ce n'est pas un `AudioTrack`. Le compteur le marque « verrou, pas de son ». `PlaybackForegroundService` tient un WakeLock et un WifiLock pour le mode Écouteurs. Il ne décode pas.

### Ce qui survit, prouvé en mémoire (pas sur un appareil)

| Objet | Ce que le test a vu |
| --- | --- |
| `AacRoute` | `markFailed` sur une chaîne reste après 50 autres clés. Home et zap n'appellent pas `forget`. `sessionWide` reste faux par défaut. |
| Registre Dart `ExclusiveAudio` | Si on n'appelle pas `unregister`, les deux lecteurs restent inscrits après un `claim`. |
| `PlayerCensus` | Sans `playerReleased` / `audioTrackClosed`, lecteur, décodeur et `AudioTrack` restent à 1. `overlapping` reste faux à 1. |
| Registre natif | `describe` ajoute `registre natif 2 ⚠ plusieurs lecteurs inscrits`. Sans le nombre (défaut −1), ces mots n'apparaissent pas : les fiches d'avant ne changent pas de forme. |
| Table Home | Coupés par le code (défaut) : plein écran, film, enregistrement TV. Pas coupés : aperçu, téléphone, témoin, sonde, pub, enregistrement téléphone, les deux services, la voix. |

Le plein écran TV réutilise **le même** `ExoPlayer` au zap (`tv_player_screen.dart`, commentaire « MÊME lecteur ») et au Home : `suspendForBackground` arrête et vide la liste, il ne détruit pas l'objet. Au retour, `resumeFromBackground` reprépare. Le réglage « Hors app : pause » (`backgroundPauseOnly`, défaut coupé) laisse la piste : le compteur dit alors « piste gardée ».

### Fenêtre où deux lecteurs natifs peuvent être inscrits

`TvPlayerScreen.dispose` appelle `_controller.dispose()` **sans l'attendre**. Côté Kotlin, `beginDispose` ne retire la vue du registre `owners` qu'à `finishDispose`, après la libération de l'`AudioTrack` ou au bout de `AudioHandoff.WAIT_MS` (1,5 s). Le compteur Dart tombe tout de suite. Le `registre natif` de la fiche suivante peut encore valoir 2 pendant cette fenêtre.

Avant d'ouvrir le plein écran, `tv_live_screen.dart` attend `TvLivePreview.releaseActive()`. L'aperçu ne démarre que si `ForegroundPlayback` n'est pas verrouillé. Le verrou est pris par le plein écran, le film et l'enregistrement TV, et relâché dans leur `dispose`.

La voix (`VoiceHotkey`) refuse le micro tant que `TvActivity.isBusy` est vrai (lecteur ou grille). Ce n'est pas un second film.

## HYPOTHÈSE

Confiance = à quel point le **code** dit que ça peut arriver. Pas une écoute.

1. **85 % — l'aperçu de la grille survit au Home.** `tv_live_preview.dart` et `tv_live_screen.dart` n'ont pas de `WidgetsBindingObserver`. Personne n'appelle pause ni stop sur cet ExoPlayer quand on appuie sur Home. Déclencheur : focus sur une chaîne assez longtemps pour que l'aperçu parte (environ 1,5 s), Home, retour. La fiche `(sources)` doit dire `Au dernier Home : aperçu avait encore du son.` Ça n'explique pas, à soi seul, une chaîne déjà en plein écran (lui est arrêté par défaut) ni le téléphone si le compteur téléphone dit « ouvert, son coupé ».

2. **85 % — 7 Motion ne coupe pas mpv au Home.** `video_player_screen.dart` n'observe pas le cycle de vie. Le mode Écouteurs, lui, **garde** le son exprès et allume le service de fond (ce mode n'est pas le défaut). Si au Home la ligne dit `téléphone … (son)` sans service de fond, c'est l'app qui n'a pas coupé. Si elle dit `ouvert, son coupé`, c'est Android ou mpv qui a coupé tout seul : le compteur ne l'a pas fait.

3. **40 % — deux sons pendant une courte fenêtre au zap ou au retour.** Dart tombe à 1 tout de suite ; le registre natif peut rester à 2 jusqu'à 1,5 s (`AudioHandoff`). L'aperçu ne repart qu'après son délai, donc les deux peuvent se croiser au retour sur la grille. Un essai précédent a déjà écarté le chevauchement **à l'oreille**. Ce compteur sert à le revoir sur l'appareil, pas à le déclarer cause. Le même défaut sur Media3 (box, « Zuno essai ») **et** sur mpv (7 Motion) empêche une fuite **propre à ExoPlayer** d'être la seule cause : les deux lecteurs ne partagent pas cet objet.

4. **20 % — la pub de démarrage parle encore quand une chaîne téléphone s'ouvre.** `StartupAdScreen` est non muette jusqu'à `dispose`. L'écran d'après (`SimpleHomeScreen`) ne lance pas une chaîne tout seul. Le chevauchement n'existe que si le `dispose` de la pub traîne. Le compteur le dirait : `pub` et `téléphone` en son.

5. **15 % — le micro laisse le mode communication.** `RecognizerIntent` peut changer le mode audio du système. Le raccourci voix ne part pas pendant une lecture (`TvActivity.isBusy`). Un délai de 25 s sans résultat **garde** le jeton micro jusqu'à la prochaine écoute, au cas où la boîte de dialogue tiendrait encore le mode. Ce n'est pas le chemin « j'ouvre France 2 et ça sonne radio », sauf si on a lancé la recherche vocale puis on est revenu sur la chaîne. La mesure de route existe déjà (`AudioRouteState`) ; ici on ne fait que compter le micro.

6. **10 % — son témoin + direct.** L'écran diagnostic n'est pas empilé sur le lecteur (les réglages sont une page du hub). Les deux jetons en « son » en même temps seraient un bug de navigation. La fiche le dirait `⚠ plusieurs sons`.

Déjà écarté par les essais d'avant (on ne les rejoue pas comme cause) : le décodeur (`c2.android.aac.decoder` aussi mauvais que FFmpeg), le volume baissé (lecteur à 1,0, focus tenu par Zuno), un passe-bas dans l'app (sondes PCM identiques, 0,9 à 3,6 % d'énergie au-dessus de 4 kHz).

## À VÉRIFIER SUR L'APPAREIL

Installer l'APK de **cette** branche. Pas la release `zuno-tv`, pas `phone-latest`. Ne rien publier. Laisser les interrupteurs déjà connus **coupés** (spectre, réessayer FFmpeg, Hors app : pause, mode Écouteurs).

1. **Box ou « Zuno essai », grille Direct.** Laisser le focus ~2 s sur une chaîne qui sonne mal (l'aperçu part). Home. Revenir. Réglages → Diagnostic du son. Lire la fiche dont le nom est `(sources)`, et la ligne `Sources :` en bas de la fiche de la chaîne. Attendu si le code est bien celui-ci : `Au dernier Home : aperçu avait encore du son.` La boîte noire, étiquette `SON`, a la même phrase.

2. **Plein écran de la même chaîne.** Home, retour, relire. Attendu : `Au dernier Home : aucune source avec du son` (le plein écran a été arrêté). Ligne Cycle : `registre natif 1` (ou 2 si l'ancienne piste n'est pas encore rendue). `Sons en même temps` ne doit pas rester à 2. `AudioTrack vivants` ne doit pas rester au-dessus de 1 une fois l'image revenue.

3. **Cinquante zaps, puis Home, puis retour.** Même lecture. Si `registre natif` ou `AudioTrack vivants` reste au-dessus de 1 **après** le retour stable, c'est une fuite de lecteur. Si les deux restent à 1 et que le son est toujours mauvais, une fuite de lecteur global n'est pas la cause sur cet essai.

4. **Téléphone 7 Motion.** Ouvrir une chaîne, Home, retour. Il n'y a pas d'écran Diagnostic : le fichier `audio-diag.json` (dossier support de l'app) a une fiche `(sources)`. Si `téléphone` est encore `son` sans `service de fond`, l'app n'a pas coupé mpv. Si c'est `ouvert, son coupé`, Android ou mpv a coupé. Allumer le mode Écouteurs doit montrer `service de fond (verrou, pas de son)` **et** `téléphone (son)` : c'est voulu.

5. **Son témoin**, seul, bouton de la fiche. Attendu : `son témoin 1 (son)`, les autres à 0. Arrêt : `son témoin 0`.

6. La fiche ne doit contenir ni `http` ni mot de passe. `redactAudioText` passe avant l'écriture, et la ligne `Sources :` n'a que des comptes.
