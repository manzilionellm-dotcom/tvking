# Publication du Worker Gold — préparation du 29 octobre 2026

## État de ce lot

Ce lot prépare une PR normale vers `claude/panel-mise-en-ligne`, à partir de
`d81da1a8e3231e951d4a836f9b05e0d4806a9cdf`. Le code applicatif porté provient de
`82b83fa02b3d1067103fdc43eeb97a268eb61917`, avec le correctif compatible des deux
schémas `device_secrets`. Aucun déploiement ni migration distante n’a été exécuté.

Le gel `.github/panel-production.json`, `panel-deploy-guard.mjs`, CODEOWNERS et
les rulesets ne sont pas modifiés. La règle d’interdiction de mise à jour de la
branche et la revue CODEOWNER obligatoire restent des blocages réels de fusion.
Une PR peut être préparée et testée ; aucun autre workflow, branche, force-push
ou jeton ne doit servir à contourner ces protections.

Le panel actif est publié séparément sur Vercel. L’entrée manuelle de ce workflow
est désormais limitée à `worker-seul` ; la validation refuse toute autre cible.
Le job historique Pages ne peut donc pas publier un ancien panel par ce chemin.

## Code exact à porter

Le point d’entrée est `android-app/cloudflare/gold.js`. Il réutilise le bundle
exporté de production, jamais le `worker.js` de l’ancienne lignée à la racine du
dossier Cloudflare.

Modules du wrapper : `device_guard.js`, `gold.js`, `gold_activation_delivery.js`,
`gold_golden.js`, `gold_golden_delivery.js`, `gold_realtime.js`,
`gold_trial_admin.js`, `gold_trial_delivery.js`, `gold_trial_device.js`,
`gold_trial_policy.js`, `gold_trial_provider.js`, `gold_trial_runtime.js`.

Provenance et build : `prepare_gold_runtime.mjs`, `production/worker.js`,
`production/gold.original.js`, `production/schema.sql`,
`production/provenance.json`, `production/.gitignore`, `package.json`,
`package-lock.json`, `wrangler.toml`.

Le build vérifie SHA-256
`ad08c5e6516c5741b686661e8ed35d16c1f9d1b20aadc164e14dc9a49628f71c`
du bundle, puis ajoute seulement les trois exports nécessaires dans
`production/worker.runtime.js`. Ce fichier généré ne doit pas être commité.
Le paquet local verrouille Wrangler à `4.42.1` pour les recettes. Le workflow
de déploiement conserve sa version déjà imposée par les tests, `4.149.0`.

Les tests `gold_trial_policy`, `gold_trial_runtime`, `golden_admin`,
`gold_realtime`, leurs deux fichiers de fixture, ainsi que les nouveaux tests
`device_secret_schema` et `legacy_export_compat` font partie de ce portage.
Le dossier `android-app/admin-panel` n’est pas remplacé.

## Audit de production avant toute publication

L’extension autonome de `worker-prod-snapshot.yml` s’exécute par déclenchement
manuel sur une branche autorisée par l’environnement `zuno-panel-audit`.
Elle conserve `CLOUDFLARE_READ_TOKEN`, le contrôle du propriétaire et les
branches uniques de snapshot. Le token doit permettre les métadonnées Workers,
Durable Objects et la lecture D1 ; une permission manquante provoque un échec.

Le mode `node .github/backend-release-preflight.mjs audit` ne dépend pas du
code candidat et ne publie rien. Il utilise uniquement les GET Cloudflare et des
requêtes D1 fixes `SELECT`/`PRAGMA`. Les secrets, valeurs de variables, URLs de
sources et lignes utilisateurs ne sont pas enregistrés. Une base sans les
nouvelles tables peut être photographiée ; cette observation ne l’autorise pas
à recevoir le nouveau Worker.

Le rapport `backend-audit.json` contient : version active à 100 %, déploiement,
binding D1, namespace `RT_HUB`, type SQLite ou KV lu sur Cloudflare, tag de
migration, domaines du Worker, état de workers.dev, tâches planifiées,
noms de bindings secrets, migrations inscrites et noms des colonnes attendues.

Lectures minimales et décisions associées :

| Observation | Décision avant publication |
|---|---|
| Version active différente de `a3f55171-173c-4a91-bfa9-1a347db085a4` | Exporter cette version et réconcilier le code ; l’archive du 26 octobre ne suffit plus. |
| Plusieurs versions servent le trafic | Arrêter le chemin de publication unique et faire revoir ce déploiement progressif. |
| `RT_HUB`, `RealtimeHub`, namespace ou type non prouvé | Ne pas inventer `new_classes`/`new_sqlite_classes`, ne pas créer un second DO. |
| Domaine supplémentaire, binding supplémentaire ou variable différente | Porter la configuration réellement nécessaire et refaire la revue ; ne pas l’écraser. |
| Migration absente du registre | Lire le schéma avant d’appliquer quoi que ce soit. |
| Schéma déjà modifié, registre incomplet | Réconcilier l’historique ; ne pas rejouer aveuglément l’ALTER. |
| Essai fournisseur activé | Arrêter : cette publication doit conserver l’essai OFF. |

