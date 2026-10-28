# Zuno sur box TV — revue du 28 octobre 2026

Cette revue porte sur la base Zuno 109 conservée dans la PR #145, avec le Cast
mobile et l'essai partagé. Elle ne remplace pas un profilage sur la box du client.
Aucun chiffre de FPS, de mémoire ou de temps de démarrage matériel n'est inventé.

## Défauts corrigés

| Zone | Défaut constaté dans le code | Correction |
| --- | --- | --- |
| Accueil et grandes listes | Les rangées, rappels et émissions reconstruisaient chacun un index de toutes les chaînes. | Un index créé à la demande et réutilisé pendant la vie du snapshot ; invalidation à chaque nouvelle liste. |
| Accueil derrière un lecteur | Le tick de 20 s, les événements de progression et les notifications lançaient encore des calculs non visibles. | Mise en attente quand un autre écran est devant, pendant la lecture et en arrière-plan ; fusion des demandes et reprise au retour. Le canal d'activation et de livraison reste actif. |
| Guide lent | Plusieurs relectures pouvaient se chevaucher. Le compteur de génération empêchait seulement l'affichage de certaines réponses. | Une seule lecture en vol ; dernière demande conservée, anciennes réponses invalidées au changement de source ou à la sortie de l'accueil. |
| Tendances | Chaque modification de progression VOD ou de favoris pouvait relancer une recherche sur tout le catalogue. | Recherche seulement après changement des chaînes, des tendances, du mode enfants ou retour à l'accueil. |
| Cache des chaînes | Un ID réutilisé gardait l'ancien nom, genre, pays et qualité ; les résultats orphelins restaient dans les maps statiques. | Clé incluant playlist et métadonnées, réutilisation des entrées inchangées, références faibles par objet et nettoyage global à chaque snapshot/suppression. Un résultat de calcul annulé n'est plus publié. |
| Confidentialité | La barre d'accueil concaténait encore l'identifiant Xtream de la source d'essai. | Libellé public seul pour les essais des deux marques. |
| Activation | Ajouter une confirmation allongeait la colonne et rétrécissait tout le panneau via FittedBox. | Cadre de taille stable, colonnes défilantes au D-pad et disposition verticale sur écran portrait. |
| Essai sur box | Petit bouton mobile et ouverture WhatsApp dépendante d'une application externe. | Carte Zuno or/noir, mention 24 H, focus à la télécommande, attente, expiration, reprise du chargement et QR WhatsApp. |

## Vérification automatisée

`home_performance_test.dart` compte les visites d'une liste de 50 000 chaînes :
100 accès au même index doivent demander 50 000 visites, au lieu de 5 000 000 si
l'index était reconstruit à chaque accès. C'est une mesure du travail algorithmique,
pas une promesse d'accélération de toute l'application.

Les tests couvrent aussi les rafales de 100 notifications, la pause/reprise,
une lecture du guide lente, les erreurs, la destruction de l'écran, le remplacement
des métadonnées à identifiant constant et le masquage des références d'essai.
`channel_cache_refresh_test.dart` vérifie aussi un changement vers une catégorie
adulte, des playlists distinctes, la libération du cache et l'annulation d'un lot.

`tv_gold_trial_card_test.dart` vérifie OK maintenu/double clic, message public,
expiration, refus, QR WhatsApp et fermeture au D-pad, client existant, messages
longs en 540p/1080p/portrait, ainsi que le défilement vers les dernières commandes.
Le workflow d'APK de revue conserve des rendus du composant en 720p : disponible,
chargement et confirmation. Ce sont des fixtures, sans compte fournisseur, avec
une police locale de test pour éviter les blocs Ahem des tests Flutter.

Les résultats effectifs des suites Flutter et de compilation sont consignés
dans la PR et les workflows GitHub Actions du commit, après leur exécution.

## Autres chemins examinés

- Direct : listes/grilles construites à la demande, pré-calcul des chaînes déjà
  présent, aperçu suspendu pendant le lecteur plein écran.
- Films et séries : grilles à la demande et mapping du catalogue dans un isolate
  déjà présents ; actualisations réseau reportées quand le lecteur est occupé.
- Direct/VOD : annulation des timers au départ et suspension native en
  arrière-plan déjà présentes. Les limites du fournisseur et les formats vidéo
  restent à valider sur matériel réel.
- Cast : compilation native et tests de transfert/reprise disponibles ; le test
  sur téléviseur/Chromecast physique reste nécessaire.

## Recette sur une vraie box

1. Comparer deux APK **profile ou release**, de même configuration, sur la même
   box et le même réseau. Ne pas conclure à partir de l'APK de revue debug.
2. Démarrage à froid puis à chaud ; accueil vide et listes 1 000 / 10 000 /
   50 000 chaînes. Relever premier écran utilisable, PSS mémoire et temps de frame
   dans Flutter DevTools/Perfetto. Conserver médiane et p95 avec modèle/Android.
3. Maintenir Haut/Bas pendant 30 s, ouvrir puis quitter Direct/Films/Séries dix
   fois, changer de profil, activer le mode enfants et supprimer une source.
   Aucun ancien catalogue ni contenu masqué ne doit réapparaître.
4. Laisser le direct 15 minutes, revenir à l'accueil, éteindre/rallumer l'écran,
   couper/rétablir le réseau. Observer absence de tâches d'accueil concurrentes,
   fuite de lecteur, son en double et croissance durable de mémoire.
5. Tester « Je teste » au D-pad : attente, confirmation/expiration, refus unique,
   interruption puis reprise du chargement, QR WhatsApp et Retour. Vérifier
   lisibilité en 720p/1080p avec l'overscan réel de la TV.

## Blocage serveur inchangé

Le véritable `gold.js` déployé est toujours absent du dépôt. Les captures du
rapport externe ne contiennent pas ses sources. L'export est nécessaire pour
valider le paquet démo, la protection **avant** l'appel fournisseur, la bascule
et la livraison rejouable. Aucun endpoint de démo n'est deviné, aucun ticket
ni crédit n'est consommé, aucune migration de production n'est exécutée.
