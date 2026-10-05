# Rapport d'ingénierie — Centre de contrôle (6 octobre 2026)

Mission : transformer le panel en centre de contrôle de production, à partir
du code réel. Ce rapport ne contient que ce qui a été lu, exécuté ou mesuré.
`NON MESURÉ` / `NON FAIT` est écrit là où c'est le cas.

## 1. Architecture trouvée (lue dans le code)

| Pièce | Réalité |
|---|---|
| Panel | React 18 + Vite + TypeScript 5.9.3 (`android-app/admin-panel`), Cloudflare Pages, 26 pages, JWT HS256 en `localStorage` |
| Backend | Un Cloudflare Worker (`worker.js` 4 463 lignes, `api_v1.js` 4 625 lignes), D1 (SQLite) `tvking_licensing`, Durable Object `RealtimeHub` |
| Schéma | `schema.sql` : apps, admin_users, resellers, customers, devices (`mac UNIQUE`), licenses (`UNIQUE(device_id, app_id)`), playlists, payments, audit_logs, notifications, credit_ledger, plan_costs ; colonnes ajoutées à chaud par `ALTER TABLE … ADD COLUMN` (pas de migrations versionnées) |
| Auth / RBAC | JWT signé `ADMIN_SECRET` ; rôles super_admin / admin / support / reseller ; droits revendeur cochés (`permissions`) vérifiés côté serveur (`resellerCan`) ; cloisonnement revendeur par `devices.reseller_id` |
| Temps réel | WebSocket `/api/box/ws` + attente longue `/api/box/wait` (anneau de 32 ordres par MAC dans le DO) ; `POST /api/box/ack` répond `ok` **sans rien enregistrer** |
| Identité box | « MAC » = `MK:` + 5 octets **dérivés de l'ANDROID_ID** (`device_identity.dart`), pas une MAC réseau ; affichée à l'écran, saisie par le revendeur |
| Paiements | Table `payments` présente ; **aucune intégration** (aucun appel Stripe/PayPal, aucun webhook dans le code) ; seuls les crédits revendeurs (`credit_ledger`) sont réels |
| Boîte noire | Journal local sur la box (`black_box.dart`) ; envoi au Worker et lecture panel = patch 1 (pas en production) |
| Tests | Worker : 7 bancs Node sur SQLite réel ; panel : 50 tests purs ; app : 486 tests Flutter |

## 2. Problèmes critiques trouvés

