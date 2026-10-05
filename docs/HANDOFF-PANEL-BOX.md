# Passation — Panel ↔ Worker ↔ App box Zuno (état au 4 octobre 2026)

Tout ce qui suit a été vérifié dans le code ou en production (lecture seule)
le 4 octobre 2026. « NON VÉRIFIÉ » est écrit quand ce n'est pas le cas.

## 1. Où sont les choses

Un seul dépôt GitHub : `manzilionellm-dotcom/tvking`.

| Pièce | Dossier | Techno | En ligne |
| --- | --- | --- | --- |
| App box Android TV / Fire TV « Zuno » | `android-app/` (point d'entrée `lib/main_tv.dart`) | Flutter 3.47, Dart, lecteur natif Media3 dans `packages/native_video_player/` | APK sur la release GitHub `zuno-tv` (clients) |
| Panel revendeur | `android-app/admin-panel/` | React + Vite + TypeScript | `https://tvking-admin.pages.dev` (Cloudflare Pages, projet `tvking-admin`) |
| Backend (« Worker ») | `android-app/cloudflare/` (`worker.js` routes publiques, `api_v1.js` routes du panel, `wrangler.toml`) | Cloudflare Worker `seven-motion-backend` + base D1 `tvking_licensing` | `https://app.7themotion.com` |

## 2. Branches : ATTENTION, deux lignes ont divergé

- **Production (panel + Worker)** = branche `claude/panel-mise-en-ligne`
  (dernier commit `0896028c`, panel mis en ligne le 4 octobre).
- **App box (travail récent)** = branche `ccr-1d45eb8b-x46ieg`, issue de
  `claude/zuno-complet`.
- `main` n'est la source d'aucune des deux productions.
- Les deux lignes se sont séparées le 24 septembre (`fde70596`). 25 fichiers
  ont été modifiés des deux côtés, dont `cloudflare/worker.js`,
  `cloudflare/api_v1.js`, l'abonnement de l'app et l'écran d'activation.
  Ne pas fusionner à l'aveugle.
- Le Worker de la ligne app (`ccr-…`) contient des routes absentes de la
  production : `/api/box/wait` (canal instantané), retraits de listes
  (`revoked`, `source_rev`), `source_revoke.js`. **Il n'est pas déployé.**
  Vérifié en production : `/api/box/wait` → 404, `/api/status` sans `revoked`.

## 3. Comment la box parle au Worker

Adresse compilée dans l'APK : `kSubscriptionBaseUrl`
(`lib/features/subscription/data/subscription_backend.dart`), défaut
`https://app.7themotion.com`, surchargeable par `--dart-define=BACKEND_URL`.

Identité de la box : MAC « `MK:XX:XX:XX:XX:XX` » (MK + 5 octets, dérivée
d'ANDROID_ID, `lib/features/device/data/device_identity.dart`). C'est la clé
de tout côté serveur. Depuis le build #152, la box l'**affiche** sans « MK: » ;
le panel complète « MK: » tout seul.

| Appel de la box | Rôle |
| --- | --- |
| `POST /api/heartbeat` | présence (« Dernière vue »), modèle, version, inventaire des listes sur la TV (« Sur la TV du client · inventaire réel ») |
| `GET /api/status/<mac>` | licence : `exists, status, paid, paid_until, days_left, expired, frozen, banned, trial_until` |
| `GET /api/device-source/<mac>` | listes poussées par le panel (`sources[]`, 1 à 3, déchiffrées) |
| `GET /api/announcement`, `/api/featured`, `/api/home-layout`, `/api/theme`, `/api/pricing`, `/api/app-version`, `/api/ad`, `/api/greeting`, `/api/servers`, `/api/feedback-prompt` | réglages publics posés depuis le panel |

Rythme : `RemoteActivationWatch` (`lib/features/subscription/data/remote_activation_watch.dart`)
essaie le canal long `/api/box/wait` ; en production il répond 404, donc la
box retombe sur la relecture régulière du statut, et relit `device-source` à
chaque tour (sauf si une chaîne joue et que la box a déjà des chaînes).

Règle d'effacement des listes sur la box
(`lib/features/playlists/domain/source_fingerprint.dart`, `fingerprintsToDrop`) :
une liste vue un jour depuis le serveur et qui n'est plus servie est effacée
(chaînes, favoris, récents compris). Présente aussi dans la v106 clients.

Listes sur la box : table SQLite `playlists`. Sur TV, plusieurs listes sont
visibles en même temps ; chacune a un drapeau `hidden`
(`PlaylistRepository.setPlaylistHidden`, masquer / réafficher instantané,
sans retéléchargement). **Le panel ne sait pas encore piloter ce drapeau.**

## 4. Comment le panel parle au Worker

Routes `/api/v1/*`, authentifiées (session du panel, `admin-panel/src/lib/api.ts`).

| Action panel | Route |
| --- | --- |
| Fiche appareil (licence, présence, listes poussées déchiffrées, inventaire TV) | `GET /api/v1/devices/:id/overview` |
| Pousser 1 à 3 listes | `PUT /api/v1/sources/:mac` `{sources:[…]}` — **remplace l'ensemble** |
| Effacer les listes poussées | `DELETE /api/v1/sources/:mac` |
| Bouton « Supprimer » par liste (en ligne depuis le 4/10) | renvoie les autres listes par `PUT`, ou `DELETE` si c'était la dernière (`admin-panel/src/lib/sources.ts`) |
| Activer / prolonger | `POST /api/v1/activate` ; essai : `POST /api/v1/trial-extend` |
| Annonces | `/api/v1/announcements` |

Le Worker de production ne garde, pour chaque liste, que
`type, label, server_url, username, password, m3u_url, epg_url`
(`normalizeSource` dans `api_v1.js`). **Tout autre champ est supprimé.**
Mots de passe et URL M3U sont chiffrés en base (`SOURCE_ENCRYPTION_KEY`).

## 5. Mises en ligne

- **Panel / Worker** : workflow `.github/workflows/deploy-panel-cloudflare.yml`
  (sur la branche `claude/panel-mise-en-ligne`), lancement manuel, entrée
  `confirme = DEPLOYER`, `cible = worker-puis-panel | worker-seul | panel-seul`,
  `mac_reference` relue avant/après. Secrets `CLOUDFLARE_API_TOKEN`,
  `CLOUDFLARE_ACCOUNT_ID`.
  - Run #3 (4/10, `panel-seul`) : vert.
  - Run #2 (3/10) : **échec à l'étape « DÉPLOYER le Worker »**, cause non
    analysée. À comprendre avant tout nouveau déploiement du Worker.
- **App box** : workflow `.github/workflows/build-zuno-tv.yml`
  (`publish`, `play_aab`, `test_box`, `backend_url`, `variante`).
  - `test_box=true` → release `zuno-tv-test` (box de test, jamais les clients).
  - `publish=true` (sans `test_box`) → release `zuno-tv` = **tous les clients**.
  - Signature obligatoire : certificat SHA-256
    `5145b8e019f6d5fb96a207f2e73673fd954f799966fd598889211556cbdf9e61`.
  - Numéro visible : chaque publication client prend le suivant (106 → 107…),
    un build de test s'appelle `107-test.<run>`.
  - Mise à jour dans l'app : lit `zuno-tv/version.json` (le build de test lit
    aussi `zuno-tv-test`), exige `sha256` et `size`.
- **AAB Google Play** : `play_aab=true` → minSdk 24, permission d'installation
  retirée. Package `com.sevenmotion.tv.seven_tv`, test fermé en cours.

## 5 bis. Mises à jour du 5 octobre

- Un autre ingénieur a fusionné la PR #97 (`cursor/canal-temps-reel-worker-c1d5`)
  dans `claude/panel-mise-en-ligne` et l'a déployée (run #4, Worker + panel).
  En production : `/api/box/wait` répond 200, le Worker prévient la box à
  chaque `activate`/`renew`/`source`/`source_clear` (voir `docs/CANAL-TEMPS-REEL.md`
  sur cette branche).
- Commit `ef3b387d` par-dessus (run #5, `panel-seul`, Worker non touché) :
  écran **« Activation à distance »** (`/activation-distance`,
  `admin-panel/src/pages/RemoteActivatePage.tsx`) = licence + liste en un
  bouton, liste vérifiée avant l'activation, listes existantes gardées ;
  correctif du bouton « Supprimer » : une liste ajoutée par le client
  (`origin = self`) n'est plus renvoyée comme liste du panel.

## 5 ter. Interrupteur allumé / éteint et box réunie (5 octobre, fin d'après-midi)

- Branche app `ccr-1d45eb8b-x46ieg` : fusion de `cursor/canal-temps-reel-box-c1d5`
  (WebSocket de l'autre ingénieur) + pastille « Mise à jour… » pendant le
  chargement d'une liste du panel (durée dans la boîte noire) + interrupteur :
  `enabled:false` → `setPlaylistHidden`, rallumage sans retéléchargement, liste
  masquée par le client jamais rallumée. Tests 422 verts.
  Build de test **#154** = `107-test.154`, versionCode 1791217147, SHA-256
  `8593179837f9890b2e5d819f183a5f6136806ada7d1468c074c248621e6c0a00`, signé `5145b8e0…`.
- Branche panel `claude/panel-mise-en-ligne` : `211f228b` (Worker garde
  `enabled:false`, interrupteur « Allumée / Éteinte » dans la fiche appareil),
  Worker **et** panel déployés (run #6). Job Worker vert ; le contrôle final du
  panel a été un faux rouge (propagation Cloudflare), repassé vert à la main,
  corrigé par des nouvelles tentatives (`39b1b842`).
- Les box clients v106 ignorent `enabled` : la liste reste visible chez elles
  jusqu'à la publication de la 107.

## 5 quater. Essais gratuits, Windows qui se met à jour, box #155 (5 octobre, soir)

- Panel `636aad6c` (run #8, panel seul, vert) : Activation à distance propose
  Essai gratuit 3 j / 7 j / 1 mois (`trial_3d`, `trial_7d`, `trial_30d`, 0 crédit,
  défaut 7 j) et Abonnement payé 1 an / à vie. Preuve sur le vrai Worker : 95/95.
- App `f5971b7` : Zuno PC se met à jour depuis l'app (`zuno-windows/version.json`,
  installeur vérifié SHA-256 + taille, `/SILENT`, relance par Inno Setup).
  Windows #13 vert (artefact seulement, non publié). Box #155 = `107-test.155`,
  versionCode 1791218094, SHA-256 `9cd1bee0…942d46`, signé `5145b8e0…`.

## 5 quinquies. « L'activation ne marche pas » : mesure et cause (5 octobre, nuit)

Rapport complet : `docs/MESURE-ACTIVATION-INSTANTANEE.md`.

- **Serveur hors de cause, mesuré** : Worker → Durable Object en 193 ms en
  production (ring de `MK:5C:E5:43:35:1F`), WebSocket ouvert en 1,1 s et
  signal rejoué en 4 ms, attente longue en 0,8 s ; en local sur le Worker
  de production, le signal atteint la box simulée 15 à 35 ms après le clic.
- **Cause prouvée dans la v106 des clients (`7b904c7d`)** : la box refuse
  d'importer la liste du panel tant que Direct ou le lecteur est ouvert
  (`if (playbackBusy) return false;`, et l'écran Direct compte comme occupé).
  La liste n'arrive qu'au retour à l'accueil ou ~5 min plus tard. Le #155 ne
  corrigeait que le chemin WebSocket.
- **Correctif app** (branche `ccr-b93e1afd-gwirw0`, issue de
  `ccr-1d45eb8b-x46ieg`) : un ordre `source` du panel importe tout de suite
  sur les deux chemins ; repli `zuno.source.order_waits_idle` (coupé) ;
  boîte noire : `[PANEL] ordre source n°N reçu (ws|attente)`,
  `[SOURCE] liste M3U du panel chargée en N s (X chaînes)` / `refusée après
  N s : raison`. 428 tests verts.
- **La boîte noire n'est PAS en production** : `POST /api/blackbox` → 404,
  pas d'écran dans le panel en ligne. Patch prêt et vérifié (Worker + panel) :
  `docs/patches/panel-worker-boite-noire.patch`, à appliquer sur
  `claude/panel-mise-en-ligne` puis déployer avec `confirme=DEPLOYER`
  (décision du propriétaire).
- Sur `MK:5C:E5:43:35:1F` : 3 listes différentes (2 du panel, 1 tapée sur la
  TV, libellé « Tv ») = 3 imports, pas un triple envoi.
- Build de test **#156** = `107-test.156`, versionCode 1791226009, SHA-256
  `bcc1cbee…95c96`, signé `5145b8e0…` (release `zuno-tv-test` seule,
  `zuno-tv` non touchée). Détail : rapport, section 7.

## 5 sexies. « Mise à jour… » pendant 10 minutes sur la box de test (5 octobre, 21:04)

Première mesure réelle du maillon import : après l'installation du #156, la
pastille est restée 10 min. Deuxième correctif sur `ccr-b93e1afd-gwirw0`,
détail dans `docs/MESURE-ACTIVATION-INSTANTANEE.md` § 7 bis :

- passe automatique (2 min après l'ouverture, puis 6 h) : ne retélécharge
  plus une liste à jour depuis moins de 6 h (avant : 2 min, donc les 3
  listes à chaque ouverture) ; Redémarrer garde la passe complète ;
  repli `zuno.refresh.auto_full` ;
- nouvelle liste sur une box vide : les 1 000 premières chaînes s'affichent
  pendant que le reste s'enregistre ; repli `zuno.import.first_batch_off` ;
  box déjà garnie : inchangé (anti-OOM P1-3) ;
- pastille « Mise à jour… · 12.4 Mo / · 18 230 / · 12 000 / 18 230 ».

## 6. Règles du propriétaire (non négociables)

- Jamais `publish=true` sans son ordre écrit ; jamais de push sur `main`.
- Ne pas toucher la release `zuno-tv` (clients), `phone-latest`, le 4K Player.
- Ne supprimer aucune branche, PR ou run.
- Chaque changement de comportement garde un interrupteur de repli coupé par
  défaut (`lib/core/app/repair_flags.dart`, `BoxFlag`).
- Commentaires en français, pas de `print()`, aucune URL de flux ni mot de
  passe dans le code, les tests ou les journaux.
- Dire « ça marche » seulement avec la commande exécutée qui le prouve.

## 7. Commandes de vérification

```bash
# App
cd android-app && flutter analyze && flutter test        # 415 verts au 4/10
# Panel
cd android-app/admin-panel && npm ci && npm test && npm run build   # 20/20
# Worker
cd android-app/cloudflare && node --check worker.js && node --check api_v1.js
```

Workflow `e2e-panel-box.yml` (branche du panel) : tests panel ↔ box, vert au 4/10.

## 8. Travail non terminé (à préciser par le propriétaire)

- Bouton « Activer / Désactiver » une liste depuis le panel : demande que le
  Worker garde un champ en plus, que la box applique `hidden`, et un bouton
  panel. Les box v106 ignoreront le champ.
- Retirer depuis le panel une liste ajoutée par le client lui-même : demande
  les « retraits » (`revoked`) du Worker de la ligne app.
- Faire converger le Worker de production et celui de la ligne app (canal
  instantané, retraits, bannières `/api/banners` qui n'existe nulle part).
- Écran noir après environ 1 min et son dégradé sur la box : correctifs
  posés, cause réelle NON VÉRIFIÉE (journaux de la box attendus).
- Essai gratuit de 7 jours alors que le test fermé Google dure 14 jours.

Documents utiles : `docs/AUDIT-ZUNO-TV-2026-10.md`,
`docs/PANEL-BOX-CARTES-ACCUEIL.md`, `docs/patches/`.
