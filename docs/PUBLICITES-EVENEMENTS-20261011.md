# Publicités et événements — 11 octobre 2026

## Usage proposé

Menu propriétaire **Contenu affiché → Publicités et événements**.

1. Choisir Publicité ou Événement, écrire le titre et le message.
2. Choisir le pays, le début et la fin de diffusion ; le fuseau est affiché.
3. Vérifier l'aperçu et enregistrer le brouillon privé.
4. Cliquer sur **Programmer** et confirmer la période.
5. Mettre en pause, reprendre, dupliquer ou archiver depuis la carte.

Un lien HTTPS public et un bouton sont facultatifs. Recherche et filtres
portent sur les 100 campagnes les plus récentes. Aucun nombre de vues n'est
inventé : « Disponible dans l'app » décrit la réponse du serveur, pas une
impression constatée. L'aperçu indique que le rendu dépend de l'app.

Les applications récupèrent le message à leur prochaine lecture des annonces
pendant la période choisie. La période ne change pas la durée de la notification
à l'écran. Ce module prépare des messages textuels ; la publicité vidéo de
démarrage conserve sa page existante. Aucun achat publicitaire ni paiement
automatique n'est introduit.

## Inspiration vérifiée, sans intégration commerciale

- YouTube : brouillon privé et date de publication avec fuseau.
  https://support.google.com/youtube/answer/1270709?hl=en
- Roku Ads Manager : fenêtre de campagne avec début et fin.
  https://help.ads.roku.com/en/articles/7191949-campaign-budget-schedule

Ces documentations motivent les fonctions proposées. Zuno n'est pas connecté
aux réseaux publicitaires de ces plateformes.

## Preuves et protection des données

Base de travail : `d81da1a8e3231e951d4a836f9b05e0d4806a9cdf`, branche isolée
`feature/panel-campagnes-20261011`. Aucun changement du site Next.js, des
branches gelées, des réglages de protection ni des publications clientes.

PROUVÉ — avant implémentation, `node --test cloudflare/campaigns.test.mjs`
depuis `android-app` : **10 échecs sur 10** ; les routes répondaient 404.
Les tests du panel échouaient également, module de dates et d'états absent.

PROUVÉ — après implémentation, la même suite enrichie : **13 tests réussis**.
Routes HTTP réelles et SQLite transactionnel, avec authentification réelle :
brouillon privé, droits propriétaire, dates, pays, idempotence de création,
version concurrente refusée en 409, curseur, pause/reprise, suppression,
interrupteur global, panne de diffusion et panne d'audit.

PROUVÉ — `npm test` dans `android-app/admin-panel` : **72 tests réussis**.
`npm run build` : compilation TypeScript et Vite réussie. Les nouvelles
assertions distinguent disponibilité, retrait et vue ; elles refusent les
dates locales impossibles. Aucun test existant n'a été retiré ni assoupli.

PROUVÉ — `node panel_security.audit.mjs` dans `android-app/cloudflare` :
**47 contrôles réussis**. Le nouveau serveur n'accepte que `super_admin`.
Les mutations et leur audit sont une transaction. Le journal ne stocke
ni texte publicitaire ni lien ; seulement statut, version et identifiant.

Les courses sont exercées avec des appels concurrents sur le banc SQLite.
Ce banc sérialise les requêtes ; la preuve de concurrence workerd est citée ci-dessous.
Le parcours E2E ajouté utilise le vrai formulaire React, le Worker local,
D1 et la route lue par l'app, sans simuler la partie difficile.

NON PROUVÉ : affichage sur téléphone et SHIELD, disponibilité de ce module
en production. Il faut une mise en ligne autorisée puis un essai physique.
Le navigateur local n'est pas installé dans l'environnement de travail.
Aucun APK ni AAB n'est produit : aucun fichier Flutter n'est modifié.

## Stockage et absence de réapparition

La nouvelle table `panel_campaigns`, ses index et la colonne nullable
`app_broadcasts.campaign_id` sont ajoutés sans supprimer de données.
Une erreur de migration reste une erreur ; seule une colonne déjà présente
et vérifiée autorise à continuer.

Le message reçoit son identifiant d'annonce au moment où il devient dû,
dans le même lot D1 que son marqueur de diffusion. Un identifiant réservé
au brouillon pourrait être dépassé par le curseur d'une autre annonce.
L'index unique empêche la double insertion. Le marqueur conservé empêche
qu'une annonce effacée soit recréée. « Tout retirer » met aussi les campagnes
futures en pause, dans la transaction de suppression.

Recherche du même motif : les annonces immédiates ne réservent pas d'identifiant
à l'avance ; le module vidéo ne passe pas par ce curseur. Le contrôle global
des annonces continue à couper également les campagnes.

## Mise en ligne et retour arrière

