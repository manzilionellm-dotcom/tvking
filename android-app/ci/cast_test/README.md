# ZUNO — Cast sur téléphone, tablette et Windows

Cette variante répond à la demande du 20 octobre 2026 : reprendre les transports Cast de 7MOTION dans les éditions ZUNO qui envoient une vidéo, tout en gardant l'édition télévision sans interface ni découverte Cast.

## Éditions

| Entrée Flutter | Édition | Fonctions Cast proposées |
| --- | --- | --- |
| `main_tv.dart` | Télévision | Aucune interface ni découverte Cast |
| `main_zuno_mobile.dart` | Téléphone et tablette Android | Pont Google Cast de 7MOTION, DLNA et Roku |
| `main_windows.dart` | Ordinateur Windows | DLNA et Roku ; pas de SDK Chromecast Windows |
| Entrées 7MOTION existantes | Inchangées | Politique existante conservée |

La distinction vient de `ZunoEdition`, configurée avant le démarrage des services. Elle ne dépend pas de la largeur, de la densité, d'une télécommande ni de `AppPlatform.isTv`, qui reste l'identité historique du panel ZUNO. Une grande tablette conserve donc le Cast ; une édition TV redimensionnée reste sans Cast.

Le nouveau point d'entrée tactile conserve les écrans et le lecteur natif de ZUNO. Il dispose d'un lanceur Android mobile, d'une orientation libre et d'une activité distincte, `ZunoCastActivity`, qui combine les ponts Google Cast existants avec les callbacks de cycle de vie du lecteur ZUNO.

## Transfert de lecture

Le contrôle met d'abord les récupérations locales en attente, réserve la pause des téléchargements pour cette route, puis attend `NativeVideoController.suspendForCast()`. Un simple état « pause » ne prouve pas une fermeture réseau. Le natif Android attend la barrière ExoPlayer et la fermeture des sources de données suivies ; Windows attend le Stop dans la file media_kit.

Le sélecteur et les changements de chaîne portent le même jeton de propriétaire. La fermeture d'une ancienne route ne peut arrêter que sa propre tentative. Au retour local, le contrôle attend aussi la fin du Stop/nettoyage distant, vérifie qu'aucune autre session n'a pris la main et que le lecteur n'a pas été révoqué.

La recherche d'appareils est indépendante de l'état de lecture. Elle conserve une diffusion en cours, une pause ou une connexion en préparation. Une suspension temporaire du SDK ne relance pas le lecteur local.

Les changements de média survenant pendant une connexion ou une commande sont regroupés sur la dernière sélection. Le contrôleur local garde le dernier média sans l'ouvrir pendant le Cast. La reprise VOD locale utilise la position capturée seulement si la sélection n'a pas changé. La progression distante complète et la recherche temporelle du récepteur ne sont pas ajoutées par cette variante.

L'enregistrement reste incompatible avec le départ du Cast : le bouton affiche « Enregistrement en cours » et reste indisponible jusqu'à sa clôture. La commande REC ne démarre pas pendant le transfert. Aucun enregistrement n'est interrompu implicitement.

## Artefacts de test

Le workflow `zuno-cast-devices-test.yml` est réservé à la branche de travail indiquée dans son déclencheur et produit des artefacts, sans publication client.

| Artefact | Identité | Mise à jour automatique |
| --- | --- | --- |
| `zuno-cast-test.apk` | `com.sevenmotion.tv.seven_tv.casttest`, nom `Zuno Cast test`, signature debug | Désactivée ; aucun canal mobile client défini |
| `zuno-windows-cast-test.zip` | Application Windows `Zuno Cast test`, sans installeur | Désactivée par `ZUNO_CAST_TEST=true` |

L'APK est distinct du package TV. Sa préparation ne réécrit pas le `MainActivity.kt` de la télévision. Les versions de SDK sont reprises de l'overlay 7MOTION. Le workflow utilise `contents: read`, sans clé de signature client, sans secret de production et sans étape de publication.

Chaque artefact contient une provenance avec le commit compilé et son empreinte SHA-256. Pour Android, les vérifications portent sur le manifeste fusionné et les classes effectivement présentes dans l'APK : lanceur mobile, absence de Leanback, activité, permissions multicast, métadonnées Cast et ponts natifs. Pour Windows, le ZIP doit contenir l'exécutable, Flutter, l'application et libmpv.

## Vérification

Les tests automatisés utilisent des appareils et adresses fictifs. Ils couvrent les éditions, les commandes et zaps pendant transfert, les annulations, les callbacks obsolètes, les recherches pendant pause, le Stop distant attendu, la fermeture réseau native, l'attachement tardif de PlatformView et les réservations de téléchargements concurrentes.

La réussite de ces tests et de la compilation ne vaut pas une mesure sur une télévision physique. Avant une publication client mobile/PC, essayer une chaîne et un film de son propre abonnement avec le récepteur cible : connexion, pause/reprise, changement de chaîne, arrêt, retour local et passage de l'application en arrière-plan. Les appareils doivent pouvoir communiquer sur le même réseau local. Les codecs, la disponibilité du flux et les capacités du récepteur restent déterminants ; aucun transcodage ni nouveau support iOS/macOS n'est ajouté.

## Références techniques

- [Media3 Player : états de lecture et commandes](https://developer.android.com/reference/androidx/media3/common/Player)
- [Google Cast Android Sender : sessions, suspension/reprise et commandes distantes](https://developers.google.com/cast/docs/android_sender/integrate)

Ces références expliquent pourquoi la découverte, la pause, la fin de session et la fermeture du lecteur sont traitées séparément. Les résultats de compilation et les versions livrées doivent être lus dans la provenance du build concerné.
