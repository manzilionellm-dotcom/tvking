# Audit Zuno — risques, valeur client, feuille de route

Date : 30 septembre 2026.
Périmètre lu : application Flutter (box Android TV), panneau d’administration, Worker Cloudflare (`android-app/cloudflare/`), workflows GitHub à la racine et dans `android-app/.github/`.
Nature du travail : audit. Aucun correctif de comportement. Le son, le décodeur audio et `NativeVideoView.kt` n’ont pas été ouverts pour modification. Aucune publication, aucun déploiement du Worker, aucune écriture sur la release `zuno-tv`, aucun contact avec le binaire « 4K Player ».

Les numéros de ligne correspondent au dépôt sur la branche `claude/app-admin-panel-connection-9fphfr`.

---

## Alerte — secrets

Aucun jeton cloud, aucune clé privée et aucun mot de passe de production réel n’ont été trouvés commitées dans le dépôt. Les vrais secrets (clé de signature des box, jeton Cloudflare, Firebase) passent par les secrets GitHub ou par Wrangler, ce qui est le bon endroit.

En revanche, le code contient **deux secrets de secours écrits en dur**. Ils ne sont pas recopiés ici.

- Clé utilisée pour signer les jetons du panneau si le secret d’administration du Worker n’est pas défini : `android-app/cloudflare/api_v1.js`, lignes 272, 958 et 3037.
- Mot de passe du premier compte administrateur si ce même secret n’est pas défini : même fichier, ligne 390.
- Un workflow de diagnostic tente une connexion au Worker de production avec ce compte et ce mot de passe de secours : `android-app/.github/workflows/diag-api.yml`, lignes 27 à 34. Ce workflow n’est pas dans le dossier `.github` de la racine, donc GitHub ne le lance pas tout seul. Le texte reste lisible par toute personne qui a le dépôt.

À faire tout de suite, sans changer l’application : vérifier dans le tableau Cloudflare que le secret d’administration du Worker est bien posé (s’il l’est, les deux filets de secours ne servent pas). Ensuite seulement, retirer ces filets du code. Ne pas coller la valeur du secret dans un ticket, un chat ou ce fichier.

---

## Les 10 problèmes les plus importants

Classés du plus grave au moins grave. « Grave » veut dire : un client peut perdre ses chaînes, ses codes, ou un inconnu peut les lire.

### 1. Critique — Les codes IPTV partent à qui connaît le code affiché sur la télé

Fichier : `android-app/cloudflare/worker.js`, lignes 2633 à 2686 (lecture) et 3498 à 3503 (adresse publique).

L’application demande ses chaînes avec `GET /api/device-source/` suivi du code MAC. La réponse contient l’adresse du serveur, l’identifiant et le mot de passe Xtream, en clair. Il n’y a pas d’autre preuve que « je suis bien cette box ».

Ce code MAC est affiché sur l’accueil de la box (`android-app/lib/features/tv/presentation/tv_hub_screen.dart`, ligne 372). Une photo de l’écran, un ticket de support ou une personne dans le salon suffit. La limite est de 120 demandes par minute et par adresse IP (lignes 3448 à 3450), et si la base est en panne la limite s’ouvre toute seule (lignes 1619 à 1620).

Le verrou d’abonnement, au même endroit (lignes 2648 à 2661), s’ouvre aussi en cas d’erreur de lecture : la box reçoit quand même les codes.

### 2. Critique — La sauvegarde cloud est une copie des codes, lisible de la même façon

Fichiers :

- `android-app/cloudflare/worker.js`, lignes 3051 à 3093 et 3557 à 3563 (`GET` et `PUT /api/backup/` + MAC, sans mot de passe).
- `android-app/lib/features/playlists/data/cloud_backup_repository.dart`, lignes 23 à 27 et 104 à 110 (l’application envoie elle-même les playlists saisies par le client).

N’importe qui peut lire ou remplacer la sauvegarde d’une box. Un remplacement peut effacer les chaînes du client ou y glisser une autre liste.

### 3. Critique — Le panneau peut s’ouvrir avec un secret de secours connu

Fichier : `android-app/cloudflare/api_v1.js`, lignes 272, 390, 936 à 945 et 958.

Si le secret d’administration n’est pas configuré, le Worker signe les jetons avec une clé écrite dans le code, et crée le compte administrateur avec le mot de passe de secours. Un jeton forgé donne alors tout le panneau : clients, licences, codes IPTV.

Même quand le secret est bien posé, il sert aussi de mot de passe permanent du super-administrateur (lignes 936 à 945). Qui le connaît entre toujours, et le mot de passe enregistré est réécrit.

