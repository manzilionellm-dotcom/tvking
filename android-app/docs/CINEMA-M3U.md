# Cinéma : films et séries lus dans le M3U

## Pourquoi

Avant, « Cinéma » ne savait lire que l'API Xtream du fournisseur
(`get_vod_categories`, `get_vod_streams`, `get_series`…). Deux cas restaient
vides :

1. **une liste M3U** (lien ou fichier) qui contient des films et des séries :
   Cinéma disait « aucun compte » ;
2. **un compte Xtream dont l'API répond « 404 »** pour les films (cas vu le
   15/11/2026 sur un téléphone : `get_vod_categories : Erreur HTTP 404`, puis
   « movie : 0 catégories »), alors que le M3U du même compte les contient.

Maintenant Cinéma lit aussi le M3U. **Les catégories sont celles du M3U**
(`group-title`), sans rien inventer.

## Ce qui se passe

| Cas | Comportement |
|---|---|
| Compte Xtream dont l'API a des films | **Rien ne change.** Aucun M3U n'est lu. |
| Compte Xtream, API « 404 » (ou 405/501), ou réponse qui n'est pas une liste (page web, « infos du compte ») | Le M3U du **même compte** (`get.php?…&type=m3u_plus`) est lu. |
| Compte Xtream, liste de catégories **vide** | Crue : le compte n'a pas de films, aucun M3U n'est lu (sinon un abonnement de directs téléchargerait un M3U à chaque ouverture). Si la personne touche « Actualiser », le M3U est lu. |
| Compte Xtream, panne passagère (réseau, délai, 5xx) | Comme avant : l'erreur remonte, aucun M3U n'est lu. |
| Liste M3U qui contient des films ou des épisodes | Son M3U est lu pour Cinéma. |
| Liste M3U de directs seulement | Rien n'est téléchargé (vérifié dans la base avant). |

Le M3U est lu **une fois** à la première ouverture de Cinéma (10 à 90 s selon
la taille ; l'écran attend), puis relu au plus **toutes les 12 h** en arrière-plan,
ou quand la personne touche « Actualiser » (au plus une fois toutes les 2 min).
Un double appui ne retélécharge pas.

## Comment une ligne est jugée (`m3u_vod_classifier.dart`)

1. adresse avec `/series/` → épisode ; avec `/movie/` → film ;
2. adresse avec `/live/` (timeshift, radio) → direct, ignoré ;
3. sinon seul un vrai **fichier vidéo** (mp4, mkv, avi, mov, wmv, flv, webm, m4v,
   mpg, mpeg, vob, divx, 3gp, ogv, m2ts) compte. Une adresse `.m3u8` ou `.ts` sans
   marqueur est un direct : une chaîne « Films 24/7 » n'est pas un film ;
4. un fichier vidéo dont le nom contient `S01E02`, `1x02` ou « Saison 1 Épisode 2 »
   est un épisode, sinon un film.

Les épisodes d'une même catégorie et d'un même nom de série forment **une
série** ; les saisons et les épisodes viennent des codes du nom.

## Où c'est rangé

`documents/zuno_m3u_vod/p<id de la liste>/` : des fichiers JSON **au format
Xtream** (`movies_<cat>.json`, `series_<cat>.json`, `episodes.pack`…), lus par
le module Cinéma exactement comme une réponse du serveur. Le reste du module
(fusion des catégories, index de recherche, catalogue sur disque, fiches séries,
reprise de lecture) n'a pas été réécrit.

Les adresses de lecture contiennent les identifiants du client. Elles ne sont
**pas** dans le catalogue partagé `zuno_catalog` (un test vérifie qu'il ne
contient ni adresse ni mot de passe) : elles restent dans ce dossier privé, au
même niveau de confidentialité que la base des chaînes. Les dossiers des listes
supprimées sont effacés ; ceux des listes seulement masquées (changement de
profil) sont gardés.

Identifiants : le **numéro du fournisseur** quand l'adresse est de type Xtream
(`…/movie/user/pass/12345.mkv` → `12345`, le même qu'avec l'API : « Reprendre »
survit à un changement de mot de passe), sinon une empreinte `h…` de l'adresse.
Catégories `mg1`/`sg1`, séries `q…` : jamais des nombres, ce qui permet
d'aiguiller un appel vers le M3U ou vers l'API.

## Limites connues (dites, pas cachées)

- **Pas de fiche détaillée** (résumé, acteurs, durée) pour un film du M3U : le
  M3U ne les contient pas. Affiche, nom et année viennent de la ligne.
- **« Récemment ajoutés »** suit l'ordre du fichier (les ajouts sont en général
  à la fin) ; ce n'est pas une vraie date.
