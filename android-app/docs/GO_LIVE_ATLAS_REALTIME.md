# Atlas realtime — procédure de mise en production (NON EXÉCUTÉE)

Préparé le 07/11/2026 16:57 CET (Europe/Stockholm). Phase B = préparation uniquement : aucun déploiement, migration distante, secret, signature ni envoi Play effectué.
PR de revue : https://github.com/manzilionellm-dotcom/tvking/pull/223
Source proposée après revue/merge : `release/atlas-console-20261029`, avec les changements de `feat/atlas-device-realtime-release-20261107`. Ne pas déployer `main` (en retard ; réconciliation séparée).

## 0. Accès et preuves contrôlés

- Wrangler local : `android-app/cloudflare/node_modules/.bin/wrangler` **4.158.0**. `wrangler whoami` : **non authentifié**. Aucune variable Cloudflare/Codemagic/Vercel/Play/keystore correspondante trouvée dans l'environnement de la box (contrôle des noms uniquement).
- GitHub : noms de secrets dépôt présents `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `ANDROID_KEYSTORE_PASSWORD` (et secrets Samsung sans rapport). Leur présence ne prouve ni validité ni droits ; valeurs jamais lues. Les secrets d'environnement GitHub n'ont pas été inventoriés.
- Vercel MCP : liste visible `atlas-console-k7q2`, projet `prj_EfE7A4Qp12tiuqeQo9NhbAQDssFX`, équipe `team_TxhAqf7Tz62ritlOcFNSmaXy`. La lecture des détails retourne **404 même avec ces identifiants** : accès aux réglages/branche de production non confirmé. Aucun token Vercel CLI en environnement. Il faut un accès production au bon projet (ou une session CLI autorisée), pas recréer un projet.
- `android-app/codemagic.yaml` : workflow **ios-the-few** uniquement, signature iOS App Store, intégration **The Few ASC Key**. Aucun workflow Android/signature Android/publication Play, aucun groupe Android/keystore déclaré. Aucun nom de variable de jeton Codemagic dans la box.
- Sur la branche release, `.github/workflows/publish-phone-aab.yml` et `publish-tv-aab.yml` publient un **artefact existant** dans une release GitHub ; ils ne construisent/signent ni n'envoient à Google Play. Ils référencent `build-android.yml`, absent de cette branche. Le registre GitHub liste `build-android.yml` et `build-zuno-play-editions.yml`, mais leur source sur `main` est introuvable (404) : aucune garantie de build signé sur la source release.
- `.github/workflows/deploy-panel-cloudflare.yml` existe sur release : déploiement Worker + Pages, manuel/protégé ; utilise les noms `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID`. Ce n'est pas un déploiement Vercel. Aucun déclenchement effectué.

### Accès à fournir avant exécution

1. Cloudflare : login Wrangler délibéré ou jeton à droits Workers Scripts + Durable Objects + D1 sur le compte du Worker (et accès à la DB ci-dessous). Les secrets GitHub existants pourraient servir dans un workflow explicitement approuvé sans les exporter vers la box.
2. Vercel : confirmer accès à l'équipe/projet ci-dessus, Root Directory, branche de production et variables API. Résoudre le 404 des détails avant tout déploiement.
3. Android : **package Play exact**, keystore d'upload existant/certificat attendu, alias et mots de passe via gestionnaire de secrets autorisé ; workflow de build signé sur la branche release. Ne jamais créer une nouvelle identité de signature au hasard.
4. Play : compte/connexion ou compte de service avec droits sur l'application et la piste choisie, choix de piste, code maximal réellement enregistré et éventuels formulaires de conformité. Codemagic est facultatif si une CI Android signée est mise en place ailleurs.

## 1. Préconditions et sauvegardes

Exécuter seulement après approbation production distincte, sur un checkout propre du commit release **révisé** :

```bash
cd /workspace/atlas-console/tvking
env -u GITHUB_TOKEN -u GH_TOKEN git fetch origin
env -u GITHUB_TOKEN -u GH_TOKEN git switch release/atlas-console-20261029
env -u GITHUB_TOKEN -u GH_TOKEN git pull --ff-only origin release/atlas-console-20261029
env -u GITHUB_TOKEN -u GH_TOKEN git status --short
cd android-app/cloudflare
export WRANGLER_SEND_METRICS=false
WRANGLER="$PWD/node_modules/.bin/wrangler"
"$WRANGLER" whoami
"$WRANGLER" deployments list --config wrangler.toml
"$WRANGLER" d1 time-travel info tvking_licensing --config wrangler.toml --json
"$WRANGLER" d1 migrations list tvking_licensing --remote --config wrangler.toml
```

Conserver dans le journal de release privé : commit, **version-id** du Worker actuellement à 100 %, bookmark D1 pré-migration, URL Vercel production précédente. Les timestamps API `Z` du journal doivent être convertis en Europe/Stockholm. Aucun dump D1 dans Git : il contient des données privées.
Cibles : Worker `seven-motion-backend`, DB `tvking_licensing` / `67303737-a50b-4258-86de-662fb9aba6e7`, binding `DB`, Durable Object `RT_HUB` / `RealtimeHub`. Préserver la migration DO existante `v1-rt-hub` ; ne pas recréer/supprimer le namespace.

## 2. D1 — migrations 010 à 012

Pré-requis : schéma existant et migrations 002–009 déjà appliqués/conciliés dans le suivi Wrangler, notamment **003** (`parent_reseller_id`). La commande ci-dessous applique **toutes** les migrations non suivies, pas seulement les trois dernières : si la liste précédente contient 002–009, **STOP** et concilier le ledger avec un DBA après comparaison de schéma. Ne pas rejouer aveuglément les ALTER TABLE historiques.
La liste attendue doit être exactement :

- `010_device_session_keys.sql`
- `011_account_security.sql`
- `012_reseller_limits.sql`

```bash
cd /workspace/atlas-console/tvking/android-app/cloudflare
WRANGLER="$PWD/node_modules/.bin/wrangler"
"$WRANGLER" d1 migrations apply tvking_licensing --remote --config wrangler.toml
"$WRANGLER" d1 migrations list tvking_licensing --remote --config wrangler.toml
```

Ces migrations ajoutent des tables/index et des triggers de limites ; pas de suppression de données. En cas d'échec, Wrangler annule la migration échouée, pas les précédentes déjà réussies. Arrêter avant le Worker si une migration manque.

## 3. Secrets nouveaux — sans valeur dans la console ni dans Git

Ne jamais activer `set -x`, `tee` ou afficher un fichier secret. Vérifier auparavant si les noms existent (`wrangler secret list`) : **ne pas écraser** une clé en service. Préserver les secrets actuels `ADMIN_SECRET`, `SOURCE_ENCRYPTION_KEY` / `SECRETS_KEY` ; une rotation non coordonnée rendrait sessions ou données illisibles.
Pour le premier provisionnement uniquement, génération OpenSSL au moment de l'opération :

```bash
cd /workspace/atlas-console/tvking/android-app/cloudflare
set +x
umask 077
WRANGLER="$PWD/node_modules/.bin/wrangler"
PRIVATE_DIR="$(mktemp -d /workspace/atlas-secrets-XXXXXXXX)"
openssl rand -hex 32 > "$PRIVATE_DIR/DEVICE_TOKEN_SECRET"
openssl rand -hex 32 > "$PRIVATE_DIR/ACCOUNT_ENCRYPTION_KEY"
"$WRANGLER" secret put DEVICE_TOKEN_SECRET --config wrangler.toml < "$PRIVATE_DIR/DEVICE_TOKEN_SECRET"
"$WRANGLER" secret put ACCOUNT_ENCRYPTION_KEY --config wrangler.toml < "$PRIVATE_DIR/ACCOUNT_ENCRYPTION_KEY"
```

Avant de supprimer ces deux fichiers locaux privés, transférer les valeurs au **gestionnaire de secrets approuvé**, sans les imprimer ni les envoyer par message. Ne pas poursuivre l'enrôlement 2FA tant que la sauvegarde sûre n'est pas confirmée. Puis supprimer uniquement les deux fichiers et leur répertoire temporaire. Les commandes `secret put` modifient la production ; elles n'ont PAS été lancées durant cette mission.
**ACCOUNT_ENCRYPTION_KEY doit rester stable** après l'enrôlement TOTP. Si des comptes ont été enrôlés en repli avec `ADMIN_SECRET`, prévoir une migration/réinscription supervisée avant de changer la clé : aucune conversion automatique du chiffrement n'est implémentée.

## 4. Worker

```bash
cd /workspace/atlas-console/tvking/android-app/cloudflare
npm ci
npm test
WRANGLER_SEND_METRICS=false npm run test:realtime
WRANGLER_SEND_METRICS=false node_modules/.bin/wrangler deploy --config wrangler.toml
```

Cible à vérifier dans la sortie : `https://seven-motion-backend.manzilionel-lm.workers.dev` (pas l'ancien backend). Vérifier `PANEL_ORIGINS` si configuré : allowlist exacte, défaut `https://atlas-console-k7q2.vercel.app`. Ne pas élargir à `*`.
Contrôles après déploiement : auth admin/sessions, appareil activé → token → ticket unique → WS, cache `no-store`, global vs MAC, révocation/limites revendeur. Mesurer sur appareil physique chaque modification et suppression de liste. Objectif < 1 s **quand connecté**, non garanti avant mesure ; hors ligne, repli léger ≈30 s, refetch complet à reconnexion/reprise. Aucun URL/M3U privé dans les journaux.

