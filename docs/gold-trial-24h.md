# Essai partagé 24 h — état et recette

## État réel au 28 octobre 2026

Cette branche prépare l'application, le panel et une politique Worker additive.
**Elle ne constitue pas encore une intégration fournisseur déployable.** Le module
`gold.js` annoncé en production n'est présent ni dans `main`, ni dans la branche
mobile du 26 octobre. L'accès Cloudflare disponible demande une authentification.
Le point d'entrée `wrangler.toml` reste inchangé : ne pas déployer le vieux
`worker.js` sur la production, qui possède des fonctions supplémentaires.

La création réelle de tickets démo, les clés AES-GCM et la livraison existante
doivent être raccordées au module déployé après récupération de ses sources.
Aucune API fournisseur n'a été inventée. Aucun ticket ni crédit réel n'a été
utilisé. Aucun compte, aucune donnée D1 ni aucun déploiement de production modifié.

## Bases des derniers builds conservées

- Branche de départ : `feature/7motion-gold-trial-20261026`,
  commit `52dcc735be2584524c2ff7a40a6c3a78bf01c7c8`.
- Zuno TV : cette branche contient entièrement
  `feature/zuno-play109-20261021`, commit
  `c8e412ccc485a26d6a336287dd0c941e318498ad` (18 commits supplémentaires,
  aucun retard), dont les corrections de démarrage JNI de la version 109.
- 7 MOTION : base mobile `37fdf3305c5de9d35e20fd6567df38008fc7a7ee`, puis
  toute la chaîne Sport, Radio, synchronisation, identité, stabilité, +18,
  lecteur, gestes, Foot, passage entre lecteurs, suppressions et essai du
  26 octobre. `prepare-gold-trial-test.sh` reconstitue cette chaîne puis
  applique les mêmes fichiers d'essai que Zuno.
- Les constructeurs existants réutilisent `apply-shared-gold-trial.sh`.
  Les signatures, identifiants de production, clés et canaux de publication
  existants ne sont pas modifiés. Les APK de revue sont des builds de test.

## Application

`GoldTrialBackend`, `GoldTrialController`, `GoldTrialCard` sont communs aux deux
compilations. Le composant est ajouté à l'accueil et à l'activation Zuno ; les
points d'insertion du dernier téléphone sont conservés.

Le corps du POST reste exactement `{mac, android_id, app_version}`. Le secret
local existant est envoyé dans `X-Device-Secret`. Seul le champ public `message`
est présenté, avec filtrage des URL, noms fournisseur et identifiants connus ;
les erreurs réseau ou les anciennes réponses sans message ont un repli français.
Un message serveur absent n'est jamais remplacé par une exception brute.

Le premier GET de source part immédiatement, puis toutes les 1,5 seconde, pendant
30 secondes au maximum. L'import réutilise `RemoteSourceRepository` et ses règles
de suppression. Une reprise de chargement n'émet pas un nouveau POST d'essai.
Le contrôleur Zuno survit à la transition activation → accueil.

L'offre disparaît si une licence payante ou une playlist existe. Un essai déjà
utilisé propose `https://wa.me/447307410512`. Le refus `rate_limited` invite à
attendre une minute, distinctement d'un plafond quotidien atteint.

**La lecture en 1–2 secondes n'est pas démontrée** : la création fournisseur et
le téléchargement du catalogue peuvent prendre davantage. Mesurer séparément
POST, réception de la source, import et première image sur appareil réel.

## Worker : raccordement obligatoire au module existant

1. Récupérer tous les modules du Worker actuellement déployé, sa configuration
   et le schéma réel D1, sans exporter les valeurs de secrets.
2. Appliquer `20261028_gold_trial_policy.sql` sur une base de staging. La migration
   ne fait que créer quatre tables et leurs index ; elle laisse l'essai OFF.
   Ne pas lancer en bloc les anciennes migrations du dépôt sur la production.
3. Dans le véritable `gold.js`, construire `createGoldTrialHandler(adapters)`.
   Les fonctions d'adaptateur exigées sont documentées au-dessus de la factory :
   `eligibility`, `listDemoKeys`, `createDemo24h`, `deliverSource`.
   `verifyTrialDevice` réutilise `devices` et `device_secrets` du dépôt ; comparer
   leur schéma à celui de production avant de le raccorder.
4. `eligibility` doit lire les essais historiques de **toutes** les clés et des
   deux apps et les abonnements existants. Une lecture incertaine doit échouer.
   Ne jamais initialiser `trial_used=false` faute d'avoir lu les anciennes tables.
5. `listDemoKeys` réutilise le pool chiffré existant et retourne des descripteurs
   avec `label`, `trial_priority`, `enabled`, `demo_tickets` (nombre, si connu).
   La priorité de `manzi10`, puis `Manzi8` est appliquée sans changer leurs comptes.
