# Contrat des commandes du panel — 2 novembre 2026

Ce document distingue une écriture acceptée par le serveur, une configuration
relue par l'application et son effet visible. Un HTTP 200 ou un accusé de
réception ne prouve pas, à lui seul, que le client a vu le changement.

Pour les annonces, l'accueil, le favori du jour, les tarifs et les serveurs,
un ordre strict attend la lecture déjà en cours puis démarre une nouvelle
requête HTTP après l'ordre. Il ne confirme jamais l'ancienne réponse du poll
UI. L'échec de cette nouvelle lecture produit `failed`, même si la précédente
avait réussi ; les lectures UI normales restent mutualisées.

## Accueil : huit sections dans le candidat ZUNO

Les huit clés historiques ont désormais un rendu dans l'accueil ZUNO. Les
nouvelles rangées de genres utilisent exclusivement les chaînes déjà importées
par le client. Elles n'ajoutent aucune source et ne changent pas les accès
Direct/Films/Séries, les reprises VOD ou les règles parentales.

| Clé du panel | Contenu de la rangée ZUNO |
| --- | --- |
| `recent` | Dernières chaînes regardées. |
| `favorites` | Favoris du profil courant. |
| `sport` | Chaînes en direct classées `sports`. |
| `entertainment` | Chaînes en direct classées `entertainment`, `series`, `music` ou `documentary`. |
| `info` | Chaînes en direct classées `news`. |
| `kids` | Chaînes en direct classées `kids`. |
| `general` | Chaînes en direct classées `other` ou `international`. |
| `cinema` | Chaînes en direct classées `movies`, libellées « Cinéma · Direct » ; aucun film VOD n'est substitué à une chaîne. |

Pour chacune des huit clés, le panel pilote la visibilité, l'ordre relatif,
le ruban et l'étoile de vedette. Une section vide reste absente. Les genres
réutilisent le classifieur du Direct, qui vérifie les marqueurs adultes avant
les autres genres. Les six nouvelles rangées excluent toujours les chaînes
classées adultes et les éléments non live, même hors mode enfants. Ce
classement repose sur les noms et groupes du fournisseur : il ne certifie
pas l'âge de chaque émission. Les contrôles parentaux du lecteur restent actifs.

Chaque nouvelle rangée contient au maximum huit chaînes, dans leur ordre
source, sans doublon d'identifiant. Le classement et la carte utilisent la
même occurrence live de l'identifiant : un doublon VOD ou adulte ne remplace
pas une carte sûre. Au-delà de 500 chaînes live distinctes, le classement
s'exécute dans un isolate. Un changement de source invalide le résultat
précédent pour ne pas afficher de cartes retirées.

L'ordre distant permute les emplacements des rangées pilotées présentes ;
les rappels, émissions suivies, recommandations et reprises de films gardent
leur ordre relatif. Sans configuration, les clés utilisent l'ordre par défaut.
Si toutes les rangées et cartes d'accueil sont absentes ou masquées, les
grandes tuiles de navigation restent accessibles. Une rangée masquée ne
reçoit pas le focus initial. Aucune modification ne démarre une chaîne.

Le chargement initial lit le cache puis le réseau. Les commandes `home`
relisent `HomeLayoutRepository` ; son écoute reconstruit les rangées.
**Le nouvel APK est nécessaire** : initialiser un dépôt dans une ancienne
application sans son rendu ne suffit pas. La publication du panel ne met
pas automatiquement à jour les applications installées.

## Correspondance des fonctions auditées

Les routes ci-dessous existent dans le bundle Gold exporté et conservé par
le candidat backend. Cela ne prouve pas que ce candidat est publié, ni que
le panel et les APK visent le même serveur en production.

