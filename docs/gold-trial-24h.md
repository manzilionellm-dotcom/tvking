# Essai partagé 24 h — état et recette

## État réel au 28 octobre 2026

L'archive `gold-export.zip` a été reçue et ses **11 empreintes vérifiées**.
Le véritable bundle est conservé dans `android-app/cloudflare/production/` ;
`gold.js` est maintenant le point d'entrée, avec les adaptateurs vers le schéma
exporté, le canal source et le contrôle administrateur de production.

**La création fournisseur reste bloquée avant tout appel réseau.** L'export ne
confirme ni le paquet démo 24 h, ni son coût payant nul, ni le format des tickets.
`sub=99` a été refusé ; aucune valeur alternative n'est inventée. Un booléen
READY ou un interrupteur forcé en base ne contourne pas ce verrou.

Le détail du raccordement, les migrations, les tests et les prérequis restants
sont dans [gold-export-integration.md](gold-export-integration.md).
Aucun ticket, crédit, compte ou déploiement de production n'a été modifié.

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

## Worker : raccordement au bundle vérifié

- `gold.js` conserve les fonctions payantes et le hook d'activation de l'export.
  L'ancienne voie de démo `action=new/sub=99` est fermée, y compris côté admin.
- `gold_trial_runtime.js` lit `gold_lines`, `gold_history`, `devices`,
  `trial_anchors`, `licenses` et `device_sources`. L'absence d'historique n'est
  jamais déduite d'une panne. Les créations anciennes et les demandes ambiguës
  restent bloquantes, y compris avec une autre MAC mais le même Android ID.
- `gold_trial_device.js` ajoute `/api/device-proof`, compatible avec les apps.
  Le secret doit correspondre à une liaison Android/MAC déjà enregistrée ;
  connaître l'Android ID ne permet pas de remplacer une preuve existante.
- `gold_trial_delivery.js` chiffre les reçus, réutilise le chiffrement source
  et les notifications du bundle ; un bail D1 sérialise les reprises. Une liste
  existante ou une suppression concurrente ne peut pas être écrasée.
- `/api/gold-trial/delivery` et le polling existant peuvent reprendre une même
  ligne sans aucun appel fournisseur. Une ancienne ligne doit avoir ses accès
  et une expiration explicite encore valide, sans réinitialiser ses 24 h.
- `gold_trial_provider.js` bloque la création tant que le contrat démo réel
  n'est pas fourni et implémenté. Les tests de création utilisent des fixtures.
- Appliquer uniquement les deux migrations Gold du 28 octobre, dans l'ordre,
  sur staging. Ne pas exécuter toutes les anciennes migrations du dépôt.

Le registre MAC/Android et le quota sont arbitrés en une instruction SQL.
Les refus et créations gardent date, IP, version, id de ligne et expiration.
Aucune purge des essais permanents n'est introduite.

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
node --test android-app/cloudflare/tests/gold_trial_policy.test.mjs android-app/cloudflare/tests/gold_trial_runtime.test.mjs
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
