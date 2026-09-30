# Catalogue films et séries — pourquoi il disparaît, et ce qui est gardé sur la box

Branche : `claude/zuno-catalogue-cache` (à partir de `claude/zuno-104`).

Ce texte dit ce qu'on a **vu dans le code**, ce que les **tests ont prouvé**, et ce qu'on **n'a pas** prouvé. Rien ici n'a été essayé sur une vraie box.

## Cause trouvée

L'écran Films / Séries de la télé (`TvCinemaScreen`) n'a pas un message spécial « le serveur est en panne ». Il affiche une liste **vide**, et le texte change selon le cas.

### « Aucun film ni série pour l'instant »

Ce texte (`tvCinemaNoSource`) s'affiche quand la liste des **catégories** est vide. Deux cas dans le code :

1. **Pas de compte Xtream** sur la box (seulement une liste M3U, ou rien). Le corps du message le dit : il faut un abonnement Xtream.
2. **Le compte existe, mais la liste des catégories revient vide.** Chaque compte est interrogé tout seul. Si l'appel échoue (délai dépassé, coupure, réponse inutilisable), l'erreur est notée dans la boîte noire et **remplacée par une liste vide**. Si **tous** les comptes échouent, le total est vide, et l'écran dit la même phrase que s'il n'y avait pas de films. On ne distingue pas « le serveur n'a pas répondu » de « le serveur n'a vraiment aucun film ».

Le délai de ces appels cinéma est de **25 secondes** (`XtreamClient` créé par `CinemaRepository`). Ce n'est pas le Worker Cloudflare : l'app parle **directement** au portail Xtream du client (`player_api.php`, actions `get_vod_categories`, `get_vod_streams`, `get_series_categories`, `get_series`). Le Worker ne fabrique pas cette liste et ne la reçoit pas.

### « Rien ici pour le moment. »

Ce texte (`tvCinemaEmptyCategory`) s'affiche quand la **catégorie ouverte** n'a aucun titre. Avant ce changement, un échec réseau était rangé en mémoire comme une catégorie vide. Rouvrir la même ligne montrait « rien ici » sans réessayer, jusqu'à quitter l'écran.

### Le catalogue ne survivait pas

Tout tenait **en mémoire vive** :

- Au bout de **10 minutes**, ouvrir Films / Séries **vidait** cette mémoire (`refreshIfStale` appelait `clear`) pour relire le fournisseur. Si le serveur ne répondait pas à ce moment-là, l'écran n'avait plus rien.
- Quitter l'application, ou la fermeture par la box, effaçait aussi tout.
- Il n'y avait **pas de copie sur le disque**.

Donc « parfois les films ne sont pas là » peut être le serveur (il ne répond pas, ou il répond vide), **ou** l'app qui a jeté la dernière liste réussie et n'a plus rien à montrer. Le code ne permettait pas de savoir lequel des deux.

L'écran téléphone « Films » (`VodRepository` / `MoviesScreen`) est un autre chemin, lui aussi sans disque : une erreur renvoyait une liste vide et le texte « Aucun film disponible ». La box télé, elle, passe par le cinéma décrit ci-dessus.

## Ce qui change

- La dernière liste **complète** (catégories, titres, affiche, année, note) est écrite dans un dossier à part : `zuno_catalog`. Ce n'est pas le fichier des chaînes, ni les favoris, ni l'historique, ni les profils.
- Au démarrage, s'il y a une copie, elle s'affiche **tout de suite**. Le serveur est relu en arrière-plan si la copie a plus de 10 minutes, ou si on appuie sur Réessayer / Redémarrer.
- La nouvelle liste **ne remplace** l'ancienne que lorsqu'elle est entière, lisible, et non vide. Une réponse vide, une erreur, ou un morceau manquant laisse l'ancienne en place.
- Le téléchargement se fait **catégorie par catégorie**, avec une pause entre deux, des essais dont l'attente double (et un décalage aléatoire), et une pause tant qu'une lecture lourde est ouverte (Direct, lecteur). Si l'app est coupée au milieu, le morceau déjà écrit est repris au prochain lancement. **L'app éteinte ne télécharge pas** : il n'y a pas de tâche Android WorkManager. La reprise a lieu quand on rouvre Zuno.
- Le fichier sur la box ne contient **ni mot de passe, ni identifiant, ni adresse de lecture**. L'adresse est reconstruite au moment de lire, avec le compte déjà enregistré. Rien de ce dossier n'est envoyé au Worker.
- Taille max : **48 Mo** pour les films, **48 Mo** pour les séries. Au-delà, on garde l'ancien catalogue plutôt que d'écrire un morceau en trop.
- S'il n'y a **ni copie ni réseau**, l'écran dit « Catalogue indisponible » et propose **Réessayer**. En bas de la colonne, une ligne discrète : « Mis à jour il y a … » quand une copie est affichée.