| Option | Écriture panel / lecture app | Effet et limite établis dans le candidat |
| --- | --- | --- |
| Accueil et Live Control | `/api/v1/home-layout` / `/api/home-layout` | Huit sections ZUNO selon le contrat ci-dessus ; historique/restauration côté serveur. |
| Favori du jour | `/api/v1/featured` / `/api/featured` | Carte ZUNO si la chaîne recherchée existe dans la liste et si l'utilisateur laisse la carte activée. Aucun flux n'est créé ou démarré par le panel. |
| Thème | `/api/v1/theme?platform=…` / `/api/theme?platform=…` | ZUNO applique nom, accent et fond clair/sombre via sa palette réactive, sans recréer la navigation ni recolorer le Cast. 7 MOTION applique le thème aux surfaces accueil/catalogue/formulaires/profil/avis ; les surfaces vidéo et Cast conservent leur apparence sombre. |
| Automatisation du thème | `/api/v1/theme/automations` / `/api/theme` | Les règles sont évaluées à la lecture, selon le calendrier UTC. Le passage d'une date ne crée pas à lui seul une nouvelle requête du client. |
| Mise à jour forcée | `/api/v1/force-update?platform=…` / `/api/app-version` | Seuil de build des installations APK compatibles, lié par le candidat Worker à un manifeste du canal client exact et à un APK disponible dont la taille et le digest correspondent. Une version seulement signalée par un appareil ne permet plus de forcer la mise à jour. Les builds Play retournent volontairement « pas de blocage » dans ce lecteur : leur mise à jour passe par le Store. Un seuil n'est pas une nouvelle compilation ni une publication d'APK. |
| Tarifs | `/api/v1/pricing` / `/api/pricing` | ZUNO affiche les tarifs explicitement configurés à l'activation et dans les réglages ; aucune offre par défaut inventée. Les appels commerciaux externes restent masqués sur Play. Un prix affiché ne crée aucun droit payé ni achat fournisseur. |
| Serveurs rapides | `/api/v1/servers` / `/api/servers` | Suggestions facultatives dans le formulaire Xtream ZUNO. Le choix explicite d'un client remplit l'URL visible et modifiable ; aucune connexion, aucun identifiant, aucune source enregistrée ne sont remplacés automatiquement. Le choix manuel reste disponible. |
| Avis clients | Réglages `reviews_enabled` / `reviews_message`, puis `/api/feedback-prompt` et `/api/feedback` | Invitation facultative sur l'accueil ZUNO, masquée en mode enfants. Le client ouvre le formulaire et envoie lui-même son message. OFF masque l'invitation. « Plus tard » masque ce texte ; un texte différent constitue une nouvelle invitation. |
| Applications | `/api/v1/apps` | Catalogue administratif. Créer une ligne ne construit pas une application et changer son package ne renomme pas un APK installé. Les applications n'utilisent pas ce catalogue comme source de leur thème. |

Les serveurs proposés doivent être activés et avoir une URL HTTP(S) avec un
hôte, sans identifiants, paramètres ou fragment. Les identifiants de serveur
sont dédupliqués ; les réponses et le cache sont filtrés de la même façon.
Dans ZUNO, la sélection applique le même formateur HTTP que la saisie manuelle,
avec résultat visible dans le champ. Aucun serveur n'est choisi d'office.
Une lecture réseau en échec n'est pas déclarée « appliquée » par la commande
panel, même si l'interface peut conserver son ancien catalogue en cache.

Le formulaire d'avis n'interrompt jamais une lecture : seule une carte sur
l'accueil propose de l'ouvrir. Le clavier peut défiler avec le formulaire.
Un envoi n'est confirmé qu'après HTTP 200 et `ok: true`. En cas d'échec, le
texte est conservé et le client peut réessayer ; l'invitation n'est pas marquée
comme traitée. Une nouvelle invitation arrivée pendant l'envoi d'une ancienne
n'est pas acquittée à sa place. Le panel n'envoie rien au nom du client.

Les annonces et la publicité ont leurs propres lecteurs et présentations ;
ils sont vérifiés séparément dans ce lot. Le lien d'une annonce est normalisé
par le modèle partagé : HTTP(S) absolu, hôte présent et aucun identifiant dans
l'URL. Un lien invalide conserve le texte mais ne produit ni bouton d'action
mobile ni QR TV. Un lien valide produit un bouton mobile et, dans la carte
d'annonce TV, un QR facultatif à scanner. Ce QR de lien d'annonce est distinct
des deux anciens QR de connexion/activation supprimés du formulaire ZUNO ;
il ne les réintroduit pas. Les modules « Bannières » et
« A/B Testing » annoncés comme futurs ne deviennent pas actifs du seul fait
qu'une carte existe dans le centre de contrôle.

