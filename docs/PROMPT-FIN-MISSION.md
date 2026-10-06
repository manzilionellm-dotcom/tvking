# Prompt — Finir la mission Zuno (panel → Worker → box)

Ce fichier est le premier message à donner, tel quel, à un agent (Claude Code
ou autre) ouvert sur le dépôt `manzilionellm-dotcom/tvking`. Il remplace
`PROMPT-MISSION-STABILITE.md` pour la suite du travail.

État au **6 octobre 2026, 12:15**. Tout ce qui suit a été lu dans le code,
exécuté ou relevé sur la vraie box. Le reste est marqué **HYPOTHÈSE**.

---

## 0. Qui tu es, ce que tu dois livrer

Tu es l'ingénieur responsable de toute la chaîne **panel revendeur → Worker
Cloudflare → box Android TV « Zuno » (app 7 MOTION, Flutter)**. Le
propriétaire n'est pas développeur. Il teste sur sa télé et t'envoie des
photos de la boîte noire et du panel. Il n'a pas de temps. Il veut des actes,
pas des explications répétées.

**Objectif.** Un revendeur clique dans le panel, et ce qu'il a demandé est
sur la télé en quelques secondes : ajout, retrait, activer/désactiver une
liste, activation, renouvellement. Une box peut avoir 2 ou 3 listes en même
temps. Rien ne revient tout seul après une suppression. L'app ne se fige
jamais et ne se ferme jamais pendant un import. Quand quelque chose échoue,
la boîte noire dit pourquoi, en une ligne.

Tu as fini quand **chaque problème de la section 4** est dans l'un de ces
deux états :
- **PROUVÉ** : code, test qui échoue sans le correctif et passe avec, build
  de test installé sur la SHIELD, ligne de boîte noire qui le montre ;
- **NON PROUVÉ** : la raison exacte, et ce qu'il faut pour le prouver.

Tu ne dis jamais « ça marche » sans preuve. Tu écris seulement PROUVÉ
(avec la commande, le test ou la ligne de journal) ou NON PROUVÉ.

---

## 1. Règles du propriétaire (non négociables)

1. **Jamais `publish=true`** sans un ordre écrit du propriétaire, mot pour
   mot dans la conversation (ex. « publie la 171 pour les clients »).
2. **Jamais de push sur `main`.** Jamais de `--force`. Jamais de réécriture
   d'historique sur une branche partagée.
3. **Ne touche pas à la release clients `zuno-tv`.** Les tests passent
   uniquement par `build-zuno-tv.yml` avec `test_box=true, publish=false`.
   La box de test se met à jour seule depuis la release `zuno-tv-test`.
4. **Chaque changement de comportement de la box a un interrupteur de
   repli**, éteint par défaut, dans
   `android-app/lib/core/app/repair_flags.dart` (clé `zuno.<zone>.<nom>`),
   avec un test qui prouve que le repli rend l'ancien comportement.
5. Commentaires **en français**. Pas de `print()` : utilise `debugPrint()`
   ou `BlackBox.instance`. Couleurs et tailles via `AppColors` /
   `AppTextStyles`. Voir `android-app/AGENTS.md`.
6. **Jamais dans le code, les tests, les logs ou les rapports** : lien de
   flux, nom d'utilisateur ou mot de passe IPTV, jeton complet, secret,
   clé privée, données de carte, lien contenant des identifiants. Dans les
   tests, utilise des hôtes `*.invalid` ou `127.0.0.1`.
7. **Le Worker et le panel ne se déploient que par**
   `.github/workflows/deploy-panel-cloudflare.yml`, sur la branche
   `claude/panel-mise-en-ligne`, avec `confirme=DEPLOYER`. Avant ET après
   chaque déploiement, relis la fiche d'une MAC de référence
   (`MK:80:78:60:07:4F`) dans le panel ou par l'API, et compare : licence,
   plan, échéance, nombre de listes. Ces valeurs doivent être identiques.
8. **Ne fusionne pas à l'aveugle** `ccr-1d45eb8b-x46ieg` et
   `claude/panel-mise-en-ligne` (18 fichiers en conflit, 10 pages du site
   supprimées côté app, voir `docs/DIVERGENCE-BRANCHES.md`). Rien de
   destructif.
