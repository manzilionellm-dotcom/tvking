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
