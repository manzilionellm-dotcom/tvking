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

## 7. Build de test #156 (vérifié)

Run `build-zuno-tv.yml` n° 156 : https://github.com/manzilionellm-dotcom/tvking/actions/runs/37358140257
(`workflow_dispatch`, `test_box=true`, `publish=false`, `play_aab=false`),
conclusion **success**, commit `70c95a39a7815e0cd5764a709ee79520a8fba9ac`.

| Champ | Valeur | Preuve |
| --- | --- | --- |
| Version visible | `107-test.156` | journal du job, `version.json` de `zuno-tv-test` |
| versionCode | `1791226009` | idem |
| SHA-256 de l'APK | `bcc1cbeef5ef10f6c6da707e8cd4ffa6fbef0b129704b00c76c49f30e2a95c96` | `version.json` de `zuno-tv-test` + digest de l'actif GitHub |
| Taille | 54 722 595 octets | idem |
| Signature | `5145b8e019f6d5fb96a207f2e73673fd954f799966fd598889211556cbdf9e61` — « ✓ signature = clé des box clients » | journal du job (`apksigner verify --print-certs`) |
| Contrôle qualité du run | `flutter analyze` + `flutter test` : étape verte (18:45:34 → 18:46:48 UTC) | journal du job |
| Backend compilé | `https://app.7themotion.com` (vérifié dans `libapp.so`) | journal du job |
| Release clients `zuno-tv` | **non touchée** (étape « Publier sur la release zuno-tv » sautée, `PUBLIER=false`) | journal du job, release inchangée depuis le 30/09 |
| Lien | https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv-test/zuno-tv.apk | release `zuno-tv-test` |

## 7 bis. Première mesure sur la box de test (5 octobre, 21:04) et deuxième correctif

Le propriétaire a installé `107-test.156` : la pastille « Mise à jour… »
est restée affichée **10 minutes** (photo). C'est le maillon 4c (import)
mesuré en vrai. La boîte noire n'a pas encore été lue, donc deux causes
restent possibles, toutes deux dans ce maillon :

| Cause | Mécanisme (code) | Correctif (branche `ccr-b93e1afd-gwirw0`) | Repli |
| --- | --- | --- | --- |
| Passe automatique 2 min après l'ouverture | `TvContentRefresh.run` → `refreshAll(skipSyncedWithin: 2 min)` : **toutes** les listes synchronisées il y a plus de 2 minutes sont retéléchargées, l'une après l'autre (3 ici) | la passe automatique (2 min / 6 h) ne retélécharge que les listes à jour depuis plus de **6 h** ; le bouton Redémarrer garde 2 min (`TvContentRefresh.skipWindow`) | `zuno.refresh.auto_full` |
| Import d'une nouvelle liste : rien à l'écran avant la fin | `_insertChannelsImpl` n'émet jamais pendant l'insertion (règle anti-OOM P1-3) | sur une box **sans chaîne**, le premier lot (1 000 chaînes) est affiché dès qu'il est en base ; une box déjà garnie garde la règle anti-OOM | `zuno.import.first_batch_off` |
| Pastille muette | « Mise à jour… » sans chiffre | « Mise à jour… · 12.4 Mo » / « · 18 230 » / « · 12 000 / 18 230 » (chiffres seulement, rien à traduire) | aucun (affichage) |

Ce qui ne change pas : le téléchargement dépend du fournisseur. Le
téléchargeur n'enchaîne PAS dix signatures de 90 s (un délai dépassé arrête
la boucle) ; seules les réponses rapides refusées font essayer la suivante.

Tests : `tv_content_refresh_window_test.dart` (3), `updating_pill_detail_test.dart`
(3), `first_batch_display_test.dart` (3, SQLite réel : premier lot émis sur
box vide, jamais sur box garnie, jamais avec le repli), `repair_flags_test.dart`.

## 7 ter. Demandes du propriétaire (5 octobre, 21:30) : plus rien à l'écran, mise à jour de l'app sans bouton, bouton instantané

Trois demandes, trois réponses, chacune avec son repli coupé par défaut.