### 4. Haut — Un revendeur peut lire et changer les codes d’une box qui n’est pas à lui

Fichier : `android-app/cloudflare/api_v1.js`, lignes 825 à 835 (routes) et 2248 à 2304 (lecture, écriture, suppression).

Dès qu’on a un compte du panneau, on peut demander les sources de n’importe quelle MAC. Il n’y a pas de contrôle « cette box appartient à ce revendeur ». La liste des clients, elle, est bien filtrée (lignes 2036 à 2038), mais la fiche d’un client par son numéro ne l’est pas (lignes 2046 à 2052).

### 5. Haut — Les mots de passe IPTV sont stockés en clair

Fichiers :

- Sur la box : `android-app/lib/features/playlists/data/playlist_database.dart`, ligne 75 (`xtream_password`). Le commentaire le dit : `android-app/lib/features/playlists/domain/playlist.dart`, lignes 61 à 62.
- Sur le serveur : `android-app/cloudflare/api_v1.js`, lignes 2223 à 2232 (colonne `password` en texte).

Une sauvegarde de la base, un accès ADB à la box, ou une copie D1 exposent tous les abonnements.

### 6. Haut — Le signal « je suis en ligne » peut envoyer l’adresse secrète de la liste

Fichier : `android-app/lib/features/subscription/data/subscription_backend.dart`, lignes 165 à 188 et 214 à 229.

Le commentaire promet de ne jamais transmettre le mot de passe. Pour une liste Xtream, c’est vrai : seul le serveur et l’identifiant partent. Pour une liste M3U, le champ `server` reçoit l’adresse complète. Ces adresses contiennent très souvent l’identifiant et le mot de passe dans le lien. Ce signal part souvent, avec le code MAC, l’identifiant Android et la chaîne en cours. Il n’y a pas d’écran « j’accepte » sur la box.

### 7. Haut — La mise à jour de la box ne vérifie pas que le fichier est le bon

Fichier : `android-app/lib/core/update/update_service.dart`, lignes 74 à 91 (lecture du manifeste) et 153 à 190 (téléchargement).

L’application lit un `version.json` puis télécharge l’adresse indiquée dedans. Il n’y a pas d’empreinte du fichier, pas de délai maximum sur le téléchargement (le contrôle du manifeste, lui, s’arrête au bout de 8 secondes). Si le serveur ne donne pas la taille, un fichier coupé peut être gardé dès qu’il dépasse 1 Mo (lignes 129 à 132). Android refusera une signature inconnue au moment d’installer, ce qui limite le pire cas. Un fichier signé avec la clé des box, ou un téléchargement qui ne finit jamais, passe quand même.

### 8. Haut — Une box peut rester ouverte sans licence, ou rester bloquée sans explication

Fichiers :

- `android-app/lib/features/tv/presentation/tv_app.dart`, lignes 373 à 380. Si le serveur ne répond pas (`statut inconnu`) et qu’il y a déjà des chaînes en mémoire, l’accueil s’ouvre. C’est voulu pour ne pas punir une coupure réseau. Combiné au point 1 (le serveur donne aussi les codes en cas de panne), un abonnement expiré peut continuer.
- `android-app/lib/features/subscription/data/subscription_state.dart`, lignes 307 à 309 et 319. Si la vérification échoue, l’erreur est jetée. L’écran d’activation continue d’attendre, sans dire « le réseau ne répond pas ».

### 9. Haut pour le client — Les pannes de chaînes et d’enregistrement se taisent

Fichiers :

- `android-app/lib/features/tv/presentation/tv_live_screen.dart`, lignes 647 à 654. Une erreur réseau est affichée comme « Recherche de tes chaînes… », le même texte que pendant un vrai chargement.
- `android-app/lib/features/playlists/data/playlist_repository.dart`, lignes 676 à 678. Si une liste échoue au rafraîchissement, on passe à la suivante sans prévenir.
- `android-app/lib/features/tv/presentation/tv_player_screen.dart`, lignes 441 à 444. Si la fin d’un enregistrement plante, l’erreur est ignorée. Le client croit que l’émission est sauvée.

Le lecteur, lui, a déjà un écran « Réessayer » après plusieurs échecs (lignes 324 à 331). Le trou est surtout avant d’arriver au lecteur, et à la fin d’un enregistrement.

### 10. Moyen, mais il bloque la suite — Presque aucun filet de test sur ces chemins

