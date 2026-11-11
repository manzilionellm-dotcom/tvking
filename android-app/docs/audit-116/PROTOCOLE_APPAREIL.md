# Protocole comparatif sur appareil — lot 1

**Mesures physiques non réalisées.** Aucun appareil physique n'est connecté à cette session. Ce protocole définit les métriques et les critères avant la comparaison ; il ne remplace pas `mesures_appareil.sh`, absent des pièces et du dépôt accessibles. `sqlite_bench.py` est également absent. Aucun résultat x86 n'est assimilé à une mesure sur box.

## Conditions communes

Comparer le build 116 exact `a4b81f7661d05866a39eeb05eec040ddbb1b7eb0` au SHA final de la PR. Utiliser Flutter 3.47.7 stable et Java 17, les mêmes dépendances effectivement verrouillées et le même matériel. Faire d'abord les mesures Flutter en **profile** sur appareil physique, puis confirmer sur l'APK release signé avec le certificat existant. Le build profile ne sert pas à prouver une mesure de l'APK release.

Consigner modèle, SoC, RAM annoncée et disponible, version Android/API, fréquence/résolution de sortie, HDR, alimentation, température, réseau, fournisseur de test, SHA source, type de build, SHA256 APK, certificat et version. Fixer langue française, profil adulte confirmé puis scénario Enfants séparé, échelle de texte 1, même disposition Phantom Black. Fixer heure et données pour les captures ; ne pas prétendre figer une horloge système de box cliente sans accord.

Utiliser un appareil de validation ou des données synthétiques dans un environnement de test. Ne jamais effacer les données d'un appareil client. Un démarrage froid signifie ici **processus arrêté puis relancé, fichiers conservés**. Aucun `pm clear`, effacement SQLite, réinstallation destructive ou remise à zéro des profils.

Catalogues : 1000 chaînes (1 source), 50000 (2×25000) et 100000 lignes enregistrées (4×25000). Le dernier conserve le plafond mémoire/chargement 50 000 ; l'avertissement décrit les lignes stockées, chargées et les objets résultants. Fixer identifiants, ordre, catégories, logos, favoris et reprises. Pour les mesures vidéo utiliser des médias de test autorisés avec durée, format, résolution, cadence et conditions réseau identiques ; aucune URL réelle dans les journaux livrés.

## Métriques et essais prévus

| Domaine | Début → fin | Échantillons par build et catalogue | Critère proposé avant mesure |
| --- | --- | --- | --- |
| Démarrage UI | lancement Android → première image Flutter utile, profil/restrictions confirmés | 30 lancements processus froid +30 reprises chaudes | médiane et p95 ne régressent pas de plus de 5 %; aucune image interdite |
| Réactivité UI | entrée télécommande/tactile → présentation de l'état attendu | 50 ouvertures Direct +50 sélections, puis5 parcours identiques de60s | p95 ne régresse pas de plus de 5 %; ordre/focus identiques |
| Première image vidéo | début natif de la session → première image native de cette session | 30 ouvertures et30 zaps par média | médiane/p95 ne régressent pas de plus de 5 %; aucun jalon synthétique compté |
| Images perdues | compteurs Media3 attribués au média/session | 5 sessions de5min par scénario | aucune augmentation reproductible hors variabilité de mesure |
| Rebufferings | transitions BUFFERING après démarrage, hors pause/seek/arrière-plan → sortie | 20 coupures réseau contrôlées +10 pauses/suspensions | compte/durée cohérents avec scénario, pas de double comptage |
| Retard au direct | valeur native disponible au point de lecture | mêmes 5 sessions, échantillons à cadence fixée | rapport séparé, valeur inconnue laissée vide, aucune comparaison d'horloges de machines différentes |
| Mémoire | PSS et heap aux mêmes jalons après stabilisation | 10 parcours identiques, mêmes caches | aucun dépassement des plafonds existants ; médiane/p95 ne régressent pas de plus de 5 % |

Ces seuils de non-régression sont des propositions de protocole et ne constituent pas une preuve de gain. Un gain sera annoncé seulement avec sa valeur mesurée, sa variabilité et les données brutes. Un résultat contradictoire provoque une investigation ciblée, jamais un changement de tampon ou de seuil protégé sans accord écrit.

## Exécution et calcul

Sur l'appareil de validation, définir avant les essais un ordre ABBA pour les builds **profile** uniquement si leur installation avec le même package et le même certificat est réalisable sans retour de version ni effacement. Les versionCodes de validation doivent alors croître et être consignés, même lorsque le SHA source revient au 116. Aucun certificat debug de remplacement n'est accepté. Sinon, conserver un ordre A puis B et déclarer cette limite de comparaison. Pour l'APK signé distribué 116, mesurer A avant la mise à jour en place vers B : ne pas désinstaller ni forcer un downgrade pour reconstituer A. Attendre la même stabilisation thermique et réseau. Marquer cache chaud/froid **observé**, sans vider le cache client. Exclure un essai seulement avec une raison consignée avant de regarder son résultat (par exemple appel système externe), conserver néanmoins sa ligne brute. Ne pas sélectionner les meilleurs essais.

Utiliser la base monotone native pour les durées vidéo. Les valeurs wall-clock, Dart et Android restent dans des colonnes séparées ; aucune soustraction entre origines non reliées. Conserver les événements de session et les compteurs disponibles, laisser les indisponibles vides. La latence des ordres du panel relève du lot 2 et n'est pas instrumentée dans ce lot.

Pour chaque groupe publier n, médiane et p95 par rang le plus proche : après tri, rang `ceil(0.95*n)` (index à partir de 1). Joindre les bruts CSV/JSON, le protocole exécuté, les exclusions justifiées, traces Flutter et captures. Colonnes minimales : appareil, RAM, API, SHA, build, SHA256APK, catalogue/source/lignes, profil, cache, démarrage, numéro essai, métrique, unité, valeur ou indisponibilité, session opaque, raison d'exclusion.

## Captures déterministes

Accueil et Direct : mêmes données synthétiques, même profil adulte confirmé, français, heure 17:00, résolution 1920×1080, DPR 1, échelletexte 1. Capturer les mêmes états/focus avant et après. Comparer les pixels RGBA, publier dimension, nombre/pourcentage de pixels différents et images originales. Vérifier séparément les nouveaux états de limite 100 000 → 50 000 et l'attente parentale : ils ne doivent pas être confondus avec une régression des états existants.

Une capture widget n'est pas une capture de l'APK sur box. Les deux niveaux de preuve doivent rester distincts.