Le précontrôle `before` compare ces faits à la configuration et à la provenance.
Il refuse une dérive. Le déploiement utilise `--keep-vars`, puis le contrôle
`after` vérifie que namespace, type, D1, domaines, date de compatibilité, flags
runtime et noms de secrets sont restés identiques. Le précontrôle de publication
lit la date et les flags dans les métadonnées de la version active, puis les
compare au fichier Wrangler ; une absence de date ou un flag non porté bloque
la publication avant le déploiement. Il n’existe aucune écriture D1 dans ces scripts.

## Quatre migrations additives, ordre et divergence connue

| Migration | Effet |
|---|---|
| `20261028_gold_trial_policy.sql` | Registres d’essai, événements, limite IP, interrupteur OFF. |
| `20261028_gold_trial_runtime.sql` | Android ID du claim, index unique, preuves appareil, reçus chiffrés, limite d’enrôlement. |
| `20261029_device_secrets.sql` | Déclaration additive historique de la table des preuves et index Android ID. |
| `20261029_golden_admin.sql` | Ordres Golden confirmés et verrou par clé. |

La présence de ces fichiers dans Git ne prouve pas leur application en
production. Il faut lire `d1_migrations` et `PRAGMA table_info` sur les tables
concernées. La migration runtime ajoute une colonne avec `ALTER TABLE` ; elle
ne doit pas être répétée hors du registre.

Les deux déclarations de `device_secrets` sont différentes : la migration
runtime utilise `updated_at`, celle du 29 utilise `enrolled_at` et `rotated_at`.
`CREATE TABLE IF NOT EXISTS` conserve le premier schéma rencontré. Le nouveau
code choisit les horodatages effectivement présents après une lecture PRAGMA ;
il ne transforme aucune table. Il refuse toujours la rotation sans preuve
valide, et les deux ordres de migration sont testés. Aucune migration corrective
des secrets existants n’est nécessaire pour ce point.

Si les migrations sont réellement manquantes après la photographie et la
recette, préparer un répertoire temporaire contenant uniquement ces quatre
fichiers exacts, puis utiliser le registre D1 pour n’appliquer que les entrées
manquantes dans cet ordre. Ne pas appliquer le répertoire historique complet,
ne pas utiliser `production/schema.sql` comme migration distante et ne pas
réinjecter les données de test. Ce workflow de publication n’applique aucune
migration automatiquement.

## Compatibilité et ordre des publications

Les nouveaux APK ont été vérifiés contre le véritable wrapper exporté et son
DO original, dans Miniflare sans nouvelle migration et avec le réseau externe
bloqué. L’ancien export répond 404 à `device-proof` et au ticket du panel ;
les nouveaux clients traitent l’enrôlement en best-effort et continuent ensuite
les requêtes existantes. Le header `X-Device-Secret` supplémentaire ne bloque
pas l’ancien Worker.

La recette a obtenu : WebSocket 101, activation initiale 201, puis statut,
sources, ACK, suppression et attente longue 200. Les sources disparaissent du
serveur après suppression. Le panel à tickets conserve son sondage 2 secondes
face à cet ancien Worker. Cela prouve le contrat exporté ; la version réellement
active doit encore être lue pour en déduire la compatibilité de production.

Il est donc possible de publier les APK compatibles avant le nouveau backend.
Les anciens APK qui ne savent pas envoyer la preuve n’obtiendront plus les ACK
ou les nouvelles connexions de canal protégés après mise à jour du Worker.
Ne pas annoncer un délai universel inférieur à 2 secondes pour un parc resté
sur d’anciennes versions, hors ligne ou sur un fournisseur lent.

## Vérification et limites restantes

Le check obligatoire `Stabilité panel et Worker` conserve les contrôles
historiques et ajoute le wrapper réel, ses tests et les précontrôles de release.
Le check `wrangler local + panel + box simulée` garde son nom et ses assertions.
Sa fixture charge maintenant les 61 tables exportées et les quatre migrations
sur une D1 locale neuve, enrôle les appareils simulés et ouvre une socket réelle.
Le paquet `ws` était déjà verrouillé à `8.22.0` dans le lockfile ; il est déclaré
explicitement pour ce client de test. Aucun flux fournisseur n’est ajouté.

Validations locales : tests des deux schémas, suites policy/runtime/Golden,
compatibilité de l’ancien export avec DO réel, 20 tests de précontrôle de
publication et 82 tests historiques des protections, sans changement de ces
guards ni de leurs tests. Les trois workflows sont valides en YAML et leurs
27 blocs Bash ont été contrôlés ; la syntaxe JavaScript du runner E2E et des
précontrôles est valide. Le lot autonome d’audit reste à ses 15 tests et à ses
trois fichiers figés pour son intégration séparée. Le parcours Playwright complet adapté doit encore
passer dans le check GitHub obligatoire ; le navigateur n’est pas disponible
dans cet environnement local. Aucune mesure de vidéo sur TV physique ni aucune
lecture de compte Cloudflare de production n’est revendiquée.

## Références API officielles

- [Versions et déploiements actifs](https://developers.cloudflare.com/api/resources/workers/subresources/scripts/subresources/deployments/methods/list/)
- [Métadonnées d’une version](https://developers.cloudflare.com/api/resources/workers/subresources/scripts/subresources/versions/methods/get/)
- [Namespaces et indicateur use_sqlite](https://developers.cloudflare.com/api/resources/durable_objects/)

Ces références définissent les lectures utilisées par le précontrôle ; elles
ne constituent pas une photographie du compte de production.