Production conservée gelée. Intégration à relire puis mise en ligne uniquement
par `deploy-panel-cloudflare.yml`, branche `claude/panel-mise-en-ligne`, avec
`confirme=DEPLOYER`, approbation du propriétaire et contrôle de la MAC de
référence avant/après : licence, plan, échéance, nombre de listes identiques.

Pour couper les campagnes : pause individuelle, archivage ou interrupteur
global Annonces. Une reprise conserve l'identifiant de notification. Une
campagne déjà diffusée doit être dupliquée pour publier un nouveau contenu.
Un retour à l'ancien Worker laisse les tables additives en place ; les messages
déjà matérialisés restent soumis à leur expiration et au contrôle global.
Ne pas supprimer les tables pour revenir en arrière.

## Résultat CI sur le code 2734584

PROUVÉ — parcours réel Chrome/Chromium + React + Worker + D1, run
[38162131019](https://github.com/manzilionellm-dotcom/tvking/actions/runs/38162131019),
job `114537069535`, succès le 11 octobre 2026 à 18:03 UTC :

- Brouillon enregistré depuis le formulaire, absent de la route publique.
- Programmation depuis le formulaire, texte relu par la route de l'app.
- Douze lecteurs concurrents sur workerd : un seul identifiant de campagne.
- Pause puis reprise par boutons : aucune seconde annonce après le curseur.
- Duplication préparée ; largeur mobile 390 px sans débordement horizontal.
- Parcours existants d'activation, trois listes, accusés, suppression et échéance
  également terminés ; bilan du lanceur : tous les contrôles locaux sont passés.

PROUVÉ — suite Worker complète locale, `node --test *.test.mjs` : 42/42
entrées du lanceur Node réussies. La CI Stabilité et la QA du site complètent
ces preuves ; aucun job de déploiement n'est autorisé par une PR.

Contre-preuves conservées dans l'historique, sans supprimer ni assouplir
les assertions :

- Run 38161301577 : nom du champ Message mêlé au compteur ; libellé explicite
  et compteur conservé comme description accessible.
- Run 38161487011 : même motif pour Type ; contrôle identique de Pays.
- Run 38161914783 : HTTP 400, « Identifiant de campagne invalide », aucun
  champ HTML invalide. Le nouvel appel encodait son objet deux fois alors que
  l'enveloppe HTTP commune encode déjà les objets. Correction des deux appels
  POST/PATCH, sans changement de l'enveloppe ni des autres écrans.
- Reprise après « Tout retirer » : test rouge HTTP 200 au lieu de 409 et état
  En pause au lieu de Retirée. Vérification dans la transaction et erreur
  explicite demandant de dupliquer. Les deux contre-preuves passent après
  correction ; la suppression ne recrée aucun message.

Limite du banc CI : sa dépendance existante Wrangler 3.90.0 utilise workerd
2024-11-06 et affiche un avertissement de compatibilité. Le déploiement reste
configuré séparément avec Wrangler 4.149.0. Le parcours prouve le protocole
et le stockage local, pas un déploiement dans le runtime de production.

## Reprise et corrections — 12 octobre 2026

La reprise a vérifié la tête `c3e70fa64adf11ade2dbcff14f15f3a302617b2c` :
ses contrôles CI étaient verts et les jobs de déploiement étaient ignorés.
La branche de production était toujours sur `d81da1a8e3231e951d4a836f9b05e0d4806a9cdf`.

Deux défauts ont ensuite été reproduits par les routes HTTP et SQLite avant
correction, sans appel à la production :

- `DELETE /api/announcement`, l'ancien retrait global, effaçait les messages
  sans interrompre les campagnes futures. À leur échéance, elles étaient
  encore publiées. Cette route utilise maintenant le même retrait atomique
  que le panel : mise en pause des campagnes et suppression des annonces.
- `PATCH /api/v1/announcements/:id` pouvait réactiver l'annonce d'une campagne
  en pause ou archivée sans modifier son statut. Cette opération reçoit
  maintenant HTTP 409 et renvoie vers **Publicités et événements**. Le bouton
  reste utilisable pour les annonces immédiates.

PROUVÉ localement sur cette correction : 16/16 tests campagnes, 45/45 entrées
du lanceur de la suite Worker, 72/72 tests panel, 47/47 contrôles de sécurité,
30/30 protections de déploiement, compilation TypeScript/Vite réussie. Aucun
test ignoré. Les deux contre-preuves échouaient avant le correctif ; le troisième
nouveau scénario vérifie l'annulation de toute la transaction si le retrait
échoue. Le secret du banc est généré localement, jamais affiché ni enregistré.

Les nouvelles vérifications ne remplacent pas le parcours workerd/Chromium en
CI. Son résultat pour la nouvelle tête est à lire dans la PR 110. Aucun code
Flutter ni configuration de déploiement ou de protection n'a été modifié.
Le gel de production reste actif ; affichage physique et déploiement restent
non prouvés.
