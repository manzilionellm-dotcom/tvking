# L1-03 — Complément des accès indirects Cast

## Portée

Ce complément protège les accès Cast ZUNO pendant le chargement ou après un
changement de profil ou de restrictions. Il accompagne le contrôle parental
de démarrage ; il n'est pas une fonction facultative. Les mécanismes de
retour arrière du lot ne permettent pas de le désactiver.

Les fichiers concernés sont `cast_manager.dart`, `zuno_cast_media.dart` et
`desktop_cast_controls.dart`. Le lecteur VOD remet également un descripteur
de média depuis `tv_vod_player_screen.dart`. Tous les nouveaux contrôles de
comportement sont conditionnés par `AppPlatform.isZuno` ; 7 MOTION conserve
ses décisions historiques.

## Autorisation conservée pendant une attente

`ZunoCastMedia` porte l'identifiant du média, l'URL exacte sélectionnée, la
source et un classement nullable. Une URL seule ne prouve ni la source ni
le classement. Un contenu VOD non classé conserve donc `null` et est refusé
en mode Enfants. Pour une chaîne, la politique normale du catalogue vérifie
également le classement, y compris son absence et le repli `other`.

Le contexte éphémère capture le profil, la révision de sa portée et la
génération des restrictions. Il ne peut être utilisé que pour ce média et
cette URL, avec les mêmes autorisations, avant et après chaque attente.
L'ancien contexte d'un lecteur ou d'une réponse réseau ne peut acquérir les
permissions d'un nouveau profil.

Les accès sans métadonnées restent possibles uniquement pour un profil
adulte prêt et sans restriction de sources. Les accès Direct et VOD connus
utilisent leur descripteur réel ; la présence dans une liste ne remplace
jamais une vérification de permission.

Le contexte valide appartient à la session Cast, pas à son widget. Quitter
le lecteur ne coupe donc pas une session autorisée. Un changement qui révoque
son droit la ferme et ne relance pas le lecteur local avec le contenu interdit.

## Tests

- `zuno_parental_cast_portable_test.dart` utilise les API du 116 pour une URL
  brute Enfants, une chaîne non classée, une réponse après révocation et le
  chemin historique de 7 MOTION.
- `zuno_parental_cast_media_test.dart` couvre VOD classée, inconnue, adulte,
  source interdite, identité de l'URL, changement de profil pendant la sonde,
  conservation d'une session valide et révocation de ses restrictions.
- `zuno_parental_cast_controls_test.dart` monte les vrais contrôles avec un
  lecteur local simulé : passation autorisée, refus d'une VOD inconnue et
  réponse de passation postérieure au changement de profil.
- `cast_parental_fixture.dart` fixe les préférences, le profil et les faux
  transports. Aucun flux externe ni donnée client n'est utilisé.

Les 18 scénarios de ce complément passent localement dans l'exécution
reconstruite du 11 novembre 2026 : 4 portables, 11 sur les métadonnées et
3 widgets. Les 4 tests portables ont été exécutés sans changement sur le
commit 116 : 3 échouent fonctionnellement (URL brute Enfants envoyée,
chaîne non classée ouverte, Play après révocation) et la conservation de
7 MOTION réussit. Le candidat fait passer ces 4 scénarios. Aucun échec ne
provient d'un symbole absent de l'ancienne version.

Les journaux locaux sont dans `evidence/recovery/cast/` hors du dépôt de
travail : `candidate-new-tests-01.log`, `baseline-portable-tests-01.log`
et `baseline-fixture-manifest-01.json`. La comparaison utilise Flutter
3.47.7 stable/Dart 3.13.5 et le même lock ; les sources de production du
témoin a4b81f sont intactes. Ces résultats sont attribués aux sources de
travail, avant le commit final, et non à une CI future.

Aucun résultat de la version locale perdue n'est réattribué au code courant.
Les workflows supplémentaires et la CI au SHA final restent requis. Il n'y
a ici aucune modification de schéma, de clé, de package, de distribution ou
de comportement commercial.

La suite Cast/Desktop complète a ensuite été exécutée avec succès :
282 tests, dont 245 existants et les 37 nouveaux scénarios L1-01/L1-03.
Aucune attente existante n'a été modifiée. Journal :
`candidate-cast-desktop-suite-01.log` dans le même dossier de preuves.

L'analyse ciblée ne signale aucune erreur et aucun nouveau diagnostic.
Les 3 avertissements et 17 informations restants existaient au 116 ; le code
de sortie 2 reste documenté dans `analysis-comparison.json`.


## Revalidation du catalogue VOD

Le complément détaillé dans `L1-03-VOD.md` ajoute un callback pur lié au média
et au classement publié. Les tests et les nombres ci-dessus décrivent les
exécutions Cast initiales ; les journaux VOD finaux et leur manifeste sont
indiqués dans ce document complémentaire. La relecture indépendante a été
menée après correction des défauts intermédiaires reproduits.

## Restauration native : portée et limite

Le 116 fermait déjà `resumed` / `resumed_at_boot` lorsqu'aucun transport local
ne possédait la session, ou lorsque le droit Adultes avait expiré. Ce traitement
reste identique : après redémarrage de Dart sans contexte local, le manager
appelle Stop puis disconnect. Il s'applique aussi à un adulte sans restriction
de sources. Le code n'invente ni le profil propriétaire ni la provenance du
média restauré. Enfants et profils à sources restreintes n'acquièrent donc
aucune autorisation implicite.

Le repli URL brute d'un adulte prêt sans restriction concerne un nouveau geste
`castTo`, pas la restauration native d'une session sans propriétaire. Une session
déjà possédée en mémoire peut reprendre si ses droits restent valides ; L1-03
ajoute la revalidation de ce contexte, sans changer l'initialisation du SDK.

Les preuves pertinentes sont :

- `zuno_cast_ownership_test.dart`, « reprise native inconnue au boot est fermée
  sans droit local » : Stop/disconnect simulés, comportement existant au 116.
- `zuno_mobile_cast_controls_test.dart`, « perte Wi-Fi puis reprise SDK : le
  mobile reste suspendu » : le transport conservé reprend sans nouvelle lecture
  locale. Ce test historique configure `CastPlatform`, pas le nouveau contrôle
  parental `AppPlatform.isZuno` ; il ne prouve pas à lui seul ce dernier chemin.
- `zuno_parental_cast_controls_test.dart` : sous les protections ZUNO, quitter
  le vrai widget après passation conserve la session autorisée.
- `zuno_parental_cast_media_test.dart` : le contexte survit au geste et permet
  pause/reprise ; une nouvelle génération de restrictions le révoque.
- `zuno_vod_catalog_lifecycle_test.dart` : trim et republication normale, y
  compris avec l'autre type indexé, conservent le Cast ; reclassement et
  ancienne sélection invalidée ne le réautorisent pas.

Ce sont des tests de logique et de widgets avec transports simulés. Ils ne
constituent pas un test de reprise de l'application sur une TV physique ni une
restauration du SDK réel après destruction du processus. Aucune nouvelle
persistance d'autorisation n'est introduite pour contourner cette limite.