## 5. Vercel — Atlas Console

Déployer **le commit relu de `release/atlas-console-20261029` après merge approuvé**, jamais `main` et jamais une branche `gh-pages`. Le nom réel trouvé est `atlas-console-k7q2`, pas `atlas-console`.
Dans un checkout de la racine du dépôt, avec un CLI Vercel installé et une authentification à droits production :

```bash
cd /workspace/atlas-console/tvking
vercel project inspect atlas-console-k7q2 --scope team_TxhAqf7Tz62ritlOcFNSmaXy --non-interactive
# STOP sur 404/auth/link_required ou tout projet/cible inattendu.
# Si nécessaire : liaison explicite autorisée au dépôt RACINE, pas au sous-dossier
# (le projet a déjà Root Directory=android-app/admin-panel).
vercel link --project atlas-console-k7q2 --scope team_TxhAqf7Tz62ritlOcFNSmaXy
vercel project inspect --non-interactive
vercel deploy --prod --skip-domain --scope team_TxhAqf7Tz62ritlOcFNSmaXy
# Copier l'URL retournée dans une variable non secrète DEPLOYMENT_URL,
# vérifier cette production préparée puis seulement après validation :
vercel promote "$DEPLOYMENT_URL" --scope team_TxhAqf7Tz62ritlOcFNSmaXy
```