6. `createDemo24h` doit appeler exclusivement l'opération démo réelle de Strong.
   Vérifier ce contrat dans le `gold.js` réel et la documentation fournisseur :
   aucun paramètre de durée payante, aucun repli sur achat/crédit. Retourner un
   reçu normalisé `{isDemo:true,paidCreditsUsed:0,expire:<ms>,line_id}`.
   Le contrôle du reçu ne peut pas annuler une dépense déjà faite par un mauvais
   adaptateur ; il ne remplace pas l'audit de l'opération démo avant son appel.
7. Un rejet confirmé sans création peut lever `DemoUnavailable` pour passer à
   la clé suivante. Un timeout/5xx ambigu conserve la réservation en `uncertain`
   et exige une réconciliation en lecture seule : ne pas créer une autre ligne.
8. `deliverSource` doit réutiliser le canal source existant, être idempotent,
   conserver le libellé public et reprendre une livraison interrompue avec
   **la même ligne**, sans aucune nouvelle création fournisseur. Ce raccordement
   est indispensable pour les états `created`/`delivery_pending`.
9. Router `/api/gold-trial` et `/api/v1/device/trial` vers ce même handler AVANT
   l'ancien routeur ; conserver toutes les autres routes du module.
   Poser les en-têtes CORS de production, dont `X-Device-Secret`.
10. Reporter les routes `/api/v1/gold/trial-control` et `/history` sous le contrôle
    JWT existant. Le patch `api_v1.js` montre l'insertion sans toucher aux autres
    routes. Conserver `/api/v1/gold/history` et ses activations payantes.
11. Quand ces contrôles et la recette démo sont terminés, seulement alors déclarer
    `GOLD_TRIAL_POLICY_READY=true`. Le panel refuse une activation avant cette
    vérification ; la variable ne déploie et ne raccorde rien toute seule.

Le registre MAC et le quota sont arbitrés en une instruction SQL. Les refus et
les créations gardent date, IP, version, id de ligne et expiration. Les traces
de débit sont temporaires mais aucune purge automatique n'est introduite :
prévoir leur rétention séparément sans jamais effacer le registre des essais.

## Panel

La page `/gold-trials` ajoute interrupteur, plafond UTC et recherche MAC. Le
registre récent se rafraîchit toutes les 1,5 seconde après chaque réponse ;
une requête lente ne s'empile pas avec la suivante, et quitter la page annule
le réseau. L'enregistrement utilise une révision pour refuser l'écrasement d'un
changement concurrent. Seuls `admin` et `super_admin` peuvent lire/modifier ces
routes. L'historique se pagine ; l'historique existant de `gold.js` est lu à part
et un échec est affiché, sans le présenter comme une absence d'essais.

## Tests automatiques

```sh
node --test android-app/cloudflare/tests/gold_trial_policy.test.mjs
node --test android-app/admin-panel/src/lib/goldTrial.test.ts
cd android-app/admin-panel
npm ci --no-audit --no-fund
npm run build
```

Android : les workflows existants exécutent les tests Flutter du composant,
la suite complète téléphone et le parcours Android virtuel. Ne pas confondre
un workflow configuré avec une exécution réussie : consulter les résultats du
commit de la PR. L'environnement local ne contient pas de SDK Flutter.

## Recette réelle à faire sur staging et appareil de test

| Cas | Résultat attendu |
| --- | --- |
| Nouvel appareil sans abonnement | Un POST, loader, une démo de 24 h, date affichée, source importée automatiquement |
| Même MAC, autre clé ou autre app, après expiration/réinstallation | 409, aucun appel de création, message français et WhatsApp |
| Deux requêtes concurrentes sur la même MAC | Une seule ligne ; l'autre requête reçoit `in_progress` |
| manzi10 sans tickets démo, Manzi8 disponible | Bascule après rejet certain ; compteur de crédits payants inchangé sur les deux comptes |
| Toutes les clés sans tickets | Aucun crédit débité ; message d'indisponibilité |
| Timeout fournisseur après réception possible | Pas de nouvelle création ; réconcilier la même opération |
| Interrupteur OFF | Aucun appel fournisseur ; message de fermeture dans les deux apps |
| Plafond journalier atteint / sixième requête en une minute | 429 approprié ; refus journalisé |
| Android ID d'une autre MAC / secret manquant, faux ou appareil banni | 403 avant toute création |
| Licence ou source déjà enregistrée | Offre cachée ; refus serveur d'un appel forgé |
| Source reçue avant le 201 / passage activation → accueil | Confirmation et import conservés, aucun deuxième POST |
| Coupure réseau après création | Reprise de livraison de la même ligne, pas de nouveau ticket |
| Panel ouvert pendant activation et refus | Événements visibles après l'intervalle de lecture, métadonnées exactes |
| Revendeur ou utilisateur non authentifié | Refus des réglages et de l'historique global |
| Navigation téléphone / D-pad Zuno / écran Sources | Aucun nom, URL ni identifiant fournisseur affiché pour l'essai |

Avant une livraison client, vérifier la signature officielle et un versionCode
strictement supérieur à l'APK installé. Cette PR ne publie ni ne fusionne les
derniers builds de production.