## Recette 7 MOTION

Le port mobile est construit par `ci/mobile/prepare_panel_controls.py`,
`mobile_controls_options.py` et les fixtures `options/*`, à partir des SHA
figés. Les tests ZUNO ne valident pas ce résultat.

Le candidat 7 MOTION possède les huit mêmes clés et la même correspondance
de genres live, avec au maximum douze cartes par genre. Les contenus non live,
adultes et les catégories masquées sont filtrés ; le catalogue existant reste
accessible indépendamment de ces rangées. Le favori du jour ouvre uniquement
la chaîne effectivement trouvée après un geste du client. L'invitation d'avis
et le sélecteur de serveur sont aussi rendus, avec les mêmes règles d'envoi
confirmé et de sélection explicite. Aucun de ces changements ne démarre de flux.

Le thème clair/sombre couvre l'accueil, le catalogue, les formulaires, le profil
et les avis. Les surfaces vidéo et Cast gardent leur aspect sombre : ce port
ne prétend pas convertir tous les anciens écrans. Les tests ciblés confirment
ces consommateurs dans la recette reconstruite ; le résultat de la suite
mobile entière reste suivi séparément.

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
Worker, ni une recette sur téléphone/TV/Cast physiques. Les écrans du panel
doivent présenter les possibilités du nouvel APK et les conditions de rendu,
sans promettre qu'un appareil ancien ou hors ligne les a déjà appliquées.

## Preuves de ce lot

- Worker candidat : 92 tests réussis, en exécutant le véritable `gold.fetch` sur SQLite locale ; isolation des revendeurs, identité matérielle, annonces (OFF, suppression, ciblage, expiration), publicité, tarifs et catalogue des serveurs. L’audit des tarifs correspond à la mutation validée.
- ZUNO, premier lot : 37 tests ciblés réussis sur appareils, annonces, publicité, thème, accueil et tarifs. Six tests supplémentaires exécutent les vrais handlers `message`, `ad`, `theme` : l'accusé `applied` attend la relecture et devient `failed` en cas de HTTP 503.
- ZUNO, consommateurs complémentaires : 13 tests ciblés réussis sur les genres, l'ordre/masquage/ruban des cartes réelles et le formulaire d'avis (erreur, réessai, clavier, changement d'invitation). La régression additionnelle sur les identifiants dupliqués a ensuite réussi avec les cinq tests du fichier des genres.
- Fraîcheur des commandes : 34 tests ciblés réussis, dont 10 cas du véritable traitement ACK (annonce, accueil, favori, tarifs et serveurs × nouvelle réponse 200/503). Une ancienne réponse 200 ne produit aucun `applied` avant la seconde réponse.
- Annonces après relecture : 9 tests partagés réussis, dont validation des liens et absence de bouton trompeur ; 1 test widget TV réussi pour l’absence de QR invalide et la conservation du message/bouton « Vu ».
- Suite ZUNO complète locale finale : 890 réussis, 8 ignorés et 2 échecs. Les deux échecs du fichier historique `relay_upstream_reconnect_test.dart` surviennent avant la connexion à la TV simulée, lors de `NetworkInterface.list` (environnement sans interface LAN utilisable, « Bad value for ai_flags »). Le moteur Cast n'a pas été modifié. Il faut le résultat de CI et une recette physique pour conclure à une validation complète.
- Analyse Dart ZUNO : aucune erreur ; les informations et avertissements ne sont pas fatals selon la commande du workflow.
- Recette mobile : reconstruction depuis les SHA figés ; 40 tests ciblés finaux réussis sur thème réel, sélection de serveur, favori du jour, avis, tarifs et ACK après ordre ; 4 tests Play réussis. Les huit clés ON/OFF, le texte à 200 % et les vrais gestionnaires mobiles sont inclus. Reconstruction de 48 fichiers, invariants 7/7 et analyse finale sans erreur. La suite mobile entière est encore en cours ; ces vérifications ne constituent pas son résultat.

Ces preuves concernent du code candidat. Elles ne constituent pas une publication
du panel, du Worker ou d'un APK chez les clients.
