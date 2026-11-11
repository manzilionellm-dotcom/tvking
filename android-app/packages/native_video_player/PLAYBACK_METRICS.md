# Mesures natives L1-07

Cette implémentation a été réécrite après la perte de l'environnement de
travail. Les résultats des fichiers perdus ne la valident pas. Les nouveaux
résultats doivent être associés à ses nouveaux SHA et journaux.

## Activation et retour arrière

Le paquet partagé conserve `NativeVideoController.playbackMetricsEnabled =
false`. Seule l'entrée ZUNO peut l'activer après lecture de
`RepairFlags.nativeMetricsOff` (défaut false côté application). Elle fournit
`onPlaybackMetrics` et range uniquement les événements `isSummary` via
`toBlackBoxLine()` dans la boîte noire. Aucun nouveau transport n'est ajouté.
L'envoi existant de la boîte noire peut inclure ces bilans lorsque son propre
interrupteur d'envoi est actif ; cet interrupteur et ce transport sont inchangés.

Le retour arrière consiste à laisser le paquet désactivé, ou à activer le
drapeau de repli ZUNO avant l'ouverture suivante. Aucun collecteur Kotlin
n'est créé sans l'argument explicite `metricsMediaId`. Le moteur PC et
l'entrée 7 MOTION ne sont pas activés par le paquet. Aucun tampon, délai de
zap, plafond mémoire ou ordre de libération de surface n'est modifié.

## Définition des mesures

- La session commence à la réception native de la demande de média. Le
  délai comprend donc l'attente native du passage d'un lecteur à l'autre.
- La première image vient exclusivement de
  `AnalyticsListener.onRenderedFirstFrame(EventTime, Object, long)` de
  Media3 1.5.1. Sa documentation définit `renderTimeMs` sur
  `SystemClock.elapsedRealtime()`, comme le début de session. Le tag du
  média, sa génération et les bornes temporelles sont vérifiés.
- Une réouverture technique ou un nouveau décodeur conserve le premier
  jalon et la session logique. Un nouveau média, une fin, un silence pour
  un autre lecteur ou une libération ferme la session.
- Les rebufferings commencent après la première image, lors de BUFFERING
  ou d'une erreur récupérable alors que la lecture est demandée. Leur durée
  inclut l'attente de reconnexion jusqu'à READY. La pause, la recherche,
  Home, Cast et les changements manuels du moteur/contraste sont exclus.
  Le temps de session total inclut les pauses ; le temps de rebuffering les
  exclut. Ce n'est pas une mesure du temps où les pixels restent figés.
- Les pertes viennent principalement des deltas de
  `videoDecoderCounters.droppedBufferCount`, après `ensureUpdated()`. Le
  compteur présent avant le zap sert d'origine. Un décodeur nouveau ou un
  compteur réinitialisé ouvre un nouveau segment. Les notifications
  `onDroppedVideoFrames` fournissent un repli identifié lorsque le compteur
  n'a pas été observé ; les deux sources ne sont jamais additionnées.
- `currentLiveOffset` est repris tel que fourni par Media3. `TIME_UNSET`
  devient null. Ce retard est une estimation du SDK qui peut dépendre de
  l'horloge du fournisseur ; aucune soustraction avec une horloge Dart ou
  une autre machine n'est ajoutée.

Les identifiants média/contrôleur/session sont éphémères au processus. Ils
figurent dans le bilan écrit dans la boîte noire, sans être relus pour
reconnaître un appareil ou une session future. Aucun nouvel identifiant
persistant d'appareil n'est créé. Le contrat ne comporte ni URL ni titre,
mot de passe ou identifiant fournisseur. Les valeurs inconnues restent
null et sont affichées « indisponible » ; un zéro réellement observé reste
distinct.

## Fréquence, mémoire et libération

Un collecteur conserve des scalaires, une identité de compteur et une
fenêtre Media3. Il n'accumule aucune liste de trames ou d'événements. Les
lectures passives utilisent le timer de position existant (500 ms), sans
nouveau timer. Au plus une première image et un bilan sont transmis par
session. Le callback Dart n'entraîne aucune reconstruction de l'interface.

Le bilan est pris avant le retrait du listener et renvoyé aussi dans la
réponse de `dispose`, car Dart peut déjà avoir détaché son handler. Le
contrôleur déduplique les deux transports, y compris après sa fermeture.

## Vérifications nécessaires

Les tests Kotlin couvrent les horloges, générations, changements de média,
rebufferings, pauses, pertes, resets, valeurs inconnues et bornes. Les tests
widget empruntent le vrai handler MethodChannel avec un double natif et
vérifient notamment qu'un événement synthétique Dart ne produit aucune
mesure native. Ils ne remplacent pas un décodeur Android réel.

La compilation Kotlin du module Android isolé a réussi sur la référence et
sur ces nouvelles sources, avec Media3 1.5.1 réellement résolu. Avant
validation du lot restent nécessaires : compilation applicative finale,
tests pixels, compteurs sur scénarios physiques contrôlés et rapprochement
des résumés avec les événements natifs. Aucun gain de fluidité ni de temps
de démarrage n'est déduit de cette instrumentation.