| Demande | Ce qui est fait | Repli | Limite vraie |
| --- | --- | --- | --- |
| « Je ne veux plus voir le bouton Mise à jour sur la télévision » | La pastille « Mise à jour… » de l'accueil (builds #154 à #157) est **cachée** : l'import se fait en silence, la mesure reste dans la boîte noire | `zuno.sync.pill_show` = true la réaffiche (diagnostic) | aucune |
| « L'app doit se mettre à jour toute seule, 1 minute après, personne ne voit » | 1 min après l'ouverture, puis toutes les 30 min, et **à la seconde** quand le panel envoie `force_update` : la box vérifie, télécharge, contrôle l'APK (SHA-256 + taille), puis **ouvre elle-même l'installateur Android** dès qu'elle est à l'accueil, une seule fois par version (`UpdateService.autoUpdate`, `shouldAutoInstall`) | `zuno.update.auto_install_off` (l'APK attend Réglages → Mise à jour) | **FACT** : Android impose à toute app installée hors Play Store une confirmation « Installer » (boîte système, une touche). Aucun code de l'app ne peut la supprimer. La seule mise à jour vraiment invisible est celle du Play Store (le test fermé Google) : ce build-là se met à jour sans rien demander. Sans l'autorisation « applications inconnues », l'app n'ouvre pas les réglages dans le dos du client : l'APK reste prêt dans Réglages. |
| « Crée un nouveau bouton qui est instantané » | Panel : **⚡ Envoi instantané** sur la fiche appareil (renvoie les listes du panel, la box est prévenue à la seconde) et suivi « Liste sur la TV après N s · X chaînes » sous le bouton d'Activation à distance, en relisant l'inventaire réel de la box toutes les 2 s. Box : après un import ordonné par le panel, l'inventaire est renvoyé tout de suite (heartbeat) | `zuno.heartbeat.after_import_off` | Le suivi ne prouve l'arrivée que pour une box ≥ 107-test.158 (les v106 remontent l'inventaire au prochain heartbeat, jusqu'à 60 s) |

Patch panel : `docs/patches/panel-envoi-instantane.patch`, à appliquer **après**
`panel-worker-boite-noire.patch` sur `claude/panel-mise-en-ligne`
(`npm test` 43/43, `tsc` propre, `npm run build` OK).

Tests app : `auto_install_policy_test.dart` (5), `repair_flags_test.dart`
(nouvelles clés), suite complète : voir § 7 quater.

Build #157 (`107-test.157`, run 37362062690, commit `56c6f63`) : vert, SHA-256
et versionCode dans `zuno-tv-test/version.json` au moment du run ; remplacé
par le #158 ci-dessous, qui contient tout.

## 7 quater. Build #159 = tout ce qui précède (vérifié)

Le #158 (même commit `7cbdca3`) a échoué sur un binaire `sqlite3` téléchargé
corrompu par le runner (empreinte différente, hors de notre code ; analyse +
tests verts), et sa relance a été annulée après 15 min de file d'attente sans
tourner. Run neuf #159 : https://github.com/manzilionellm-dotcom/tvking/actions/runs/37365911230
(`test_box=true`, `publish=false`), conclusion **success**.

| Champ | Valeur |
| --- | --- |
| Version visible | `107-test.159` |
| versionCode | `1791229916` |
| SHA-256 de l'APK | `46166a48efbc19d83ce71dd529be46d6950999a283edc391e85039a7e5cdfacf` |
| Taille | 54 735 842 octets |
| Signature | `5145b8e019f6d5fb96a207f2e73673fd954f799966fd598889211556cbdf9e61` (clé des box clients) |
| Contenu | #156 (ordre du panel = import immédiat) + #157 (passe auto 6 h, premier lot, chiffres) + pastille cachée, mise à jour auto de l'app, inventaire renvoyé après import |
| Release clients `zuno-tv` | non touchée |
| Lien | https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv-test/zuno-tv.apk |

Suite Flutter sur ce commit : 443 verts, 2 ignorés (`flutter test`, 05/10 19:25 UTC).

## 7 quinquies. Première mesure complète sur la box de test (5 octobre, 22:19) : H4 prouvée

Le propriétaire a activé une box `107-test.159` depuis le panel en ligne avec
un lien M3U (`thekung.801802.com:80`, derrière Cloudflare). Photos : panel,
« Mes sources » vide, boîte noire.

| Maillon | Observé | Preuve |
| --- | --- | --- |
| Panel | « Cette liste était déjà sur la box : rien à renvoyer » : le panel en ligne n'a **pas** envoyé la liste (déjà sur le serveur), seul le signal d'activation est parti | capture panel |
| Box, réception | la box a quand même relu la liste du serveur à son tour suivant : `22:21:31 [SOURCE] nouvelle liste M3U reçue du panel : chargement` | boîte noire |
| Box, import | `22:21:31 W [SOURCE] liste M3U du panel refusée après 90,0 s : Impossible de récupérer la playlist` — le fournisseur n'a rien livré en 90 s (délai unique en-têtes 90 s / corps 90 s) | boîte noire |
| Fournisseur | depuis Internet, l'hôte répond en 0,4 s sur `/` (Cloudflare) ; la génération de la liste avec identifiants, elle, dépasse 90 s ou le corps n'arrive pas en 90 s sur le Wi-Fi de la box | `curl` racine, sans identifiants |

**H4 PROUVÉE** pour cette liste : l'ordre arrive, l'import démarre à la
seconde, c'est la livraison de la liste par le fournisseur qui échoue au
délai de 90 s. « Mes sources » reste vide parce qu'une liste refusée n'est
pas gardée (volontaire : pas de source morte).

Correctif (build #160) : `M3uFetcher` attend 120 s la première réponse,
puis continue **tant que des octets arrivent** (60 s de silence maximum,
10 min au total) au lieu d'un délai total de 90 s. La boîte noire dit où ça
coince : `délai dépassé après N s (aucune réponse du serveur)` ou `(corps,
X Mo reçus)`. Repli `zuno.m3u.timeout_legacy`. Tests
`m3u_fetch_timeouts_test.dart` (4 : lent mais régulier passe ; muet au milieu
coupé avec la raison ; sourd coupé aux en-têtes ; repli 90/90/90).

Limite vraie : si le fournisseur met plus de 2 minutes à répondre ou coupe
lui-même, aucun délai côté box ne l'arrangera ; il faut alors un lien plus
léger (sans films/séries) ou un autre fournisseur. La boîte noire le dira.

## 7 sexies. « Instantané comme les grandes marques » : le lien get.php lu par l'API Xtream

Ce que font réellement les grandes applications avec un lien
`get.php?username=…&password=…` : elles ne téléchargent pas le fichier M3U
(chaînes + films + séries, des dizaines de Mo, parfois plus de 90 s à
générer). Elles lisent les **mêmes identifiants par l'API Xtream**
(`player_api.php`), qui renvoie la liste des chaînes TV seule en JSON léger,
en quelques secondes ; films et séries viennent ensuite, à la demande.

Build #160 : quand le panel envoie un lien get.php, la box en extrait le
compte (`m3u_link.dart`, pur, testé), importe les chaînes TV par l'API
(chemin Xtream déjà en place, par catégorie si la liste est grande), et ne
retombe sur le téléchargement du fichier M3U que si l'API refuse. La liste
garde les deux empreintes (Xtream et lien) pour que l'effacement et
l'interrupteur allumé / éteint du panel la retrouvent
(`SourceFingerprint.ofPlaylist`, testé). Le panel (patch « envoi instantané »)
reconnaît la liste dans l'inventaire sous sa forme Xtream.

Repli : `zuno.source.m3u_link_as_m3u` (ancien comportement : fichier M3U).
Boîte noire : `nouvelle liste Xtream (lien) reçue du panel : chargement`,
`liste Xtream (lien) du panel chargée en N s (X chaînes)` ; en cas de refus
de l'API : `API Xtream refusée pour ce lien : repli sur le fichier M3U`.

Limite vraie : un lien vers un fichier `.m3u` statique, ou un fournisseur
qui n'a pas d'API Xtream, suit le chemin M3U (avec les délais de § 7
quinquies). Un fournisseur qui limite le nombre de connexions compte
l'appel API comme une connexion, comme le téléchargement M3U.

## 7 septies. Mesure du #160 sur la box de test (22:59) : l'API répond, l'écriture échoue

Boîte noire `107-test.160`, MAC `MK:80:78:60:07:4F` (licence à vie, 3 listes
servies : thekung ×2 avec un mot de passe déformé par le clavier du
téléphone — apostrophe typographique `%E2%80%99` et accent `%CC%81` —, et
business-cloud-8 propre) :

```
22:59:41 I [XTREAM] pro.business-cloud-8.ru : 50000 chaînes live récupérées
22:59:41 I [ACTION] Insertion en base de 50000 chaînes
22:59:41 W [SOURCE] liste Xtream (lien) du panel refusée après 145.6 s :
                    DatabaseException(FOREIGN KEY constraint failed (code 787 …
22:59:41 W [SOURCE] API Xtream refusée pour ce lien : repli sur le fichier M3U
```

Lecture :

- **L'API Xtream marche** avec ce lien : 50 000 chaînes TV (plafond
  `kMaxChannelsPerImport`) ramenées en 145 s, par catégorie (liste > 10 Mo).
  Le fournisseur n'est plus le bloqueur pour cette liste.
- **L'écriture en base a échoué** : « FOREIGN KEY constraint failed » à
  l'insertion des chaînes = la ligne de la liste (`playlists.id`) n'existait
  plus au moment d'écrire ses chaînes. Quelque chose a supprimé la liste
  pendant les 145 s de téléchargement. Les suppressions de listes ne
  laissaient **aucune trace** dans la boîte noire : impossible de dire qui.
  Corrigé dans le #161 : chaque suppression écrit `liste N supprimée
  (raison)` (client, plus envoyée par le panel, import échoué, vide après
  synchro). La prochaine occurrence nommera le coupable.
- Le repli M3U après un refus de l'API était inutile quand le serveur a
  **répondu** « identifiants refusés » : mêmes identifiants, même refus,
  plus jusqu'à 2 minutes de silence. #161 : `XtreamAuthException` → pas de
  repli, ligne `identifiants refusés par le fournisseur : vérifier le mot de
  passe dans le panel`. Un serveur muet ou sans API garde le repli.

Ce que font les grandes applications (IBO, TiviMate, Smarters) avec un
compte Xtream, et que la box ne fait pas encore : afficher les
**catégories** dès `get_live_categories` (quelques Ko, < 1 s), puis charger
les chaînes **par catégorie à la demande**, au lieu d'attendre les 50 000
chaînes. C'est la seule façon de tenir 3 à 5 s sur un fournisseur à 50 000
chaînes, et c'est la prochaine étape structurelle une fois l'écriture
corrigée.

## 7 octies. « Les listes envoyées à 19 h s'installent à 23 h » et « la liste que j'efface revient »

Deux constats du propriétaire le 5 octobre vers 23 h, deux causes lues dans
le code, deux correctifs.

**1. La box réessayait la mauvaise liste avant la bonne, à chaque tour.**
Trois listes servies à la box de test, dont deux avec le mot de passe
déformé. À chaque tour (toutes les 25 s tant que la box n'a pas de chaîne),
la box reprenait les listes dans l'ordre du serveur : la mauvaise (jusqu'à
2 minutes de silence), puis la bonne, puis l'autre mauvaise. Build #162 :
une liste refusée est mise de côté 5 min, puis 15, 45 min, 2 h, 6 h au plus,
et passe **après** les listes jamais refusées ; un ordre du panel ou le
bouton Redémarrer remet tout le monde en course (`source_retry.dart`, pur,
9 tests). Boîte noire : `N liste(s) refusée(s) récemment mise(s) de côté`.
Repli `zuno.source.retry_always`.

**2. Le panel ne savait pas retirer une liste ajoutée par le client.** Le
panel en ligne affiche « Ajoutée par le client. Elle ne se retire pas depuis
le panel. » : effacer les listes du panel laisse celle du client (Mon espace
ou TV), qui réapparaît sur la fiche. Patch `docs/patches/panel-supprimer-liste-client.patch`
(à appliquer après les deux précédents) : Worker `DELETE
/api/v1/sources/:mac/self/:id` (jeton du panel, revendeur propriétaire
seulement, box prévenue « source »), bouton **Supprimer** sur les listes du
client dans la fiche appareil. Test Worker `self_source_panel.test.mjs`
(13 : 401 sans jeton, 403 autre revendeur, 404 id inconnu, retrait, la box
ne reçoit plus la liste, la liste du panel reste). Panel : 44 tests, build.

**Build #162 vérifié** (`build-zuno-tv.yml`, `test_box=true`, `publish=false`,
run 37375978821, commit 510964a) : `107-test.162`, versionCode 1791235805,
SHA-256 `8a776baa2603eb61042757aa5103da739bcaa3b0a84e90ab36c0f3cca304a7bd`,
54 754 170 octets, `mandatory: false`. Contient tout ce qui précède (§ 7 bis
→ 7 octies). Suite Flutter avant commit : 466 verts, 2 ignorés.

## 7 nonies. « Il me donne toujours l'ancien serveur » et « si j'efface, il efface réellement ? » (5 octobre, 23:50)

Boîte noire `107-test.162` photographiée par le propriétaire, plus trois
mesures faites depuis le serveur de session (lecture seule, aucun identifiant
affiché, scripts dans le bloc-notes de session, non versionnés).

**Ce que dit le serveur (`GET /api/device-source/<mac>`, `GET /api/box/wait`)**
- Listes servies à `MK:80:78:60:07:4F` : 4 (thekung panel, pro.business-cloud-8
  panel, tv.business-cloud-8 panel, thekung « 6 » ajoutée par le client, dont le
  lien est **collé deux fois** : `…output=tshttp://thekung…`).
- `updated_at` des listes : **21:10:12 UTC = 23:10:12 heure de la box**.
- Dernier signal `activate` : **21:49:24 UTC (23:49:24)**, sans aucun signal
  `source` derrière. Le clic « Activer » de 23:49 n'a donc écrit aucune liste.
- Cause (code du panel en ligne, `RemoteActivatePage.sendList` sur
  `claude/panel-mise-en-ligne`) : la liste saisie est **ajoutée** aux listes du
  panel, « maximum 3 » ; la box en ayant déjà 3, le plan répond `full` et le
  panel refuse (« Cette box a déjà 3 listes du panel »). Résultat : la box garde
  l'ancien serveur. **PROUVÉ** (données serveur + code).
- Correctif : `docs/patches/panel-activation-remplace.patch` (4e patch, après
  les trois autres) : « Activer avec une liste » = **cette liste remplace les
  listes du panel** ; les listes du client restent (le Worker les garde
  d'office) ; même liste déjà seule → renvoyée quand même (c'est ce renvoi qui
  prévient la box). Texte du panel : « L'ancienne liste du panel est
  remplacée ; la liste ajoutée par le client reste. » Pour ajouter sans
  remplacer : fiche appareil → Liste de chaînes (inchangé). Tests panel : 47
  verts, build OK (TypeScript 5.9.3 du `package-lock`).

**Les fournisseurs, mesurés depuis le serveur (21:52–21:54 UTC)**

| Liste | API Xtream (`player_api.php`) | Lien M3U (`get.php`) |
|---|---|---|
| thekung (panel) | compte 0,58 s `auth=1` ; 92 catégories 0,38 s ; **11 857 chaînes TV, 3,33 Mo en 0,72 s** | en-têtes après **14,6 s**, corps **> 50 Mo** (sondage coupé à 50 Mo ; le M3U contient aussi films et séries) |
| pro.business-cloud-8 (panel) | compte 0,32 s `auth=1`, `status=Active` | **HTTP 884** + HTML en 0,36 s (refus du serveur) ; depuis la box : aucun en-tête en 120 s (boîte noire 23:50:06) |
| tv.business-cloud-8 (panel) | compte 0,37 s `auth=1`, `status=Active` | HTTP 884 + HTML en 0,43 s |

Lecture : avec le #162 (lien get.php lu comme compte Xtream), thekung se charge
en secondes (c'est la ligne « nouvelle liste Xtream (lien) reçue du panel :
chargement » de 23:50:06). Le lien M3U du même compte, lui, met 14,6 s avant le
premier octet et pèse plus de 50 Mo : c'est la voie qui remplissait la mémoire.
Les deux comptes business-cloud-8 sont valides à l'API mais leur `get.php`
refuse (884) ou ne répond pas à la box : le repli M3U y coûte 120 s pour rien.

**Fermeture brutale 23:47 (ANR, 330 Mo)** : **NON VÉRIFIÉ**. Les lignes
photographiées commencent à 23:49:28, après le redémarrage. Les lignes `GEL`
(« fil UI bloqué ~N ms pendant : … ») et le fil d'Ariane entre 23:44 et 23:47
nomment l'action en cours au moment du gel ; sans elles, aucune cause n'est
affirmée. Hypothèse la plus probable, non prouvée : import M3U de plus de
50 Mo (thekung par le lien, avant le passage par l'API) sur une box 1 Go.

**« Si j'efface, il efface réellement ? »** (code lu, pas supposé)
- Depuis le **panel**, une liste du panel : oui, le serveur ne la sert plus à
  l'instant, la box l'efface à la vérification suivante (tout de suite si la
  WebSocket est ouverte, sinon ≤ 5 min). Une liste **ajoutée par le client** :
  non, impossible depuis le panel en ligne tant que le 3e patch n'est pas en
  ligne.
- Depuis la **télé** (« Mes sources » → Supprimer), une liste envoyée par le
  panel : elle est effacée localement puis **revient** à la vérification
  suivante, parce que le serveur la sert toujours. C'est le « j'efface, il
  revient après cinq minutes ». Correctif box (ce commit) : la télé le dit
  avant de supprimer (« … envoyée par ton revendeur : supprimée ici, elle
  revient à la prochaine vérification ») et la boîte noire note « liste N
  supprimée (client, liste encore servie par le panel) ». Règle pure
  `RemoteSourceRepository.servedByPanel`, 3 tests. Aucun interrupteur : seul le
  texte et la raison changent, pas le comportement.

**Build #163 vérifié** (`build-zuno-tv.yml`, `test_box=true`, `publish=false`,
run 37379758296, commit dab884b) : `107-test.163`, versionCode 1791237816,
SHA-256 `dbc30ee9f72734d81360dc09aada2cc1030b8208ebda0308a510c004cb9a012e`,
54 755 742 octets, `mandatory: false`. Suite Flutter avant commit : 469 verts,
2 ignorés.

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
