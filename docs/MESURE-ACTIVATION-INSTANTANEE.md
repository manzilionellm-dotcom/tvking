# Activation instantanée panel → box : mesure, cause, correctif (5 octobre 2026)

Mission : le revendeur clique dans le panel, la box du client doit afficher
les chaînes en quelques secondes. Le propriétaire dit « ça ne marche pas ».
Tout ce qui suit a été **mesuré** (commande exécutée) ou **lu dans le code
livré**. Ce qui n'a pas pu l'être est marqué `NON VÉRIFIÉ`.

## 1. Résultat en une phrase

Le serveur prévient la box en moins d'une seconde ; c'est **la box v106 des
clients qui refuse d'importer la liste tant que le client regarde la télé**
(écran Direct ou lecteur ouvert), donc la liste n'arrive qu'au retour à
l'accueil ou jusqu'à 5 minutes plus tard. En plus, **la boîte noire n'existe
pas en production** : personne ne pouvait lire « liste chargée en N s ».

## 2. Tableau par maillon

| Maillon | Délai mesuré AVANT | Délai APRÈS correctif | Preuve |
| --- | --- | --- | --- |
| 1. Panel → Worker (`POST /api/v1/activate`, `PUT /api/v1/sources/:mac`) | 21 à 36 ms (Worker de production en local, 7 clics) | inchangé (Worker non touché) | `mesure_locale.mjs` : wrangler dev sur `claude/panel-mise-en-ligne` + box simulée |
| 2. Worker → Durable Object (`notifyBox`) | **193 ms** en production : `device_sources.updated_at` 17:08:28.076 → signal `source` seq 7 à 17:08:28.269 (MAC `MK:5C:E5:43:35:1F`) | inchangé | `GET /api/device-source/<mac>` + `GET /api/box/wait/<mac>?after=0` (lecture seule) |
| 3a. DO → box par WebSocket | prod : prise ouverte en **1 076 ms**, dernier signal rejoué **4 ms** après ; local : signal reçu **15 à 28 ms** après le clic, avant même la réponse HTTP du panel | inchangé | `ws_probe.mjs` (prod, lecture seule) ; `mesure_locale.mjs` (local) |
| 3b. DO → box par attente longue (`/api/box/wait`, v106) | prod : réponse en **820 ms** avec les 7 signaux de la MAC ; local : **19 à 35 ms** après le clic | inchangé | mêmes commandes |
| 4a. Box : décision d'importer (v106, clients) | **jamais tant que Direct ou le lecteur est ouvert** (`if (playbackBusy) return false;`, et l'écran Direct compte comme occupé) → liste au retour à l'accueil, ou re-vérification lente de l'écran Direct : **25 × 12 s = 5 min** | ordre `source` du panel = import **tout de suite**, même pendant la lecture (chemins WebSocket ET attente longue) | code de la v106 : commit `7b904c7d`, `activation_pace.dart`, `tv_live_screen.dart` ; correctif testé : `activation_pace_test.dart` (6 cas), `repair_flags_test.dart` |
| 4b. Box : décision d'importer (build de test #155) | WebSocket : tout de suite ; repli attente longue : bloqué si une chaîne joue et que la box a déjà des chaînes | les deux chemins passent par le même `_tick(sourceOrdered: true)` : une seule lecture de `device-source` par ordre | `remote_activation_watch.dart` |
| 4c. Box : import (téléchargement + analyse + SQLite) | machine de test : **0,5 s** (5 000 chaînes, 0,8 Mo), **0,8 s** (20 000, 3,3 Mo), **1,8 s** (50 000, 8,3 Mo) — `NON VÉRIFIÉ` sur box 1 Go, téléchargement réel non compté | inchangé ; la boîte noire note maintenant « chargée en N s (X chaînes) » ou « refusée après N s : raison » | `panel_m3u_import_timing_test.dart` (`MESURE import_m3u_*`) |
| 5. Lecture de la mesure par le propriétaire (boîte noire) | **impossible** : `POST /api/blackbox` → **404** en production, le panel en ligne n'a pas d'écran Boîte noire | patch prêt : `docs/patches/panel-worker-boite-noire.patch` (34 + 95 + 8 tests Worker verts, panel 37 verts + build) — **non déployé** (ordre écrit requis) | `curl -X POST https://app.7themotion.com/api/blackbox` → 404 ; `grep blackbox` sur `claude/panel-mise-en-ligne` → rien |

Délai total attendu après correctif, build 107 : **signal < 1 s + import** (quelques
secondes pour une liste moyenne). Le chiffre réel sur box se lit dans la boîte
noire, lignes `[PANEL] ordre source n°N reçu (ws|attente)` puis
`[SOURCE] liste M3U du panel chargée en N s (X chaînes)`.

## 3. Hypothèses

| # | Hypothèse | Verdict | Pourquoi |
| --- | --- | --- | --- |
| H1 | App fermée / box en veille | `NON VÉRIFIÉ` | « Dernière vue » (heartbeat) n'est lisible qu'avec un compte panel ; aucun compte fourni. Rien dans le code ne contredit l'hypothèse : sans app ouverte, aucun canal. À lire sur la fiche appareil. |
| H2 | v106 : attente longue seule, et une chaîne qui joue bloque l'import | **PROUVÉ (par le code livré)** | `7b904c7d` : `SourceFetchDecision` refuse dès `playbackBusy`, et `TvActivity.enter()` est appelé par l'écran Direct lui-même (`tv_live_screen.dart:171`). Le seul rattrapage est le timer 12 s × 25 de l'écran Direct (~5 min), ou le retour à l'accueil. |
| H3 | Ordre rapide, import lent | **FORTEMENT PROBABLE comme amplificateur, NON VÉRIFIÉ sur box** | 3 listes distinctes servies à cette MAC = 3 imports complets. Sur machine de test 50 000 chaînes = 1,8 s ; une box 1 Go est 5 à 10 fois plus lente et télécharge vraiment. Le build #156 écrit le chiffre réel. |
| H4 | Import refusé (lien mort, 0 chaîne) | `NON VÉRIFIÉ` | Aucune boîte noire en production (404). Le build #156 écrit « refusée après N s : raison ». |
| H5 | Le DO ne prévient pas la MAC, ou un seq déjà vu est ignoré | **FALSIFIÉ** | Ring de production : 7 signaux pour la MAC, chacun 100 à 200 ms après l'écriture ; WebSocket et attente longue reçoivent en < 40 ms en local ; un `seq` est rejoué à la connexion seulement s'il est plus grand que le dernier vu (`box_channel_session.dart`). |

