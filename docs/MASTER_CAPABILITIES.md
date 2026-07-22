# Capacités du compte MAÎTRE / ADMIN — fiche de revue

> Référence **fidèle au code** (routes, handlers, garde-fous) pour évaluer si le
> périmètre est suffisant. Chaque ligne renvoie à un endpoint/fonction réel.
> Couches : **Panel** (Cloudflare Worker `cloudflare/api_v1.js` + `worker.js`),
> **App** (`lib/features/subscription/`), **Gateway** (`gateway/`).

---

## 0. Rôles & garde-fous

| Rôle | Où | Portée |
|---|---|---|
| `super_admin` (exploitant) | Panel `/api/v1/*` | **Toutes** les routes `masters/*` (403 sinon — `api_v1.js:1124`). |
| MAC « maître » | App + backend | Démo **illimitée** : envoi de tests sans quota ni paiement (`isMasterMac`, worker.js). |
| `ADMIN_TOKEN` | Gateway `/admin/*` `/metrics` | Gestion familles/clones + supervision (`gateway/src/server.js`). |

Un maître est identifié par sa **MAC** dans la table `app_masters` (D1).

---

## 1. Gestion des comptes maîtres — Panel (super_admin)

| Action | Méthode / Route | Handler |
|---|---|---|
| Lister les maîtres | `GET /api/v1/masters` | `handleMastersList` |
| Ajouter un maître | `POST /api/v1/masters` `{mac, note?}` | `handleMastersAdd` |
| Retirer un maître | `DELETE /api/v1/masters/:mac` | `handleMastersRemove` |

## 2. Copieur intelligent — Panel (super_admin)

| Action | Méthode / Route | Détail |
|---|---|---|
| Copier la ligne assignée | `GET /api/v1/masters/channels?mac=` | Lit `device_sources` du maître. |
| Copier un lien collé | `POST /api/v1/masters/channels` `{mac, paste, gateway_base?, gateway_user?, gateway_pass?}` | `paste` = lien Xtream (`get.php…`) ou URL M3U ; auto-détection (`autoDetectSource`). |

- Range **tout** en catégories ; plafond `_COPY_MAX_CHANNELS = 6000`, troncature
  **signalée** (`truncated`), jamais silencieuse.
- Si `gateway_base` (+ identité de diffusion) est fourni, les URLs de lecture
  sont bâties **sur la façade** avec l'**identité de diffusion** (pas les
  identifiants fournisseur).

## 3. Liste de test indépendante — Panel (super_admin)

| Action | Méthode / Route | Détail |
|---|---|---|
| Lire la liste curée | `GET /api/v1/masters/test-list?mac=` | Renvoie `m3u`, `count`, `gateway_base`, `gateway_user`, `has_gateway_pass`. Secret **jamais** réaffiché. |
| Enregistrer la liste | `PUT /api/v1/masters/test-list` `{mac, m3u, gateway_base?, gateway_user?, gateway_pass?}` | Valide la façade (`https://` + domaine, sinon 400 actionnable). Le secret n'est réécrit que s'il change. |

Édition côté panel (`MastersPage.tsx`, liste **ORDONNÉE**) : **réordonner**
(glisser + ▲/▼), **renommer**, **regrouper**, **supprimer**, **ajouter à la
main**. **L'ordre du M3U = l'ordre de lecture** (servi verbatim).

## 4. Diagnostic (boîte noire) — Panel + App

| Action | Route | Contrôles |
|---|---|---|
| Diag panel | `GET /api/v1/masters/diag?mac=` (`handleMasterDiag`) | maître ? · source ? · **façade https joignable** ? · **identité de diffusion** ? · liste servie ? · **1re chaîne réellement jouable** ? |
| Diag app | `GET /api/invite/diag/:mac` (`handleInviteDiag`) | idem, côté appareil. Vert = **lecture réelle** (plus de faux vert nip.io). |
| Faits bruts | `GET /api/invite/selftest/:mac` | maître ?, source (hôte/type), test actif ?, liste de test. |

## 5. Distribution de tests — App (console maître) & backend

| Action | Route | Règle maître |
|---|---|---|
| Suis-je maître ? | `GET /api/invite/master/:mac` | — |
| Créer un code | `POST /api/invite/create` `{mac, hours?, channel?, mode?}` | **Aucun quota, aucun paiement requis** (`handleInviteCreate`). |
| Activer un code | `POST /api/invite/redeem` `{mac, code}` | Maître : **re-testable** (pas de « 1 pass à vie »), pas de quota hebdo (`inviteRedeemDecision`). |
| Octroyer direct | `POST /api/invite/grant` `{mac, guest_mac, hours?, channel?, mode?}` | Assigne la liste de test au testeur (`copyMasterSourceForTest`). |
| Récupérer sa chaîne | `GET /api/invite/mine/:mac` | Côté testeur invité. |

