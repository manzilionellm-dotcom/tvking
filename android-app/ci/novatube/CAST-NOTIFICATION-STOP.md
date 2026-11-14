# Arrêt du Cast depuis la notification NOVATUBE Play

## Portée de cette correction

Base applicative : `785d11a5e09c040d8492981785788957c1ba9c08`.
L'AAB7 déjà signé n'est pas modifié par ce patch. La version, la signature,
le manifeste, les gardes de compilation et les workflows restent inchangés.

Le service était utilisé pour le maintien du relais Cast, mais son bouton
« Arrêter » fermait seulement le service et ses verrous. Il n'envoyait aucun
arrêt au relais Dart ou au transport distant. Son texte parlait également
d'audio de fond, même pendant une diffusion vers un écran.

## Chemin de l'arrêt utilisateur

1. CastManager crée un jeton aléatoire de 128 bits pour la révision de session
   qui utilise réellement le relais. Les mises à jour de la même session
   réutilisent ce jeton ; une nouvelle session en reçoit un nouveau.
2. PipService mémorise le callback avant d'envoyer le démarrage natif.
3. NovatubeActivity fournit un ResultReceiver privé au service explicite non
   exporté. Sa classe ne retient pas l'Activity ; le canal courant est faible
   et peut être remplacé lors d'une recréation. Aucun broadcast public.
4. La notification Cast utilise ACTION_STOP_CAST, distincte de ACTION_STOP.
   L'identité du PendingIntent immuable comprend le jeton dans son URI data,
   car les seuls extras ne distinguent pas deux PendingIntent.
5. Le service vérifie son propriétaire avant tout effet. Il retire le FGS,
   libère les verrous et transmet une fois le jeton par le ResultReceiver.
6. PipService consomme le callback correspondant avant await. CastManager
   revérifie jeton et révision, puis appelle disconnectIfOwned : retrait du
   relais, arrêt du watchdog et Stop du transport par les chemins existants.

L'arrêt programmatique ACTION_STOP n'émet aucun événement natif→Dart.
Il porte aussi le jeton pour qu'une ancienne fermeture ne puisse pas arrêter
le FGS d'une nouvelle session. Une demande audio sans jeton ne possède pas
une notification Cast active.

La réponse tardive de POST_NOTIFICATIONS est revérifiée contre la même
révision et le même jeton avant toute republication. La petite politique
native conserve aussi le dernier arrêt utilisateur afin de rejeter un START
de permission déjà en route lorsque le service s'arrête.

## Compatibilité et texte

Les noms de méthodes startBackgroundAudio / stopBackgroundAudio ne changent
pas. Les paramètres nouveaux sont optionnels et ignorés par les anciennes
activités. Le signal utilisateur et le nouveau mode de notification natif
sont activés uniquement par BuildConfig.NOVATUBE_PLAY. Aucun fichier natif
ZUNO, overlay partagé ou autre package n'est modifié.

Sans paramètres Cast, le texte et le canal audio existants sont conservés.
En mode Cast, le corps utilise la traduction existante « Cast en cours sur »
avec le vrai nom du récepteur, et l'action « Arrêter le cast ». Le canal Cast
est séparé du canal audio ; l'identifiant de notification reste 1002 et le type
du service reste mediaPlayback.

La fin d'une session utilise la même restitution au lecteur local que
l'arrêt UI existant. En arrière-plan, NativeVideoView refuse déjà toute
réouverture réseau via AppForeground ; cette logique n'est pas modifiée.

## Validation locale et limites

- 42 tests JVM réussis : les 36 tests natifs existants et 6 cas de propriété/
  course du nouveau PlaybackStopSession, via les JAR Kotlin/JUnit déjà
  épinglés et le runner existant. Ce sont des tests de logique pure.
- 5 tests Flutter ajoutés pour le protocole audio historique, la consommation
  unique du callback, les messages anciens/malformés, l'arrêt interne
  silencieux et le vrai chemin disconnect de CastManager avec transport
  simulé, y compris une permission accordée trop tard.
- Les tests Flutter ne sont pas exécutés localement : aucun SDK Flutter/Dart
  n'est disponible dans cet environnement. Le workflow existant devra les
  exécuter avant la construction du prochain AAB.
- Aucune compilation Android, installation, publication ou nouvelle preuve
  d'exécution réelle n'est revendiquée par ces tests unitaires.

Après une compilation revue du prochain AAB, vérifier réellement le bouton
de notification pendant un relais actif : fin du trafic de ce relais,
disparition du service 1002 et arrêt du récepteur. Les bancs verrouillés sur
l'AAB7 continuent de prouver uniquement le binaire 7 jusqu'à leur nouvel
épinglage explicite sur un binaire vérifié.

## Références de plateforme

- https://developer.android.com/reference/android/app/PendingIntent
- https://developer.android.com/reference/android/os/ResultReceiver
- https://developer.android.com/develop/background-work/services/fgs/stop-fgs
