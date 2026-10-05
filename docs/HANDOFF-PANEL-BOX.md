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

## 5 septies. Plus de pastille, mise à jour de l'app sans bouton, ⚡ Envoi instantané (5 octobre, 21:30)

Demandes écrites du propriétaire, détail dans `docs/MESURE-ACTIVATION-INSTANTANEE.md` § 7 ter :

- **Pastille « Mise à jour… » cachée** par défaut (`zuno.sync.pill_show` la réaffiche).
- **Mise à jour de l'app sans bouton** : 1 min après l'ouverture, puis
  toutes les 30 min, et dès l'ordre `force_update` du panel : APK vérifié
  puis installateur Android ouvert tout seul à l'accueil, une fois par
  version (`UpdateService.autoUpdate`). Repli `zuno.update.auto_install_off`.
  **Android garde sa confirmation « Installer »** (hors Play Store, aucune
  app ne peut l'éviter) ; le build Play Store se met à jour sans rien.
- **⚡ Envoi instantané** (panel, patch `docs/patches/panel-envoi-instantane.patch`,
  à appliquer après le patch boîte noire) : renvoi des listes + suivi
  « Liste sur la TV après N s ». La box ≥ #158 renvoie son inventaire tout
  de suite après un import du panel (repli `zuno.heartbeat.after_import_off`).

- Build de test **#159** = `107-test.159`, versionCode 1791229916, SHA-256
  `46166a48…dfacf`, signé `5145b8e0…`, contient tout (#156 + #157 + ci-dessus).
  Le #158 (même commit) : binaire `sqlite3` corrompu côté runner, puis relance
  annulée en file d'attente ; aucun changement de code entre les deux.

## 5 octies. Mesure réelle sur la box de test : H4 prouvée, délais M3U (5 octobre, 22:20)

Boîte noire de la box `107-test.159` : `nouvelle liste M3U reçue du panel :
chargement` puis `refusée après 90,0 s : Impossible de récupérer la
playlist`. L'ordre arrive, l'import part à la seconde, le fournisseur ne
livre pas en 90 s. Correctif #160 : en-têtes 120 s, puis on continue tant
que des octets arrivent (silence 60 s max, 10 min total), raison précise
dans la boîte noire ; repli `zuno.m3u.timeout_legacy`. Rapport § 7 quinquies.

## 5 nonies. Lien get.php lu par l'API Xtream (5 octobre, 22:40)

« Instantané comme les grandes marques » : un lien `get.php?username&password`
envoyé par le panel est importé par l'API Xtream (chaînes TV seules, JSON
léger, quelques secondes), repli automatique sur le fichier M3U si l'API
refuse. Empreintes doubles (Xtream + lien) pour l'effacement et
l'interrupteur. Repli `zuno.source.m3u_link_as_m3u`. Patch panel
`panel-envoi-instantane.patch` régénéré (reconnaît la liste en Xtream).
Rapport § 7 sexies. Build #160.

## 5 decies. #160 mesuré : l'API Xtream ramène 50 000 chaînes, l'écriture échoue (22:59)

Boîte noire de la box de test : `50000 chaînes live récupérées` en 145 s,
puis `refusée : FOREIGN KEY constraint failed` = la ligne de la liste a
disparu pendant le téléchargement ; aucune ligne ne disait qui l'avait
supprimée. #161 : chaque suppression de liste est journalisée avec sa
raison ; un refus explicite des identifiants ne déclenche plus le repli
M3U (`XtreamAuthException`). Rapport § 7 septies. Prochaine étape pour
3-5 s sur 50 000 chaînes : catégories d'abord, chaînes par catégorie à la
demande (ce que font IBO / TiviMate / Smarters).

## 5 undecies. Listes refusées mises de côté ; le panel retire une liste du client (5 octobre, 23 h)

- Box #162 : une liste refusée (mot de passe faux, serveur muet) ne bloque
  plus les autres : mise de côté 5 min → 6 h, retentée après les listes
  saines ; un ordre du panel ou Redémarrer retente tout. Repli
  `zuno.source.retry_always`. Rapport § 7 octies.
- Panel/Worker : `docs/patches/panel-supprimer-liste-client.patch` (après
  les deux autres) : `DELETE /api/v1/sources/:mac/self/:id` + bouton
  Supprimer sur « Ajoutée par le client ». C'est la liste qui « revenait ».
- Build #161 = `107-test.161`, versionCode 1791234986, SHA-256
  `454d26b8…a963a` : refus d'identifiants sans repli M3U, suppressions de
  listes journalisées.
- Build #162 = `107-test.162`, versionCode 1791235805, SHA-256
  `8a776baa2603eb61042757aa5103da739bcaa3b0a84e90ab36c0f3cca304a7bd`
  (54 754 170 octets, run 37375978821, commit 510964a) : #161 + listes
  refusées mises de côté. Même adresse APK (`zuno-tv-test`), même signature
  attendue `5145b8e0…9e61` (workflow inchangé).

## 5 duodecies. « Toujours l'ancien serveur » : le panel remplace désormais (5 octobre, 23:50)

- Prouvé par le serveur : listes servies datées 23:10:12, clic « Activer » à
  23:49:24 sans écriture de liste. Le panel en ligne ajoutait (max 3) et
  refusait : la box gardait l'ancien serveur. Rapport § 7 nonies.
- 4e patch `docs/patches/panel-activation-remplace.patch` (après les trois
  autres) : « Activer avec une liste » remplace les listes du panel, garde
  celles du client, renvoie même si identique. 47 tests panel, build OK.
- Mesuré : thekung par l'API Xtream = 11 857 chaînes en 0,7 s ; par le lien
  M3U = 14,6 s avant en-têtes et > 50 Mo. business-cloud-8 : API `auth=1`,
  `get.php` HTTP 884 (refus) ; depuis la box, muet 120 s.
- Box (ce commit) : « Mes sources » prévient qu'une liste du panel revient si
  on la supprime sur la télé ; la boîte noire nomme la raison. Pas de flag.
- ANR 23:47 (330 Mo) : non élucidé, il faut les lignes `GEL` 23:44–23:47.
- Build #163 = `107-test.163`, versionCode 1791237816, SHA-256
  `dbc30ee9f72734d81360dc09aada2cc1030b8208ebda0308a510c004cb9a012e`
  (54 755 742 octets, run 37379758296, commit dab884b) : #162 + avertissement
  « Mes sources » et raison de suppression dans la boîte noire.

## 5 terdecies. Ligne de liste disparue pendant l'import : filet et preuve (6 octobre, 00:16)

- Reproduit sur #163 (130,9 s, 50 000 chaînes, `FOREIGN KEY constraint
  failed`). Qui efface la ligne : NON VÉRIFIÉ, tous les chemins sont
  journalisés, lire les lignes avant 00:16:07. Rapport § 7 decies.
- Box #164 : ligne remise avant l'écriture (`zuno.import.reinsert_off`),
  `[DB] liste N : X ligne(s), Y chaîne(s) effacée(s)`, plus de
  re-téléchargement d'une liste en cours d'ajout (`zuno.refresh.pending_legacy`).
- `docs/PROMPT-MISSION-STABILITE.md` : prompt de mission complet à donner à
  un agent pour continuer (critères mesurables, règles, état, ordre des
  travaux, pièges).
- Build #164 = `107-test.164`, versionCode 1791239332, SHA-256
  `f26c876a8d3b7e09a0f8633d8c70f2097c022bb259358f8f85e46e41882cd9dd`
  (54 759 145 octets, run 37382518913, commit 11ad567).
- Windows #14 (même code que #164, commit 8699205, `publish=false`, artefact
  de run seulement, expire le 4 novembre) : run 37384540506, artefact
  `zuno-windows-8699205…`. `Zuno-Setup.exe` 29 439 413 octets, SHA-256
  `387ef85bbfac67286447d1a8d8c4bee1281a87a434e67c5fa3a78dba73cc90ad` ;
  `zuno-windows.zip` 38 652 654 octets, SHA-256
  `35989483b59195576e4b11c221ad4f7fdf9c4b10c9e24a49b0459f5198ad8b2d`
  (empreintes calculées sur l'artefact téléchargé). La release publique
  `zuno-windows` date toujours du 3 octobre (run #11, commit 2471156).

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