**Durées maître** (`MASTER_ALLOWED_HOURS`, worker.js) — bien plus large qu'un
invité (5/24/48 h) :

| h | 1 | 5 | 24 | 48 | 720 | 1440 | 4320 | 8760 |
|---|---|---|---|---|---|---|---|---|
| = | 1 h | 5 h | 1 j | 2 j | 30 j | 60 j | 180 j | **1 an** |

Code valable **48 h** avant usage (`INVITE_CODE_TTL_MS`). **Coupure à l'échéance
automatique** (`guest_until`/`expires_at`, sans cron).

## 6. Prêt / transfert (hérité du Pass Partage)

| Action | Route | Détail |
|---|---|---|
| Transférer | `POST /api/invite/transfer` `{mac, target_mac}` | Entre mes appareils. |
| Prêter | `POST /api/invite/lend` `{mac, guest_mac, hours?}` | Prêt **24 h / 48 h** (`LOAN_ALLOWED_HOURS`). |
| Reprendre | `POST /api/invite/reclaim` `{mac}` | Le propriétaire récupère avant l'échéance. |
| État du prêt | `GET /api/invite/loan/:mac` · `/loan-status/:mac` | Se **rend tout seul** à l'échéance (`loanSettleDecision`). |

## 7. Gateway — familles / clones & supervision (ADMIN_TOKEN)

| Action | Route |
|---|---|
| Santé publique | `GET /health` |
| Métriques Prometheus | `GET /metrics` |
| Statut détaillé | `GET /admin/status` (hub, sessions, users, système CPU/RAM) |
| Recharger users à chaud | `GET /admin/reload-users` |
| Lister/créer une famille | `GET`/`POST /admin/families` |
| Supprimer une famille | `DELETE /admin/families/:id` |
| Ajouter un clone | `POST /admin/families/:id/users` |
| **Révoquer** un clone | `DELETE /admin/families/:id/users/:username` |

## 8. Service public (opaque)

| Action | Route |
|---|---|
| Servir la liste de test curée | `GET /api/master-list/:ref(.m3u)` (`handleMasterListServe`) |

La `ref` (`ml_…`) est un **hash non réversible** de la MAC maître : le testeur
et le fournisseur ne voient **jamais** la vraie MAC (`masterListRef`).

---

## Garanties (invariants)

1. **Indépendance fournisseur** : la petite liste curée sert **tous** les tests
   → chaînes partagées → le gateway **mutualise** (N testeurs d'une chaîne = **1**
   connexion amont) → le fournisseur ne voit **qu'une connexion**.
2. **Plafond ligne** : le gateway ne dépasse **jamais** `PROVIDER_MAX_CONNECTIONS`
   (503 propre au-delà — `hub.js`). Reconnexion + failover (`upstream.js`).
3. **Confidentialité** : MAC maître masquée (réf opaque) ; identifiants
   fournisseur **absents** du M3U servi quand l'identité de diffusion est réglée ;
   mot de passe **jamais** réaffiché.
4. **Séparation des stats** : les sessions maître/admin vont dans
   `admin_presence` → **jamais** comptées dans « En ligne » ni les stats clients.
5. **Joignabilité réelle** : façade = `https://` + domaine valide (Caddy +
   Let's Encrypt) → le diagnostic est **honnête** (vert = lecture réelle).

---

## Points à trancher par l'ingénieur (limites connues)

- **Révocation d'un test actif** : pas de bouton « couper ce test maintenant »
  côté console maître — la coupure se fait par **expiration automatique**. (La
  révocation existe pour les **clones gateway** via `DELETE /admin/families/...`.)
  → *À ajouter si un « kill switch » immédiat par testeur est requis.*
- **Copie M3U pure via façade** : `_rewriteOrigin` ne réécrit que l'origine ; le
  chemin garde les jetons de la playlist source. L'identité de diffusion
  s'applique au **chemin Xtream** (cas principal).
- **Tests panel** : `admin-panel/` n'a pas de runner JS (couverture par `tsc` +
  contrat « service verbatim » du worker). Logique pure worker/gateway testée
  (`gateway/test/*`, `cloudflare/*.smoke.mjs`).
- **Pagination des très grosses lignes** : plafond 6000 + troncature signalée,
  pas de lazy-load serveur incrémental.
