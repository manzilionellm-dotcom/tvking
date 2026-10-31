# Raccordement de l'export Gold — 28 octobre 2026

## Provenance vérifiée

Archive fournie par le propriétaire : `gold-export.zip`, SHA-256
`a59522fba4e2c4bfb289fff04c8b8cff837ac23273dd86ffc5c7daca22155de9`.
Les 11 fichiers correspondent à `SHA256SUMS.txt`.

| Fichier d'origine | SHA-256 |
| --- | --- |
| gold.js | ff9cd709565169eef17a0b14ec7138f580bcf1e99e6fb838bfa1f3ebf38e6f96 |
| worker.js | ad08c5e6516c5741b686661e8ed35d16c1f9d1b20aadc164e14dc9a49628f71c |

Version déclarée dans l'export : `a3f55171-173c-4a91-bfa9-1a347db085a4`,
26 octobre à **18:59:53, Stockholm**. Cette archive ne prouve pas qu'aucun
déploiement n'a eu lieu depuis ; relire la version active avant publication.

Le bundle `production/worker.js`, le wrapper `production/gold.original.js`
et le schéma `production/schema.sql` sont conservés sans modification.
Le build vérifie le bundle puis produit `worker.runtime.js`, ignoré par Git :
seuls trois exports sont ajoutés (`sealSource`, `openSourceList`, `notifyBox`).
Aucune fonction, route, classe Durable Object ou implémentation du bundle
n'est remplacée par la lignée plus ancienne présente dans le dépôt.

## Comportement ajouté

- `wrangler.toml` pointe sur `gold.js`. Le wrapper restauré délègue au bundle
  vérifié, conserve l'activation payante, et intercepte les routes d'essai.
- Les deux alias d'essai partagent le registre permanent MAC/Android ID.
  Les anciens essais/démos sont lus dans toutes les clés et toutes les apps.
  Un ancien échec ambigu bloque une nouvelle création ; un refus de paquet
  explicite observé dans l'export n'est pas assimilé à une création réussie.
- L'ordre effectif demandé le 29 octobre est **Manzi8, puis manzi10**. Le compte manzi10 sans libellé est
  identifié par l'ID attesté dans le rapport d'export. Aucun compte, clé, plafond
  propre ou réglage payant du pool n'est modifié. Le panel affiche les tickets
  comme **non vérifiés**, sans confondre le plafond local et les tickets réels.
- L'enrôlement ajoute une empreinte de secret par appareil. Il exige l'accord
  de `devices` et `trial_anchors`, puis refuse une rotation sans preuve valide.
  L'app réannonce son secret avant l'essai ; une répétition valide est idempotente.
- La source est chiffrée avec la primitive `enc1` de production. Les nouveaux
  reçus sont chiffrés AES-GCM avec MAC et id de ligne comme données associées.
  Les anciennes colonnes de `gold_lines` ne sont ni effacées ni réécrites.
- Une livraison interrompue reprend le même reçu, par le polling déjà utilisé
  ou `POST /api/gold-trial/delivery`. Aucun POST fournisseur n'est nécessaire.
  Une ancienne ligne active peut être récupérée si ses accès et sa date de fin
  sont présents et valides. Une date sans fuseau n'est pas devinée.
- L'insertion de source et sa révision sont transactionnelles. Une liste déjà
  enregistrée ou une suppression concurrente gagne ; aucun remplacement ni
  découpage à trois listes pouvant supprimer une liste client n'est utilisé.
  Après une livraison réussie, la suppression du client n'est pas annulée.
- L'essai peut ouvrir le lecteur jusqu'à l'expiration du reçu via l'extension
  d'ancre déjà comprise par le bundle. Il ne réinitialise pas l'ancien essai et
  ne modifie aucune licence payante. Les appareils bannis/frozen sont refusés.
- Les nouvelles sources d'essai exigent la preuve d'appareil sur les lectures
  source/config/backup/self-source. Les appareils antérieurs sans reçu gardent
  leur compatibilité. Ce patch n'est pas un audit complet des anciennes API.
- Le panel utilise les vrais JWT de production, les rôles admin/super_admin,
  CORS pour atlas-console, une pagination stable des anciens événements et
  l'historique récent actualisé toutes les 1,5 seconde. La réponse admin ne
  contient pas les accès de ligne ni le JSON fournisseur brut. Les anciennes
  activations payantes dans `audit_logs`, antérieures à Gold, sont incluses.
- L'app envoie la marque en `X-App-Brand`, sans changer les trois champs POST.
  Le label peut donc être « Zuno TV Essai » ou « 7 MOTION Essai ».

## Blocage fournisseur restant

**Aucun essai réel ne peut être créé par cette révision.**

Faits confirmés par le propriétaire le 29 octobre, sans nouvel appel de notre
part : l'API v1.81 n'accepte que `sub=1,3,6,12` (mois), refuse `sub=99` et
n'expose pas de lecture des tickets démo. Aucun appel API démo 24 h n'est
documenté. Une ligne M3U « 1 Day », « Price: Free », créée par le formulaire
web `/addnew?t=lines` a coûté un ticket démo et zéro crédit sur manzi10 :
crédits 84 → 84, démos 9 → 8. Ce résultat web ne prouve pas un contrat API.

