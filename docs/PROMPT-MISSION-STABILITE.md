# Prompt de mission — Zuno stable de bout en bout (panel → Worker → box)

À copier tel quel comme premier message d'une session d'agent (Claude Code ou
équivalent) ouverte sur le dépôt `manzilionellm-dotcom/tvking`. Tout ce qui
est entre `[…]` est à remplir par le propriétaire avant d'envoyer.

---

## Ta mission

Tu es l'ingénieur responsable de la chaîne complète **panel revendeur →
Worker Cloudflare → box Android TV « Zuno »**. Objectif unique, mesurable :
**un revendeur clique dans le panel, et les chaînes sont sur la télé en
quelques secondes, à chaque fois, sans que personne n'ait à toucher la box.**
Et quand ce n'est pas le cas, la boîte noire de la box dit exactement pourquoi.

« Stable » veut dire, mesuré sur la box de test, cinq fois de suite :

| Critère | Seuil | Preuve attendue |
|---|---|---|
| Clic « Activer » ou « ⚡ Envoi instantané » → chaînes à l'écran | ≤ 10 s pour un fournisseur normal (≤ 15 000 chaînes), ≤ 30 s pour 50 000 chaînes | lignes boîte noire `[PANEL] ordre source … reçu (ws)` puis `liste … chargée en N s (X chaînes)` avec horodatages |
| Liste retirée dans le panel → disparue de la télé | ≤ 10 s | ligne `[DB] liste N supprimée (plus envoyée par le panel)` |
| Liste refusée par le fournisseur | ne bloque jamais une liste saine ; la raison est lisible | ligne `refusée après N s : <raison>` puis la liste suivante commence dans la même seconde |
| Fermetures brutales (ANR, mémoire) pendant un import | 0 sur 5 imports de 50 000 chaînes | carte « Dernière session terminée normalement » + `[MEM]` ≤ 250 Mo |
| Mise à jour de l'app | installée seule dans les 5 min suivant un repos, sans bouton | ligne `[MAJ] installee <versionCode>` |

Tu ne dis jamais « ça marche » : tu montres la commande, la ligne de boîte
noire ou le test qui le prouve. Si tu n'as pas la preuve, tu écris
`NON VÉRIFIÉ` et ce qu'il faudrait pour l'obtenir.

## Lis d'abord (dans cet ordre, avant toute modification)

