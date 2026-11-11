# L1-03 — Revalidation VOD et maintien des sessions autorisées

## Problème reproduit

Un `VodPlayItem` normal créé avant une feuille conserve ses champs historiques.
Sur le 116, le même objet ouvre encore le lecteur après remplacement du
catalogue par un classement adulte ou inconnu, sans changement de profil.
Une recharge de catégorie du même identifiant et les anciens téléchargements
à `sourceKey` vide présentent aussi des accès indirects à vérifier.

Le test portable `zuno_vod_catalog_revalidation_test.dart` s'exécute sans API
nouvelle sur le commit `a4b81f7661d05866a39eeb05eec040ddbb1b7eb0`, arbre
`13d5ef7848c92a50c0fdf613f5cceed0def95030` : **7 échecs fonctionnels et 5 succès**.
Chaque échec compte une vraie tentative de route par `Navigator` : attendu 0,
obtenu 1. Aucun échec ne dépend d'un symbole absent. L'observateur ferme la route
avant montage du moteur : ce test ne constitue pas une lecture vidéo native.
Les 12 mêmes scénarios passent avec les sources corrigées.

## Autorité et événements d'invalidation

La sélection n'accorde aucun droit. `VodPlayItem.isAllowedNow` contrôle la
préparation parentale, les sources permises et le classement actuel avant et
après les attentes d'ouverture. Les enfants exigent un classement connu normal.
Les films nouvellement découverts d'un profil adulte prêt conservent le
comportement historique ; une reprise opaque sans classement demeure refusée.
Un identifiant structuré `pN:m/e/s:…` peut fournir la source d'un ancien
téléchargement ; une URL ou un identifiant ambigu ne la prouvent pas.

`CinemaClassification` est un jeton éphémère mis à jour par le dépôt. Une
sélection ou une lecture UI **ne peut jamais assouplir un jeton courant**.
Seule une publication contrôlée le met à jour. Sa présence ne remplace ni les
permissions du profil ni la vérification de source.

| Événement | Traitement |
|---|---|
| `trim`, éviction LRU, fermeture du widget | Libère les listes lourdes sans oublier le classement du média encore détenu. |
| Page effectivement relue, forcée ou normale | Actualise les jetons de cette catégorie ; une absence devient inconnue. Les autres jetons ne suivent la révision que s'ils étaient encore valides avant cette réponse. |
| Croissance de l'index | Actualise les objets présents, sans réautoriser un jeton déjà adulte ou inconnu depuis une page plus récente. |
| Publication complète du catalogue | Relit les catégories serveur pertinentes pour les jetons détenus et publie les nouveaux classements avec l'en-tête, avant notification. |
| `clear`, suppression mémoire d'un type, changement de profil/catalogue | Invalide la révision ; une autre catégorie ne peut ressusciter l'ancien droit. |
| Réponse d'index antérieure à une page neuve | Conserve les catégories actualisées dans le snapshot courant, puis laisse terminer les autres catégories. |

Le registre ne contient que des `WeakReference`. Un `Expando` relie également
le jeton aux objets `CinemaTitle` déjà détenus, afin qu'un ancien objet reste
filtré après éviction de sa page. Le nettoyage des clés mortes intervient aux
ajouts/publications. Sa cardinalité dépend des objets encore détenus : il n'a
pas de plafond numérique autonome, et ce dispositif n'est pas une mesure de
consommation mémoire.

La revalidation d'une publication lit une catégorie à la fois et ne conserve
que les titres recherchés. Elle ne charge pas un deuxième index. Pendant une
construction, les seules clés des catégories actualisées sont mémorisées ; la
fusion réemploie le snapshot courant avec des listes temporaires de références.
`_indexMax` et le cache de 30 pages ne sont pas augmentés. Aucun gain de mémoire
ou de fluidité n'est annoncé sans mesure physique.

Si un média ne peut plus être retrouvé dans les catégories serveur connues de
son jeton, son classement devient inconnu et les enfants restent bloqués. Une
perte de preuve n'est jamais transformée en permission.

## Présentation, lecture et Cast