9. **Jamais de secret backend dans le navigateur** (panel).
10. **Interdit pour obtenir du vert** : supprimer un test gênant, assouplir
    une assertion, mocker la partie difficile, coder le résultat en dur,
    avaler une exception, ajouter un réessai aveugle qui cache une course.
    Si un test est faux, prouve exactement pourquoi, puis remplace-le par
    une meilleure preuve.
11. **Mesure avant de toucher.** Pour chaque problème : reproduis-le dans un
    test, ou cite la ligne de boîte noire, AVANT d'écrire le correctif.
12. Messages de commit en français, clairs, avec la ligne
    `Co-Authored-By:` et la ligne `Claude-Session:` de ta session.
13. **Réponses au propriétaire** : en français simple, courtes. Il lit sur
    son téléphone. Dis-lui ce qu'il doit faire, et ce qu'il doit voir quand
    c'est réussi. Ne répète pas ce que tu lui as déjà dit.

---

## 2. Où tout se trouve

### Branches

| Branche | Rôle | Règle |
|---|---|---|
| `ccr-b93e1afd-gwirw0` | **Ta branche de travail.** Code de la box (Flutter), docs, patchs | Tu développes et tu pousses ici |
| `claude/panel-mise-en-ligne` | **Production** du Worker et du panel (tête `fb0277e`, déployée, run #12 vert) | Modifs Worker/panel ici, en petits commits, puis déploiement par le workflow |
| `ccr-1d45eb8b-x46ieg` | Ancienne branche de l'app. Contient `device_guard` (`3f1c841`) | Lecture et `cherry-pick -x` seulement |
| `main` | Site web Next.js | Interdit |

### Dossiers

- **Racine du dépôt** : site Next.js. Hors mission, n'y touche pas.
- **`android-app/lib/`** : app box / téléphone / PC.
  - Entrées : `main_tv.dart` (box), `main.dart` (téléphone), `main_windows.dart`.
  - `core/app/repair_flags.dart` : interrupteurs de repli.
  - `core/blackbox/` : journal (boîte noire), envoyé au panel.
  - `core/update/update_service.dart` : mise à jour automatique. La ligne
    `[MAJ] installee X · disponible Y (N source(s))` compte les adresses
    de mise à jour, pas des listes de chaînes.
  - `features/playlists/data/` :
    - `playlist_repository.dart` : base SQLite, insertion, relecture
      (`_emitCurrentState`, l. ~1122) ;
    - `remote_source_repository.dart` : listes envoyées par le panel,
      suppression sur la télé (`deleteFromTv`), refus
      (`zuno.source.tv_refused.v1`) ;
    - `xtream_client.dart` : import Xtream, en bloc unique ou par
      catégorie ;
    - `playlist_import_limits.dart` : `kXtreamSingleShotBytes = 10 Mo`,
      `kMaxChannelsPerImport` ;
    - `m3u_fetcher.dart`, `m3u_parser.dart`, `box_reset.dart`,
      `removed_list_notice.dart`.
  - `features/playlists/domain/tv_delete.dart` : règle pure de suppression
    sur la télé.
  - `features/subscription/data/remote_activation_watch.dart` : boucle
    panel → box (WebSocket, attente longue, curseur `seq`).
  - `features/subscription/domain/box_channel.dart` : `frameAlreadyHandled`.
  - `features/subscription/{domain/order_ack.dart,data/order_ack_client.dart}` :
    accusés RECEIVED / APPLIED / FAILED.
  - `features/channels/domain/channel.dart` : `ChannelPrecompute`
    (pré-calcul en isolate ; `cached…` = lecture sans calcul).
  - `features/tv/domain/live_shelves.dart` : Tendances / « Pour vous »,
    lecture du cache seulement.
  - `features/tv/presentation/tv_live_screen.dart` : écran Direct.
  - `features/tv/presentation/tv_sources_screen.dart` : écran « Mes
    sources ».
  - `features/epg/data/epg_fetch.dart` : téléchargement du guide (gzip,
    l. ~58-63).
  - Textes : `lib/l10n/app_fr.arb` (modèle) et `app_en.arb`.
- **`android-app/test/`** : tests Flutter (516 réussis, 2 ignorés au
  6 octobre).
- **`android-app/cloudflare/`** (référence = `claude/panel-mise-en-ligne`) :
  - `worker.js` : routes publiques `/api/…`, dont
    `GET /api/device-source/:mac`, `/api/self-source`, `/api/box/{ws,wait,ack}`
    et `/api/blackbox`.
  - `api_v1.js` : routes du panel `/api/v1/…`, dont
    `/api/v1/metrics/latency?hours=24` (l. ~1361).
  - `box_orders.js` : ordres, révisions, latence.
  - `device_sources_store.js` : comparaison-échange sur `version`.
  - `box_channel.js` : Durable Object `RealtimeHub`.
  - `schema.sql` (migrations additives par `ALTER TABLE … ADD COLUMN`).
  - Tests :
    - `failure_injection.test.mjs` : 60 ;
    - `panel_security.audit.mjs` : 47 ;
    - `cors_panel.test.mjs` : 6 ;
    - `order_ack_trace`, `activation_m3u`, `blackbox`, `box_channel`,
      `linkage_sim`, `reset_box_panel`, `self_source_panel`.
  - Banc D1 fidèle : `test_support/d1_sqlite.mjs` (`createD1`).
  - E2E : `concurrency.e2e.mjs`, `latency_local.e2e.mjs`, servis par
    `test_support/miniflare_server.mjs`.
- **`android-app/admin-panel/`** : panel React + Vite + TypeScript.
  - En ligne : https://tvking-admin.pages.dev
  - `src/lib/api.ts` : appels et en-têtes. Tout nouvel en-tête doit aussi
    être autorisé dans le CORS du Worker ; `cors_panel.test.mjs` le
    vérifie.
  - `src/lib/activation.ts` : plans d'essai et plans payés.
  - Pages : `ActivatePage.tsx`, `DevicesPage.tsx`, `ChainesPage.tsx` /
    PushSource (« Listes »), `BlackBoxPage.tsx`, `TracePanel.tsx`.
  - Tests : 60/60.
- **`.github/workflows/`** :
  - `build-zuno-tv.yml` : build de la box ;
  - `deploy-panel-cloudflare.yml` : mise en ligne du Worker et du panel.
    Il est sur la branche de production.
  - `quality-zuno.yml`, `worker-prod-snapshot.yml`.
- **`docs/`, à lire avant de coder, dans cet ordre** :
  1. `HANDOFF-PANEL-BOX.md` : passation complète, sections 5 sedecies à
     5 tervicies = dernières 24 h.
  2. `RAPPORT-CONTROL-CENTER.md` : 16 bugs racines, PROUVÉ / NON PROUVÉ,
     mesures locales.
  3. `MESURE-ACTIVATION-INSTANTANEE.md` : toutes les mesures box (§ 7 decies
     = ligne de liste qui disparaît).
  4. `DIVERGENCE-BRANCHES.md` : conflits, plan de réconciliation,
     `device_guard`.
  5. `patches/` : correctifs déjà appliqués en production. Ne les réapplique
     pas.

### Les deux box

| Box | MAC | État au 06/10 12:12 |
|---|---|---|
| NVIDIA SHIELD (box de test du propriétaire) | `MK:80:78:60:07:4F` | v107-test.170 (versionCode 1791275287), à jour. Mémoire stable ≈ 273 Mo. 0 liste. Dernière session « terminée normalement » (= installation de la mise à jour, 10:48) |
| Fire TV (client, Canada) | `MK:5C:E5:43:35:1F` | Hors ligne depuis le 05/10 19:16, ancien build 1791218094, 2 listes. Ne recevra les correctifs box qu'après une publication clients, sur ordre écrit |

### Builds de test (tous signés `5145b8e0…9e61`)

| Build | versionCode | SHA-256 | Contenu |
|---|---|---|---|
| #168 | 1791271081 | `3462665d…` | La suppression sur la télé tient |
| #169 | 1791272560 | `80fac869…` | ANR Direct corrigé (rayons lus en cache) |
| #170 | 1791275287 | `a516b0a25882998f126ed44b301f02aabf511bee93ea45fbd6784ccc9b93a636` (54 800 918 octets) | Ordre rejoué à la reconnexion non retraité |

---

## 3. Ce qui est déjà PROUVÉ (ne le refais pas)

- **Production Worker et panel** : patchs 1 à 8 (run #10), CORS (run #11),
  plan payé gardé quand on ajoute un essai (run #12). Les trois runs sont
  verts, avec la MAC de référence inchangée avant et après.
- **Sur la SHIELD, vu dans la boîte noire (build #168)** :
  - la liste ajoutée par le client est supprimée sur la télé ET sur le
    serveur, et ne revient pas ;
  - la liste du panel est refusée et n'est plus réimportée ;
  - l'ordre `source_clear` est accusé « appliqué » 1 s plus tard, avec son
    `trace`.
- **Concurrence (workerd + D1 local, Miniflare 4)** :
  - 100 activations simultanées → 1 licence ;
  - 5 crédits pour 100 activations → 5 réussites, solde jamais négatif ;
  - 100 envois du panel et 3 ajouts du client → aucune liste perdue.
- **Plusieurs listes en même temps, activer/désactiver instantané sans
  retéléchargement** : `test/features/playlists/tv_delete_test.dart`.
- **Tests au vert le 6 octobre** :
  - Flutter : 516 réussis, 2 ignorés ;
  - panel : 60/60 ;
  - Worker : `failure_injection` 60/60, audit 47/47, `cors_panel` 6/6.

---

## 4. Ce qui reste à finir, par priorité

Pour **chaque** point, dans cet ordre :

1. Mesure : test rouge ou ligne de journal citée.
2. Cause racine prouvée.
3. Correctif minimal.
4. Interrupteur de repli (box).
5. Test vert, plus une contre-preuve avec le repli allumé.
6. Recherche du même motif ailleurs dans le code.
7. Build de test.
8. Preuve sur la SHIELD.
9. Ligne PROUVÉ / NON PROUVÉ dans `docs/HANDOFF-PANEL-BOX.md`.

### P0 — Prouver sur la vraie box que la grosse liste ne fige plus Direct

- **Symptôme d'origine** : ANR le 06/10 à 09:07:21 sur la SHIELD. Direct a
  reçu 50 000 chaînes alors que le drapeau « pré-calcul terminé » était
  resté vrai depuis le lot de 1 000.
- **Correctif déjà livré** : commit `9e19cc5`, build #169, repli
  `zuno.direct.shelves_legacy`. Sur la machine de test : 4 861 ms → 14 ms.
- **Ce qui manque** : la preuve sur la SHIELD. Elle n'a aucune liste depuis
  ce matin.
- **Action** : demande au propriétaire, en 3 lignes :
  1. Dans le panel, ouvrir « Listes », saisir `80:78:60:07:4F`, envoyer la
     grosse liste (≈ 50 000 chaînes).
  2. Ouvrir Direct pendant le chargement et après.
  3. Photographier la boîte noire.
- **Réussi si** :
  - pas de « fermeture inattendue » ;
  - `[MEM]` reste sous ≈ 300 Mo ;
  - on voit `liste … chargée en N s (X chaînes)` ;
  - aucune ligne `[GEL]` de 3 s ou plus pendant l'import. Le chien de
    garde de `core/blackbox/black_box.dart` consigne tout retard de plus
    de 700 ms de son timer de 500 ms. Les lignes `[MEM] [périodique]`
    arrivent toutes les 30 s (`_kMemoryEvery`) : leur écart ne mesure pas
    un gel.

### P1 — Sécurité : codes IPTV lisibles avec la seule MAC (risque le plus grave)

- **Fait (PROUVÉ en lecture le 05/10)** : en production,
  `GET /api/device-source/:mac` (`worker.js`, l. ~3919 sur la branche de
  travail) rend les identifiants IPTV déchiffrés à quiconque connaît la
  MAC. Seul frein : 120 lectures par minute et par IP. Les MAC sont
  affichées sur l'écran des box.
- **Correctif existant, non déployé** : `3f1c841` sur `ccr-1d45eb8b-x46ieg`.
  Il ajoute `device_guard.js` : un secret propre à chaque box, comparé en
  temps constant. Il ferme aussi la sauvegarde cloud aux inconnus.
- **À faire, sans rien casser** (plan détaillé :
  `docs/DIVERGENCE-BRANCHES.md`, étapes 3 et 6) :
  1. Branche d'intégration depuis `claude/panel-mise-en-ligne`.
  2. `git cherry-pick -x 3f1c841`. Résous `api_v1.js`, `worker.js` et
     `source_crypto.js` à la main. `source_crypto.js` doit lire les DEUX
     formats chiffrés (expand-contract), et un test doit relire un lien
     chiffré par chaque version.
  3. **Deux époques** : une box sans secret enregistré garde la lecture
     tant que sa licence est valide. Écris un test qui le prouve. Sans lui,
     la Fire TV du client, sur un ancien build, perdrait ses chaînes.
  4. Côté box, sur `ccr-b93e1afd-gwirw0` : le code envoie déjà un secret.
     `lib/features/device/data/device_secret.dart` le génère, et
     `DeviceSecret.instance.headers()` l'ajoute dans
     `remote_source_repository.dart` (l. ~257 et ~287). Vérifie par un
     test que le nom d'en-tête et le format correspondent exactement à ce
     qu'attend `device_guard.js`, et que l'enrôlement a lieu au premier
     lancement.
  5. Tests verts : `zuno_security.test.mjs`, l'audit, `failure_injection`
     et l'e2e. Ensuite seulement, déploie par le workflow, en relisant la
     MAC de référence avant et après.
- **Réussi si** :
  - un appel sans secret pour une MAC enrôlée reçoit un refus (401/403)
    qui ne contient aucun identifiant ;
  - la SHIELD continue de charger ses listes ;
  - la Fire TV, sur l'ancien build, n'est pas coupée.

### P2 — Guide TV : `FormatException: Filter error`

- **Lieu** : `android-app/lib/features/epg/data/epg_fetch.dart`, l. ~58-63.
  Le flux est décompressé en gzip si l'URL finit par `.gz` ou si un
  en-tête dit gzip.
- **HYPOTHÈSE** (confiance moyenne, à prouver avant tout correctif) :
  double décompression. Le client HTTP de `dart:io` décompresse déjà
  (`autoUncompress` vaut vrai par défaut) une réponse
  `Content-Encoding: gzip`. L'en-tête reste visible, donc le code
  redécompresse un flux qui n'est plus du gzip, et le décodeur lève
  « Filter error ».
- **Autre cause possible** : un serveur qui répond une page HTML ou du XML
  non compressé à une URL `.gz`.
- **Preuve à produire** :
  1. Un test avec un `HttpServer` local de `dart:io` qui sert du XMLTV
     gzippé avec `Content-Encoding: gzip`, sur une URL `.gz` et une URL
     normale. Il doit reproduire l'erreur.
  2. Un second test avec un `.gz` qui contient du texte brut.
- **Correctif robuste** : décider de la décompression d'après les deux
  premiers octets du flux (`1f 8b`), pas d'après l'URL ni les en-têtes.
  Repli : `zuno.epg.gzip_by_header`.
- **Réussi si** : le guide se charge, et la boîte noire montre
  `[EPG] … N programmes` sans `Filter error`.

### P3 — La ligne de la liste disparaît pendant un long import (`FOREIGN KEY constraint failed`)

- **Fait** : boîte noire `107-test.163`, 00:16:07. L'import a échoué après
  130,9 s, parce que la ligne `playlists` n'existait plus au moment
  d'insérer les chaînes. Un filet de sécurité existe (§ 7 decies de
  `MESURE-ACTIVATION-INSTANTANEE.md`).
- **Ce qui manque : qui efface la ligne. NON VÉRIFIÉ.** Tous les chemins
  de suppression passent par `_deletePlaylist(reason)`, qui est
  journalisé. La réponse est donc dans les lignes de la boîte noire juste
  AVANT l'échec.
- **Candidats encore ouverts** :
  - une seconde synchronisation (`RemoteSourceRepository.sync`), lancée par
    un ordre WebSocket ou la vérification périodique pendant l'import, qui
    juge la liste « plus servie » ou « vide » ;
  - `pruneEmptyPlaylists` ;
  - la remise à neuf (`box_reset.dart`).
- **Action** :
  1. Écris un test qui lance un import lent (`MockClient` qui retient la
     réponse) et une synchronisation forcée en même temps.
  2. Vérifie que la ligne survit.
  3. Si le test est rouge : une liste en cours d'import ne doit être
     supprimable par aucun chemin automatique. Ajoute un verrou par id de
     liste, testé, avec un repli.
  4. Demande au propriétaire les 30 lignes de boîte noire qui précèdent
     une éventuelle nouvelle occurrence.

### P4 — Relire 50 000 chaînes prend ≈ 2,2 s sur le fil principal

- **Lieu** : `playlist_repository.dart`, `_emitCurrentState()` (l. ~1122).
  Il lance `getAllChannels()` puis la conversion des lignes en `Channel`.
  La ligne de journal correspondante est `[DB] lecture : N chaînes … en X ms`.
- **Mesure à faire** : sépare le temps de la requête SQLite (déjà hors du
  fil avec sqflite) du temps de construction des objets (sur le fil
  principal).
- **Correctif probable** :
  - construire les `Channel` dans un isolate (`compute`) à partir des
    lignes brutes ;
  - ou paginer, en ne lisant que les colonnes utiles à Direct.
  Interdit : un réessai ou un délai qui masquerait le problème. Repli :
  `zuno.db.read_main_isolate`.
- **Réussi si** : la mesure de construction sur le fil principal passe
  sous 100 ms pour 50 000 chaînes dans un test, et sur la box aucun écart
  de plus de 1 s n'apparaît entre deux lignes `[MEM]`.

### P5 — Import Xtream : 914 appels et 136 s quand la liste dépasse 10 Mo

- **Lieu** : `xtream_client.dart`, l. ~170-240. Au-delà de
  `kXtreamSingleShotBytes` (10 Mo), l'import retélécharge la liste
  catégorie par catégorie, une à une.
- **Cause** : protection mémoire des box à 1 Go.
- **Options, à mesurer avant de choisir** :
  - (a) Lire le JSON en flux, sans tout charger. C'est la meilleure option
    si elle est faisable : un seul appel, mémoire bornée.
  - (b) Relever le seuil sur les box qui ont assez de mémoire disponible
    (la SHIELD a ≈ 950 Mo de libre sur 2 946). Le seuil doit dépendre de
    la mémoire libre réelle, pas d'un modèle de box.
  - (c) Lancer 4 à 6 catégories en parallèle, avec un plafond, sans
    dépasser la limite du fournisseur.
- Repli : `zuno.xtream.per_category_serial`.
- **Réussi si** : moins de 30 s pour 50 000 chaînes sur la SHIELD, `[MEM]`
  sous 350 Mo, et aucun refus du fournisseur (HTTP 429 ou 403) dans le
  journal.

### P6 — Latence de production jamais relevée

- **Lieu** : `GET /api/v1/metrics/latency?hours=24` (admin). Le panel
  l'affiche déjà (`api.ts`, l. ~684).
- **Action** : relève p50, p95 et p99 par opération (activation,
  renouvellement, listes), pour les segments `applied` et `failed`, et le
  nombre d'ordres `expired`. Inscris les chiffres avec leur date dans
  `RAPPORT-CONTROL-CENTER.md` § 6.
- **Règle** : une valeur absente s'écrit `NON MESURÉ`, jamais `0`.

### P7 — Réconciliation des branches (à faire seulement après P1)

- Suis `docs/DIVERGENCE-BRANCHES.md`, étapes 1 à 7.
- Ne reprends jamais les suppressions de pages du site.
- Termine par une PR relue par une personne. Jamais de fusion directe.

---

## 5. Commandes (ce qui définit « vert »)

```bash
# Box (dans android-app/)
flutter analyze                     # 0 erreur ; ne pas ajouter d'avertissement dans un fichier touché
flutter test                        # ≥ 516 réussis, 0 échec

# Worker (dans android-app/, sur la branche de production)
node --experimental-sqlite cloudflare/failure_injection.test.mjs
node --experimental-sqlite cloudflare/panel_security.audit.mjs
node --experimental-sqlite cloudflare/cors_panel.test.mjs
node --experimental-sqlite cloudflare/order_ack_trace.test.mjs
# (+ activation_m3u, blackbox, box_channel, linkage_sim, reset_box_panel, self_source_panel)

# E2E réel : workerd + D1 local + Durable Object, SANS le proxy de wrangler dev
npx wrangler@4 deploy --dry-run --outdir /tmp/paquet   # dans android-app/cloudflare
WORKER_BUNDLE=/tmp/paquet/worker.js \
MINIFLARE=<chemin>/node_modules/miniflare/dist/src/index.js \
  node --experimental-sqlite cloudflare/concurrency.e2e.mjs   # miniflare@4, pas la 5 alpha

# Panel (dans android-app/admin-panel/)
npm ci && npm test && npm run build      # 60/60 + build OK
```

**Build de test de la box** : lance `build-zuno-tv.yml` sur
`ccr-b93e1afd-gwirw0` avec `test_box=true, publish=false`. Relève ensuite
le versionCode, le SHA-256, la taille et la signature (`5145b8e0…9e61`).
La SHIELD vérifie toutes les 60 s et installe seule quand l'app est à
l'écran.

---

## 6. Pièges déjà rencontrés (ne perds pas de temps dessus)

- **wrangler 3.x** (fixé à 3.90 dans le workflow de déploiement) fuit des
  descripteurs de fichiers en local. Ne l'utilise jamais pour un test de
  charge.
- **`wrangler dev` (v4)** place un ProxyWorker qui perd des POST sous
  charge (« Network connection lost »). Pour l'e2e, utilise Miniflare 4
  avec le paquet `--dry-run`.
- **Modifier un fichier du Worker pendant un `wrangler dev`** recharge le
  Worker et fausse la mesure en cours (503).
- **`pkill -f` / `pgrep -f`** dont le motif apparaît dans ta propre
  commande tue ton propre shell. Mets ces commandes dans un script.
- **Tout en-tête ajouté côté panel** (`api.ts`) doit être autorisé dans le
  CORS du Worker (`worker.js` ET `api_v1.js`). Sinon, toute modification
  depuis le panel affiche « Connexion impossible ». C'est arrivé en
  production le 6 octobre ; `cors_panel.test.mjs` protège maintenant ce
  cas.
- **Les getters `Channel.cleanName` / `genre` / `country` CALCULENT**
  (expressions régulières) quand la valeur manque. Sur le fil UI, lis
  uniquement `ChannelPrecompute.cached…`.
- **« Lire MAX puis insérer »** ou **« compter puis insérer »** sur D1
  donne des doublons sous concurrence. Fais le calcul DANS l'`INSERT`
  (`INSERT … SELECT … WHERE NOT EXISTS`, `ON CONFLICT DO NOTHING`).
- Migrations : **additives seulement** (expand-contract). Un retour arrière
  sur Cloudflare restaure le code, pas les données.

---

## 7. Format de ton rapport final

1. Un tableau, une ligne par problème P0 à P7, avec les colonnes :
   problème · cause racine · correctif (fichier:ligne, commit) · test ·
   repli · build · preuve box · **PROUVÉ / NON PROUVÉ**.
2. Les résultats exacts de chaque suite de tests (nombres, pas « vert »).
3. Les empreintes de chaque build de test.
4. Les risques de production restants, une ligne chacun.
5. Pour le propriétaire, trois lignes au plus en français simple : ce
   qu'il doit faire sur la télé, et ce qu'il doit voir.

Mets à jour `docs/HANDOFF-PANEL-BOX.md`, `docs/RAPPORT-CONTROL-CENTER.md`
et ce fichier (section 2, « Les deux box », et section 4) à la fin de
chaque étape, puis pousse sur `ccr-b93e1afd-gwirw0`.
