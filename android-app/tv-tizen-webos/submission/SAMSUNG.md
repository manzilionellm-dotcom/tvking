# Dossier de préparation Samsung TV — ZUNO

État : préparation technique, non soumis, non certifié. Date : 15 octobre 2026.

## Fiche proposée (français)

- Nom : ZUNO
- Version : 1.0.0 (nouvelle application uniquement ; comparer à la fiche existante).
- Langue de cette version : français.
- Description courte : Lecteur TV pour vos sources personnelles M3U et Xtream.
- Description : ZUNO permet de lire sur Samsung Smart TV les sources M3U ou Xtream que vous associez à votre appareil depuis le panel. Parcourez les catégories et les chaînes avec votre télécommande, puis lancez la lecture plein écran. Aucune chaîne, playlist ni offre de contenu n’est incluse. Vous devez disposer de sources autorisées et d’une connexion Internet. Une licence ZUNO peut être nécessaire.
- Fonctionnalités disponibles : direct, catégories, lecture native Samsung, pause/reprise, retour à la liste, statut de licence, sources assignées au panel.
- Ne pas annoncer : VOD/séries/EPG/4K/DRM/sous-titres universels, compatibilité avec tous codecs ou tous modèles.

## Informations et pièces encore requises

- [ ] Compte Samsung TV Seller Office accessible et identité légale de l’éditeur.
- [ ] Identité Tizen réelle si application déjà enregistrée, version et certificat auteur correspondant. Ne pas écraser une identité existante avec les valeurs provisoires.
- [ ] Signature du WGT avec le profil Samsung, puis contrôle du paquet dans le SDK/Seller Office.
- [ ] Adresse email d’assistance et pays de distribution choisis par l’éditeur.
- [ ] URL publique de politique de confidentialité complète et vérifiée ; `zuno.7themotion.com/legal` est une référence existante du site, pas une politique validée pour cette version TV. Confirmer collecte, durées de conservation, suppression et contact.
- [ ] Compte/licence d’évaluation et source de test autorisée, durables pendant toute la certification. Ne pas déposer les identifiants dans le dépôt.
- [ ] Quatre vraies captures de l’app, JPEG de moins de 500 Ko, en 1920×1080 ou 1280×720. Ne pas utiliser les données simulées des tests comme preuve de lecture réelle.
- [ ] Logo transparent et fond aux formats demandés par le Seller Office ; l’icône du widget est incluse, les visuels store restent à finaliser.
- [ ] Document App UI Description au format Samsung, décrivant les écrans et commandes ci-dessous.
- [ ] Reprendre les motifs d’un éventuel rejet Samsung précédent et vérifier chacun sur le nouveau paquet.

## Parcours pour les testeurs / UI Description

1. Démarrage : création/récupération de l’identifiant d’installation, heartbeat au service.
2. Activation : identifiant MK visible, bouton Réessayer et À propos/confidentialité. Le testeur communique l’identifiant au responsable du panel, qui lui assigne une licence et une source de test autorisée. Prévoir une procédure d’assistance accessible pendant toute la revue.
3. Direct : catégories à gauche et chaînes à droite ; flèches pour déplacer le focus, OK pour sélectionner catégorie/chaîne.
4. Lecteur : AVPlay plein écran ; touches Lecture/Pause/Stop si présentes ; Retour arrête le lecteur et revient au direct.
5. Retour à la racine : popup Quitter avec Annuler/ Quitter. L’app ne capture pas l’appui long système de sortie.
6. Arrière-plan : lecture arrêtée ; retour sur la liste au réveil.
7. Perte réseau : message d’échec et possibilité de réessayer, sans affichage des identifiants de sources.

## Matrice obligatoire sur TV réelle — résultats à renseigner

| Vérification | Résultat actuel |
|---|---|
| Installation et lancement WGT signé sur modèles ciblés | Non effectué |
| Backend réel : heartbeat, licence, sources, TLS/CORS | Non effectué |
| Lecture vidéo ET audio HLS et TS autorisés | Non effectué |
| Télécommande physique, focus après défilement, grandes listes | Non effectué |
| Retour, sortie, Home, veille, réveil | Non effectué |
| Gel/expiration pendant lecture et renouvellement | Non effectué |
| Réseau absent, timeout, source vide ou invalide | Simulations automatisées partielles ; TV à faire |
| Persistance de l’identité après redémarrage | Test unitaire ; TV à faire |

Les contrôles automatisés ne remplacent ni les tests matériels ni l’acceptation Samsung. Ne soumettre qu’après levée des points ci-dessus.


## Avancement réel dans le Seller Office — 15 octobre 2026

Connexion au compte Samsung vérifiée dans le navigateur. Une nouvelle fiche **ZUNO**, type **Web App**, langue par défaut **French**, a été créée : ID Seller Office **3202610049649**. Le titre ZUNO, la description française du lecteur de direct et les mots-clés lecteur/M3U/Xtream ont été enregistrés ; le portail a confirmé la sauvegarde. Aucun paquet n’a été téléversé et aucune demande de publication n’a été envoyée.

La fiche antérieure **The Few**, ID **3202608047609**, est de type **.Net App**, avec le paquet **thefew-tizen.tpk** version **1.0.0**. Son historique du 14 août 2026 signale un refus documentaire : captures de prévisualisation et politique des touches manquantes dans le document de présentation. Samsung demande un document complet et une version supérieure pour une nouvelle soumission de cette ancienne application. Cette fiche antérieure n’a pas été modifiée.

La nouvelle fiche Web ZUNO est distincte de cette ancienne fiche .NET. Ne pas présenter le WGT comme une mise à jour du TPK, ni reprendre un certificat ou une identité d’application sans vérification. Pour ZUNO, les prochains livrables sont le WGT signé, les captures réelles, le document UI Description, les informations de service et les accès de test. La connexion Gmail/Samsung ne remplace pas le certificat de signature local.