Ce qui existe : 19 fichiers de test sous `android-app/test/` (lecture de listes M3U, secours d’adresse, cast, cinéma, carrousel). Ils partent seulement quand le gros workflow `Build Zuno TV` compile l’application (`.github/workflows/build-zuno-tv.yml`, lignes 320 à 321). L’analyse Flutter n’échoue pas sur les avertissements.

Ce qui manque :

- Aucun test d’activation, de licence, de sauvegarde cloud, ni de mise à jour.
- Aucun test du Worker ni du panneau (zéro fichier de test dans `android-app/admin-panel`).
- Le workflow « qualité » prévu pour ça est au mauvais endroit : `android-app/.github/workflows/quality.yml`. GitHub ne lance que les workflows du dossier `.github/workflows` à la racine. Celui de la racine (`qa-gates.yml`) ne couvre que le site web, pas la box.
- Le déploiement automatique du Worker (`android-app/.github/workflows/deploy-worker.yml`) est au même endroit : il ne part pas. Le workflow racine `worker-prod-snapshot.yml` (lignes 5 à 8) dit déjà que le Worker en ligne est plus récent que le dépôt. On peut donc corriger le mauvais fichier et croire que la production a changé.

Le code parental est dans le même sac « facile à contourner » : code `0000` par défaut, stocké en clair, sans compteur d’essais (`android-app/lib/features/security/data/app_pin_settings.dart`, lignes 40 à 57). Le mode enfants de la box s’appuie dessus.

---

## Les 10 améliorations qui aideraient le plus les clients

Ce ne sont pas des rustines de sécurité. Ce sont les écarts visibles sur une box, par rapport à ce qu’un foyer attend d’un bon lecteur.

1. **Dire la vérité quand ça ne marche pas.** Trois phrases suffisent : « Pas de réseau », « Le code de cette box n’est pas activé », « Cette liste est refusée par le fournisseur ». Aujourd’hui les trois ressemblent à une recherche sans fin (`tv_live_screen.dart`, lignes 647 à 654).
2. **Mettre le guide TV sur la box.** La grille existe déjà (`android-app/lib/features/epg/presentation/tv_guide_screen.dart`) mais elle n’est branchée que sur l’écran profil du téléphone. L’accueil box n’a que Direct, Films, Séries, Serveur et Réglages (`tv_hub_screen.dart`, lignes 8 à 11). Sur le direct, on ne voit que l’émission en cours, une requête à la fois (commentaire ligne 1177 de `tv_live_screen.dart`).
3. **Le replay sur la box.** Le modèle de chaîne connaît déjà le rattrapage (`android-app/lib/features/channels/domain/channel.dart`, lignes 73 à 80) et le téléphone sait construire l’adresse. Le dossier `lib/features/tv/` ne s’en sert pas. Un foyer qui a raté le journal ne peut pas le revoir depuis la télécommande.
4. **Un zapping qui explique.** Le changement de chaîne existe (haut / bas, `tv_player_screen.dart`, ligne 305). Quand une chaîne est morte, le lecteur réessaie puis s’arrête. Un libellé du type « cette chaîne ne répond pas » et un passage proposé à la suivante évitent l’impression que l’application est gelée.
5. **Une mise à jour qui finit.** Le pré-téléchargement est déjà là pour que le client n’attende pas (`update_service.dart`, lignes 100 à 115). Il manque le délai maximum, l’empreinte du fichier, et un texte si le téléchargement a échoué au lieu d’une barre qui ne bouge plus (point 7).
6. **Un code enfants qui n’est pas 0000.** Demander un code choisi au premier lancement du mode enfants, et bloquer après plusieurs erreurs. Le fichier est cité au point 10.
7. **Retrouver ses chaînes après une réinstallation, sans les offrir à tout le salon.** La sauvegarde cloud a le bon but (`cloud_backup_repository.dart`, lignes 4 à 7). Il faut la garder, mais la fermer à clé (point 2), pas la supprimer.
8. **Une recherche qui pardonne les fautes.** Sur la box, la recherche garde les chaînes dont le nom contient exactement les lettres tapées (`tv_search_screen.dart`, lignes 4 à 6). « bein » ou « psg » ratent souvent le vrai nom. Le téléphone a déjà des pistes plus riches ; la télécommande, avec un clavier lent, en a encore plus besoin.
9. **Deux profils sur la même box.** Aujourd’hui un seul mode enfants pour tout l’appareil. Un profil « enfants » et un profil « salon », avec les favoris et la dernière chaîne de chacun, évite que le journal de 20 h remplace le dessin animé (et l’inverse).
10. **Savoir quelles box cassent vraiment.** Il n’y a pas d’outil de mesure produit (recherches vides, chaînes qui n’ouvrent pas, temps avant la première image). Crashlytics, s’il est branché, part tout seul en version publiée (`crash_reporting_firebase.dart`, ligne 46) et ne dit pas « le client n’a pas trouvé sa chaîne ». Un petit journal anonyme, avec un choix clair dans les réglages, dirait quoi réparer en premier.

