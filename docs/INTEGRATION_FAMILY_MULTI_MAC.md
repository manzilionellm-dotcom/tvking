# Intégration — ligne M3U unique (multi-MAC)

Option **additive** du panel admin + Worker Cloudflare + **branche mince
Gateway**. Toggle **OFF** (défaut) = comportement actuel, **zéro régression**.

Aucun fichier sous `lib/` (apps mobile/TV) n’est touché.

## Problème (max_connections = 1)

Si le M3U servi contient encore `http://fournisseur/live/user/pass/id.ts`,
chaque appareil ouvre sa propre connexion amont. Avec `max_connections=1`,
un seul écran joue.

**Correctif :** toggle ON → toutes les URLs média sont réécrites vers
**notre** proxy. Le hub (Worker `sharedUpstreamFetch` **ou** Gateway
`hub.subscribe`) n’ouvre **qu’une** session fournisseur par chaîne et
fan-out les octets aux N clients.

Constat terrain (ligne Xtream, max=1) : `player_api` OK depuis un
datacenter ; `get.php` souvent 884 ; `live/*.ts` OK en résidentiel, 511
depuis un DC. D’où : construire le M3U via `player_api` en priorité, et
préférer le **Gateway résidentiel** pour le TS (voir `GATEWAY_PUBLIC_BASE`).

Ce n’est **pas** un contournement de limite : une chaîne = une connexion
amont (comme `gateway/src/hub.js`). Des chaînes **différentes** saturent
toujours `PROVIDER_MAX_CONNECTIONS`.

## Ce que ça fait

- L’admin colle un CSV de MAC + allume le toggle sur la page Famille.
- Chaque MAC est activée via `handleFamilyAddMember` ; `device_sources`
  pointe vers `/api/m3u/{token}` (pas `get.php`).
- `GET /api/m3u/:token` :
  - **OFF** → `302` fournisseur (inchangé).
  - **ON**  → M3U généré, URLs sur **notre hôte**, tokens rafraîchis.
- `GET /api/m3u/:token/live/:id.ts` (mode Worker) : proxy fan-out.
- Mode Gateway : URLs `/live/{token}/{token}/{id}.ts` → `handleLive` +
  `hub.subscribe` (déjà là).

## Fichiers

| Fichier | Rôle |
|---|---|
| `cloudflare/migrations/011_family_multi_mac.sql` | `multi_mac_enabled` DEFAULT 0, `multi_macs` |
| `cloudflare/family_multi_mac.js` | parse, enable, rewrite proxy, hub `sharedUpstreamFetch` |
| `cloudflare/api_v1.js` | `PUT /api/v1/families/:id/multi-mac` |
| `cloudflare/worker.js` | `/api/m3u/:token` + `/live|movie|series/:id` |
| `gateway/src/users.js` | `authenticate` accepte le jeton panel (32 hex) |
| `gateway/src/server.js` | `handlePlayerApi` : `max_connections` client ; `handleLive` inchangé (hub) |
| `admin-panel/src/pages/FamiliesPage.tsx` | textarea CSV + toggle |
| `admin-panel/src/lib/api.ts` | `familiesApi.enableMultiMac` |

## Où brancher (hooks) — carte exacte

```
Apps / MAG
    │  GET /api/m3u/{token}          (playlist, Worker)
    │  GET /api/m3u/{token}/live/id.ts   (média, Worker si pas de gateway)
    │  GET /live/{token}/{token}/id.ts   (média, Gateway)
    ▼
Worker handlePublicFamilyM3u          OFF → 302  |  ON → rewriteM3uThroughProxy
Worker handlePublicFamilyMedia        sharedUpstreamFetch (1 open / clé)
    │
    │  env.GATEWAY_PUBLIC_BASE ? URLs mode gateway
    ▼
Gateway server.js
    handlePlayerApi  ← callPlayerApi (creds LIGNE) + rewritePlayerApi
                       si user.panelFamily → max_connections = 12 (écrans)
    handleGetPhp     ← openGetPhp + makeM3URewriter(token, token)
    handleLive       ← hub.subscribe(streamKey, upstreamStreamPath)
                       1re TV : openStream(live/UPSTREAM_USER/PASS/id.ts)
                       TV suivantes même id : 0 connexion amont en plus
```

### 1. Worker — branché

`cloudflare/worker.js` :

```js
// playlist
if (api/m3u && length === 3)
  return handlePublicFamilyM3u(env, token, request);
// média
if (api/m3u && live|movie|series && length === 5)
  return handlePublicFamilyMedia(env, token, kind, file, request);
```

`buildMultiMacM3u(..., { token, proxyBase, proxyMode })` :

- `proxyMode: 'worker'` si `GATEWAY_PUBLIC_BASE` vide →
  `https://<worker>/api/m3u/{token}/live/{id}.ts`
- `proxyMode: 'gateway'` si `env.GATEWAY_PUBLIC_BASE` est posé →
  `https://<gw>/live/{token}/{token}/{id}.ts`

### 2. Gateway — branche mince (branchée)

`gateway/src/users.js` → `authenticate` **après** l’échec users.json :

```js
if (isPanelFamilyToken(username, password)) {
  // username === password === token 32 hex (family_links)
  return { panelFamily: true, maxStreams: 100, familyId: '__panel_family__' };
}
```

Puis les handlers **existants** suffisent :

| Hook | Fichier | Ligne (approx.) | Rôle |
|---|---|---|---|
| `authenticate` | `users.js` | `isPanelFamilyToken` | jeton panel = user virtuel |
| `handlePlayerApi` | `server.js` | après `callPlayerApi` | `rewritePlayerApi` + `max_connections` si `panelFamily` |
| `handleGetPhp` | `server.js` | `makeM3URewriter(user.username, user.password)` | URLs → `/live/{token}/{token}/…` |
| `handleLive` | `server.js` | `hub.subscribe` | fan-out 1 amont → N clients |
| `openGetPhp` / `callPlayerApi` | `upstream.js` | creds `UPSTREAM_*` | **une** identité fournisseur |
| `makeM3URewriter` | `xtream.js` | déjà là | masque host + user/pass ligne |

`PROVIDER_MAX_CONNECTIONS=1` côté gateway : une 2ᵉ **chaîne distincte**
est refusée (503). N télés sur **la même** chaîne passent.

### 3. Variable Worker

```
GATEWAY_PUBLIC_BASE=https://tv.mondomaine.com
```

Sans cette var, le Worker proxifie lui-même le TS (peut être 511 si le
fournisseur bloque les datacenters — d’où le Gateway résidentiel).

## Migration D1

```bash
wrangler d1 execute tvking_licensing \
  --file=cloudflare/migrations/011_family_multi_mac.sql --remote
```

Runtime : `ensureFamilyMultiMac` (ALTER idempotent).

## Smoke

```bash
node cloudflare/family_multi_mac.smoke.mjs
# Gateway (réécriture + jeton panel) :
cd gateway && node --test test/unit.test.mjs
```

Contrats :

- OFF = pas d’intercept (302 conservé).
- ON = hôte des URLs média = notre proxy, **pas** l’hôte fournisseur.
- N `sharedUpstreamFetch` concurrents → `openFn` appelé **1** fois.

## Succès

- Toggle **OFF** : `GET /api/m3u/:token` reste un 302.
- Toggle **ON**, max_connections=1 : N MAC sur **la même** chaîne jouent
  (1 session amont). Pas de `live/user/pass` fournisseur dans le M3U.
- Aucun fichier sous `lib/` modifié.
