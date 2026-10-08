# Audit mobile avant mise à jour Play — 8 octobre 2026

La mise à jour concerne com.manzilionellm.tvking, application Play 4972286457582978602. Les clients Zuno TV et phone-latest sont hors publication. La publication gérée est déjà activée dans Play ; conserver ce verrou.

## Mesure avant correction

PROUVÉ : la page Production affiche 7 ANR perçues par utilisateur sur 1721 (0.3.4). Une trace est nommée « _bucketOfCategory — Input dispatching timed out » ; une autre « _LinkedHashMapMixin.putIfAbsent ». Des traces String::Concat et IrregexpInterpreter sont également présentes. Détail relu : Samsung Galaxy A14, Android 15, thread principal ; pile _bucketOfCategory → _CategoryBrowserViewState._buildCategoryList → build. Les taux agrégés indisponibles ne permettent pas de déduire zéro incident.

PROUVÉ (code préparé avant correction) : CategoryBrowserView._bucketOfCategory parcourt les genres de la catégorie dans build ; _computeTop parcourt aussi le bassin. Channel.genre, country, quality et cleanName remplissent leurs maps au premier accès avec les vrais classifiers/TitleCurator. Ce travail reste sur le fil de l’écran dans la base mobile 37fdf3305c5de9d35e20fd6567df38008fc7a7ee et son patch Sport précédent. Une mémoïsation ne déplace pas le premier calcul. Le réchauffement du cache de recherche présentait le même chemin froid.

NON PROUVÉ : la reconstruction exacte des sept sessions 1721, leurs listes et appareils. La concordance trace/code identifie un chemin bloquant, sans attribuer tous les incidents à une seule cause ni promettre leur disparition.

## Correctif minimal isolé au téléphone

Préparer réellement les quatre métadonnées via Flutter compute avant l’émission du repository. Ne transmettre à l’isolate que id, nom et catégorie, aucune adresse de flux. Installer les maps en une opération synchrone avant les événements. Chaque nouvelle émission et suppression invalide la révision précédente : un ancien calcul ne peut remettre une liste effacée. Les valeurs des chaînes restantes restent chaudes pendant la suppression. Une exception de préparation est journalisée avec un code constant et un compteur, puis propagée ; aucun retour silencieux au calcul bloquant.

Interrupteur persistant dans le patch mobile : zuno.mobile.channel_metadata_legacy, false par défaut. true reprend l’ancienne livraison avec calcul paresseux et vidage ancien. Le constructeur applique ce patch uniquement à la base mobile épinglée ; aucun changement du comportement de la box.

## Preuves prévues

- channel_metadata_isolate_test.dart : vrais classifiers, vrai isolate ; 50 000 chaînes, un événement Timer arrive avant la fin du calcul ; résultats identiques et renouvellement d’un identifiant.
- mobile_metadata_delivery_test.dart : vraie base SQLite FFI et vrai schéma de production ; toutes les valeurs prêtes à l’émission, repli persistant, suppression pendant le vrai calcul, lecture plus récente. Aucune requête ni préparation simulée.
- Même assertion « livraison : chaque chaîne émise arrive déjà classée », rejouée avec METADATA_LEGACY_PROOF=true. La CI exige précisément Expected: true / Actual: <false> et le message du contrat ; un échec de compilation ou de SQLite ne constitue pas cette preuve.
- Suite Flutter entière en mode réparé et contrôles natifs APK/AAB, sans relâcher les assertions précédentes.

NON PROUVÉ à la rédaction : exécution de ces nouveaux tests, nouveau build et essai sur téléphone réel. La CI suivante doit compléter ce rapport. L’ancien bundle #106 est validé nativement, mais ne contient pas ce nouveau correctif.


## Première preuve CI du correctif

PROUVÉ : Quality #110, run 37783987885, commit 1397d65c442d290567ff64ec73c432e6df7b2759. Le job mobile 113338549064 termine l’étape « Analyse et vrais tests du téléphone » avec success à 13:37:49 UTC. Cette étape exige d’abord l’échec précis du même test en repli réel, puis exécute la suite Flutter entière en mode réparé. Le constructeur passe ensuite à son unique compilation APK. Le code Play 1723 distingue cette réparation de la compilation parallèle précédente réservant 1722.

PROUVÉ (séparation du Store) : le constructeur passe PLAY_BUILD=true au bundle. UpdateService.checkDetailed retourne avant toute recherche d’APK externe lorsque kIsPlayBuild est vrai ; prepare_play retire REQUEST_INSTALL_PACKAGES. La mise à jour du client Store reste donc confiée à Google Play.

NON PROUVÉ à ce stade : nouveau binaire signé livré, import 1723 et essai sur téléphone physique. Les journaux finaux de la CI doivent encore donner les lignes de tests et contrôles natifs.


## Résultat final de cette exécution

PROUVÉ : le même test de livraison échoue avec le repli réel (13:35:42 UTC), puis `01:52 +1469 ~36: All tests passed!` à 13:37:49 UTC. Le job 113338549064 et tout Quality #110 sont verts. Les assertions et les classifiers ne sont pas simulés ni assouplis.

PROUVÉ : bundle Play 1723 / 0.3.5, 129 155 633 octets ; SHA-256 bcd408e255302d76394058298db7798ef63123b60ecacb994ae32da470aa3b36. Package, minSdk 24, targetSdk 36, récepteur privé, WAV, signature, ELF et ZIP 16 Ko sont contrôlés. Rapport réel de l’APK universel : goal_sound:true, scheduled_receiver:true, native_libraries_checked:32, errors:[]. L’artefact téléchargé et l’asset de la release test ont le même digest.

PROUVÉ : Google a accepté l’import 1723. La release 0.3.5 contient seulement ce bundle ; notes FR/EN sauvegardées. Six changements envoyés, console passée à « Modifications en cours d’examen », vérifications rapides en cours et publication gérée activée. Le bundle précédent est retiré de la release, récupérable dans la bibliothèque d’artefacts. Aucun déploiement clients effectué par cette action.

NON PROUVÉ : accord Google, publication réelle et essai sur téléphone. Il faut vérifier un gros import et la navigation, puis Cast et une alerte suivie sur un appareil physique. La concordance code/trace et les tests ne permettent pas d’affirmer que les sept ANR historiques ont toutes la même cause ni qu’il n’en restera aucune.

Preuves :

- https://github.com/manzilionellm-dotcom/tvking/actions/runs/37783987885
- APK mobile de test : https://github.com/manzilionellm-dotcom/tvking/releases/download/7motion-test/7motion.apk
- Console observée : https://play.google.com/console/u/0/developers/6790957789570734722/app/4972286457582978602/publishing
