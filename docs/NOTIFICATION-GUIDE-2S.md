# Notification du guide : deux secondes — 9 octobre 2026

## Mesure avant correction

PROUVÉ : la carte historique n'a pas de minuterie. Après extraction à comportement constant,
le test `le bandeau libère l’image après deux secondes` échoue à 2 000 ms :
`Expected: no matching candidates`, `Found 4 widgets with type "Text"`.
Le même test constate encore un texte à 1 999 ms.
- Commit de reproduction : `958eef5c79abdfa35e12e6d23813ed5715afe621`.
- Commande CI : `flutter test --reporter expanded`, après `flutter analyze --no-fatal-infos --no-fatal-warnings`.
- Run rouge : https://github.com/manzilionellm-dotcom/tvking/actions/runs/37947967355
- Résultat : 540 réussites, une régression reproduite, deux tests ignorés préexistants.

## Correction et contre-preuve

PROUVÉ par tests Flutter : une ligne « Programme commencé il y a 19 min »
ou « Program started 19 min ago », visible avant 2 000 ms puis retirée.
Une minuterie est attachée à la carte, et la génération du lecteur sert de clé.
Une reconstruction ne prolonge pas l'affichage. Un ancien zap ne ferme pas la nouvelle carte.
Le retour du replay ne réaffiche pas une carte expirée. La fermeture annule la minuterie.

Le résumé textuel est consultable dans le Guide ouvert par le client.
Le bandeau ne supprime pas `_missed` dans le lecteur.
Les méthodes `_loadMissed`, `_rewindMissed` et `_backToLive` restent identiques.
La lecture effective d'un replay sur une TV physique reste NON PROUVÉE par ces tests de widgets.

Repli : `RepairFlags.missedNoticeLegacy`, clé `zuno.guide.notice_legacy`.
Absent ou illisible = faux. Vrai = grand bandeau historique permanent et Guide historique.
La contre-preuve charge la clé depuis les préférences et vérifie que les textes sont
encore présents après une minute. Les tests vérifient aussi la remise à zéro.

- Correctif : `e2606b0c4666145375c436408cc1dc26c485440d`.
- PR : https://github.com/manzilionellm-dotcom/tvking/pull/105
- Run vert : https://github.com/manzilionellm-dotcom/tvking/actions/runs/37948942338
- Résultat : `01:22 +550 ~2: All tests passed!`.
- Analyse Flutter réussie ; deux suggestions `prefer_const_constructors` dans le nouveau test.
- Aucun test supprimé ni assertion assouplie. Le premier test conserve les mêmes bornes et assertions ;
  son hôte MaterialApp reçoit les délégués de traduction nécessaires au nouveau texte.

Recherche du même motif : le lecteur mobile, le lecteur VOD TV et le lecteur
d'enregistrement n'affichent pas cette carte du guide. Les contrôles VOD disposent
déjà d'une minuterie distincte de cinq secondes ; elle est conservée.

## Livraison et essai physique

Construction demandée par le workflow existant de la PR de preuve #102 :
`build-zuno-tv.yml`, `test_box=true`, `publish=false`, `play_aab=false`.
Run : https://github.com/manzilionellm-dotcom/tvking/actions/runs/37949476085

PROUVÉ : construction Android réussie le 9 octobre 2026 à 15:22 UTC.
Le contrôle intégré au build confirme de nouveau `+550 ~2: All tests passed!`.
- Version : `107-test.125`, code Android `1791558880`.
- APK : 54 815 714 octets, asset GitHub `625347338`.
- SHA-256 : `8ae166925374fad696a99108cb911e0531da0c37f7ad7bebd0b3b7ba280a7edb`.
- Téléchargement : https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv-test/zuno-tv.apk
- Le canal de test et son manifeste ont été mis à jour. Les métadonnées de la
  release clients `zuno-tv`, relues avant et après, sont identiques.
- Aucun nouvel AAB : le build demandé cible uniquement la box de test.

NON PROUVÉ : installation sur SHIELD, disparition visible sur la TV et ligne
de boîte noire réelle. Aucune SHIELD n'est connectée à cet environnement.
Après installation de l'APK de test, ouvrir une chaîne dont le guide indique
un programme commencé depuis au moins trois minutes. Attendre deux secondes,
ouvrir le Guide, puis vérifier la boîte noire :
`[GUIDE] notification masquée après N ms`.
N est mesuré au chronomètre monotone sur la box ; les timers virtuels du test
Flutter ne sont pas une mesure de latence matérielle.
Aucune publication clients ni modification du Worker/panel dans cette correction.