1. `docs/HANDOFF-PANEL-BOX.md` — où sont les choses, branches, routes, règles.
2. `docs/MESURE-ACTIVATION-INSTANTANEE.md` — toutes les mesures faites, les
   hypothèses H1–H5 et leur statut, les correctifs build par build (#156 →
   #164), les limites connues.
3. `docs/patches/*.patch` — les correctifs panel/Worker **écrits mais pas
   encore en production** (ordre d'application : boîte noire → envoi
   instantané → supprimer liste client → activation remplace).
4. `android-app/lib/core/app/repair_flags.dart` — chaque changement de
   comportement a son interrupteur de repli, défaut OFF.
5. `android-app/AGENTS.md` — conventions Flutter du projet.

## Carte complète du projet (tout ce qui existe, pour ne rien chercher)

- **Dépôt** `manzilionellm-dotcom/tvking`. Racine : site web Next.js (ne pas
  y toucher pour cette mission). Tout le reste est sous `android-app/`.
- **App box / PC** (`android-app/lib/`) : entrées `main_tv.dart` (box),
  `main_windows.dart` (PC, même code), `main.dart` (téléphone).
  `core/` : app (interrupteurs `repair_flags.dart`), blackbox (journal),
  branding, crash, curation, flavor, i18n (`lib/l10n/*.arb`, fr = modèle),
  network, notifications, observability, support, theme, update
  (`update_service.dart` : `version.json` GitHub, installation automatique),
  widgets. `features/` : about, admin, ads, box_extras, carousel, cast,
  channels, cinema, country_home, device (identité MAC), epg, feedback,
  followed, missed_show, onboarding, panel_board, player (lecteur natif
  Media3 dans `packages/native_video_player/`), playlists (import M3U/Xtream,
  `remote_source_repository.dart` = listes du panel, `box_reset.dart` =
  remise à neuf, `source_retry.dart`, `m3u_link.dart`), pricing, profile(s),
  recordings, remote, security, settings, simple_home, sports, subscription
  (`remote_activation_watch.dart` = boucle panel → box, `box_channel_session`
  = WebSocket, `box_signal_client` = attente longue, `domain/box_signal.dart`
  = table des ordres), subtitles, theme, time_picks, tv (écrans TV,
  `tv_content_refresh.dart`), vod, voice.
- **Interrupteurs de repli** (tous défaut OFF, `repair_flags.dart`) :
  zuno.player.hold_frame_legacy, zuno.blackbox.raw, zuno.blackbox.fsync_all,
  zuno.sync.during_playback, zuno.epg.refresh_off, zuno.epg.inline_parse,
  zuno.history.on_open, zuno.mac.show_prefix, zuno.update.legacy,
  zuno.channel.legacy, zuno.sync.pill_off, zuno.panel.visibility_off,
  zuno.source.order_waits_idle, zuno.refresh.auto_full,
  zuno.import.first_batch_off, zuno.heartbeat.after_import_off,
  zuno.sync.pill_show, zuno.update.auto_install_off, zuno.m3u.timeout_legacy,
  zuno.source.m3u_link_as_m3u, zuno.source.retry_always,
  zuno.import.reinsert_off, zuno.refresh.pending_legacy, zuno.reset.off,
  zuno.update.test_poll_legacy.
- **Worker** (`android-app/cloudflare/`, prod = `claude/panel-mise-en-ligne`) :
  `worker.js` routes publiques (`/api/` ad, ai, announcement, app-version,
  backup, blackbox, box (ws/wait/ack), clients, device-source, featured,
  feedback, feedback-prompt, greeting, heartbeat, history, home-layout,
  panel, pricing, release, screen, self-source, servers, sports, status,
  theme, trending) ; `api_v1.js` routes du panel (`/api/v1/` activate, ad,
  announcements, apps, audit-logs, auth, backup, blackbox, customers,
  devices, families, featured, feedback, feedback-prompt, force-update,
  grant-trial-all, home-layout, licenses, me, online, plan-costs, pricing,
  references, resellers, servers, sources (+ `/self/:id`, `/reset`), stats,
  theme, transfer, trial-extend) ; `box_channel.js` (ordres, Durable Object
  `RealtimeHub`, `CHANNEL_KINDS`) ; `blackbox_journal.js` ; `schema.sql` ;
  tests `*.test.mjs` (activation_m3u 95, blackbox 34, box_channel 8,
  linkage_sim, reset_box_panel 17, self_source_panel 13), lancés par
  `node --experimental-sqlite cloudflare/<fichier>`.
- **Panel** (`android-app/admin-panel/`, React + Vite, prod =
  https://tvking-admin.pages.dev) : pages Account, Activate (grande
  activation), Activations, Ad, Apps, BlackBox, ControlCenter, Customers,
  Dashboard, Devices (fiche appareil : ⚡ Envoi instantané, Liste de chaînes,
  Boîte noire, Effacer les listes, Réinitialiser la box, Transférer, Geler,
  Bannir, Supprimer), Families, Featured, ForceUpdate, History, HomeManager,
  Login, Notifications, Online, PushSource (= Listes, `/chaines`), References,
  RemoteActivate (licence seule), Resellers, Reviews, Tarifs, Theme,
  Transfer. `src/lib/` : api.ts, sources.ts (plans purs), instant.ts,
  blackbox.ts, i18n.tsx, robust.ts, mac.ts, plans.ts. Tests `npm test`
  (47), build `npm ci && npm run build`.
- **Workflows GitHub** (`.github/workflows/`) : `build-zuno-tv.yml` (box,
  `test_box` / `publish`), `build-zuno-windows.yml` (PC, `publish`),
  `deploy-panel-cloudflare.yml` (panel + Worker, `confirme=DEPLOYER`),
  `deploy-pages.yml`, `publish-*.yml` (téléphone, TV, cinéma, maître),
  `cleanup-old-apks.yml`, `qa-gates.yml`, `quality-zuno.yml`,
  `set-admin-password.yml`, `worker-prod-snapshot.yml`,
  `dns-zuno-subdomain.yml`. Secrets disponibles : `ANDROID_*` (signature),
  `CLOUDFLARE_*`, `GITHUB_TOKEN`. Aucun jeton d'API du Worker en secret.
- **Releases GitHub** : `zuno-tv` (clients, `version.json`), `zuno-tv-test`
  (box de test), `zuno-windows` (PC), `latest` (téléphone).
- **Docs** (`docs/`) : HANDOFF-PANEL-BOX (passation), MESURE-ACTIVATION-
  INSTANTANEE (mesures), PROMPT-MISSION-STABILITE (ce fichier),
  CANAL-TEMPS-REEL, PANEL-INSTANTANE, PANEL-BOX-CARTES-ACCUEIL,
  AUDIO-BOITE-NOIRE, SECURITE-ZUNO, AUDIT-ZUNO(-TV-2026-10), CATALOGUE,
  INTELLIGENT, RESEARCH-TV-UX, RELEASE-103/104/106, `patches/` (5 patchs
  panel/Worker à appliquer dans l'ordre).

## Contexte minimal

- Un dépôt. App box : `android-app/` (Flutter, entrée `lib/main_tv.dart`).
  Panel : `android-app/admin-panel/` (React). Worker : `android-app/cloudflare/`
  (Cloudflare Worker + D1 + Durable Object `RealtimeHub`).
- Production panel+Worker = branche `claude/panel-mise-en-ligne`. App box =
  branche de travail `[ccr-… ou la branche indiquée par le propriétaire]`.
  `main` n'est la source d'aucune production. Ne jamais fusionner à l'aveugle.
- Chaîne temps réel : panel `PUT /api/v1/sources/:mac` → `notifyBox` →
  Durable Object → box par WebSocket `/api/box/ws?mac=` (builds ≥ 153) ou
  attente longue `/api/box/wait` ou relecture périodique. Mesuré : serveur
  193 ms, WebSocket 1,1 s. **Le serveur n'est pas le goulot.**
- Box de test : MAC `[MK:…]`, licence à vie. Fournisseurs servis :
  `[thekung … / business-cloud-8 …]`. Une liste de 50 000 chaînes y prend
  130–145 s à télécharger par l'API Xtream.
- Boîte noire : Réglages → Boîte noire sur la télé (défiler avec HAUT/BAS,
  CH+/CH− par page, « Copier » = presse-papiers). Les lignes `GEL … pendant :
  …` nomment l'action qui a figé le fil UI ; `[MEM]` donne la mémoire ;
  `[DB] liste N : 0 ligne(s)…` prouve qu'une ligne avait déjà disparu.

## Règles du propriétaire (non négociables, à appliquer sans discuter)

1. Jamais `publish=true` sans ordre écrit du propriétaire. Jamais de push sur
   `main`. Ne pas toucher à la release client `zuno-tv`.
2. Tests sur la box uniquement par `build-zuno-tv.yml` avec `test_box=true`,
   `publish=false`. Chaque build : relever versionName, versionCode, SHA-256,
   taille, run id, commit, et les écrire dans `docs/MESURE-ACTIVATION-INSTANTANEE.md`.
3. Tout changement de comportement garde un interrupteur de repli dans
   `repair_flags.dart`, défaut OFF, avec sa clé `zuno.…`, testé dans
   `test/core/app/repair_flags_test.dart`.
4. Commentaires en français, pas de `print()`, jamais d'URL de flux, de mot de
   passe ni d'identifiant fournisseur dans le code, les tests, les journaux,
   les rapports ou les messages.
5. Déploiement du Worker uniquement par `.github/workflows/deploy-panel-cloudflare.yml`
   avec `confirme=DEPLOYER` ; relire une MAC de référence avant et après.
   C'est le propriétaire qui déclenche.
6. Mesurer avant de toucher : une cause est une ligne de boîte noire, une
   mesure réseau ou un test qui échoue, jamais une supposition. Les
   hypothèses non prouvées restent étiquetées `NON VÉRIFIÉ`.
7. Chercher comment les applications établies font (IBO, TiviMate, Smarters,
   Xtream UI) avant d'inventer : catégories d'abord, chaînes à la demande,
   imports jamais en double, panel = maître des listes.
8. Un message au propriétaire = ce qui est prouvé, ce qui a changé, le lien et
   les empreintes du build, ce qui dépend de lui. Court, en français, sans
   jargon inutile.

## État au 6 octobre 2026 (ne pas refaire ce qui est fait)

Prouvé et corrigé côté box (builds #156 → #164, tous `107-test.N`) :
- v106 n'importait rien pendant qu'une chaîne jouait (H2) → import immédiat sur
  ordre du panel, repli `zuno.source.order_waits_idle`.
- Pastille « Mise à jour… » cachée ; mise à jour de l'app installée seule
  (`UpdateService.autoUpdate`), repli `zuno.update.auto_install_off`.
- Lien `get.php` lu comme compte Xtream (chaînes TV en secondes), repli M3U
  seulement si l'API ne refuse pas les identifiants ; repli `zuno.source.m3u_link_as_m3u`.
- Délais M3U : 120 s en-têtes, 60 s de silence, 10 min au total ; repli
  `zuno.m3u.timeout_legacy`.
- Liste refusée mise de côté 5 min → 6 h, après les listes saines ; repli
  `zuno.source.retry_always`.
- Ligne de liste disparue pendant le téléchargement → constatée, journalisée
  avec la durée, remise, import terminé ; repli `zuno.import.reinsert_off`.
- Passe « nouvelles chaînes » ne re-télécharge plus une liste dont l'ajout est
  en cours ; repli `zuno.refresh.pending_legacy`.
- Chaque suppression de liste est journalisée avec sa raison et le nombre de
  lignes réellement effacées.

- Remise à neuf depuis le panel (`reset_at` du statut → `BoxReset` efface
  tout, puis relit les listes) ; repli `zuno.reset.off`.
- Box de test : vérification de mise à jour toutes les 60 s (clients :
  30 min + ordre `force_update` immédiat) ; repli `zuno.update.test_poll_legacy`.

Écrit, testé, **pas encore en production** (panel/Worker, `docs/patches/`,
5 patchs dans l'ordre) : boîte noire lisible dans le panel ; ⚡ Envoi
instantané avec « liste sur la TV après N s » ; retrait d'une liste ajoutée
par le client ; « Activer » remplace au lieu d'ajouter ; **Réinitialiser la
box** (`POST /api/v1/sources/:mac/reset`) ; Activation = licence seule et
page **Listes** à part (remplace par défaut, ajoute si décoché).

Mesuré, pas élucidé :
- **Qui efface la ligne de la liste pendant un import de 130 s ?** Reproduit
  deux fois (#160, #163). Aucun chemin de suppression n'est silencieux dans le
  code depuis #161 : la réponse est dans les lignes de boîte noire qui
  précèdent `Insertion en base de 50000 chaînes`. Depuis #164, la ligne
  `[DB] liste N : 0 ligne(s), 0 chaîne(s) effacée(s)` confirme la disparition
  et `disparue pendant le téléchargement (N s)` la date.
- **ANR à 330 Mo** (5 octobre 23:47) : lignes `GEL` manquantes.
- Fournisseurs `business-cloud-8` : API `auth=1` mais `get.php` HTTP 884 ;
  depuis la box, muet 120 s → le repli M3U y coûte 120 s pour rien.

## Travail à faire, dans cet ordre

**P0 — Fermer les deux inconnues avec des preuves.**
1. Demander au propriétaire (ou lire dans le panel une fois le patch boîte
   noire déployé) les lignes 00:13:50 → 00:16:07 du 6 octobre et 23:44 →
   23:47 du 5 octobre. Nommer la cause de la ligne disparue et de l'ANR.
   Corriger la cause racine, pas seulement le symptôme ; garder la remise de
   ligne comme filet.
2. Repli M3U : ne jamais retomber sur le fichier quand l'API a déjà rendu des
   chaînes (échec d'écriture = pas un problème de fournisseur) ni quand le
   serveur a répondu un statut hors 2xx/404 sur `player_api.php`. Test Dart
   pur sur la décision, ligne boîte noire explicite.

**P1 — Mise à jour de l'app instantanée (demande du 6 octobre).**
Aujourd'hui la box apprend qu'un APK existe en lisant `version.json` sur
GitHub (60 s box de test, 30 min clients) ; le panel → Mise à jour forcée
envoie l'ordre `force_update`, immédiat. Pour que le **build** prévienne la
box lui-même : ajouter un secret GitHub (jeton admin ou jeton dédié
« build ») et, dans `build-zuno-tv.yml` après la publication, un appel au
Worker (`POST /api/v1/force-update` pour les clients après `publish=true`,
ou un ordre `force_update` à la seule MAC de test pour `test_box=true`,
route à créer `POST /api/v1/devices/:mac/force-update`). Mesure de
succès : ligne `[MAJ] installee <versionCode>` moins de 90 s après la fin
du workflow, confirmation Android comprise. Jamais de jeton dans le dépôt.

**P1 — Tenir 3 à 5 s sur les gros fournisseurs, comme les grandes applications.**
3. Import en deux temps : catégories + première catégorie affichées tout de
   suite, les autres catégories en arrière-plan par lots, jamais deux imports
   en parallèle, pic mémoire mesuré ≤ 250 Mo sur 50 000 chaînes (`[MEM]`).
   Plafond actuel `kMaxChannelsPerImport = 50000` à respecter.
4. Un import = une transaction par lot, reprise possible après une mort du
   processus (la liste reste cohérente : soit l'ancienne, soit la nouvelle).

**P2 — Entrées propres.**
5. Site « Mon espace » et panel : normaliser les liens `get.php` à la saisie
   (apostrophe courbe `’`, accent flottant, lien collé deux fois, espaces),
   refuser avec un message clair, jamais corriger en silence un mot de passe.
6. Télé « Mes sources » : une liste servie par le panel est marquée comme
   telle ; la supprimer sur la télé est expliqué (elle revient), le retrait
   définitif se fait dans le panel.

**P3 — Mise en production (décisions du propriétaire, tu prépares, il
déclenche).**
7. Appliquer les 4 patchs sur `claude/panel-mise-en-ligne`, lancer les tests
   Worker (`node --experimental-sqlite cloudflare/*.test.mjs`) et panel
   (`npm ci && npm test && npm run build`), déployer avec `confirme=DEPLOYER`,
   relire la MAC de référence avant/après.
8. Faire tourner `107-test` cinq jours sur la box de test sans fermeture
   brutale, puis seulement proposer `publish=true` au propriétaire.

## Comment tu travailles (méthode imposée)

- Avant chaque correctif : la mesure T0 (ligne de boîte noire, mesure réseau
  depuis le serveur sans identifiant affiché, ou test qui échoue).
- Chaque correctif : code + test (Dart pur si possible, sinon harnais
  `sqflite_common_ffi` + `MockClient`) + interrupteur de repli + ligne de
  boîte noire lisible par un non-technicien + paragraphe dans
  `docs/MESURE-ACTIVATION-INSTANTANEE.md` (section numérotée, datée, avec la
  mesure avant/après) + ligne dans `docs/HANDOFF-PANEL-BOX.md`.
- Avant chaque push : `flutter analyze` sans nouvelle erreur, `flutter test`
  entier vert (≥ 476 tests au 6 octobre), tests Worker et panel verts si
  touchés. Puis un build de test et ses empreintes.
- Après chaque build : attendre la photo ou la copie de la boîte noire du
  propriétaire, et lire ce qu'elle dit avant de proposer la suite.
- Commits en français, un sujet par commit, jamais d'identifiant de modèle
  d'IA dans le code ou les messages de commit.

## Pièges connus (ils ont déjà coûté du temps)

- Flutter n'est pas installé sur une machine neuve : cloner `stable` dans
  `/opt/flutter`. Le build GitHub peut échouer sur un hash d'asset `sqlite3`
  du runner : relancer un run neuf, ce n'est pas le code.
- Panel : `tsc -b` échoue avec TypeScript 6 (global) ; utiliser le 5.9.3 du
  `package-lock` (`npm ci` puis `npm run build`).
- MAC dans les URL du Worker : `MK:…` en clair ; encodée (`%3A`), certaines
  routes répondent `invalid mac`.
- `lib/l10n/generated/` est ignoré par git : lancer `flutter gen-l10n` après
  avoir ajouté une clé dans `app_fr.arb` et `app_en.arb` (fr = modèle).
- `Playlist.createdAt` est un `int` (ms), pas un `DateTime`.
- Les tests Worker tournent sur SQLite réel (`node --experimental-sqlite`),
  avec des comptes et adresses `example.test` uniquement.
- Une liste « ajoutée par le client » (`origin: 'self'`) n'est pas dans le
  PUT du panel : le Worker la garde d'office ; seule la route
  `DELETE /api/v1/sources/:mac/self/:id` (patch 3) la retire.

## Ce que tu rends à la fin de chaque session

1. Le tableau `maillon | délai mesuré avant | délai après | preuve`, mis à jour.
2. La liste des causes trouvées, chacune étiquetée PROUVÉ / FORTEMENT
   PROBABLE / NON VÉRIFIÉ avec sa preuve.
3. Le lien du build de test, versionName, versionCode, SHA-256, taille,
   signature attendue `5145b8e0…9e61`.
4. Les interrupteurs de repli ajoutés, avec leur clé.
5. Ce qui dépend du propriétaire, en une ligne chacun.
6. Rien d'autre : pas de promesse, pas de « ça devrait marcher ».

---

Contexte à remplir par le propriétaire :
- Branche de travail de l'app : `[…]`
- MAC de la box de test : `[…]`
- Fournisseurs servis à la box de test (noms d'hôte seulement) : `[…]`
- Jeton ou accès au panel pour lire la boîte noire : `[non / oui, voir env]`
- Décisions déjà prises : patchs déployés `[oui/non]`, `publish` autorisé `[non]`