## 4. Faits sur la MAC `MK:5C:E5:43:35:1F` (lecture seule)

- Licence : active, payée, 402 jours restants.
- 3 listes servies : 2 posées par le panel (`origin: panel`, sans libellé) et
  1 ajoutée **sur la box** (`origin: self`, libellé « Tv »). Les 3 liens sont
  **différents** (3 jeux d'identifiants, même fournisseur) : ce n'est pas un
  triple envoi, mais 3 imports. La liste « Tv » prouve qu'on a contourné le
  panel en tapant la liste à la main sur la TV.
- Historique des signaux (ring du DO) : `source` 16:37 → `activate` 17:13 →
  `source_clear` 18:01 → `renew` + `source` 18:02 → `renew` + `source` 18:35
  (UTC). Six tentatives en deux heures = symptôme « ça ne marche pas ».

## 5. Correctif livré (branche `ccr-b93e1afd-gwirw0`, base `ccr-1d45eb8b-x46ieg`)

- `SourceFetchDecision.shouldFetch(ordered:, orderWaitsIdle:)` : un ordre
  `source` / `source_clear` relit les listes tout de suite.
- `RepairFlags.sourceOrderWaitsIdle`, clé `zuno.source.order_waits_idle`,
  **coupé par défaut** ; `true` rétablit l'attente du retour à l'accueil.
- `RemoteActivationWatch` : WebSocket et attente longue appellent le même
  `_tick(sourceOrdered:)` ; lignes boîte noire `[PANEL] ordre <kind> n°<seq>
  reçu (ws|attente)` et, si une chaîne joue, `ordre liste reçu pendant la
  lecture : import tout de suite`.
- `RemoteSourceRepository` : `liste M3U du panel chargée en 12,4 s (18230
  chaînes)` / `refusée après N s : <raison expurgée>`.
- Tests : `flutter analyze` 0 erreur, 0 avertissement ; `flutter test`
  **428 verts, 2 ignorés** (les deux e2e qui exigent `RUN_E2E`) — 425 avant.

Non corrigé volontairement (la mesure ne l'accuse pas) : affichage par lots
pendant l'import, EPG repoussé, import en isolate (déjà le cas pour l'analyse).

## 6. Patch production « boîte noire » (à appliquer sur `claude/panel-mise-en-ligne`)

`docs/patches/panel-worker-boite-noire.patch` — 13 fichiers :

- Worker : `blackbox_journal.js`, `POST /api/blackbox` (limite 240/min), `GET
  /api/v1/blackbox/:mac` et `POST …/ask` (admin, ou revendeur propriétaire de
  la MAC), `blackbox_pull` dans `GET /api/status/:mac`. Table
  `device_blackbox` créée à la volée (idempotent, pas de migration à lancer).
- Panel : page `/blackbox`, entrée « Boîte noire » dans le menu, bouton sur la
  fiche appareil, `blackboxApi`.
- Vérifié sur une copie neuve de la branche : `git apply --check` OK,
  `blackbox.test.mjs` 34/34, `activation_m3u.test.mjs` 95/95,
  `box_channel.test.mjs` 8/8, `npm test` 37/37, `npm run build` OK.

Mise en ligne = **décision du propriétaire** : appliquer le patch sur
`claude/panel-mise-en-ligne`, puis `deploy-panel-cloudflare.yml`
(`confirme=DEPLOYER`, `cible=worker-puis-panel`, `mac_reference` relue avant
et après). Le Worker garde `RealtimeHub` et le binding `RT_HUB` : rien ne
change pour le canal.

## 7. Build de test

Voir la section « Build #156 » ci-dessous (remplie à la fin du run).

## 8. Remesure après correctif (à faire par le propriétaire, box de test)

1. Installer `107-test.156` sur la box de test (release `zuno-tv-test`).
2. Ouvrir une chaîne sur la box (lecteur plein écran).
3. Dans le panel : « Activation à distance », MAC de la box de test, une liste.
   Noter l'heure du clic.
4. Sur la box : Réglages → Boîte noire (ou, une fois le patch déployé, panel →
   Boîte noire). Lire :
   - `[PANEL] ordre source n°N reçu (ws)` — doit suivre le clic de < 2 s ;
   - `[PANEL] ordre liste reçu pendant la lecture : import tout de suite` ;
   - `[SOURCE] liste M3U du panel chargée en N s (X chaînes)` — c'est le
     chiffre H3 réel. S'il dépasse 10 s, la piste suivante est l'affichage par
     lots pendant l'import (non fait ici, non accusé par la mesure).
5. Comparer avec la v106 (même liste) : la ligne n'apparaît qu'au retour à
   l'accueil ou après ~5 min.

Ce que je n'ai pas pu faire ici : aucune box physique, aucun compte panel.
La chaîne serveur a été mesurée en production (lecture seule) et en local sur
le Worker de production ; la box a été mesurée par ses tests Dart.