Le filtre de titres et miniatures emploie la même autorité que l'ouverture.
Une feuille déjà visible retire son contenu et ferme sa propre route quand le
droit disparaît. Les fiches film/série et le lecteur se réabonnent au classement
publié et libèrent les abonnements à leur fermeture.

Le descripteur Cast porte un callback du média, sans capturer un `State` Flutter.
Quitter le widget ou libérer l'index ne coupe pas un Cast autorisé. Une
republication normale d'un film reste compatible avec l'index Séries actif ;
un reclassement adulte ferme la session Enfants. Une nouvelle sélection ne
réautorise pas un ancien objet d'index après éviction du cache de pages.

Les anciennes lignes de cache dont la clé de catégorie provenait de la table
précédente sont interprétées à la lecture avec la catégorie du fichier publié.
Aucun cache client n'est réécrit pour cette correction. Aucun schéma, champ
persistant, favori, historique ou téléchargement n'est migré ou supprimé.

## Fichiers et isolation

- `cinema_repository.dart` : publications cohérentes, jetons et filtre visuel.
- `tv_cinema_common.dart` : autorisations, factories et protection de feuille.
- `tv_cinema_screen.dart`, `tv_cinema_detail_screen.dart` : invalidation UI.
- `tv_vod_player_screen.dart` : revalidation de la lecture et contexte Cast.
- `zuno_cast_media.dart`, `cast_manager.dart` : conservation et révocation du
  contexte de session, avec abonnement au classement du catalogue.

Les nouvelles décisions sont limitées à `AppPlatform.isZuno`. Les branches
historiques de 7 MOTION demeurent actives lorsque ce drapeau est faux. Les
protections obligatoires ne possèdent aucun interrupteur permissif. Un retour
arrière ne peut pas rétablir le chemin d'ouverture du 116 : il doit conserver
le refus des enfants tant que le classement courant n'est pas démontré.
Les workflows partagés restent requis au SHA final.

## Preuves locales et limites

Preuves sous `evidence/recovery/cast/`, hors du checkout, Flutter 3.47.7 stable,
Dart 3.13.5, même lock. Les tests utilisent un espace réseau sans route externe,
des transports simulés et une base temporaire propre aux fixtures.

- `vod-baseline-portable-tests-02.log` et
  `vod-baseline-fixture-manifest-02.json` : source116 intacte, 7 échecs/5 succès,
  fixture SHA-256 `44ea01a9dc80b8b5b5a530f65af3eacba3aba946f8b39ccad8b3c492e4a46b27`.
- `vod-read-authority-after-tests.log` : **19 scénarios VOD réussis**, code0,
  dont les 12 portables et 7 scénarios de cycle de vie.
- `vod-two-reserves-before-tests.log` : deux défauts du candidat intermédiaire
  reproduits (page réseau normale et Cast pendant l'autre index).
- `vod-held-token-before-tests-02.log` : promotion indue réellement envoyée au
  Cast et index abandonné reproduits avant correction.
- `vod-read-authority-before-tests.log` : nouvelle sélection après LRU envoyée
  au Cast avant le garde d'autorité. La fixture correspondante est conservée
  dans `vod-read-authority-before-fixture.dart.txt`. La fixture finale précise
  aussi que le second titre appartient à une autre catégorie, pour vérifier
  la fin de cette indexation indépendante sans réintroduire une ligne retirée
  d'une page complète nouvellement publiée.
- `vod-final-targeted-tests-02.log` : **156 tests ciblés réussis**, code0,
  incluant les tests Cinéma existants, les gardes parentaux Cast/Direct,
  la fermeture des widgets et la reprise SDK historique.
- `vod-analysis-05.log` et `vod-analysis-comparison-final-05.json` : zéro erreur
  ou nouveau diagnostic ; 3 avertissements et 22 informations préexistants,
  code2 conservé. Il ne s'agit pas d'une analyse globalement verte.

Les journaux intermédiaires ne sont pas attribués à un futur commit ou à une CI.
Le manifeste final des sources de travail associe les fichiers à leurs
empreintes ; la suite globale et la CI doivent encore porter sur le SHA final.
Aucune compilation APK, exécution native, mesure physique ou comparaison de
performance n'est déduite de ces tests Flutter.