---

## Feuille de route

Ordre choisi pour ne pas casser les box qui paient, et pour que chaque étape soit vérifiable.

### Étape A — Protéger les codes, sans changer l’image

1. Dans Cloudflare, confirmer que le secret d’administration est posé. Ne pas le copier ici.
2. Couper l’accès public en lecture des mots de passe. `device-source` et `backup` ne doivent répondre qu’à la box qui possède un secret à elle (créé à l’activation, stocké sur l’appareil), pas à la seule MAC affichée à l’écran.
3. Tant que ce secret n’existe pas sur les box déjà installées : refuser au moins l’écriture du backup par un inconnu, et ne plus renvoyer le mot de passe qu’à une box dont la licence est lisible (plus d’ouverture automatique si la base tousse).
4. Retirer les deux secrets de secours du code, et retirer l’essai de connexion du workflow de diagnostic.
5. Empêcher un revendeur de lire la fiche ou les sources d’une box qui n’est pas dans son stock. Le filtre existe déjà pour la liste des clients : le réutiliser.

Ne pas déployer le Worker tant que le code en ligne n’a pas été comparé au dépôt (`worker-prod-snapshot.yml` le dit : la production est en avance).

### Étape B — La box dit ce qui se passe

6. Remplacer l’écran « Recherche de tes chaînes… » infini par les trois messages du point client 1.
7. Afficher l’erreur d’activation (réseau, pas encore payé, gelé) au lieu de masquer l’exception.
8. Si l’enregistrement ne se ferme pas, le dire. Ne pas laisser un fichier vide présenté comme réussi.
9. Ajouter un délai au téléchargement de mise à jour, et refuser un fichier dont la taille ne correspond pas.

Ces changements sont dans l’application. Les tester sur une box de test avant toute release clients. Ne pas mettre `publish=true`. Ne pas écrire sur la release `zuno-tv` tant qu’une box de test n’a pas installé le build.

### Étape C — Filet, pour ne pas réouvrir les trous

10. Déplacer le workflow qualité à la racine `.github/workflows/`, pour qu’il lance vraiment `flutter test` sur les pull requests, sans compiler l’APK entier.
11. Ajouter des tests courts : activation (serveur muet, licence expirée, liste locale), sauvegarde refusée sans secret, manifeste de mise à jour sans empreinte, revendeur qui demande la MAC d’un autre.
12. Chiffrer le mot de passe Xtream sur la box et dans D1. L’application doit continuer à lire les anciennes lignes en clair le temps de la migration, sinon les clients perdent leurs listes.

### Étape D — Ce que le foyer voit

13. Brancher le guide TV déjà écrit sur l’accueil de la box.
14. Brancher le replay déjà prévu dans le modèle de chaîne.
15. Recherche tolérante sur la box.
16. Code enfants choisi par le foyer, avec blocage après plusieurs essais.
17. Mesure simple et consentie : chaîne qui n’a pas démarré, recherche sans résultat, temps jusqu’à la première image.

Le lecteur vidéo et l’audio ne sont pas dans cette liste. Ils ont leurs propres correctifs en cours ; cet audit ne les mélange pas.

---

## Ce qui tient déjà

Pour ne pas tout jeter :

- Les listes IPTV ne sont pas écrites en dur dans l’application. Elles viennent du panneau ou de la saisie du client.
- Le lecteur de la box réessaie, puis s’arrête avec un bouton « Réessayer », au lieu de boucler sans fin.
- La mise à jour est déjà pensée pour être téléchargée avant que le client appuie, et le manifeste TV est publié à la main pour ne pas harceler les box.
- Le workflow de build refuse de publier l’APK clients si la signature n’est pas celle des box déjà installées, et un simple push de branche ne publie pas (`build-zuno-tv.yml` : publication seulement depuis `main`, ou lancement manuel avec publication demandée).
- Le panneau sépare déjà le rôle propriétaire et le rôle revendeur sur plusieurs actions, et le login a une limite de tentatives (qui s’ouvre toutefois si la base tombe, ligne 124 de `api_v1.js`).

---

## Hors de cet audit

Non lu pour modification, volontairement : décodeur audio, `NativeVideoView.kt`, binaire « 4K Player », secrets réels côté Cloudflare ou GitHub (leurs valeurs n’apparaissent pas dans le dépôt).