Les détails projet sont actuellement inaccessibles : confirmer **Root Directory `android-app/admin-panel`** et branche avant ces commandes. Ne pas créer de projet de remplacement pour contourner le manque d'accès. Vérifier les variables API production sans exposer leur valeur. Déploiement préparé et promotion sont tous deux des actions production nécessitant autorisation.
Erreur Vercel connue : Root Directory absent de `gh-pages`. Proposition uniquement, **non appliquée** : Ignored Build Step `test "$VERCEL_GIT_COMMIT_REF" = "gh-pages"` (code 0 = ignorer ; code 1 = construire). Les autres branches continuent à construire ; `main` reste à réconcilier plus tard.

## 6. AAB / Google Play — bloqueurs de sécurité, version

- Source release : `android-app/pubspec.yaml` **0.3.0+11**, Gradle `versionCode = flutter.versionCode` ; aucun override Android Codemagic confirmé. Ce n'est **pas** une preuve de versionCode 117 sur Play.
- Gradle de cette branche : `applicationId = com.example.tv_king`, signature `release` avec la **clé debug**. **Ne pas téléverser cet AAB sur Play.** Confirmer le package Play réel et adapter le build/CI signé avant toute publication. Ne pas inventer package/alias/clé.
- Proposer **118 seulement si le maximum Play constaté est ≤117** ; sinon `maximum Play + 1`. Ne pas réduire un ancien code élevé (même sur une autre piste). Aucune version modifiée aveuglément.
- Une fois identité de package, clé d'upload, version et workflow revus : commande de build type `flutter build appbundle --release --build-number=118 --dart-define=API_BASE=https://seven-motion-backend.manzilionel-lm.workers.dev` ; **118 à remplacer par le code validé**. Le workflow doit injecter la configuration release, pas conserver `signingConfigs.debug`.
- Vérifier certificat de signature, package et versionCode de l'artefact avant upload ; API Play ou accès console autorisé + piste de test/production choisie + formulaires éventuels requis. Commencer par test interne ou déploiement progressif après validation physique mobile/TV. Aucun upload, build signé ni workflow externe déclenché dans cette phase.

## 7. Retours arrière

### Worker
```bash
cd /workspace/atlas-console/tvking/android-app/cloudflare
node_modules/.bin/wrangler rollback "$PREVIOUS_WORKER_VERSION_ID" --config wrangler.toml --message "Retour arriere Atlas realtime"
```
Utiliser un **version-id** capturé à l'étape 1, pas un deployment-id. Conserver DO/migrations/bindings. Vérifier compatibilité du code antérieur avec les nouveaux schémas/triggers avant retour.

### D1
Ne pas supprimer les tables de sessions ni les clés d'appareil pour un simple rollback code. Les triggers 012 peuvent affecter l'ancien Worker : vérifier les politiques et privilégier une correction en avant ou une migration inverse relue, jamais `DROP` improvisé. Pour incident majeur seulement : maintenance, gel des écritures, approbation explicite de la perte des écritures post-bookmark, puis `wrangler d1 time-travel restore tvking_licensing --bookmark "$PRE_MIGRATION_BOOKMARK" --config wrangler.toml`. Cette restauration destructive exige une décision distincte ; tester d'abord sur copie et restaurer aussi un Worker compatible.

### Secrets
Ne jamais régénérer ACCOUNT_ENCRYPTION_KEY en rollback. Restaurer **la même** valeur sauvegardée via `wrangler secret put ACCOUNT_ENCRYPTION_KEY`, sinon réinscription 2FA supervisée nécessaire. Une rotation DEVICE_TOKEN_SECRET invalide les tokens d'appareil et requiert leur renouvellement par activation/status. Garder l'ancien code/secret cohérents.

### Vercel
```bash
vercel rollback "$PREVIOUS_VERCEL_DEPLOYMENT_URL" --scope team_TxhAqf7Tz62ritlOcFNSmaXy
```
Le rollback désactive l'assignation automatique des nouvelles productions ; la rétablir par une promotion validée. Vérifier domaines, API et sessions ensuite.

### Google Play
Arrêter le rollout/la piste problématique. On ne peut pas diminuer le versionCode : corriger et republier avec un numéro supérieur au maximum enregistré. Garder package et clé d'upload inchangés. Révocation des accès et changement des mots de passe admin par défaut avant ouverture publique, sans jamais consigner ces anciens identifiants dans le PR/runbook.