1. **Codes IPTV lisibles par la seule MAC.** `GET /api/device-source/:mac`
   (production) rend les identifiants fournisseur déchiffrés, sans
   authentification ni limite de débit. Vérifié en lecture seule sur la box
   de test le 5 octobre (sortie masquée). Le correctif (`device_guard.js`,
   secret d'appareil, commit 3f1c841) n'existe que sur la branche app,
   jamais déployé.
2. **Activation non idempotente.** Double clic, nouvel envoi après un délai
   dépassé, deux onglets : chaque requête réactive et redébite.
3. **Renouvellements concurrents perdus.** Deux renouvellements lisaient la
   même date de fin puis l'écrivaient : deux débits, un seul prolongement.
4. **Licence et journal de crédits écrits en requêtes séparées** : une
   panne entre les deux laissait une licence sans ligne de ledger.
5. **Audit sans état « avant » ni corrélation** pour l'activation ; remise
   à neuf et retrait de liste client non audités (patchs 3 et 5).
6. **Box : « effacer l'ancienne puis espérer ».** Les listes retirées par le
   panel étaient effacées avant d'importer la nouvelle ; un lien faux
   laissait le client sans rien.
7. **Accusé de réception fictif** (`/api/box/ack` n'enregistre rien) : le
   serveur ne sait pas quelle box a reçu quel ordre.
8. **Panel en production en retard** sur 5 patchs (boîte noire, envoi
   instantané, retrait liste client, activation qui remplace, remise à neuf).

## 3. Causes racines

- Deux lignes de code divergentes depuis le 24 septembre (production
  `claude/panel-mise-en-ligne`, app `ccr-…`) : les correctifs de sécurité
  de la ligne app ne sont jamais arrivés en production.
- D1 n'offre pas de transaction interactive : le code faisait lecture puis
  écriture sans condition. `batch()` (atomique) n'était utilisé que pour
  une partie des écritures.
- Pas de clé d'idempotence ni d'identifiant de corrélation dans le contrat
  panel → Worker.

## 4. Changements faits (patch 6 + box)

| Où | Changement | Preuve |
|---|---|---|
| Worker `api_v1.js` | `Idempotency-Key` sur `POST /api/v1/activate` : réponse gardée 24 h, rejeu identique (`Idempotent-Replayed: true`), même clé + autre corps → 409, clé en vol → 409 ; clé propre à l'acteur ; sans clé = comportement d'avant | `activation_idempotency.test.mjs` 20/20 |
| Worker `api_v1.js` | Renouvellement conditionnel (`WHERE id=? AND expires_at IS ?`), relecture et nouvel essai, sinon 409 `activation_conflict` | idem (prolongement à partir de la date précédente) |
| Worker `api_v1.js` | Dégel + débit + ledger dans **un** `batch()` D1 | idem (une licence, un débit, solde exact) |
| Worker `api_v1.js` | `X-Request-Id` accepté du panel ou généré, renvoyé dans la réponse, écrit dans `audit_logs.correlation_id` (colonne additive) | idem |
| Worker `api_v1.js` | Événement d'activation audité : état avant (statut, plan, fin), état après, acteur, appareil, client, `took_ms` mesuré, corrélation | idem |
| Worker `worker.js` | Audit de `device.reset` et `source.self_remove` | — |
| Worker `worker.js` | `GET /api/device-source/:mac` : 120 lectures / min / IP (mitigation, pas le correctif) | `reset_box_panel.test.mjs` 19/19 (121e → 429, autre IP → 200) |
| Panel | Clé d'idempotence sur les 3 écrans d'activation, gardée après coupure ou 5xx, jetée après réponse | `idempotency.test.ts` 3 tests ; 50/50 ; build OK |
| Panel | Menu regroupé : Centre de contrôle, Clients, Applications, Revendeurs, Contenu, Boîte noire, Système (aucune page renommée ni supprimée) | build OK |
| Box | Import d'abord, effacement ensuite ; si la nouvelle liste est refusée, l'ancienne reste (repli `zuno.source.drop_first_legacy`) | `keep_old_lists_test.dart` 5 ; suite 486 |

## 5. Migrations base

Toutes additives, sans verrou long, sans suppression :
- `audit_logs.correlation_id TEXT` (`ALTER TABLE … ADD COLUMN`, une fois par isolate).
- Table `idempotency_keys(k PK, actor_id, request_hash, status, body_json, created_at)`, purge > 24 h.
- `devices.reset_at INTEGER` (patch 5).
Retour arrière : colonnes et table ignorées par l'ancien code.

## 6. Latence d'activation

| Mesure | p50 | p95 | p99 | Où |
|---|---|---|---|---|
| Appel complet, sans clé (n=400) | 1,06 ms | 2,33 ms | 4,23 ms | Node + SQLite en mémoire (code seul) |
| Appel complet, avec clé (n=400) | 1,39 ms | 3,93 ms | 8,93 ms | idem |
| `took_ms` écrit dans l'audit | 0 ms | 1 ms | 1 ms | idem |
| **Production (D1 + réseau)** | `NON MESURÉ` | | | à lire dans `audit_logs.after_json.took_ms` après déploiement |

L'idempotence ajoute 3 requêtes D1 par activation (lecture, réservation,
réponse) : sur D1, chacune est un aller-retour. Coût réel `NON MESURÉ`.

## 7. Propagation des listes

Mesuré le 5 octobre (rapport `MESURE-ACTIVATION-INSTANTANEE.md`) : serveur →
Durable Object 193 ms, WebSocket 1,1 s. Aucune nouvelle mesure ce jour.

## 8. Sécurité

- Fait : idempotence (anti double débit), conditionnel sur renouvellement,
  limite de débit sur la lecture des codes, audit des actions destructives.
- Trouvé et **non corrigé ici** : lecture des codes par MAC seule (voir 2.1),
  accusé de réception fictif, JWT en `localStorage` (exposé à un XSS).

## 9. Boîte noire / observabilité

Identifiant de corrélation du panel jusqu'à l'audit ; latence serveur
d'activation écrite à chaque activation. La chaîne « audit → ordre DO →
réception box → accusé » n'est pas encore corrélée (accusé fictif).

## 10. Tests exécutés (6 octobre)

| Suite | Résultat |
|---|---|
| Worker `activation_idempotency` (nouveau) | 20 / 20 |
| Worker `activation_m3u` | 95 / 95 |
| Worker `blackbox` | 34 / 34 |
| Worker `box_channel` | 8 / 8 |
| Worker `reset_box_panel` | 19 / 19 |
| Worker `self_source_panel` | 13 / 13 |
| Worker `linkage_sim` | 12 / 13 — échec **préexistant**, identique sur la production sans patch |
| Panel `npm test` | 50 / 50 ; `npm run build` OK (TypeScript 5.9.3) |
| App `flutter test` | 486 réussis, 2 ignorés ; `flutter analyze` sans erreur |

Limite : le banc Node exécute les requêtes l'une après l'autre ; la course
réelle de deux requêtes simultanées n'y est pas reproductible. La branche
« clé en vol » est prouvée en posant l'état intermédiaire.

## 11. Fichiers modifiés

Patch 6 `docs/patches/panel-activation-idempotente-et-securite.patch` :
`cloudflare/api_v1.js`, `cloudflare/worker.js`,
`cloudflare/activation_idempotency.test.mjs` (nouveau),
`cloudflare/reset_box_panel.test.mjs`, `admin-panel/src/lib/api.ts`,
`admin-panel/src/lib/idempotency.ts` (+ test, nouveaux),
`admin-panel/src/pages/{Activate,RemoteActivate,Devices}Page.tsx`,
`admin-panel/src/components/Sidebar.tsx`, `admin-panel/src/lib/i18n.tsx`,
`admin-panel/package.json`. Box : `remote_source_repository.dart`,
`repair_flags.dart`, `keep_old_lists_test.dart`, `repair_flags_test.dart`.

## 12. Risques restants

1. Codes IPTV lisibles par MAC (critique tant que `device_guard` n'est pas en production).
2. Six patchs non déployés : la production n'a aucune de ces protections.
3. `linkage_sim` rouge sur la production (attend `live-sync.ts`, absent).
4. Pas de migrations versionnées : le schéma réel de D1 n'est connu que par le code.
5. Ce qui n'a **pas** été fait (demandé par la mission) : centre paiements
   (aucune intégration n'existe), liaison par clé Android Keystore,
   moteur d'incidents et alertes, cycle de vie des publicités, santé
   système mesurée, recherche globale, drapeaux de déploiement par
   pourcentage, révisions versionnées des listes avec retour arrière,
   fiche client unifiée, refonte mobile du panel.

## 13. Dépend d'éléments externes

- Déploiement : `deploy-panel-cloudflare.yml` avec `confirme=DEPLOYER` (propriétaire).
- Paiements : compte et secrets du prestataire (aucun aujourd'hui).
- Play Integrity : projet Google Cloud et application sur le Play Store.
- Mesure p50/p95/p99 en production : déploiement préalable.

## 14. Priorité suivante exacte

Porter `cloudflare/device_guard.js` (commit 3f1c841) sur
`claude/panel-mise-en-ligne` : secret d'appareil exigé sur
`/api/device-source/:mac` dès qu'une box est enrôlée, lecture par MAC seule
gardée pour les box jamais enrôlées (v106), route `POST /api/device-proof`.
Mesure de succès : `curl` sans en-tête sur la MAC d'une box enrôlée →
401 ; la box de test continue de recevoir ses listes.