`gold_trial_enabled` reste à 0. `gold_trial_provider.js` refuse avant réseau,
déchiffrement de clé ou consommation. L'ancien endpoint admin de démo reste
fermé. Ni un paramètre supposé, ni une automatisation du formulaire, ni ON
dans D1, ni `GOLD_TRIAL_POLICY_READY=true` ne remplace la confirmation écrite
de Strong de l'appel API exact d'une démo 24 h.

À obtenir **par écrit de Strong** avant de rouvrir le développement fournisseur,
pour **chacun** des deux comptes, sans créer de ligne :

1. Contrat exact de création **démo 24 h uniquement**, code/action et paramètres.
2. Confirmation que cette opération ne peut pas utiliser des crédits payants,
   y compris lorsque le compteur de démos vaut zéro.
3. Réponse de consultation des tickets, avec les noms/types des champs.
4. Réponses de succès et de refus certain, permettant de distinguer tickets
   épuisés, paquet invalide et timeout après création possible.

Avec ces preuves, implémenter `createVerifiedDemo24h`, lire les quotas avant
création, appliquer le plafond propre de la clé atomiquement et tester les
fixtures de réponses. Un timeout reste incertain : jamais de bascule aveugle.
Le test actuel de bascule valide la politique sur fournisseur simulé ; il ne
prouve pas la disponibilité des tickets Strong ni une gratuité réelle.

Le bouton « Je teste » est désormais entièrement masqué dans les deux apps,
sans activation réseau ni chargement. Un ancien
serveur répondant `trial_disabled` affiche aussi ce texte. Les migrations D1,
la livraison de sources existantes et le temps réel continuent indépendamment.

## Migration et déploiement

Les migrations sont additives et ne sont appliquées **que dans les tests locaux** :

1. `migrations/20261028_gold_trial_policy.sql` : réglages OFF, claims, événements,
   limite glissante persistante 5/minute/IP.
2. `migrations/20261028_gold_trial_runtime.sql` : identité Android du claim,
   index unique, empreintes d'appareil, reçus chiffrés et limitation d'enrôlement.

La seconde contient un ALTER suivi par le registre de migrations ; elle ne
doit pas être rejouée hors de ce registre. Ne pas appliquer toutes les anciennes
migrations du dépôt ni utiliser le schéma exporté comme migration de production.
Sur staging, vérifier les contraintes et le contenu des tables antérieures.

Le bundle exporté n'avait pas de clé source dédiée. Sans `SOURCE_ENCRYPTION_KEY`
ni `SECRETS_KEY`, le wrapper emploie une dérivation distincte du secret admin
existant pour les nouvelles sources ; les reçus ont une autre dérivation.
Les lectures en clair anciennes restent compatibles. Changer/ajouter une clé
après chiffrement exige une réencryption contrôlée : ne pas faire une rotation
aveugle. Les anciens mots de passe en clair restent une migration séparée à
préparer, sans purge et avec toutes les voies de renouvellement vérifiées.

Le binding `RT_HUB` et la classe `RealtimeHub` sont conservés. Le type historique
de migration `v1-rt-hub` n'est pas prouvé (`new_classes`/`new_sqlite_classes`) :
relire la configuration Cloudflare exacte avant déploiement ; aucune migration
DO n'a été inventée. Aucun Worker, panel Vercel ou D1 de production n'a été modifié.

## Vérification reproductible

```sh
node --test android-app/cloudflare/tests/gold_trial_policy.test.mjs \
  android-app/cloudflare/tests/gold_trial_runtime.test.mjs \
  android-app/admin-panel/src/lib/goldTrial.test.ts
cd android-app/admin-panel
npm ci --no-audit --no-fund
npm run build
```

Les tests reconstruisent les **61 tables exportées**, appliquent les deux
migrations et vérifient les comptes de lignes antérieures. Ils exécutent le
vrai routeur, l'authentification JWT et le chiffrement du bundle, avec SQLite
transactionnel et des comptes fictifs. Aucun compte fournisseur n'est contacté.

Recette : nouvel appareil et succès simulé ; même MAC et même Android/autre MAC ;
deux clics concurrents ; clé vide confirmée puis bascule simulée ; timeout sans
bascule ; OFF ; quota ; preuve invalide ; délivrance concurrente ; panne puis
reprise ; suppression sans réapparition ; ancienne ligne récupérée sans achat ;
pagination 205 événements ; refus de toute activation réelle non vérifiée.

Restent à vérifier sur staging/appareil réel : contrat fournisseur, délai jusqu'à
la première image, Cast sur récepteur physique, qualité 4K/HDR et débit. L'Android
ID reste déclaratif sans attestation matérielle ; le secret protège la liaison
après enrôlement mais ne prouve pas, à lui seul, un appareil physique unique.

La création payante passe désormais uniquement par Golden confirmé dans le panel ;
voir [golden-admin.md](golden-admin.md). L’activation classique ne crée plus de ligne Strong.