- **Une série dont les épisodes n'ont pas de code** (`/series/` sans `S01E02`)
  reçoit saison 1, numéros dans l'ordre du fichier.
- **Plafonds** : 80 000 films et 200 000 épisodes par liste (le début du M3U est
  gardé, la coupure est écrite dans la boîte noire) ; fichier de 300 Mo au
  maximum. Il est écrit sur le disque pendant la lecture, jamais gardé en
  mémoire, puis effacé.
- **Film en `.m3u8` ou `.ts` sans `/movie/`** dans l'adresse : pris pour un direct.
- **En-têtes propres à une ligne** (`#EXTVLCOPT`, `|User-Agent=`) : ignorés.
- Le texte « Les films et séries viennent de ton abonnement Xtream » (écran sans
  aucun compte) n'a pas été réécrit.

## Boîte noire (lignes `CINEMA`)

- `le serveur n'a pas de films via son API → lecture du M3U du compte`
- `M3U p1 : 12 345 films, 210 séries (4 321 épisodes), 87 catégories, 31 000 adresses lues en 42 s`
- `M3U p1 : aucun film ni série dans ce fichier (… adresses lues)`
- `M3U p1 : lecture impossible : …` / `téléchargement impossible : …`

## Interrupteur de secours

`zuno.cinema.m3u_off` (réglage de réparation, comme les autres) : vrai = on
revient exactement à l'ancien comportement (Xtream seulement, aucun M3U lu).

## Ce qui est vérifié, ce qui ne l'est pas

Vérifié par des tests automatiques (lecteur de lignes, rangement, lecture par les
analyseurs Xtream déjà en place, module Cinéma de bout en bout avec un faux
serveur) : liste M3U en lien et en fichier local, compte Xtream en « 404 », réponse
d'infos au lieu d'une liste, liste vide (aucun M3U lu, sauf « Actualiser »), API
qui marche (aucun M3U lu), panne 503 (aucun M3U lu), M3U refusé, page web à la
place du M3U, redémarrage (rien retéléchargé, films toujours lisibles),
« Actualiser » (relu après 2 min, échec = ancien catalogue gardé).

Vérifié aussi sur un **vrai réseau** (`m3u_vod_network_test.dart` : un petit
serveur HTTP local, de vraies prises, pas un faux client) : réponse en morceaux,
réponse compressée (gzip), redirection, panel qui refuse les trois premiers
lecteurs et n'accepte que le quatrième, page web à la place du M3U, connexion
**coupée** en route (échec net, rien laissé sur le disque, la reprise marche),
serveur qui se tait (arrêt au délai d'inactivité), plafond de taille, fichier
de 26 Mo reçu en entier, compte Xtream dont l'API répond 404 puis M3U lu pour de
vrai, et liste M3U compressée avec films, séries et épisodes.

Un piège rencontré en écrivant ces tests : un faux serveur qui « coupe » mal
(en-têtes déjà partis) se tait au lieu de raccrocher, et le test passe pour la
mauvaise raison (délai d'inactivité au lieu d'une vraie coupure). Le test
vérifie donc que l'erreur est bien une fin de connexion, pas un silence.

Limite connue : l'échec d'un téléchargement coupé reprend le texte commun aux
listes de directs (« le serveur a refusé les N signatures… »), suivi de la
vraie cause (« Connection closed… »). La cause est exacte, la première phrase
est trop sévère pour une simple coupure.

**Non vérifié** : le M3U d'un vrai fournisseur (taille, lenteur, formats de
noms), le temps de la première lecture sur une box à 1 Go, et la lecture d'un
film dont l'adresse vient du M3U sur une vraie box.
