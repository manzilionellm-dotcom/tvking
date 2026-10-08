# Passation — Panel ↔ Worker ↔ App box Zuno (état au 4 octobre 2026)

Tout ce qui suit a été vérifié dans le code ou en production (lecture seule)
le 4 octobre 2026. « NON VÉRIFIÉ » est écrit quand ce n'est pas le cas.

## 1. Où sont les choses

Un seul dépôt GitHub : `manzilionellm-dotcom/tvking`.

| Pièce | Dossier | Techno | En ligne |
| --- | --- | --- | --- |
| App box Android TV / Fire TV « Zuno » | `android-app/` (point d'entrée `lib/main_tv.dart`) | Flutter 3.47, Dart, lecteur natif Media3 dans `packages/native_video_player/` | APK sur la release GitHub `zuno-tv` (clients) |
| Panel revendeur | `android-app/admin-panel/` | React + Vite + TypeScript | `[adresse du service masquée]` (Cloudflare Pages, projet `tvking-admin`) |
| Backend (« Worker ») | `android-app/cloudflare/` (`worker.js` routes publiques, `api_v1.js` routes du panel, `wrangler.toml`) | Cloudflare Worker `seven-motion-backend` + base D1 `tvking_licensing` | `[adresse du service masquée]` |

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
`[adresse du service masquée]`, surchargeable par `--dart-define=BACKEND_URL`.

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
    `5145b8e0…cbdf9e61`.
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
  `85931798…1e6c0a00`, signé `5145b8e0…`.
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
  production (ring de `[MAC masquée]`), WebSocket ouvert en 1,1 s et
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
- Sur `[MAC masquée]` : 3 listes différentes (2 du panel, 1 tapée sur la
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
  `8a776baa…a304a7bd`
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
  `dbc30ee9…cb9a012e`
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
  `f26c876a…882cd9dd`
  (54 759 145 octets, run 37382518913, commit 11ad567).
- Windows #14 (même code que #164, commit 8699205, `publish=false`, artefact
  de run seulement, expire le 4 novembre) : run 37384540506, artefact
  `zuno-windows-8699205…`. `Zuno-Setup.exe` 29 439 413 octets, SHA-256
  `387ef85b…73cc90ad` ;
  `zuno-windows.zip` 38 652 654 octets, SHA-256
  `35989483…98ad8b2d`
  (empreintes calculées sur l'artefact téléchargé). La release publique
  `zuno-windows` date toujours du 3 octobre (run #11, commit 2471156).

## 5 quaterdecies. Réinitialiser la box, listes à part, mise à jour de test en 60 s (6 octobre, 00:54)

- 5e patch `docs/patches/panel-reinitialiser-et-listes.patch` (après les
  quatre autres) : Worker `POST /api/v1/sources/:mac/reset` + `reset_at`
  dans `/api/status` + ordre « reset » ; panel : bouton **Réinitialiser la
  box** (fiche appareil), Activation = licence seule, page **Listes**
  (remplace par défaut, ajoute si décoché). 17 tests Worker, 47 panel.
- Box #165 : `BoxReset` (efface tout sur `reset_at`, repli `zuno.reset.off`),
  box de test vérifie une mise à jour toutes les 60 s (repli
  `zuno.update.test_poll_legacy`). Rapport § 7 undecies.
- Pourquoi la mise à jour prenait 3 à 5 min : aucun signal du build vers la
  box, lecture de `version.json` toutes les 30 min. Pour les clients, le
  bouton Mise à jour forcée du panel est déjà immédiat.
- Build #165 = `107-test.165`, versionCode 1791241671, SHA-256
  `c0d5edd5…45ee89f8`
  (54 767 130 octets, commit 67d0a85).

## 5 quindecies. Activation idempotente, audit corrélé, sécurité des codes (6 octobre)

- 6e patch `docs/patches/panel-activation-idempotente-et-securite.patch`
  (après les cinq autres, vérifié : s'applique proprement) : `Idempotency-Key`
  sur l'activation, renouvellement conditionnel, débit + ledger atomiques,
  `X-Request-Id` jusqu'à l'audit, état avant/après et `took_ms`, audit de la
  remise à neuf, limite 120/min/IP sur `/api/device-source`, menu regroupé.
- Box : import avant effacement (repli `zuno.source.drop_first_legacy`).
- **Critique** : codes IPTV lisibles par la seule MAC en production ; le
  correctif `device_guard.js` n'existe que sur la branche app.
- Rapport complet : `docs/RAPPORT-CONTROL-CENTER.md`.

## 5 sedecies. Ordres suivis, accusés réels, révisions, concurrence (6 octobre)

- 7e patch `docs/patches/panel-ordres-accuses-trace-revisions.patch`, après
  les six autres. Ordre vérifié sur `636aad6` propre : boîte noire, envoi
  instantané, retrait liste client, activation qui remplace, remise à neuf,
  activation idempotente, puis celui-ci. L'ancien
  `panel-supprimer-liste-mac-sans-mk.patch` est déjà en production
  (`0896028`) : ne pas l'appliquer.
- Worker : ordres `ord_…` + `trace_id` (CREATED → SENT → RECEIVED → APPLIED /
  FAILED / EXPIRED), `POST /api/box/ack` qui enregistre vraiment, révisions
  de listes avec retour arrière vers une révision accusée, écritures de
  listes par comparaison-échange, chronologie `GET /api/v1/timeline`,
  centiles `GET /api/v1/metrics/latency` (owner).
- Panel : chronologie sous la page Boîte noire.
- Box : accusés RECEIVED puis APPLIED/FAILED (repli `zuno.ack.off`),
  dernière bonne liste gardée tant qu'aucune nouvelle n'est chargée.
- Tests locaux de charge : Miniflare 4 seul avec le paquet de déploiement
  (`cloudflare/test_support/miniflare_server.mjs`), pas `wrangler dev`
  (rapport § 1, bugs 15 et 16).
- Divergence des branches et plan de réconciliation :
  `docs/DIVERGENCE-BRANCHES.md`. Rapport : `docs/RAPPORT-CONTROL-CENTER.md`.
- Build #166 = `107-test.166`, versionCode 1791243281, SHA-256
  `e3b547e3…7254f8ca`
  (54 768 727 octets, commit a09a832).
- Build #167 = `107-test.167`, versionCode 1791248258, SHA-256
  `d2da1aa5…ca786f06`
  (54 779 385 octets, commit ea9b22e, signature `5145b8e0…9e61` relue sur
  l'APK téléchargé). Contient les accusés d'ordres de la box.

## 5 septdecies. Une seule activation, menu sans répétition (6 octobre)

- 8e patch `docs/patches/panel-une-seule-activation.patch`, après le 7e.
  Vérifié : la série 1-8 s'applique sur `636aad6` propre et donne l'arbre
  testé.
- « Grande activation de toutes les applications » et « Activation à
  distance » faisaient le même geste avec trois listes de durées
  différentes (la fiche appareil en avait une troisième). Il reste un seul
  écran, **Activer une box** (`/activate`) : MAC comme sur la box, nom,
  essai gratuit 3 / 7 / 14 / 30 j, abonnement 1 / 3 / 6 mois, 1 an, à vie,
  un bouton qui dit le prix. La fenêtre « Activer / prolonger » de la fiche
  appareil utilise le même choix. Licence seulement ; les listes restent
  dans **Listes**.
- `/activation-distance` mène à `/activate`, MAC comprise (liens et
  favoris déjà copiés).
- Menu : plus de titre de section qui répète une entrée (« Clients ›
  Clients », « Boîte noire › Boîte noire »…). Libellés traduits pour de bon
  en anglais et en arabe.
- Supprimé : le bloc « Ajouter des jours d'essai » (doublon de l'essai
  gratuit). La route Worker `POST /api/v1/trial-extend` reste en place.
- Tests : `activation.test.ts` (8), panel 60/60, build OK ; 3 de ces tests
  échouent sur le panel en ligne (contre-preuve).

## 5 octodecies. MIS EN LIGNE (6 octobre, 04:23 heure de la box)

- Sur ordre écrit du propriétaire (« termine le travail »), les 8 patchs
  sont sur `claude/panel-mise-en-ligne` (un commit par patch, avance
  rapide, rien réécrit), tête `7f2813e`. Le repère du workflow est passé de
  « Activation 1 an » à « Activer une box ».
- `deploy-panel-cloudflare.yml` run #10 (37403717544) : Worker puis panel,
  les deux verts ; MAC de référence `[MAC masquée]` identique avant et
  après.
- Relu en direct : le panel sert `index-5rb0at2A.js` (même nom que le build
  testé) avec « Activer une box » ; Worker : `/api/box/ack` répond,
  `/api/v1/metrics/latency` et `/api/v1/timeline` → 401 sans jeton.
- Retour arrière : versions du Worker listées par le run (étape AVANT) ;
  déploiements Pages précédents dans Cloudflare.

## 5 novodecies. « Supprimer » sur la télé tient (6 octobre, build #168)

- Cause mesurée : le serveur servait toujours « Mon abonnement » (panel) et
  « 6 » (client) ; la télé n'effaçait que sa copie, la vérification
  suivante la réimportait.
- Box (commit f9eaef2) : liste du client supprimée aussi sur le serveur ;
  liste du panel plus réimportée tant que le panel ne la renvoie pas ;
  serveur injoignable = rien d'effacé. Repli `zuno.source.tv_delete_legacy`.
- Build #168 = `107-test.168`, versionCode 1791271081, SHA-256
  `3462665d…f493c911`
  (54 793 836 octets), signature `5145b8e0…9e61` relue sur l'APK.

## 5 vicies. Urgence : « Connexion impossible » dans le panel (6 octobre, 09:31)

- Cause : depuis la mise en ligne #10, le panel envoie `X-Request-Id`,
  `X-Client-Sent-At` et `Idempotency-Key` ; le Worker ne les autorisait pas
  (pré-vol CORS). Le navigateur bloquait TOUTE écriture du panel : rien
  n'arrivait à la box. Aucun test ne jouait le pré-vol d'un navigateur.
- Correctif `676cce9` sur `claude/panel-mise-en-ligne` (patch
  `docs/patches/panel-cors-entetes.patch`), mis en ligne par le run #11
  (Worker seul, vert). Relu en direct : les trois en-têtes sont autorisés.
- Garde-fou : `cloudflare/cors_panel.test.mjs` lit les en-têtes posés par
  le panel et échoue si le Worker ne les autorise pas (rouge sur l'ancien
  code, vert maintenant).

## 5 unvicies. Preuves sur la vraie box + ANR de Direct corrigé (6 octobre, build #169)

- Prouvé sur la SHIELD (boîte noire, #168) : liste du client supprimée sur
  la télé ET le serveur (09:29:51) ; liste du panel refusée, plus
  réimportée (09:31:31) ; ordre `source_clear` n°22 reçu par WebSocket et
  accusé « appliqué : no_source (révision 2) » 1 s plus tard avec son
  `trace` : le premier accusé réel d'une box.
- ANR du 06/10 09:07 : Direct recevait 50 000 chaînes avec un drapeau de
  pré-calcul resté vrai du lot de 1 000 ; Tendances / « Pour vous »
  curaient les 50 000 noms sur le fil UI. Corrigé (commit 9e19cc5) : drapeau
  remis avant, rayons lus en cache seulement. Mesure machine de test :
  4 861 ms → 14 ms. Repli `zuno.direct.shelves_legacy`.
- Restent visibles dans le journal : relecture de 50 000 chaînes ≈ 2,2 s
  (`[DB] lecture`), ligne de liste disparue pendant un import de 128 s
  (filet actif), guide `FormatException: Filter error`, import Xtream
  catégorie par catégorie (914 appels, 136 s).
- Build #169 = `107-test.169`, versionCode 1791272560, SHA-256
  `80fac869…beeb8d2e`
  (54 800 024 octets), signature `5145b8e0…9e61` relue.

## 5 duovicies. Ordre rejoué à la reconnexion (6 octobre, build #170)

- Mesuré (#169, 10:16:59) : l'ordre n°22 déjà appliqué à 09:35:55 est
  renvoyé par le Durable Object à l'ouverture de la prise, retraité et
  accusé « en échec : not_run ». Le serveur l'a ignoré (état terminal
  APPLIED), mais le journal mentait.
- Correctif (commit a000384) : la prise WebSocket lit le dernier numéro
  traité gardé par l'attente longue et ignore un ordre déjà traité. Repli
  `zuno.realtime.ws_replay_legacy`.
- Aussi dans ce journal : 09:57 → 10:15, `Failed host lookup: 'github.com'`
  = le DNS de la box ne répondait plus (réseau local, pas l'app) ; la mise
  à jour attend que l'app soit à l'écran pour ouvrir l'installateur
  Android (« installateur non ouvert (déjà proposé) »).
- Build #170 = `107-test.170`, versionCode 1791275287, SHA-256
  `a516b0a2…9b93a636`
  (54 800 918 octets), signature `5145b8e0…9e61` relue.

## 5 tervicies. « trial_7d · 401 j restants » sur une box payée (6 octobre)

- Mesuré : `[MAC masquée]` (Fire TV AFTKM, Canada, hors ligne depuis le
  05/10 19:16) payée jusqu'au 11/11/2027, affichée « trial_7d ». Un essai
  ajouté à une licence payée active remplaçait le plan.
- Correctif `fb0277e` sur `claude/panel-mise-en-ligne`, run #12
  (Worker puis panel) : essai sur payé actif → jours ajoutés, plan payé
  gardé ; panel : libellé lisible (« Essai 7 j », « 1 an »).
  Tests failure_injection L1–L5 (L1 rouge sur l'ancien code).
- La licence déjà marquée « trial_7d » le reste tant qu'un abonnement payé
  n'est pas réactivé (aucune réécriture de données en production).
- Rappel propriétaire : les listes de `5C:E5…` ne vont pas sur la SHIELD
  (`[MAC masquée]`) ; chaque box a ses propres listes.


## 5 suite. P0 Direct : capture SHIELD reçue le 6 octobre à 12:27

- **NON PROUVÉ — fin de l'import de la grosse liste sur la SHIELD.** La
  capture du propriétaire affiche `107-test.170+1791275287`, une mémoire
  process de 273 Mo et « Dernière session terminée normalement » pour la
  session précédente (10:48). Les dernières lignes visibles vont jusqu'à
  12:12:31. Aucune ligne visible « liste … chargée en N s (X chaînes) » ne
  permet d'attester cet import, et cette capture ne montre pas Direct
  pendant ni après le chargement.
- **PROUVÉ — cadence du journal mémoire par lecture du code du build #170.**
  Dans `android-app/lib/core/blackbox/black_box.dart`, commit `a000384`,
  ligne 91 : `_kMemoryEvery = Duration(seconds: 30)` ; ligne 165 :
  `Timer.periodic(_kMemoryEvery, (_) => logMemory('périodique'))`.
  Un intervalle d'environ 30 s entre ces lignes ne démontre donc pas un
  gel. Le critère « aucun écart de plus de 5 s entre deux lignes
  [MEM] [périodique] » est **NON PROUVÉ et incompatible avec cette cadence**,
  même avec un fil UI disponible ; il demande une instrumentation adaptée.
  Le chien de garde existant utilise un timer de 500 ms et journalise
  `[GEL]` au-delà de 700 ms de retard ; aucune ligne de ce type n'est
  visible sur la capture, ce qui ne prouve pas leur absence pendant l'import.
- **À obtenir pour la preuve sur la SHIELD :** journal actualisé couvrant
  l'import, sa ligne de fin avec durée et nombre de chaînes, les mesures
  mémoire pendant le chargement et les éventuelles lignes `[GEL]` ; essai
  de navigation dans Direct pendant puis après l'import. Les « 2 source(s) »
  de `[MAJ]` comptent les adresses de mise à jour, pas les listes de chaînes.
- Cette vérification est une lecture du code et de la capture, sans nouveau
  test local ni changement du comportement de la box. Le correctif
  `9e19cc5` reste à prouver sur la SHIELD sous cette charge.

## 5 suite bis. P0 : vérifications terminées côté dépôt et panel (6 octobre)

- **PROUVÉ — build de test disponible et installé.** Le [build #170](https://github.com/manzilionellm-dotcom/tvking/actions/runs/37435992306)
  du commit `a000384` est vert. La publication clients est ignorée et la
  publication de test a réussi. La capture du propriétaire affiche
  `107-test.170+1791275287` ; la fiche SHIELD relue dans le panel affiche
  également `VERSION APP 1791275287`. Aucun nouveau comportement de box
  n'a été ajouté pendant cette vérification ; aucun nouveau build n'est requis
  pour le correctif `9e19cc5`, déjà inclus dans cette version.
- **PROUVÉ — tests et mesure CI du correctif Direct.** Journal du job
  `112177807929`, build #170 :
  `08:28:06Z 00:49 +516 ~2: All tests passed!` ;
  `08:27:39Z [mesure] rayons depuis le cache, 50 000 chaînes : 18 ms` ;
  `08:27:46Z [mesure] ancien calcul sur le fil appelant, 50 000 chaînes (machine de test) : 6937 ms`.
  Ce sont des mesures sur le runner, pas sur la SHIELD. La contre-preuve
  exécute les anciens getters. **NON PROUVÉ — contre-preuve avec le vrai
  interrupteur allumé dans l'écran Direct** : `live_shelves_test.dart`
  n'allume pas `RepairFlags.liveShelvesLegacy` ; `repair_flags_test.dart`
  vérifie sa clé et son défaut faux. Il faut un test de l'écran avec le
  repli allumé et la transition 1 000 → 50 000 chaînes pour couvrir ce point.
- **PROUVÉ — parcours panel/Worker réparé sans modifier le produit.** Le
  [run E2E #22](https://github.com/manzilionellm-dotcom/tvking/actions/runs/37439344358)
  échouait à `run.mjs:314` : attente du titre `Activation` pendant 20 s,
  alors que le vrai écran s'appelle `Activer une box`. Son défaut est
  désormais `trial_7d`, sa saisie MAC a une étiquette, et son résultat payé
  commence par `Activée jusqu’au`.
  Le commit `afc108bc` sur `claude/panel-mise-en-ligne` ne change que ce
  parcours : choix réel du bouton radio `1 an`, vérification de
  `aria-checked`, puis assertions inchangées sur licence active `yearly`,
  échéance, listes et accès de la box simulée. Le [run #23](https://github.com/manzilionellm-dotcom/tvking/actions/runs/37457752964)
  est vert : 29 contrôles, `11:39:19Z BILAN tous les contrôles locaux sont passés`.
  `npm test` dans `android-app/admin-panel` passe aussi : 60 tests,
  0 échec. Recherche des mêmes anciens sélecteurs dans les parcours :
  aucune autre attente de ce titre ou de cette ancienne phrase de résultat.
  L'exécution E2E dans cet environnement local est **NON PROUVÉE** :
  Wrangler s'arrête avant le parcours sur
  `uv_interface_addresses returned Unknown system error 1` ; le run GitHub
  ci-dessus fournit la preuve d'exécution avec le vrai Worker local et D1.
- **PROUVÉ — état relu de la SHIELD `[MAC masquée]`.** Le panel affiche
  appareil actif, abonnement à vie, échéance à vie, **0 /3 source poussée**.
  Dernière présence affichée : 06/10 à 12:31, hors ligne lors de la relecture.
  La boîte noire reçue, datée par le panel du 06/10 à 12:32:26, contient
  322 lignes, de 10:59:23 à 12:32:22. Extraits sans donnée de flux :
  `06/10 11:29:00 I [SCREEN] Direct ouvert` ;
  `06/10 11:29:00 I [DIRECT] 0 chaînes · 0 catégories` ;
  `06/10 12:32:22 I [MEM] [périodique] process 198 Mo (rss 275, natif 96)`.
  Aucune fin d'import ni ligne `[GEL]` dans ce journal reçu. Leur absence
  sur cette période sans import ne prouve pas le comportement sous charge.
- **NON PROUVÉ — P0 sur la vraie SHIELD avec la grosse liste.** Il manque
  la liste de cette box et l'essai dans Direct pendant puis après son import.
  Il faut envoyer cette liste d'environ 50 000 chaînes à `[MAC masquée]`,
  ouvrir Direct, puis obtenir le journal couvrant le chargement et sa fin
  (durée et nombre de chaînes), la mémoire sous charge et les éventuels gels.
  Le critère initial mémoire à 5 s est incompatible avec le timer de 30 s
  décrit ci-dessus. Le prompt de reprise a été corrigé dans `2a1cf62` :
  aucune ligne `[GEL]` de 3 s ou plus pendant l'import. Le journal reçu
  sans import ne permet pas encore de valider ce critère. Les listes
  d'une autre MAC ne sont pas utilisées pour ce test.
- Aucun déploiement Worker/panel ni publication clients effectué. La seule
  écriture produit pendant la lecture du panel est une demande de journal
  technique à la MAC de référence ; aucune licence ni liste n'a été modifiée.

## 5 suite ter. Ajout instantané, guide, Xtream (6 octobre, après-midi)

- **PROUVÉ — « Ajouter » dans l'écran Listes n'efface plus les autres
  listes.** Cause : l'écran ne renvoyait que les listes Xtream du panel ;
  ajouter un M3U effaçait les autres M3U et rallumait les listes éteintes.
  Commit `719928d` (branche de production) : `planAddList`, liste de la box
  avec Allumer/Éteindre et Retirer, « Suivi de l'envoi » qui lit l'état réel
  de l'ordre (accusés de la box) au lieu d'annoncer « box prévenue ».
  Preuves : panel 70/70 ; E2E local complet vert, puis [run #25](https://github.com/manzilionellm-dotcom/tvking/actions/runs/37468941723)
  vert ; contre-preuve : ancien écran → `ECHEC Ajouter conserve les deux M3U`
  (et run #24 rouge sur l'ancien écran).
- **PROUVÉ — guide `FormatException: Filter error`.** Cause : le client HTTP
  de dart:io décompresse déjà `Content-Encoding: gzip` en laissant l'en-tête ;
  le code redécompressait. Même erreur pour une adresse `.gz` servie en
  clair. Commit `da651cf` : décision sur les octets `1f 8b`. Vrai serveur
  HTTP local + vrai client : 3 cas → 4 programmes ; repli
  `zuno.epg.gzip_by_header` allumé → `FormatException`.
- **PROUVÉ (machine de test) — import Xtream par catégorie, 4 à la fois.**
  Commit `c2d1bef` : même résultat qu'en série, ≤ 4 appels simultanés ;
  40 catégories à 40 ms : 1 032 ms contre 2 183 ms. Repli
  `zuno.xtream.per_category_serial`. **NON PROUVÉ sur la SHIELD.**
- `flutter test` : 523 réussis, 2 ignorés.
- **NON PROUVÉ** : P0 (grosse liste dans Direct sur la SHIELD), P1
  (`device_guard`), P3 (qui efface la ligne de liste), P4 (lecture 2,2 s,
  aucune mesure de gel sur la box), P6 (latence de production).

## 5 suite quater. Téléphone : panel en direct, liens get.php (6 octobre, fin d'après-midi)

- **PROUVÉ sur les vraies apps (propriétaire, 06/10 ~17:00) : « les 2 apps
  fonctionnent »** avec le panel — box SHIELD (v107-test.171) et téléphone
  (7motion-test, build #1734, versionCode 3734, SHA-256
  `2483dad2…f57cbe3c`, signé
  `5145b8e0…9e61`).
- L'app téléphone est une AUTRE lignée de code que la box : branche
  `claude/phone-panel-direct`, partie de `claude/motion-mobile-106`.
  Le correctif téléphone `db317b7` de cette branche (code Zuno) ne la
  concerne pas.
- Commits téléphone : `c1c2056` + `20b3907` (écoute du panel par
  `GET /api/box/wait`, premier plan, repli `zuno.mobile.live_wait_off`) ;
  `37fdf33` (lien get.php du panel → API Xtream, repli M3U ; liste retirée
  ou éteinte au panel → enlevée ; replis `zuno.mobile.getphp_as_m3u`,
  `zuno.mobile.panel_reconcile_off`). Tests : 6 + 7 nouveaux,
  `test/features/playlists` 168/168.
- Mesuré sur le fournisseur du propriétaire : get.php en fichier M3U
  > 200 Mo (744 000 entrées, 49 s avant le premier octet) ; par l'API
  Xtream : 28 490 chaînes TV, 8 Mo, 1 s.
- Canal clients `phone-latest` inchangé (1729) ; `zuno-tv` inchangé.
  **Publication clients : NON FAITE, attend l'ordre écrit du propriétaire.**

## 5 suite quinquies. Signalement « à distance ne marche plus » (6 octobre, 19 h)

- **PROUVÉ — photo SHIELD reçue à 19:11, build installé 170.**
  `107-test.170+1791275287` ; `06/10 19:10:11 I [DIRECT] 0 chaînes · 0 catégories`.
  `[MAJ] installée 1791275287 · disponible 1791292678 (2 source(s))`
  compte les adresses de mise à jour, pas les listes de chaînes.
- **PROUVÉ — relecture du panel, connexion owner, vers 19:17–19:18
  Europe/Stockholm.** Fiche `[MAC masquée]` : active, abonnement
  à vie, échéance à vie, en ligne, version app `1791275287`,
  **0/3 source poussée**. Aucune licence ni liste modifiée.
- **PROUVÉ — chronologie serveur relue pour cette MAC.**
  34 événements sur 7 jours ; dernier changement de listes : retrait du
  06/10 à 09:35, révision 2. Ordre créé, publié, reçu puis appliqué par la
  box : `no_source`. Aucun nouvel envoi enregistré ensuite dans cette
  chronologie au moment de la lecture.
- **PROUVÉ — journal relu dans le panel (335 lignes).**
  `06/10 19:07:16 I [DB] lecture : 0 chaînes, 0 liste(s) en 16 ms` ;
  `06/10 19:07:17 I [PANEL] ordre source_clear n°22 déjà traité : ignoré (renvoyé à la reconnexion)`.
  Le repli de séquence n'est donc pas mis en cause par cette trame : cet
  ordre avait déjà été appliqué à 09:35.
  `06/10 19:18:17 I [MAJ] installateur Android → build 1791292678`
  prouve l'ouverture de l'installateur, **pas** l'installation.
- **NON PROUVÉ — panne actuelle du canal panel → Worker → SHIELD.**
  L'état observé est vide côté panel et côté TV ; aucun nouvel ordre de
  liste n'est disponible pour mesurer sa livraison. La photo seule ne
  prouve ni un import tenté ni son échec. Il faut envoyer la liste depuis
  **Listes** vers `[MAC masquée]`, puis relever le suivi Reçu/Appliqué
  (ou l'erreur réelle) et la fin d'import dans la boîte noire.
- **PROUVÉ — journal actuel reçu, nouvelle lecture vers 19:23.** Le panel
  contient des lignes de la SHIELD jusqu’à `06/10 19:22:46` ; la réception
  du journal est active. La chronologie relue reste à 34 événements, dernier
  ordre de listes appliqué à 09:35. Une tentative de préparer un test de retrait
  sur l’état vide a été interrompue par une restriction du navigateur avant
  confirmation ; aucun nouvel ordre de retrait n’apparaît dans la chronologie.
  Ce n’est **pas** une preuve de livraison d’un nouvel ajout.
- Aucun correctif du canal ni nouveau build effectué pour ce signalement :
  la cause d'un éventuel clic d'ajout non enregistré reste **NON PROUVÉE**.
  Le Studio TV et le verrouillage restent en cours ; les modifications
  publicités sont locales et ne sont pas déployées.


- **PROUVÉ — ajout effectué avec le lien fourni par le propriétaire vers
  `[MAC masquée]`, le 06/10 à 19:27 Europe/Stockholm.** Une liste
  ajoutée, remplacement décoché. Le panel affiche « Listes confirmées sur
  la box » et **1/3 source poussée**.
- **PROUVÉ — trajet serveur du nouvel ordre.** La chronologie passe de
  34 à 41 événements : révision 3 publiée, ordre créé puis publié,
  **reçu**, **appliqué : `loaded`**, révision confirmée : `loaded`, tous
  affichés à 19:27. Trace de corrélation
  `[trace masquée]`. Ce reçu est une preuve de
  livraison et d’application ; l’heure arrondie à la minute ne mesure pas
  une latence précise en secondes.
- **PROUVÉ — relecture de l’inventaire réel déclaré par la SHIELD après
  cet ajout.** Une liste Xtream active, **28 490 chaînes**, version
  déclarée `1791275287` (build 170). Licence active à vie, plan à vie,
  échéance à vie : identiques à la lecture avant ajout. Le nombre de
  listes passe volontairement de 0 à 1 ; aucun déploiement effectué.
- **PROUVÉ — l’état vide observé avant l’ajout correspondait à une
  configuration vide au panel et à l’ordre de retrait déjà confirmé à
  09:35.** Le nouvel ajout est confirmé dans l’inventaire de la vraie box.
  Il n’y a pas de panne de livraison reproduite par cet envoi ; aucun
  correctif du canal ni nouveau build nécessaire pour le réaliser.
- **PROUVÉ — nouveau journal reçu à 19:32:51, relu ensuite dans le panel.**
  `06/10 19:27:02 I [PANEL] ordre source n°23 reçu (ws)` ;
  `06/10 19:27:09 I [SOURCE] liste Xtream (lien) du panel chargée en 6.7 s (28490 chaînes)` ;
  `06/10 19:27:10 I [PANEL] inventaire envoyé au panel après la liste (applied)` ;
  `06/10 19:27:10 I [PANEL] ordre source n°23 appliqué : loaded (révision 3)`.
  Import API : 7,7 Mo, 28 490 chaînes ; première lecture de 1 000 chaînes
  en 38 ms, insertion complète en 3 076 ms, relecture complète en 1 196 ms.
- **PROUVÉ — mesures mémoire enregistrées pour cet import et sa suite.**
  Avant import à 19:27:03 : process 143 Mo, RSS 229 Mo ;
  après récupération à 19:27:05 : process 143 Mo, RSS 274 Mo ;
  à 19:27:16 : process 143 Mo, RSS 262 Mo ;
  à 19:32:46 : process 174 Mo, RSS 249 Mo.
  Aucun `[GEL]` ni nouveau démarrage dans le journal de 19:27 à 19:32.
  Ces échantillons ne mesurent pas un pic mémoire entre deux relevés.
- **NON PROUVÉ — P0 Direct sur la SHIELD et latence exacte depuis le clic.**
  Aucune ouverture de Direct après cet ajout n’est dans le journal reçu.
  Il faut ouvrir Direct sur la télévision puis photographier la boîte
  noire fraîche. Cet import compte 28 490 chaînes ; il ne prouve pas le
  scénario P0 d’environ 50 000 chaînes. Les relevés périodiques mémoire
  sont espacés de 30 s par construction ; la règle d’un écart maximal
  de 5 s entre ces lignes n’est pas une mesure de gel exploitable.
  La durée d’import est mesurée ; le clic n’a pas d’horodatage précis relevé.
- **NON PROUVÉ — retrait immédiat d’une liste lors de cette vérification.**
  La nouvelle liste est conservée pour l’essai Direct. Aucun retrait
  supplémentaire n’a été effectué ; la preuve doit venir d’un retrait
  demandé sur une liste de test et de son reçu réel, avec disparition
  de l’inventaire de la SHIELD.

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
cd android-app && flutter analyze && flutter test        # 504 verts, 2 ignorés au 6/10
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


### Verrouillage du panel demandé par le propriétaire — 7 octobre 2026

PROUVÉ (code et CI) : commit `2b7d1ea` sur la branche de production. Le manifeste garde les références distinctes du dernier panel et du dernier Worker et active le gel des déploiements. Aucun fichier de produit n’est changé. Les 12 tests de protection échouent avant correction ; `node --test .github/panel-*.test.mjs` passe ensuite 30/30. Panel 70/70, compilation réussie, injection de pannes 60/60 et audit sécurité 47/47. Run GitHub `37602392077` : « Stabilité panel et Worker » réussi ; jobs Worker et panel sautés, aucun déploiement. Run `37602392026` : parcours local panel + Worker + box simulée réussi. La comparaison avant/après vérifie aussi le nombre de listes et ne journalise aucune donnée d’accès.

PROUVÉ (verrou d’administration GitHub, 7 octobre après connexion du propriétaire) : la règle `24673987` « Zuno - panel gele » est active, cible uniquement `refs/heads/claude/panel-mise-en-ligne` et impose `update`, `deletion`, `non_fast_forward`. Relecture `GET /repos/manzilionellm-dotcom/tvking/rulesets/24673987` : `bypass_actors: []`, `current_user_can_bypass: never`. La branche est passée de `protected: false` à `protected: true` et sa tête reste `2b7d1ea5ff3fdad144dfc660f39b093c15020243`. Aucune tentative de poussée ni de déploiement n’a été faite pour éprouver le gel.

PROUVÉ (protection après un futur dégel autorisé) : règle active `24674146`, même branche exacte, aucun contournement. Relecture API : PR et une approbation obligatoires, revue CODEOWNERS obligatoire, approbations périmées annulées, conversations résolues. Les deux contrôles requis sont « Stabilité panel et Worker » et « wrangler local + panel + box simulée », avec source GitHub Actions `integration_id: 15368` et branche à jour obligatoire. Le propriétaire reste le seul CODEOWNER des workflows, du panel et du Worker ; fichier relu sur la branche de production. Le gel est une règle séparée : le désactiver plus tard ne désactivera pas les revues et contrôles.

PROUVÉ (environnement de déploiement) : environnement `zuno-panel-production`, identifiant `23714823721`, créé et réglages enregistrés dans GitHub. Relecture de la page après sauvegarde : approbateur unique `manzilionellm-dotcom`, contournement administrateur désactivé, une branche autorisée `claude/panel-mise-en-ligne`, aucun tag autorisé. L’auto-validation reste possible pour le seul propriétaire. L’environnement n’a aucun secret à ce stade. Preuves visuelles conservées : `preuve-zuno-deploiement-1791401820325.jpg` et `preuve-zuno-regles-1791401950452.jpg`. Ces réglages n’ont modifié ni le produit ni la version en ligne.

NON PROUVÉ (fermeture complète des accès de déploiement) : le relevé réel des réglages Actions montre encore `CLOUDFLARE_API_TOKEN` et `CLOUDFLARE_ACCOUNT_ID` parmi les secrets globaux du dépôt. GitHub indique sur cette page qu’ils sont utilisables par les collaborateurs dans les Actions. Le workflow `set-admin-password.yml` utilise notamment le jeton global sans l’environnement protégé ; geler une seule branche ne ferme donc pas ce chemin. La suppression du jeton stocké dans GitHub est préparée, mais non exécutée : elle demande une confirmation au moment de la suppression définitive, selon la règle du navigateur. Après accord, retirer le jeton global et relire son absence. Cela bloque les tâches Cloudflare GitHub utilisant ce jeton, jusqu’à la fourniture par le propriétaire d’un accès limité à l’environnement protégé lors d’un futur dégel autorisé. Une éventuelle copie du jeton détenue hors GitHub ne serait pas révoquée par cette seule suppression. Aucune valeur de secret n’a été lue, copiée ou modifiée. Preuve du dialogue non validé : `preuve-zuno-acces-global-1791401919055.jpg`.

Le propriétaire conserve le pouvoir d’administration et peut modifier les règles dans les réglages ; un compte propriétaire partagé donne ce pouvoir à la personne qui l’utilise.

NON PROUVÉ (disponibilité permanente) : les protections du code ne prouvent pas l’absence de panne réseau, d’hébergement ou de fournisseur. Aucune mise à jour de la SHIELD n’est requise pour les changements de workflow de ce commit. Les publicités non publiées restent dans le travail local, en attente d’une nouvelle autorisation.

### Sport et recherche qualité d’image — 8 octobre 2026

PROUVÉ (reproduction avant correction) : recherches publiques Sport mesurées depuis le poste le 7 octobre, réponses HTTP 200 après 8 457 à 11 698 ms ; matchs après 8 651 ms. L’app accordait 8 secondes à ces deux chemins, puis rendait une liste vide. Test HTTP réel sur 127.0.0.1, réponse après 9 secondes : commit `cf766ca`, Quality Zuno #96, run `37732862205`, job `113165731064`. Ligne `TimeoutException after 0:00:08.000000: Future not completed`, puis `Expected: an object with length of <1> / Actual: []`. Résultat : 524 réussis, 2 ignorés, un échec (la reproduction). Worker réussi. L’échec envoyé par courriel est celui de cette preuve rouge.

PROUVÉ (correctif et contre-preuve) : commit `78c0a5e`, Quality Zuno #97, run `37733978959`, job `113169240071`, `flutter analyze --no-fatal-infos --no-fatal-warnings`, `flutter test --reporter expanded`. Ligne finale du 8 octobre à 05:48:29 UTC : `01:14 +533 ~2: All tests passed!`. Les recherches et les matchs acceptent la réponse après 9 secondes en un seul appel ; avec `zuno.sports.network_legacy=true`, le délai de 8 secondes et l’échec silencieux reviennent. Le drapeau est éteint par défaut, chargé depuis les préférences et remis à zéro par le test. HTTP 503, connexion refusée, JSON illisible et vraie recherche vide restent distincts. Les scores déjà reçus restent présents après une panne ; le réessai est manuel. Le client est fermé à la fin ou au délai de 20 secondes. La boîte noire écrit la raison sans adresse, requête ou exception brute. Les deux appels du sélecteur d’équipe ont été vérifiés pour le même motif. Le proxy Worker peut encore renvoyer HTTP 200 vide après sa propre panne : ce chemin n’a pas été modifié, le panel étant gelé.

PROUVÉ (sources publiques réellement consultées) : OpenLigaDB, API sans clé et données ODbL ; `getmatchdata/bl1` a répondu HTTP 200 avec 9 matchs en 8 131 ms, le premier tour 2026 avec scores et buts en 6 433 ms. Schéma observé : score du match `resultTypeID=2`, mi-temps `resultTypeID=1`, buteur `goalGetterName`, horaire `matchDateTimeUTC`. Projet officiel : https://github.com/OpenLigaDB/OpenLigaDB-Samples (180 étoiles au relevé). OpenFootball : https://github.com/openfootball/football.json (1 035 étoiles, CC0) ; fichiers 2026-27 Ligue 1, Premier League, La Liga et Serie A relus. Son README dit mise à jour JSON quotidienne et sources amont sans mise à jour automatique garantie ; ce n’est pas du direct. SportsDataverse a aussi été examiné (89 étoiles, code MIT), mais la licence du code ne prouve pas les droits commerciaux ni la stabilité du service de données sous-jacent. Aucune clé, achat ou collecte d’articles n’a été ajouté.

NON PROUVÉ (nouvel accès scores et calendrier sur SHIELD) : bouton et accès direct à OpenLigaDB / OpenFootball ajoutés sur demande depuis Sport, raison de panne visible, limite de réponse 1 Mo et décodage hors du fil UI. Repli `zuno.sports.community_off`, éteint par défaut, restitue l’ancien écran sans ce service ; son test exige zéro appel HTTP lorsqu’il est allumé. OpenLigaDB est actualisé toutes les 60 secondes seulement sur l’écran actif et après un succès ; une panne attend Réessayer. Les buts sont du texte fourni par la source, pas des vidéos. Les calendriers OpenFootball sont explicitement différés. Validation de ce lot et construction de test en attente au moment de ce relevé.

PROUVÉ (validation de ce lot) : commit `17649d271aa3856a280c4054789259e7be0bb9b7`, Quality Zuno #98, run `37735191874`. Job `113173032295` : analyse réussie et ligne `01:17 +540 ~2: All tests passed!` à 06:01:53 UTC. Les 7 nouveaux tests passent par un vrai serveur HTTP et le décodage en isolate : ordre des résultats mi-temps/final, buteurs, UTC, choix de saison, score non communiqué, repli sans appel, HTTP 503, JSON illisible, limite de volume et réponse reçue après 9 secondes. Job Worker `113173032467` réussi. QA gates, run `37735191692`, réussi. Les drapeaux de repli, le réseau et le décodage sont vérifiés ; rendu et utilisation sur la SHIELD restent NON PROUVÉS.

NON PROUVÉ (installation et effet réel sur la box) : pas d’ADB ni de journal actuel de la SHIELD dans cette session. La photo du propriétaire ne prouve pas l’exécution du nouveau correctif. Après l’APK de test, ouvrir Sport, rechercher une équipe puis Scores et calendriers ; relever `[SPORT] recherche chargée…`, `[SPORT] matchs chargés…` et `[SPORT] calendrier chargé…`, ou la raison précise. La preuve d’import de 50 000 chaînes sans gel du Direct reste séparée et attendue.

NON PROUVÉ (dispatch APK habituel) : les fichiers Quality Zuno et Build Zuno TV sont absents de `main` (lecture GitHub 404), et le bouton Run workflow n’est pas disponible sur le constructeur. Aucun changement de `main`. La PR brouillon #102 vise uniquement l’instantané `ccr-sport-preuve-20261008` ; aucune fusion. L’appel de test réutilise `build-zuno-tv.yml`, avec `test_box=true`, `publish=false`, après les barrières Flutter et Worker. Il exige le propriétaire, le dépôt et les deux branches exactes ; seuls quatre secrets de signature sont transmis. La publication clients automatique sur push est supprimée dans ce workflow de travail. Le canal de test doit être vérifié après la construction ; avant celle-ci, la release clients porte l’APK de digest `6321fa53aa240d805bb5cabcd9c3e1b67d9f6b690a7d58a8c1a9cd52129a0a50` et le manifeste de digest `9085457271e17df67c65d435bebecba4bb211a96d1ad9b21c3793fde823329a8`.

PROUVÉ (APK construit et canal de test) : même run #98, job `113173686531` « APK Sport pour la box de test / Build Zuno TV APK », réussi. Le constructeur utilisé est bien `.github/workflows/build-zuno-tv.yml`. Version `107-test.98`, versionCode `1791439480`, source `17649d2`. Journal : `✓ Built build/app/outputs/flutter-apk/app-release.apk (54.8MB)` à 06:12:13 UTC ; minSdk 21 ; certificat APK `5145b8e019f6d5fb96a207f2e73673fd954f799966fd598889211556cbdf9e61`, conforme à la clé des box. Étape « Publier sur la release zuno-tv » sautée ; étape « Publier pour la box de test (release zuno-tv-test) » réussie. Relecture publique de `zuno-tv-test/version.json` : HTTP 200, version et taille concordantes, 54 809 432 octets, SHA-256 `2da2afda6687641fdd2d7d738041cd6c3eb61c8a12b0357cb30cb1acb28a9230`. Les métadonnées, notes, identifiants, tailles, digests et dates des trois fichiers clients sont identiques avant/après. La branche panel reste protégée à `2b7d1ea`. Installation réelle sur SHIELD NON PROUVÉE : aucune preuve d’installation et aucun journal de cette version n’ont encore été reçus. La mise à disposition de l’APK ne prouve pas son installation ; la validation de l’installateur Android peut être nécessaire. Retourner à l’accueil, accepter la version de test proposée, puis Sport → Scores et calendriers. Preuve : https://github.com/manzilionellm-dotcom/tvking/actions/runs/37735191874 ; APK : https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv-test/zuno-tv.apk.

La version visible porte le numéro du run Quality (#98) qui appelle le constructeur ; son versionCode est supérieur au précédent test (`1791292678`). Le chiffre « 98 » ne représente donc pas une régression de version. Le commit suivant ne met à jour que ce document ; il ne change ni l’app, ni les tests, ni le constructeur. Il évite une seconde compilation et une seconde proposition d’installation du même code. La preuve verte reste attachée explicitement à `17649d2` et au run #98.

NON PROUVÉ (mise à jour du descriptif de la PR) : la tentative de modification du titre et du corps de #102 a été rejetée par le contrôle automatique, qui l’a qualifiée de communication externe non autorisée. Aucun contournement ni nouvel envoi ; le descriptif initial reste en place. Les commits, les contrôles, l’APK et cette passation sont disponibles indépendamment. La PR reste brouillon, sans fusion ni suppression.

PROUVÉ (recherche documentaire, aucun gain mesuré) : Zuno utilise déjà SurfaceView, la surface recommandée par Android pour la vidéo TV, HDR et sortie à la résolution de l’écran : https://developer.android.com/media/media3/ui/surface. Le code possède déjà un choix de piste et un réglage de correspondance de fréquence ; celui-ci concerne la fluidité. NVIDIA confirme l’upscaling IA uniquement pour SHIELD 2019, avec limites différentes pour Pro et tube et selon le contenu : https://nvidia.custhelp.com/app/answers/detail/a_id/4886 et https://nvidia.custhelp.com/app/answers/detail/a_id/4925. Les modèles 2015/2017 n’en disposent pas. Les deux fiches diffèrent pour le cas 1440p/60 : retenir le cas commun confirmé 1080p/60 sur Pro 2019, ne pas promettre l’autre. Gain sur cette SHIELD NON PROUVÉ : modèle exact, résolution/fréquence du contenu et comparaison avant/après encore nécessaires. Aucun filtre vidéo, mise à niveau Media3 ou promesse de vraie 4K n’a été ajouté.

Réglages vérifiés : Zuno → Réglages → En plus → Fréquence de l’écran (présent dans `tv_extras_screen.dart` et relié aux lecteurs Direct, cinéma et enregistrement). Android décrit le bénéfice possible sur les saccades et ne garantit pas le mode demandé : https://developer.android.com/media/optimize/performance/frame-rate. NVIDIA, sur modèle compatible : Paramètres → Mise à l’échelle IA → Optimisée par l’IA ; le mode Démo compare côte à côte : https://www.nvidia.com/fr-fr/shield/support/shield-tv/ai-upscaling/. Les limites générales de ce guide sont plus anciennes que celles de la FAQ Pro ; ne pas les mélanger. Garder le moteur matériel pour l’essai comparatif. L’option Contraste de Zuno est déjà indisponible dans le code courant ; elle n’a pas été activée.


### Sport du téléphone sans abonnement — 8 octobre 2026 (test livré ; téléphone réel attendu)

PROUVÉ (mesure avant correction) : le mobile 7motion-test vient de la lignée `claude/phone-panel-direct`, source `37fdf3305c5de9d35e20fd6567df38008fc7a7ee`. Son écran appelle `/api/sports/big` et sa sentinelle `/api/sports/live`. Quatre GET publics, avec le vrai client urllib depuis le poste : domaine principal, HTTP 404 après 8 053 et 8 106 ms ; domaine de secours, HTTP 404 après 4 587 et 4 602 ms. Le Worker de production relu expose la recherche et les matchs par équipe, mais aucune de ces deux routes. L'expiration d'une clé payante est NON PROUVÉE ; remplacer un secret ne rétablit pas une route absente.

PROUVÉ (recherche) : la documentation officielle TheSportsDB réserve les scores v2 à son offre premium. OpenLigaDB est une API communautaire gratuite sans authentification, données ODbL, documentée dans https://github.com/OpenLigaDB/OpenLigaDB-Samples et https://www.openligadb.de/lizenz. Appels publics réels `/getmatchdata/bl1` et `/getmatchdata/bl2` : HTTP 200, 9 matchs chacun, 8 541 et 8 364 ms. `/getavailableleagues` : HTTP 200, 835 entrées ; codes 2026 `bl1`, `bl2`, `la1`, `pl`, `ucl` relus. Le projet OpenFootball fournit des fichiers quotidiens, pas une source de buts instantanés. Aucune clé trouvée dans un dépôt tiers n'est utilisée.

PROUVÉ (trois autres compétitions mesurées) : vrais GET parallèles avec urllib, timeout 20 s, `/getmatchdata/la1` HTTP 200, 10 matchs, 8 068 ms ; `/getmatchdata/pl` HTTP 200, 10 matchs, 7 886 ms ; `/getmatchdata/ucl` HTTP 200, 18 matchs, 8 072 ms. Les réponses contiennent les champs UTC et résultats attendus. Ces cinq compétitions ne prouvent pas une couverture de tous les championnats ni des scores immédiats ; la cadence existante de 45 s avec un cache de 60 s peut espacer les téléchargements à environ 90 s.

NON PROUVÉ (correctif préparé, validation attendue) : patch `patches/mobile-sport-gratuit.patch`, appliqué uniquement au téléphone source 37fdf330. Base mobile et branche box restent distinctes, sans fusion. Affiches, scores et rappels partagent le téléchargement OpenLigaDB, délai 20 s, cache 60 s, un seul appel par compétition sous concurrence. Les scores déjà reçus restent présents après une panne ; la raison reste visible et aucun réessai automatique n'est ajouté. Le geste Actualiser reprend les appels. La fiche lit les buteurs et minutes du fournisseur ; statistiques, compositions et pronostics absents ne sont pas fabriqués. Aucun statut LIVE ni minute n'est déduit de l'horloge. Un score partiel ne devient pas un résultat final. Les alertes du nouveau fournisseur ne ciblent que les matchs suivis ou les noms exacts des équipes favorites.

NON PROUVÉ (tests et livraison en attente) : 12 tests nouveaux avec vrai HttpServer sur 127.0.0.1, vrai client, vrai décodeur : succès sans clé, ancien 404 avec le repli, format historique, concurrence/cache, HTTP 503 et reprise manuelle, panne partielle, JSON/schéma/volume, réponse après 9 s, résultat final, suivi hors journée, détection de but sans doublon et fiche du buteur. Repli `zuno.mobile.sports_legacy` dans `lib/core/app/repair_flags.dart`, éteint par défaut, lu au démarrage. Interrupteurs de notifications et permission Android restent nécessaires. Une minuterie Dart ne prouve pas les alertes lorsque le téléphone ferme ou gèle l'app ; pas de notification push ajoutée.

NON PROUVÉ (APK à construire) : le workflow réutilisable `build-7motion-sport-test.yml` reprend les étapes natives du constructeur mobile validé, récupère exactement 37fdf330 puis applique ce patch. Analyse, tous les tests du téléphone, signature maîtresse, package mobile et versionCode supérieur au test précédent et aux clients sont bloquants. Publication limitée au tag fixe `7motion-test` ; relecture complète `phone-latest` avant/après. La PR de preuve #102 n'est jamais fusionnée. Aucun déploiement Worker/panel, aucun dégel et aucune modification des clients. Le constructeur TV ne part pas pour ce commit qui ne change que le patch téléphone et ses workflows. Réception réelle d'un but sur le téléphone NON PROUVÉE, attend l'installation puis un match suivi avec autorisation Android.

PROUVÉ (vérifications locales limitées) : `git diff --check` dans les deux arbres de travail ; application du patch contrôlée sur un index temporaire chargé par `git read-tree 37fdf3305c5de9d35e20fd6567df38008fc7a7ee`, puis `git apply --cached --check`. YAML des deux workflows lu avec PyYAML ; chaque script `run` vérifié avec `bash -n` (5 et 24 scripts). Les valeurs des traductions FR/EN déjà présentes sont identiques à la base mobile. La comparaison des releases normalise uniquement `download_count` : télécharger l'APK de référence incrémente ce compteur. Elle conserve les identifiants, notes, tailles, digests, dates et toutes les autres métadonnées. Vérification locale : une variation du seul compteur est acceptée ; une variation de digest reste refusée. Ces contrôles ne remplacent ni Flutter analyze ni les tests Flutter.

NON PROUVÉ (écriture distante bloquée, action non exécutée) : l'appel GitHub `create_tree` destiné aux quatre fichiers de la branche de travail a été arrêté par le contrôle automatique : « Automatic approval review failed: You've hit your usage limit ». Le message indique que la revue n'a pas pu être effectuée et interdit son contournement. Aucun arbre, commit ni déplacement de référence n'a été exécuté ; la tête distante relevée reste `307972ec92271a03b453e84cfbc8b702ea11292d`. Le message propose de réessayer à 10:31 AM sans préciser le fuseau. Aucun autre chemin d'écriture n'est utilisé.

NON PROUVÉ (validation manquante et reprise exacte) : Flutter, Dart et adb sont absents du poste (`shutil.which`). Après rétablissement du contrôle d'approbation, relire la tête de `ccr-b93e1afd-gwirw0`, préparer un commit français des quatre fichiers avec les signatures de session, mettre à jour la branche sans force et sans fusion, puis contrôler la CI de la PR de preuve. Les douze tests et l'analyse du téléphone doivent passer avant de construire et livrer uniquement `7motion-test`. Comparer `phone-latest` avant/après, relever package, versionCode et certificat de l'APK puis demander la preuve sur le téléphone. L'APK existant du 6 octobre n'inclut pas ce patch ; il ne doit pas être présenté comme réparé. Installation réelle et réception d'une notification de but restent NON PROUVÉES.

Reprise demandée le 8 octobre à 11:03, heure de Stockholm : tête de travail `307972ec` et PR brouillon #102 relues, sans changement ; métadonnées et digests des APK `phone-latest` et `7motion-test` identiques au relevé précédent. La reprise utilise le même contrôle d'approbation GitHub, sans chemin alternatif. Les résultats CI devront être ajoutés après leur exécution.

PROUVÉ (reprise autorisée et validation du code mobile) : commit `b4b4ca30277b5e4342dc85825961b32fff666024` envoyé normalement sur la seule branche de travail. Quality Zuno #99, run `37754285873` : box 540 réussis, 2 ignorés ; Worker réussi ; QA gates #126 réussi. Job mobile `113235757153` : analyse réussie et `2026-10-08T09:11:24.4298443Z 01:45 +1458 ~36: All tests passed!`. Les douze scénarios HTTP réels du nouveau fournisseur, notamment succès sans clé et repli vers les anciennes routes 404, sont présents dans le journal. Aucun test retiré, aucune assertion de résultat assouplie.

PROUVÉ (compilation, livraison arrêtée par le contrôle Android) : même job, `2026-10-08T09:19:18.6453934Z ✓ Built build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (67.5MB)`. La comparaison du certificat attendu est franchie, puis aapt2 relève package `com.manzilionellm.tvking.tv_king`, versionName `0.3.4-sport-test.99`, versionCode `1791452684`. L'étape de compatibilité sort avec le code 1 avant tout téléchargement de référence ou publication. La valeur minSdk n'était pas imprimée : cause exacte de l'écart NON PROUVÉE. `7motion-test` n'a pas été remplacée.

NON PROUVÉ (diagnostic Android suivant) : lire le minSdk du manifeste binaire avec la commande officielle `apkanalyzer manifest min-sdk`, documentée sur https://developer.android.com/tools/apkanalyzer ; imprimer aussi le résultat de l'ancien lecteur aapt2. L'exigence `minSdk == 24` est conservée sans exception. Conserver l'APK compilé comme artefact même si ce contrôle échoue, pour une mesure réelle ; la publication reste conditionnée à tous les contrôles. Aucun changement du patch mobile déjà testé. Le constructeur ne relance pas aveuglément Gradle : une nouvelle CI accompagne cette instrumentation.

Le sélecteur de la CI est étendu à `phone` : seules une modification du patch mobile ou de son constructeur demandent un nouvel APK mobile. La passation seule conserve le binaire validé. Le commit b4b4ca3 donne localement `box=false, phone=true` avec le vrai script. La contre-preuve de la passation seule devra être relevée après son commit.

PROUVÉ (cause du contrôle Android, sans assouplissement) : nouveau commit `42f918b2a4af2d2f1722d191ab473389af9bba17`, Quality Zuno #100, run `37756549158`, job mobile `113243275723`, réussi. Ligne du 8 octobre à 09:40:04 UTC : `minSdk manifeste=24 ; ancien lecteur aapt2=absent`. Le lecteur de présentation aapt2 ne trouvait pas le champ attendu ; l'outil officiel lit 24 dans le manifeste réel de l'APK. L'exigence minSdk 24 et les autres barrières sont conservées. Le patch Flutter est identique au premier essai : aucun changement des tests pour obtenir du vert. Même analyse réussie et `2026-10-08T09:30:49.8332072Z 01:42 +1458 ~36: All tests passed!`. La box reste à 540 réussis, 2 ignorés ; Worker et QA gates sont réussis. Aucun constructeur TV lancé.

PROUVÉ (APK mobile signé et livré sur le test) : `0.3.4-sport-test.100`, versionCode `1791453849`, package `com.manzilionellm.tvking.tv_king`, minSdk 24, certificat `5145b8e019f6d5fb96a207f2e73673fd954f799966fd598889211556cbdf9e61`. Deux comparaisons réelles des APK de référence : codes test précédent 3734 et clients 3729, même certificat, tous deux inférieurs au nouveau. Release `7motion-test` relue : fichier `7motion.apk`, asset `621384545`, 67 453 296 octets, SHA-256 `26884064954f0ed119059f5bed52d58d1d84546bbf16e2e6bb400eced4a99f6e`, mis à jour à 09:40:14 UTC. Journal de publication à 09:40:16 UTC : `PROUVÉ : APK publié identique au fichier signé et testé` et `PROUVÉ : phone-latest identique avant et après`. Relecture indépendante API concordante, y compris toutes les métadonnées clients hors compteur de téléchargements. Branche du panel relue, toujours `2b7d1ea`, aucun déploiement ni dégel. Preuve CI : https://github.com/manzilionellm-dotcom/tvking/actions/runs/37756549158 ; APK mobile de test : https://github.com/manzilionellm-dotcom/tvking/releases/download/7motion-test/7motion.apk.

NON PROUVÉ (installation et alertes sur le téléphone du propriétaire) : installer cet APK mobile de test, autoriser les notifications Android puis suivre un match via sa cloche dans Sport. Confirmer que l'affiche et le score s'affichent, puis relever une alerte quand le score du fournisseur augmente pendant que l'app reste active. Ni photo de cette version ni réception réelle de but encore reçue. Ce package de test ne prouve pas une mise à jour de l'application Play Store, dont le package est différent. Source communautaire limitée aux cinq compétitions relevées, délai de saisie non garanti ; aucune notification push lorsque le processus est fermé ou gelé n'est ajoutée. Les clients `phone-latest`, les clients Zuno et le Worker/panel restent hors publication.

PROUVÉ (téléchargement indépendant du fichier livré) : GET public de l'APK avec urllib, 12 496 ms ; fichier de 67 453 296 octets et SHA-256 `26884064954f0ed119059f5bed52d58d1d84546bbf16e2e6bb400eced4a99f6e`, identiques à l'asset et à la CI. Lecture ZIP de `lib/arm64-v8a/libapp.so` : les marqueurs `api.openligadb.de`, `getmatchdata/` et `zuno.mobile.sports_legacy` sont présents dans le binaire Flutter livré. Cela prouve la présence du correctif compilé, sans remplacer la preuve d'affichage et de notification sur le téléphone réel.

PROUVÉ (contre-preuve de la passation seule) : commit `4d2513b2d5d1ca2d39b24ece3cc08eef27fdf0a9`, un seul fichier modifié, `docs/HANDOFF-PANEL-BOX.md`. Quality Zuno #101, run `37758873037` : sélecteur, Worker et Flutter réussis ; deux jobs `APK mobile Sport gratuit` et `APK Sport pour la box de test` terminés avec `conclusion: skipped`. QA gates #128 réussi. L'asset mobile reste `621384545` avec le même digest. Le compte rendu de cette preuve ne change à son tour que ce document ; l'APK validé reste celui du run #100.


### Audit natif avant la mise à jour Play — 8 octobre 2026

PROUVÉ (récepteur Android avant/après) : l'APK mobile #100, code 1791453849, ne déclare pas ScheduledNotificationReceiver. Les APK #103 et #104 déclarent ce récepteur, privé, après ajout au constructeur. Commande sur les trois vrais fichiers : `PYTHONPATH=../apk-audit-deps python3 android-app/ci/mobile/verify_apk.py <apk>`. Avec le lecteur de ressources corrigé : #100 sort en erreur, uniquement « Récepteur des rappels absent ou exporté » ; #103 et #104 donnent goal_sound:true, scheduled_receiver:true, 16 bibliothèques arm64 contrôlées, errors:[] et code de sortie 0. Aucun émulateur ni remplacement d'Android par un mock.

PROUVÉ (erreur du premier test sonore, rectifiée) : les échecs CI #103 (run 37770677375) et #104 (run 37773949740) annonçaient un son absent. Cette conclusion était fausse. Androguard 4.1.3 initialise resource_keys lors de get_items() ou get_types() ; get_res_id_by_key() ne le fait pas. Sur les mêmes fichiers, sans modifier leur contenu : avant get_types, identifiant None ; après, identifiant 0x7f100002. La table Android résout goal_roar vers `res/Xx.wav` (nom optimisé par aapt2), 132 344 octets, 66 150 trames, 22 050 Hz mono. Ce fichier existe aussi dans #100 ; SHA-256 351fafc7547a04e7210c805a4915519c475dd71c21deb59bbfdbc67998ce97da. La recherche du chemin littéral res/raw ne constituait donc pas une preuve d'absence. Les précédentes affirmations contraires sont remplacées par cette mesure.

Le contrôle de 21ffaee appelle maintenant get_items avant la recherche par nom, puis ouvre réellement chaque WAV résolu dans le ZIP. Ni l'exigence sonore, ni le récepteur privé, ni le certificat, ni l'alignement 16 Ko ne sont assouplis. Recherche du même motif dans le nouveau banc : un seul appel get_res_id_by_key, corrigé. La référence statique du manifeste dans 32918dc reste une racine explicite de conservation, mais sa nécessité est NON PROUVÉE : l'hypothèse d'une perte par R8 était fausse. La génération déterministe du son et la règle de conservation restent dans le constructeur.

PROUVÉ (tests Flutter, CI arrêtée avant livraison) : #103, job 113290128931, `01:46 +1461 ~36: All tests passed!` ; #104, job 113300907822, `01:50 +1461 ~36: All tests passed!`. Le nouveau canal goal_roar_v2 a le repli zuno.mobile.notifications_legacy, éteint par défaut ; trois tests exigent l'ancien v1 lorsque le repli est allumé et le retour à v2 lorsqu'il est éteint. La documentation officielle flutter_local_notifications 18.0.1 confirme les composants de rappels nécessaires et l'immuabilité du son des canaux Android. Les deux runs se sont arrêtés sur le faux résultat sonore avant toute livraison : phone-latest et 7motion-test n'ont pas été remplacées par ces APK.

PROUVÉ (identité Store) : console relue, application « Lecteur IPTV – 7 MOTION », package com.manzilionellm.tvking, production 1721 (0.3.4), 43 appareils installés. Certificat d'importation SHA-256 5145b8e019f6d5fb96a207f2e73673fd954f799966fd598889211556cbdf9e61, identique à la clé stable du constructeur. L'APK de test porte un identifiant distinct. Le bundle 0.3.5 doit reprendre l'identifiant Store et ses restrictions de permissions, passer bundletool, puis le contrôle de son APK universel réel : composants, WAV, signature, ELF et ZIP 16 Ko.

NON PROUVÉ (suite attendue) : nouvelle CI avec le lecteur de ressources corrigé, contrôle du bundle et import du brouillon Play. Réception sonore réelle d'un but ou d'un rappel sur le téléphone non observée. Les taux de crash et ANR étaient indisponibles dans la vue initiale ; aucun zéro incident n'est déduit. Aucun envoi pour examen ni déploiement Play. Worker/panel gelés et releases clients inchangées.

PROUVÉ (contrôle natif vert, blocage suivant identifié) : commit 21ffaee, Quality #105, run 37774336945, job 113305400916. Ligne `02:01 +1461 ~36: All tests passed!`, puis APK 0.3.5-sport-test.105, code 1791463938, goal_sound:true, scheduled_receiver:true, 16 bibliothèques contrôlées, errors:[]. Le bundle compile et bundletool validate réussit. Build-apks échoue ensuite : « Passwords must be prefixed with pass: or file: ». Le constructeur utilisait env:, accepté par apksigner mais non par bundletool 1.18.3. La documentation officielle https://developer.android.com/tools/bundletool décrit les deux préfixes acceptés. Correctif minimal : fichiers temporaires privés (umask 077), préfixe file:, suppression par trap à la sortie ; aucune valeur secrète dans les arguments ou journaux. NON PROUVÉ : contrôle complet de l'APK universel et livraison après ce correctif, encore attendus.


### Fiche Play, Cast et mots clés — 8 octobre 2026

PROUVÉ (recherche et limite de mesure) : sources officielles Android consultées et fonctions relues dans le mobile, détail dans ASO-7MOTION-20261008.md. Rapport réel Play Console « Terme de recherche » : 115 visiteurs du 7 septembre au 4 octobre, puis 287 du 10 juillet au 4 octobre, tous regroupés dans « Autre » ; aucun classement de mots individuels disponible. Aucun volume mondial ni gain de téléchargements inventé.

PROUVÉ (brouillons Store enregistrés) : nouveau nom « 7 MOTION - IPTV Player & Cast » (29/30), description FR 73/80 et 2 633/4 000, description en-US 77/80 et 2 315/4 000. La console affiche « Vos modifications ont été enregistrées » pour chacune. Termes pertinents intégrés naturellement : IPTV Player, Android, M3U, M3U8, Xtream Codes, Chromecast, Google Cast, Live TV, VOD, EPG, TV Guide, XMLTV, favoris, replay/catch-up, PiP, sous-titres, pistes audio, contrôle parental, historique et reprise. La langue française reste par défaut. Confidentialité conservée.

PROUVÉ (images) : bannières française et anglaise créées avec imagegen ; Google Play a enregistré ses copies recadrées à 1 024 × 500, assignées à leurs langues. Affiche verticale anglaise créée séparément. Cast est qualifié par « compatible », et l'absence de contenu fourni est visible. Les quatre captures réelles existantes sont conservées. Les deux bannières sont déclarées individuellement comme créées ou modifiées avec l'IA selon le formulaire actuel ; aucune déclaration inventée sur les anciens éléments. Preuve de l'assignation anglaise et du message d'enregistrement conservée.

NON PROUVÉ : mise en ligne de ces changements, validation Store du nouveau bundle et gain de recherches/installations. L'enregistrement en brouillon ne constitue pas une publication. Aucun changement au Worker/panel ni à la release clients Zuno.


### Audit mobile : bundle validé et classement des grosses listes — 8 octobre 2026

PROUVÉ (barrières natives complètes) : commit f305abb, Quality #106, run 37777452403, job 113313261682 réussi. APK mobile code 1791465130 ; bundle Play 0.3.5, même code, package com.manzilionellm.tvking, minSdk 24, targetSdk 36, récepteur de rappel privé et WAV présents, 32 bibliothèques du bundle contrôlées, errors:[]. Ligne 12:49:53 UTC : « PROUVÉ : bundle Play validé, composants des notifications présents, bibliothèques et ZIP alignés 16 Ko ». À 12:50:15 UTC : APK publié identique au fichier signé et testé ; phone-latest identique avant et après. AAB de test SHA-256 18b1cef336c997ad370d19e885dbd02c8f3586a21a673779e4e76ca4ffb30c2e. Aucune validation physique ni publication Store n’est déduite de ces contrôles.

PROUVÉ (mesure avant nouveau correctif) : la page Production de la console affiche 7 ANR perçues par utilisateur pour 1721 (0.3.4), dont « _bucketOfCategory — Input dispatching timed out » et « _LinkedHashMapMixin.putIfAbsent ». Les taux restent indisponibles. La base mobile préparée appelle encore Channel.genre à froid depuis _bucketOfCategory et _computeTop ; les getters de nom, pays et qualité ont le même calcul paresseux sur le fil UI. Recherche du même motif : accueil, suggestions et réchauffement du cache de recherche. Cette concordance identifie un chemin lourd encore présent ; elle ne prouve pas la cause des sept incidents distincts.

NON PROUVÉ (nouveau correctif, validation en cours) : patch mobile préparant les quatre valeurs dans un isolate réel avant livraison ; remplacement atomique des caches, révision annulant les lectures dépassées et les calculs encore en vol lors d’une suppression. Repli zuno.mobile.channel_metadata_legacy éteint par défaut, qui restitue la livraison froide. Tests réels : 50 000 chaînes et événement UI pendant le calcul ; SQLite réel avec suppression et lecture concurrentes ; même assertion de livraison rejouée avec le repli pour la preuve rouge, puis suite complète en mode réparé. La CI doit confirmer ces tests et construire le nouveau bundle avant son import dans Play. Détails dans AUDIT-MOBILE-PLAY-20261008.md. Aucun code TV, Worker ou panel modifié.


### Mise à jour Play 0.3.5 / 1723 envoyée — 8 octobre 2026

PROUVÉ (tests de la réparation mobile) : Quality #110, run 37783987885, commit 1397d65c442d290567ff64ec73c432e6df7b2759, job mobile 113338549064 terminé avec success. Ligne réelle 13:35:42 UTC : « PROUVÉ : le même test échoue sur la livraison froide avec le repli réel ». Puis 13:37:49 UTC : `01:52 +1469 ~36: All tests passed!`. Les nouveaux tests exécutent le vrai isolate sur 50 000 chaînes et le vrai SQLite pour la livraison, la suppression pendant le calcul et la lecture plus récente. Repli zuno.mobile.channel_metadata_legacy chargé depuis les préférences, éteint par défaut ; true restitue les caches froids. Root Flutter : 540 réussis, 2 ignorés ; tests Worker verts ; constructeur TV skipped. Ce sont des preuves CI, pas des essais de télévision ou de téléphone réel.

PROUVÉ (nouveau bundle réel) : 0.3.5, code Play 1723, com.manzilionellm.tvking, minSdk 24, targetSdk 36, goal_sound:true, scheduled_receiver:true, 32 bibliothèques natives contrôlées, errors:[]. Ligne 13:48:52 UTC : « PROUVÉ : bundle Play validé, composants des notifications présents, bibliothèques et ZIP alignés 16 Ko ». Artefact 11554388587 téléchargé puis SHA contrôlé : AAB 129 155 633 octets, SHA-256 bcd408e255302d76394058298db7798ef63123b60ecacb994ae32da470aa3b36, identique à la release test (asset 621968027). APK de test 0.3.5-sport-test.110, code 1791468669, asset 621968034, 67 453 728 octets, SHA-256 bb7e2d15b1bd15dc04afbd03592b309cc868bdfe0187137324bc74f315735825. À 13:49:12 UTC : APK publié identique au fichier signé et testé ; phone-latest identique avant et après. Branche panel relue : 2b7d1ea5ff3fdad144dfc660f39b093c15020243. Aucune publication clients Zuno ni déploiement Worker/panel par cette mission.

PROUVÉ (envoi Google enregistré) : Play Console, release 8, 0.3.5, seul bundle 1723. L’ancien bundle 1791465130 est retiré du brouillon ; la boîte de confirmation indique qu’il reste dans la bibliothèque d’artefacts. Notes fr-FR et en-US enregistrées, 2 langues sur 2. Les six changements incluent la version, la fiche anglaise et les changements français de titre, description courte, description complète et bannière. Après confirmation d’envoi et fin des vérifications rapides, la console affiche « Vos modifications sont en cours d’examen » et « Publication gérée activée ». Preuve visuelle conservée : 7motion-google-review-1723-1791468716579.jpg. Dernière publication affichée : 20 septembre. L’envoi pour examen n’est pas la publication clients.

NON PROUVÉ (validation Google et publication) : réponse de Google encore attendue. La publication gérée est conservée ; ne pas publier aux clients sans l’ordre du propriétaire. NON PROUVÉ (réparation sur appareil physique) : importer une grosse liste sur le téléphone de test et parcourir les catégories pendant et après le chargement, essayer Cast avec un appareil compatible et observer une alerte de but avec la cloche activée, l’app active et les notifications autorisées. Aucun de ces essais physiques n’a été observé. Les sept ANR historiques ne sont pas déclarées résolues par la seule CI.

PROUVÉ (recherche de mots complétée) : fiches officielles de lecteurs IPTV et multimédia établis comparées ; termes pertinents intégrés naturellement à nos descriptions, y compris Video Player, Media Player, M3U/M3U8, Xtream Codes, Chromecast/Google Cast, Live TV/VOD, EPG/TV Guide/XMLTV, Catch-up, PiP, sous-titres et contrôle parental. Détail et sources dans ASO-7MOTION-20261008.md. NON PROUVÉ : volumes des requêtes individuelles et gain de classement/installations ; les données privées disponibles restent « Autre ».


### Publication mobile autorisée et automatique — 8 octobre 2026

PROUVÉ (ordre du propriétaire) : « Termine la publication ». Cet ordre porte sur la version mobile Play 0.3.5 / 1723 et ses fiches française et anglaise préparées dans cette conversation.

PROUVÉ (mesure avant action) : après rechargement, les six changements étaient revenus dans « Modifications pas encore envoyées pour examen ». L’activité montre l’envoi 16 annulé le 8 octobre à 16:07, heure affichée par la console. L’explication indique que les modifications ont été retirées de l’examen dans la vue d’ensemble de la publication. NON PROUVÉ : identité de l’auteur de ce retrait ; la page consultée ne l’indique pas.

PROUVÉ (publication préparée et envoi confirmé) : release relue, seul nouveau bundle 1723 (0.3.5), API minimale 24, cible 36, notes enregistrées pour deux langues sur deux. Sous l’ordre écrit ci-dessus, publication gérée désactivée : l’option indique que les mises à jour validées sont publiées automatiquement. Les six changements sont renvoyés. Les vérifications rapides se terminent ; un rechargement confirme « Vos modifications sont en cours d’examen » et « Publication gérée désactivée ». Preuve visuelle : 7motion-publication-auto-1723-1791472865737.jpg. Console : https://play.google.com/console/u/0/developers/6790957789570734722/app/4972286457582978602/publishing

NON PROUVÉ (disponibilité clients) : décision finale Google encore attendue ; dernière publication affichée le 20 septembre 2026. La configuration automatique est enregistrée, mais aucun déploiement terminé n’est déduit de cet envoi. L’essai sur téléphone physique demeure NON PROUVÉ. Cette autorisation ne concerne ni la release clients Zuno, ni un déploiement Worker/panel.


### Publication mobile effective — 8 octobre 2026

PROUVÉ (Google Play, après rechargement) : la vue d’ensemble indique « Dernière publication le 8 octobre 2026 » et aucune modification non publiée. Le tableau Tester et publier affiche la dernière version de production 0.3.5 avec un pourcentage de déploiement de 100 %. Dans Production → Versions, la release 0.3.5 est « Disponible sur Google Play », date de sortie affichée « 8 oct. 17:36 », avec un seul code de version : 1723. Canal actif, 178 pays/régions, 22 295 appareils Android pris en charge. La confirmation porte sur com.manzilionellm.tvking, pas sur une autre application du compte.

PROUVÉ (preuve conservée) : 7motion-publie-1723-1791474375429.jpg montre le statut de disponibilité, la version 0.3.5 et le code 1723 dans la console. URL vérifiée : https://play.google.com/console/u/0/developers/6790957789570734722/app/4972286457582978602/tracks/production?tab=releases

NON PROUVÉ : réception effective de la mise à jour sur chaque téléphone, résolution physique des ANR et des alertes, effet de la nouvelle fiche sur les recherches/installations. Ces points restent distincts de la publication Store désormais prouvée ; les métriques de stabilité de 1723 sont encore indisponibles au moment de la lecture.


### Radios du monde — APK mobile de test, 8 octobre 2026

PROUVÉ (point de départ) : la base mobile publiée 37fdf3305c5de9d35e20fd6567df38008fc7a7ee, puis le patch Sport existant, ne comportent ni entrée Radio dans SimpleHomeScreen ni client de catalogue radio. La demande du propriétaire porte sur une capacité nouvelle et un lien d'app de test. Le correctif reste dans patches/mobile-radio.patch : pas de fusion avec les branches divergentes, pas de modification du site, du Worker ou du panel.

PROUVÉ (code et garde de repli) : recherche Radio Browser par nom, pays, langue et genre ; pages de 50 stations ; exclusion des entrées invalides, hors ligne et doublons. Favoris par profil, stockés exclusivement sous forme d'UUID. Les réponses anciennes ne peuvent pas écraser une recherche récente ou remettre un favori retiré. Limite de corps HTTP, délais et découverte/bascule de miroirs bornés ; un refus 4xx, notamment 429, n'est pas répété sur un autre serveur. L'écran défile et n'initialise le lecteur qu'au choix explicite d'une station. Pause, reprise, arrêt et nettoyage à la fermeture. Repli zuno.mobile.radio_legacy dans repair_flags.dart, éteint par défaut et relu depuis les préférences : true retire l'entrée et coupe le catalogue sans aucun appel réseau.

PROUVÉ (tests sur le vrai transport) : Quality #118, run 37814771480, commit f553376b7b53042180311371e040e0369a1d0ce3, job mobile 113441580778 terminé avec success. Les 13 tests HTTP exécutent le client et le contrôleur de production contre un serveur réel 127.0.0.1 : requêtes/filtres/pagination, retrait, course entre recherches, timeout, refus 429, bascule 503, JSON invalide et limite de corps sans Content-Length. Trois tests supplémentaires couvrent le carnet, les profils et la préférence de repli ; seul le canal système SharedPreferences est remplacé, car il n'est pas disponible dans flutter test. Aucun lecteur audio natif n'est simulé pour prétendre prouver l'écoute.

PROUVÉ (contre-preuve et vert) : à 17:17:02 UTC, ligne réelle « PROUVÉ : le même test HTTP échoue sur le repli Radio réel ». Commande : flutter test test/features/radio/radio_browser_http_test.dart --plain-name 'catalogue : une requête HTTP réelle charge une radio' --dart-define=RADIO_LEGACY_PROOF=true --reporter expanded. Les assertions conservées attendent une station ; le repli rend zéro station et aucune requête. À 17:19:07 UTC : « 01:51 +1485 ~36: All tests passed! ». App de référence : 540 tests réussis, 2 ignorés. Worker : contrôles de sécurité verts, dont 33 passed, 0 failed. La construction TV est skipped.

PROUVÉ (service public réel) : dart run ci/radio_catalog_probe.dart utilise le même client, sans faux catalogue et sans imprimer de nom ni d'adresse de diffusion. À 17:19:09 UTC : « PROUVÉ : API Radio Browser réelle, 50 stations sur la page, 240 pays ». Ce sont 240 entrées de pays et territoires du catalogue à cet instant ; cela ne prouve pas une liste exhaustive de toutes les radios de la planète ni leur disponibilité permanente. Références : https://api.radio-browser.info/ et https://docs.radio-browser.info/ ; API publique gratuite sans clé payante, crédit affiché dans l'écran.

PROUVÉ (binaire livré) : APK Android arm64 0.3.6-radio-test.118, versionCode 1791481950, package com.manzilionellm.tvking.tv_king, minSdk 24, targetSdk 36 ; contrôleur APK : goal_sound:true, scheduled_receiver:true, native_libraries_checked:16, errors:[]. Signature SHA-256 5145b8e019f6d5fb96a207f2e73673fd954f799966fd598889211556cbdf9e61, identique aux précédents APK de test et phone-latest ; versionCode supérieur aux deux. Release 7motion-test, prerelease:true, asset 622506406, 67 584 800 octets, SHA-256 3dc8c78e5f21ca8714ee050392cbc19daf2dedf8e2f0eec0da25908126d32c31, mise à jour de l'asset à 17:26:56 UTC. À 17:26:58 UTC : « PROUVÉ : APK publié identique au fichier signé et testé » et « PROUVÉ : phone-latest identique avant et après ». Aucun nouveau bundle Play préparé : play_aab=false. Les fonctionnalités Sport déjà présentes sont conservées.

Lien APK vérifié : https://github.com/manzilionellm-dotcom/tvking/releases/download/7motion-test/7motion.apk
CI vérifiée : https://github.com/manzilionellm-dotcom/tvking/actions/runs/37814771480

NON PROUVÉ (téléphone physique) : lancement de l'APK, rendu en portrait/paysage, lecture sonore réelle, pause/reprise et conservation d'un favori après relancement. Pour le prouver : installer cet APK de test, ouvrir Accueil → Radios du monde, choisir un pays et une station, écouter puis utiliser Pause/Reprendre/Arrêter ; ajouter un favori, fermer et rouvrir la section. L'écoute ne doit pas démarrer au simple affichage du catalogue. Aucune installation ou observation sur la SHIELD n'a été effectuée pour cette fonction mobile. La version clients Zuno et la version Play publiée ne sont pas mises à jour par cette livraison.


### Audit du panel et de l’app, activation FD préparée — 8 octobre 2026, 18:12 UTC

PROUVÉ (mesure avant modification, panel signé en Super Admin) : les fiches MK:77:6B:FD:B0:A2 et MK:77:6B:F0:B0:A2 désignent deux appareils distincts. La première, code donné par le propriétaire, est une AFTSSS Android 9, vue depuis le 8 octobre à 19:27 (heure affichée), encore connectée à 20:01, versionCode 1791439480 ; son état affiche « Essai en cours · 7 jours restants ». La seconde affiche « Activé à vie », premier et dernier contact à 19:40 et aucun modèle ni version d’app dans son détail. NON PROUVÉ : auteur ou origine de cette différence ; les observations ne prouvent pas une erreur de saisie ni une panne de transport.

PROUVÉ (action préparée, non effectuée) : écran Activer une box, MAC MK:77:6B:FD:B0:A2 et plan À vie sélectionnés. Preuve visuelle conservée : zuno-activation-FD-preparee-1791482871083.jpg. Le contrôle automatique d’autorisation a rejeté le clic Activer parce que le propriétaire demandait l’activation sans avoir explicitement choisi la durée à vie ni autorisé un transfert depuis F0. Aucun contournement, transfert, retrait ou nouvelle activation n’a été exécuté. NON PROUVÉ : activation définitive de FD et réception sur la télé. Pour poursuivre : ordre écrit précisant le plan ; après validation, relire la licence et les accusés, puis observer la box.

PROUVÉ (risque de l’autre procédure, lecture seule) : handleDeviceTransfer dans api_v1.js de claude/panel-mise-en-ligne, tête 2b7d1ea5ff3fdad144dfc660f39b093c15020243, déplace les licences et exécute DELETE FROM device_sources WHERE mac = ? sur la MAC de destination avant remplacement. Cette procédure n’est pas utilisée pour régler cette activation, afin de conserver les sources de destination. NON PROUVÉ : contenu actuel des listes et livraison des ordres sur FD ; les observations supplémentaires des pages Appareils et Boîte noire sont bloquées par la protection des observations du navigateur après la connexion. Le blocage de lecture n’est pas une preuve de panne du Worker.

PROUVÉ (panel, lecture seule) : tableau de bord 525 clients, 525 appareils, 158 licences dont 87 actives et 71 expirées. Centre de contrôle : 8 modules actifs sur 11 ; Bannières reste indiqué Phase 2, A/B Testing Phase 5. NON PROUVÉ : finalisation des publicités avancées et leur rendu sur appareil. Aucun changement de contenu ni déploiement du panel ou du Worker pendant cet audit.

PROUVÉ (protections relues via GitHub) : règles 24673987 « Zuno - panel gele » et 24674146 « Zuno - revue et tests obligatoires » actives sur la seule branche claude/panel-mise-en-ligne, sans acteur de contournement. La première interdit modification, suppression et réécriture ; la seconde exige revue, CODEOWNERS et les deux contrôles de stabilité. Tête de production inchangée : 2b7d1ea5ff3fdad144dfc660f39b093c15020243. NON PROUVÉ : suppression ou révocation des anciens secrets globaux signalés dans la passation du 7 octobre ; l’existence des règles de branche ne prouve pas à elle seule que toutes les autres voies de déploiement sont fermées, ni une disponibilité permanente.

PROUVÉ (app, preuves distinctes) : Google Play Production relu le 8 octobre après chargement d’un document neuf : dernière release 0.3.5, « Disponible sur Google Play », sortie affichée 8 oct. 17:36. La release GitHub 7motion-test reste une préversion ; APK 67 584 800 octets, actualisé à 17:26:56 UTC, conforme à la livraison Radio #118 consignée ci-dessus. Le fichier AAB de cette même release date de 13:49:11 UTC : aucun nouveau bundle Radio ne lui est attribué. Quality #119, run 37817002298, tête 38dbc478a1f5f6bd993adf388417642b7b797e35, est success. NON PROUVÉ : écoute radio sur téléphone physique, réception de la licence sur Fire TV et import des 50 000 chaînes sur SHIELD. Aucun de ces essais physiques n’est remplacé par une réussite CI.


### Chaînes absentes sur FD : liste trouvée sur F0 — 8 octobre 2026, vers 20:38 Europe/Stockholm

PROUVÉ (mesure panel avant correction) : dans Listes, MK:77:6B:FD:B0:A2 affiche « Listes de cette box (0) » et « Aucune liste sur cette box ». Pour MK:77:6B:F0:B0:A2, le même écran affiche une seule liste M3U allumée. La fiche Appareils confirme que FD est la TV AFTSSS Android 9, active et vue le 8 octobre à 20:34 ; F0 n’a toujours ni modèle ni version d’app et sa dernière présence remonte à 19:40. La liste enregistrée sur F0 n’est donc pas une liste affectée à la MAC FD demandée. NON PROUVÉ : auteur de l’affectation à F0, validité actuelle de la liste chez son fournisseur et éventuels autres problèmes d’import.

PROUVÉ (intention précisée) : le propriétaire a corrigé la demande vers les chaînes absentes (« No les chaine ne par pas la » puis « Fais tou que sa marche »). Aucune activation définitive n’est nécessaire pour ajouter cette liste pendant l’essai actuel ; aucun plan d’abonnement n’est modifié. Correction préparée : ajouter la liste existante de F0 sur FD, avec Remplacer décoché, sans effacer F0 ni changer les licences.

PROUVÉ (action limitée et blocage précis) : le bouton de copie de la liste sur la fiche F0 affiche « Copié ✔ ». La tentative de collage dans Nouveau lien sur FD échoue : « Browser Use virtual clipboard has no data to paste ». Le contrôle automatique d’autorisation refuse ensuite la lecture du presse-papiers, car il peut contenir un lien IPTV avec identifiants et estime cette lecture non nécessaire à la simple vérification booléenne présentée. Aucun contournement ni extraction depuis l’état interne de l’app ou du navigateur. Aucun lien ni identifiant n’est imprimé, consigné ou enregistré dans cette passation.

NON PROUVÉ (correction et réception) : aucun ajout de liste n’a été soumis. Relecture après ces tentatives : FD conserve zéro liste, Nouveau lien vide et Ajouter la liste désactivé. Preuve visuelle conservée : zuno-chaines-FD-aucune-liste-1791484699239.jpg. Pour terminer la copie automatique : confirmation explicite de la copie de la liste de F0 vers FD, y compris réutilisation de ses identifiants sur cette TV ; ou saisie directe du lien par le propriétaire dans le formulaire du panel. Après ajout, observer l’accusé réel et l’inventaire de FD puis la liste sur la TV. Aucun déploiement, nouvelle construction ou modification de comportement de l’app n’est exécuté pour cette correction de configuration.
