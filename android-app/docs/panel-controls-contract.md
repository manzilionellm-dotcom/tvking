# Contrat des commandes du panel — 2 novembre 2026

Ce document distingue une écriture acceptée par le serveur, une configuration
relue par l'application et son effet visible. Un HTTP 200 ou un accusé de
réception ne prouve pas, à lui seul, que le client a vu le changement.

## Accueil : portée du port ciblé ZUNO

Le gestionnaire historique conserve huit clés. L'accueil ZUNO actuel possède
des rangées différentes : il ne faut pas réinterpréter les clés pour cacher
un accès ou inventer du contenu. Le port de ce lot conserve les cartes et
leurs actions, le contrôle parental et les tuiles Direct/Films/Séries.

| Clé du panel | Effet dans le nouvel accueil ZUNO |
| --- | --- |
| `recent` | Rangée des dernières chaînes : afficher/masquer, ordre relatif avec Favoris, ruban et étoile de vedette. |
| `favorites` | Rangée Favoris : afficher/masquer, ordre relatif avec les dernières chaînes, ruban et étoile de vedette. |
| `sport`, `entertainment`, `info`, `kids`, `general` | Pas de rangée équivalente sur cet accueil. Les réglages historiques restent enregistrés mais ne pilotent pas les catégories du Direct. |
| `cinema` | Pas d'équivalence avec la reprise d'un film. Ne masque ni les films/séries, ni leurs accès, ni leurs règles parentales. |

Les rappels, émissions suivies, recommandations et reprises de films gardent
leur ordre relatif. Sans configuration, l'accueil reste identique. Si les
deux rangées pilotées sont masquées et qu'aucun autre contenu personnel n'est
présent, les grandes tuiles restent accessibles. Une rangée masquée ne reçoit
pas le focus initial. Aucune modification ne démarre une chaîne toute seule.

Le chargement initial lit le cache puis le réseau. Les commandes `home`
relisent le même dépôt ; son écoute reconstruit les rangées. Ce comportement
nécessite le nouvel APK : une ancienne application sans consommateur de
`HomeLayoutRepository` ne change pas d'interface après une simple publication
du panel. Dans la recette 7 MOTION auditée, le navigateur de catégories n'a
pas de rendu de cette disposition ; initialiser le dépôt seul ne suffit pas.

## Correspondance des fonctions auditées

Les routes ci-dessous existent dans le bundle Gold exporté et conservé par
le candidat backend. Cela ne prouve pas que ce candidat est publié, ni que
le panel et les APK visent le même serveur en production.

| Option | Écriture panel / lecture app | Effet et limite établis lors de l'audit |
| --- | --- | --- |
| Accueil et Live Control | `/api/v1/home-layout` / `/api/home-layout` | Contrat par clé ci-dessus ; historique/restauration côté serveur. |
| Favori du jour | `/api/v1/featured` / `/api/featured` | Carte ZUNO si la chaîne recherchée existe dans la liste et si l'utilisateur laisse la carte activée. La recette mobile auditée lit la configuration mais ne possède pas cette carte dans son navigateur de catégories. |
| Thème | `/api/v1/theme?platform=…` / `/api/theme?platform=…` | ZUNO applique maintenant nom, accent et fond clair/sombre via sa palette réactive, sans recréer la navigation ni recolorer le Cast. La recette 7 MOTION conserve son fond sombre : le mode clair y reste indisponible. |
| Automatisation du thème | `/api/v1/theme/automations` / `/api/theme` | Les règles sont évaluées à la lecture, selon le calendrier UTC. Le passage d'une date ne crée pas à lui seul une nouvelle requête du client. |
| Mise à jour forcée | `/api/v1/force-update?platform=…` / `/api/app-version` | Seuil de build des installations APK compatibles. Les builds Play retournent volontairement « pas de blocage » dans ce lecteur : leur mise à jour passe par le Store. Un seuil n'est pas une nouvelle compilation ni une publication d'APK. |
| Tarifs | `/api/v1/pricing` / `/api/pricing` | ZUNO affiche les tarifs explicitement configurés à l’activation et dans les réglages ; aucune offre par défaut inventée. Les appels commerciaux externes restent masqués sur Play. Un prix affiché ne crée aucun droit payé ni achat fournisseur. |
| Applications | `/api/v1/apps` | Catalogue administratif. Créer une ligne ne construit pas une application et changer son package ne renomme pas un APK installé. Les applications n'utilisent pas ce catalogue comme source de leur thème. |

Les annonces et la publicité ont leurs propres lecteurs et présentations ;
ils sont vérifiés séparément dans ce lot. Les modules « Bannières » et
« A/B Testing » annoncés comme futurs ne deviennent pas actifs du seul fait
qu'une carte existe dans le centre de contrôle.

## Identité produit et livraison

`platform=tv` désigne ZUNO, y compris ZUNO sur téléphone. `platform=mobile`
désigne 7 MOTION. Ce champ ne décrit pas le matériel et ne doit pas être
remplacé par le type Android TV/téléphone pour sélectionner un thème ou une
politique de mise à jour.

Au début de l'audit, les apps officielles visaient `api.zuno8k.com` alors que
le panel de release conservait l'ancien `workers.dev` dans sa réécriture,
sa CSP et son URL WebSocket. Les trois chemins doivent être cohérents ;
modifier uniquement `VITE_API_BASE` ne suffit pas.

Les essais automatiques prouvent le comportement de la version testée. Ils
ne prouvent ni l'installation chez tous les clients, ni le déploiement du
Worker, ni une recette sur téléphone/TV/Cast physiques. Une fonction non
prise en charge doit être présentée comme telle, jamais comme « appliquée ».

## Preuves de ce lot

- Worker candidat : 76 tests réussis, en exécutant le véritable `gold.fetch` sur SQLite locale ; isolation des revendeurs, identité matérielle, annonces (OFF, suppression, ciblage, expiration), publicité et tarifs.
- ZUNO : 37 tests ciblés réussis sur appareils, annonces, publicité, thème, accueil et tarifs. Six tests supplémentaires exécutent les vrais handlers `message`, `ad`, `theme` : l’accusé `applied` attend la relecture et devient `failed` en cas de HTTP 503.
- Suite ZUNO complète locale : 859 réussis, 8 ignorés et 2 échecs. Les deux échecs du fichier historique `relay_upstream_reconnect_test.dart` surviennent avant la connexion à la TV simulée, lors de `NetworkInterface.list` (environnement sans interface LAN utilisable, « Bad value for ai_flags »). Le moteur Cast n’a pas été modifié. Il faut le résultat de CI et une recette physique pour conclure à une validation complète.
- Analyse Dart ZUNO : aucune erreur ; les informations et avertissements ne sont pas fatals selon la commande du workflow.
- Recette mobile : reconstruction depuis les SHA figés et 7 invariants Python réussis. Le résultat de la suite Flutter mobile est suivi séparément dans le workflow `mobile-panel-sync-tests.yml` ; les tests ZUNO ne la remplacent pas.

Les serveurs rapides du panel ne sont pas consommés par les parcours actuels : le dépôt Dart est conservé pour compatibilité historique. La demande d’avis est présente sur l’ancien accueil mobile, pas sur le parcours ZUNO TV. Les champs correspondants doivent annoncer cette portée et ne pas prétendre à une livraison universelle.

Ces preuves concernent du code candidat. Elles ne constituent pas une publication du panel, du Worker ou d’un APK chez les clients.
