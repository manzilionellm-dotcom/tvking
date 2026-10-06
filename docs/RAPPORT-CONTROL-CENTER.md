# Rapport d'ingénierie — Centre de contrôle (6 octobre 2026)

Ce rapport ne contient que ce qui a été lu, exécuté ou mesuré.
Deux mots seulement pour l'état d'un comportement : **PROUVÉ** (une
commande l'a montré, citée) ou **NON PROUVÉ**. Aucune mesure locale n'est
présentée comme une mesure de production.

Code concerné : production `claude/panel-mise-en-ligne` (`636aad6`) +
`docs/patches/` 1 à 7, et la box sur `ccr-b93e1afd-gwirw0`.
Mis en ligne le 6 octobre (run #10 de `deploy-panel-cloudflare.yml`, branche `claude/panel-mise-en-ligne` à `7f2813e`) : patchs 1 à 8.

## 1. Bugs racines

Pour chaque bug : cause, pourquoi c'était possible, correctif d'architecture,
test qui l'aurait attrapé, recherche du même motif ailleurs.

| # | Bug | Cause racine | Pourquoi possible | Correctif | Test qui l'attrape | Même motif ailleurs |
|---|---|---|---|---|---|---|
| 1 | Révisions de listes en double ou manquantes sous concurrence (workerd : 10 envois → révisions 1..5) | Numéro calculé par « lire MAX puis insérer » en deux requêtes | D1 n'a pas de transaction interactive | Numéro alloué DANS l'insertion (`COALESCE(MAX(rev),0)+1`, clé (mac, rev)), dans le même lot que l'écriture, gardé par `changes() = 1` | `concurrency.e2e.mjs` E ; `failure_injection` B5 | Trouvé et corrigé : position des serveurs par défaut (#9). Lecture seule ailleurs (`currentRevision`) |
| 2 | Listes perdues : un ajout du client écrasé par un envoi du panel | 5 écrivains faisaient lecture → modification → écriture sans condition | Pas de colonne de version | `device_sources.version` + comparaison-échange (`casWriteSources`) ; épuisement → 409 explicite, jamais de perte | E (100 panel + 3 client) ; B5 | Les 5 écrivains passent tous par `casWriteSources` ; `writeDeviceSourceItems` supprimé |
| 3 | « no such table » sur une 2e base | Drapeaux « table prête » globaux au processus | Un isolate Worker sert plusieurs bases en test | Drapeaux par base (`WeakSet`/`WeakMap` sur `env.DB`) | `failure_injection` G (3 bases) ; contre-preuve : drapeau global remis → échec | 6 drapeaux corrigés (worker, blackbox, trial, store, ordres, tendances) ; box : favoris et récents |
| 4 | Clé d'idempotence bloquée 24 h, ou double débit, si le Worker meurt après l'écriture | La réponse était gardée APRÈS la transaction | Écriture métier et marqueur séparés | Marqueur de validation écrit DANS la transaction ; reprise depuis le marqueur ; réservation sans marqueur > 60 s reprise | `failure_injection` C1–C5 | — |
| 5 | Crédits négatifs possibles sans clé d'idempotence | Débit inconditionnel en mode historique | Deux chemins de débit | Débit toujours `WHERE credit_balance >= ?` ; 402 si 0 ligne | E2E D : 5 crédits, 100 activations → 5 réussites, solde 0 | — |
| 6 | 580 accusés sur 600 perdus en mesure locale | Les accusés partageaient le seau 60/min/IP de la box | Un seul seau pour tout `/api/box/*` | Seau `boxack` séparé, 600/min | `failure_injection` E10 | — |
| 7 | Un ordre en échec compté « appliqué » dans les centiles | Segment calculé sur `applied_at` sans état | — | Segments séparés `applied` / `failed` | `order_ack_trace` (latence) | — |
| 8 | Ajout de liste par le client → 500 sur une base où le panel n'a jamais écrit | Le magasin lisait `reseller_id`, colonne posée seulement par la route panel | Deux routes créaient la table, chacune avec ses colonnes | Le magasin garantit lui-même toutes ses colonnes ; « prêt » seulement après vérification | `failure_injection` H1, H2 ; audit 9 ; contre-preuve : correctif retiré → H1 rouge | Trouvé en rejouant l'audit sur une vraie base |
| 9 | Serveurs par défaut créés en même temps : même position | « lire MAX puis insérer » | Même motif que #1 | Position calculée dans l'insertion | `failure_injection` I1 : avant `[1,1,1,1,1,1,2,2,2,2]`, après `1..10` | — |
| 10 | Premières connexions admin simultanées : 9 sur 10 en 500 | « compter puis insérer » le premier compte | Même motif | Insertion conditionnelle `WHERE NOT EXISTS`, une requête | `failure_injection` J1 : avant 9 × 500, après 10 × 200, 1 compte | — |
| 11 | Inscription revendeur simultanée du même identifiant : 500 au lieu de 409 | Lecture puis insertion sans gestion de `UNIQUE` | Même motif | `ON CONFLICT(email) DO NOTHING` → 409 | `failure_injection` K1 : 201 + 4 × 409, 1 compte | Création par l'owner : déjà 409 (`catch`) |
| 12 | Box : la dernière bonne liste effacée quand la nouvelle est en délai de réessai | `keepOldLists` ne regardait que les listes essayées | Liste mise de côté ≠ liste refusée | Effacer seulement si une nouvelle liste a été chargée | `last_known_good_test.dart` ; contre-preuve avec `zuno.source.drop_first_legacy` | — |
| 13 | Faux vert : un banc de test rendait `run()` sans `results` pour `RETURNING` | Six copies de faux D1 divergentes | Pas de banc commun | Un seul banc fidèle sur SQLite réel (`test_support/d1_sqlite.mjs`) | Tous les bancs Worker migrés | L'audit sécurité avait sa propre fausse base (#14) |
| 14 | Audit sécurité 41/45 sur le code corrigé | Sa fausse base reconnaissait le SQL par morceaux de texte : ni `ALTER`, ni `UPDATE … WHERE version`, ni `INSERT … SELECT … RETURNING`, ni `batch()` | — | Audit migré sur le banc fidèle ; il lit les octets stockés en table au lieu des arguments capturés, et vérifie en plus l'historique des révisions | `panel_security.audit.mjs` 47/47 | — |
| 15 | Test de concurrence rouge par intermittence (4 écritures sans réponse) | **Outil** : wrangler 3.114 / son workerd local garde ~21 à 29 sockets par requête vers le serveur Miniflare (état CLOSE_WAIT) → plafond de 20 000 descripteurs | — | Banc relancé hors wrangler 3 | Code de production pur, route `/api/status` triviale : même fuite sous wrangler 3 (+2 138 descripteurs pour 100 requêtes), aucune sous wrangler 4.147.0 (200 à 290 après 1 000 écritures) | Ne concerne pas le runtime Cloudflare de production |
| 16 | Sous wrangler 4, 2 POST clients sur 103 perdus dans 2 lancements sur 29 (« Network connection lost ») | Cause exacte NON PROUVÉE. PROUVÉ : l'erreur est levée par le « ProxyWorker » que `wrangler dev` place devant le Worker (son message), et ce proxy réessaie GET/HEAD après « a dropped connection to the UserWorker », jamais POST | Ce proxy n'existe qu'en développement | Banc lancé sur Miniflare 4 seul, avec le paquet de `wrangler deploy --dry-run` (`test_support/miniflare_server.mjs`) | 12 lancements sur 12 verts sans le proxy ; avec le proxy, les écritures perdues n'étaient PAS validées (version = nombre de succès) | Mémoire workerd stable (743 à 758 Mo de pic sur 6 lancements) : pas une fuite du Worker |

`linkage_sim` 13/13 : l'assertion fausse attendait l'ancien rafraîchissement
du panel. Le commit `516b87f` l'a déplacé dans `bindPanelRefresh` /
`panelPollInterval(panelChannelUp())`. L'assertion vérifie maintenant ce
câblage réel.

## 2. Fichiers corrigés

Worker (`android-app/cloudflare/`, patch 7 `panel-ordres-accuses-trace-revisions.patch`) :
`box_orders.js` (nouveau : ordres, révisions, latence), `device_sources_store.js`
(nouveau : comparaison-échange), `box_channel.js`, `api_v1.js`, `worker.js`,
`source_url.js`, `blackbox_journal.js`, `trial_access.js`.

Panel (`android-app/admin-panel/src/`) : `lib/api.ts`, `lib/timeline.ts`
(nouveau), `pages/TracePanel.tsx` (nouveau), `pages/BlackBoxPage.tsx`,
`package.json`.

Box (`android-app/lib/`) : `features/subscription/domain/order_ack.dart` et
`data/order_ack_client.dart` (nouveaux), `domain/box_channel.dart`,
`data/box_signal_client.dart`, `data/remote_activation_watch.dart`,
`features/playlists/data/remote_source_repository.dart`,
`features/playlists/data/favorites_repository.dart`,
`features/channels/data/recently_watched_repository.dart`,
`core/app/repair_flags.dart` (repli `zuno.ack.off`, coupé par défaut).

## 3. Tests ajoutés

| Fichier | Ce qu'il prouve |
|---|---|
| `cloudflare/test_support/d1_sqlite.mjs` | Banc D1 fidèle : `undefined` refusé, `RETURNING`, lot = transaction, injection de pannes avant/après écriture, entrelacement |
| `cloudflare/order_ack_trace.test.mjs` | États d'ordre, accusés dupliqués sans effet, accusé inconnu refusé et journalisé, révision ancienne n'écrase pas, retour arrière, chronologie, centiles |
| `cloudflare/failure_injection.test.mjs` | C1–C5 reprise après panne, E1–E10 et E4b accusés (inconnu, autre box, doublon, tardif, perdu), F1–F2 dernière bonne liste, G bases multiples, B1–B5 torture 2/10/50/100, H1–H2, I1, J1, K1 |
| `cloudflare/concurrency.e2e.mjs` | Vraie concurrence sur workerd + D1 local + Durable Object réel, 2/10/50/100 requêtes simultanées |
| `cloudflare/test_support/miniflare_server.mjs` | Le paquet de déploiement servi par Miniflare, sans le proxy de développement |
| `cloudflare/latency_local.e2e.mjs` | Mesure locale p50/p95/p99 par le même calcul que la production |
| `admin-panel/src/lib/timeline.test.ts` | Libellés de chronologie, « non mesuré » au lieu de 0 |
| `test/features/subscription/order_ack_test.dart` | Décision APPLIED/FAILED de la box, corps exact de l'accusé |
| `test/features/subscription/order_ack_client_test.dart` | Worker sans route (404) → 1 envoi ; 503 + coupure → réussi au 3e ; panne durable → 4 essais ; repli → 0 envoi |
| `test/features/playlists/last_known_good_test.dart` | 500, délai, vide, HTML, délai de réessai : l'ancienne liste reste ; contre-preuve |

## 4. Tests exécutés et résultats exacts (6 octobre 2026)

| Suite | Résultat |
|---|---|
| Worker `activation_idempotency` | 20 / 20 |
| Worker `activation_m3u` | 95 / 95 |
| Worker `blackbox` | 34 / 34 |
| Worker `box_channel` | 8 / 8 |
| Worker `failure_injection` | 55 / 55 |
| Worker `linkage_sim` | 13 / 13 |
| Worker `order_ack_trace` | 46 / 46 |
| Worker `reset_box_panel` | 19 / 19 |
| Worker `self_source_panel` | 13 / 13 |
| Worker `api_v1_robustesse.smoke` | 36 / 36 |
| Worker `worker_security.smoke` | 6 / 6 |
| Worker `panel_security.audit` | 47 / 47 (45 d'origine + 2 ajoutés) |
| E2E `concurrency.e2e`, Miniflare 4 sans proxy, paquet de déploiement | 23 / 23 sur 12 lancements sur 12 (6 par mode d'essai) |
| E2E `concurrency.e2e`, wrangler 4.147.0 | 23 / 23 sur 27 lancements valides sur 29 ; 2 rouges = bug 16 (outil) ; 3 autres écartés : Worker modifié pendant le test (rechargement, 503) |
| Panel `npm test` / `npm run build` | 52 / 52 ; build OK |
| App `flutter test` | 504 réussis, 2 ignorés |
| App `flutter analyze` | 0 erreur ; 32 avertissements, aucun dans un fichier touché |
| Patchs 1-7 sur `636aad6` propre | s'appliquent dans l'ordre ; arbre obtenu identique octet pour octet à l'arbre testé (`diff -r` vide) |

## 5. Comportements PROUVÉS

- **Ordre suivi de bout en bout** : chaque activation, renouvellement,
  changement de listes et remise à neuf crée un ordre `ord_…` avec
  `trace_id`, publié au Durable Object réel, porté par la trame WebSocket et
  l'attente longue, accusé RECEIVED puis APPLIED par la box, persisté
  (`concurrency.e2e`, dernier test ; `order_ack_trace`).
- **Machine d'états stricte** : CREATED → SENT → RECEIVED → APPLIED / FAILED,
  EXPIRED après 10 min ; un accusé tardif est marqué `late_ack` ; un état
  terminal ne bouge plus ; accusés dupliqués sans effet ; ordre inconnu ou
  d'une autre MAC → 404 journalisé.
- **Même clé d'idempotence × 100 simultanées** : 1 exécution, 1 débit,
  1 licence, réponses identiques (E2E A).
- **100 renouvellements simultanés** : 100 débits = 100 × 365 jours,
  101 soldes distincts au journal (E2E B).
- **100 premières activations simultanées d'un client neuf** : 1 appareil,
  1 licence, 0 client orphelin (E2E C).
- **5 crédits, 100 activations simultanées** : exactement 5 réussites,
  95 refus 402, solde 0, jamais négatif (E2E D).
- **Mesure locale sans perte** : 600 ordres joués (200 par opération), 0 non
  vu par la box simulée, 600 accusés APPLIED.
- **100 envois de listes du panel + 3 ajouts client simultanés sur la même
  box** : aucune liste client perdue, révisions continues sans trou, une
  révision par écriture réussie, un ordre par envoi réussi, dernière
  révision = liste servie. Les écritures qui épuisent la
  comparaison-échange reçoivent un 409 explicite (E2E E).
- **Panne après validation** : la requête rejouée rend la réponse
  reconstruite depuis le marqueur, sans second débit (C1–C5).
- **Dernière bonne liste** : la box garde l'ancienne liste tant qu'aucune
  nouvelle n'est chargée ; le serveur ne republie en retour arrière qu'une
  révision accusée APPLIED.
- **Codes chiffrés au repos** : `m3u_url`, `sources_json` et l'historique
  des révisions ne contiennent pas le lien en clair (audit 8, lu en table).
- **Compatibilité** : le code de production actuel répond 404 sur
  `/api/box/ack` ; la box envoie alors une fois et s'arrête.

## 6. Comportements NON PROUVÉS

- Latence en production (p50/p95/p99) : **NON MESURÉE**, rien n'est déployé.
  Les chiffres locaux du § 8 ne la remplacent pas.
- Sémantique de `changes()` dans un lot et `INSERT … SELECT … RETURNING` sur
  la D1 de production : prouvée sur workerd + D1 local (même moteur SQLite),
  pas sur l'infrastructure Cloudflare.
- Accusés envoyés par une vraie box : prouvé par tests et par le chemin
  workerd ; pas encore observé depuis la box de test (build #167 à installer).
- Correctif `device_guard` (codes IPTV par MAC) : non porté sur la production.
- Paiements et webhooks : aucune intégration n'existe dans le code.
- Liaison par clé Android Keystore : non faite.
- Séparation « téléchargement / analyse » de l'import sur la box : non faite.

## 7. Risques de production restants

1. **Codes IPTV lisibles par la seule MAC** (`GET /api/device-source/:mac`),
   freinés seulement par 120 lectures/min/IP une fois le patch 6 déployé.
2. Patchs 1 à 8 en ligne depuis le 6 octobre ; la latence de production se lit maintenant dans `GET /api/v1/metrics/latency` (pas encore relevée).
3. **Fusion à l'aveugle** des branches : 18 fichiers en conflit, et 10 pages
   du site supprimées côté app (`docs/DIVERGENCE-BRANCHES.md`).
4. Au-delà d'environ 50 écrivains simultanés sur **la même box**, les
   suivants reçoivent 409 et doivent renvoyer (mesuré : 100 envois → 53 à 57
   réussis, 46 à 48 refus 409, aucune perte).
5. Une réponse perdue après validation (coupure réseau) sur un envoi de
   listes : l'écriture a eu lieu, le panel voit une erreur ; renvoyer crée
   une révision de plus avec le même contenu (pas de clé d'idempotence sur
   les listes).
6. JWT du panel en `localStorage` (exposé à un XSS).
7. Le workflow de déploiement fixe wrangler 3.90.0 : il sert seulement à
   l'envoi, mais ne doit pas servir aux tests locaux de charge (bug 15).
8. Bug 16 : la cause exacte de la coupure du proxy de développement n'est
   pas établie ; seul est prouvé qu'elle disparaît sans ce proxy et
   qu'aucune écriture n'est validée sans réponse dans ces cas.

## 8. Mesures locales (workerd + D1 local, PAS la production)

Miniflare 4 sans proxy, paquet de `wrangler deploy --dry-run`, N = 200 par
opération, requêtes l'une après l'autre, box simulée (elle accuse aussitôt :
`box_apply` mesure ici l'écart entre ses deux accusés, pas un vrai import).
0 ordre sur 600 non vu par la box simulée. Valeurs en ms, p50 / p95 / p99.

| Opération | API (T1→T2) | publication (T2→T3) | reçu (T3→T4) | appliqué (T3→T5) | bout en bout (T0→T5) |
|---|---|---|---|---|---|
| Activation | 11 / 17 / 22 | 5 / 6 / 14 | 12 / 17 / 25 | 19 / 27 / 34 | 36 / 49 / 53 |
| Renouvellement | 10 / 15 / 19 | 2 / 3 / 3 | 13 / 19 / 35 | 19 / 28 / 42 | 32 / 46 / 76 |
| Listes | 10 / 14 / 22 | 2 / 3 / 4 | 12 / 18 / 21 | 19 / 27 / 31 | 31 / 42 / 50 |

Ce que ces chiffres ne contiennent pas : le trajet Internet, la latence de la
D1 de production, l'import réel des chaînes sur la box. Ils donnent le
plancher du code serveur, rien de plus. Production : **NON MESURÉE**.

## Annexe — architecture lue dans le code

| Pièce | Réalité |
|---|---|
| Panel | React 18 + Vite + TypeScript 5.9.3, Cloudflare Pages, JWT HS256 |
| Backend | Un Worker (`worker.js`, `api_v1.js`), D1 `tvking_licensing`, Durable Object `RealtimeHub` |
| Schéma | `schema.sql` + colonnes ajoutées par `ALTER TABLE … ADD COLUMN` (pas de migrations versionnées) |
| Identité box | « MAC » = `MK:` + 5 octets dérivés de l'ANDROID_ID |
| Paiements | Table `payments` présente, aucune intégration |

Migrations du patch 7, toutes additives : tables `box_orders`,
`source_revisions` ; colonnes `device_sources.version`, `origin`,
`reseller_id`, `sources_json` (si absentes), `idempotency_keys.committed_at`,
`commit_ref`. L'ancien code les ignore : retour arrière du code sans perte.
