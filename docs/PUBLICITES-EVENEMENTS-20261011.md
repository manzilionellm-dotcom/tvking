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

PROUVÉ — après implémentation, la même suite enrichie : **12 tests réussis**.
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
Ce banc sérialise les requêtes ; il ne remplace pas la preuve workerd.
Le parcours E2E ajouté utilise le vrai formulaire React, le Worker local,
D1 et la route lue par l'app, sans simuler la partie difficile.

NON PROUVÉ à la rédaction : exécution du nouveau parcours navigateur en CI,
affichage sur téléphone et SHIELD, disponibilité de ce module en production.
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