Le bouton Redémarrer ne jette plus la copie disque. Il demande seulement un nouvel essai.

## Ce qui est prouvé (tests lancés ici)

Machine de développement, **pas une box**. Commande : `flutter test` dans `android-app`.

Résultat : **290 tests passés, 1 ignoré** (cet ignoré existait déjà, ce n'est pas le catalogue).

Les 19 tests du fichier `test/features/cinema/catalog_cache_test.dart` couvrent :

- le délai entre essais (il double, il plafonne à 2 minutes, le décalage aléatoire ajoute jusqu'à 30 %) ;
- le refus de publier une liste vide, incomplète, ou d'une version inconnue ;
- une erreur qui ne doit pas être mémorisée comme « catégorie vide » ;
- le remplacement : tant qu'il manque une catégorie, l'écran ne voit pas la nouvelle liste ;
- une réponse vide qui **ne remplace pas** un catalogue déjà enregistré ;
- une coupure entre les deux renommages : on retrouve l'ancien ;
- un fichier d'une version inconnue qu'on ne supprime pas ;
- l'absence de mot de passe et d'URL de lecture dans le fichier ;
- des fichiers voisins nommés favoris / historique / profils qui ne sont pas modifiés, et le ménage des vieux dossiers du cache ;
- la reprise : la catégorie déjà écrite n'est pas retéléchargée ;
- la pause tant qu'une « lecture » est signalée occupée ;
- le plafond de 48 Mo : on n'écrit pas le morceau de trop, et on n'insiste pas au passage suivant.

`dart analyze` sur les fichiers touchés : **aucune erreur**. `flutter analyze` sur tout le projet signale encore des infos et avertissements **déjà présents** avant ce travail (const, champs inutilisés ailleurs). On n'en a pas ajouté d'erreur.

Le build automatique de la branche a aussi fini, sur GitHub, pour le commit `7634aaae` :

- les 6 checks de la PR sont verts, dont `flutter analyze + test` (290 tests passés, 1 ignoré, comme en local) ;
- le job « Build Zuno TV APK » a réussi : https://github.com/manzilionellm-dotcom/tvking/actions/runs/36771504223 ;
- le journal affiche `PUBLIER: false` et `version visible = 104 (précédente publiée : 102, publication : false)` ;
- les étapes « Publier sur la release zuno-tv » et « Publier pour la box de test » sont **sautées** ;
- l'APK existe seulement comme artefact de ce run. Il n'a pas été installé, et `version.json` de la release clients n'a pas été réécrit.

## Ce qui n'est PAS prouvé

- **Aucun essai sur une box** v102, v103 ou v104. Pas de télécommande, pas d'écran télé, pas de coupure réseau réelle.
- **Aucun essai avec un vrai portail Xtream.** Les tests utilisent de fausses réponses en mémoire.
- On n'a **pas ouvert** l'écran Films dans l'application. Le bouton Réessayer et la ligne « Mis à jour il y a … » sont dans le code ; personne ne les a vus sur une télé.
- Le test « favoris / historique / profils » utilise des **fichiers factices** à côté du dossier cache. Il ne lit pas les vrais favoris d'une box. Le code du cache n'ouvre pas ces réglages, mais ce n'est pas une migration jouée sur un appareil déjà rempli.
- On n'a **pas** lancé le workflow à la main avec `test_box=true`. Le run observé est le build automatique du push, pas une installation sur une box de test.
- Le Worker Cloudflare n'a pas été déployé. Le 4K Player n'a pas été touché. Aucun push vers `main`.

## Test simple, sur la box (à faire par quelqu'un)

À faire **après** qu'une version de cette branche a été installée sur **une** box de test, pas sur les box des clients.

1. Ouvre Zuno **avec le réseau**, va dans **Films**, attends que les catégories et des affiches apparaissent. Laisse l'app ouverte une minute (le catalogue se copie en arrière-plan). Reviens à l'accueil, rouvre Films : la ligne en bas de la colonne doit dire « Mis à jour … ».
2. **Coupe le réseau** de la box (Wi-Fi off, ou câble retiré).
3. Ferme Zuno complètement, puis rouvre-le.
4. Va dans **Films**. La liste des catégories et les affiches déjà vues doivent **être là**, sans message « indisponible ».
5. Coupe encore le réseau, **efface les données de l'app** (ou installe sur une box qui n'a jamais ouvert Films). Rouvre Films : là, le message « Catalogue indisponible » et le bouton **Réessayer** sont normaux, parce qu'il n'y a rien d'enregistré.
6. Rallume le réseau, appuie sur **Réessayer**. Les films doivent revenir.

Si l'étape 4 montre un écran vide alors que l'étape 1 avait marché, le correctif ne tient pas sur la box. Le dire tel quel. Ne pas l'installer chez les clients tant que ce test n'est pas fait.
