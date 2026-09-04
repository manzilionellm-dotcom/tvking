# Intégration — ligne M3U unique (multi-MAC)

Option **additive** du panel admin + Worker : N adresses MAC (10–12)
partagent **une seule** session amont chez le fournisseur. Toggle **OFF**
(défaut) = comportement actuel, **zéro régression**.

Aucun fichier sous `lib/` (apps mobile/TV) n’est touché.

## Ce que ça fait

- L’admin colle un CSV de MAC + allume le toggle sur la page Famille.
- Chaque MAC est activée via le chemin **existant**
  (`handleFamilyAddMember` → licence + `family_members`).
- La source poussée n’est **plus** le `get.php` Xtream en dur : c’est
  `https://<worker>/api/m3u/{token}` (M3U partagé).
- `GET /api/m3u/:token` :
  - **OFF** → `302` vers le fournisseur (inchangé).
  - **ON**  → le Worker fetch **une fois** le M3U amont (credentials
    `families.source_json`), le met en cache, rafraîchit les tokens
    signés expirés, et le sert aux N appareils.

Le serveur fournisseur ne voit qu’**un** client : le Worker.

## Fichiers

| Fichier | Rôle |
|---|---|
| `cloudflare/migrations/011_family_multi_mac.sql` | `families.multi_mac_enabled` (DEFAULT 0), `families.multi_macs` |
| `cloudflare/family_multi_mac.js` | helpers (parse, enable, build, refresh, intercept) |
| `cloudflare/api_v1.js` | `PUT /api/v1/families/:id/multi-mac` + overwrite source si toggle ON |
| `cloudflare/worker.js` | branche dans `handlePublicFamilyM3u` |
| `admin-panel/src/pages/FamiliesPage.tsx` | textarea CSV + toggle |
| `admin-panel/src/lib/api.ts` | `familiesApi.enableMultiMac` |

Les tables `families` / `family_members` / `family_links` sont **réutilisées**
(`ensureFamiliesTables`). Rien n’est réécrit.

## Où brancher (hooks)

### 1. Worker — déjà branché

Dans `cloudflare/worker.js`, près du match `GET /api/m3u/:token` :

```js
// handleRequest → segments [api, m3u, token]
return await handlePublicFamilyM3u(env, segments[2], request);
```

`handlePublicFamilyM3u` appelle `interceptFamilyProfile(request, fam)` :

- `intercept === false` → le `302` historique (Xtream `get.php` ou URL M3U).
- `intercept === true`  → `buildMultiMacM3u` (1 session amont).

Si les colonnes n’existent pas encore, le `SELECT` étendu échoue et on
retombe sur `SELECT source_json` seul = OFF = 302. Filet anti-régression.

### 2. API v1 — déjà branché

Dans `cloudflare/api_v1.js`, bloc `parts[0] === 'families'` :

```
PUT|POST /api/v1/families/:id/multi-mac
  body: { mac_csv, multi_mac_enabled }
  → handleFamilyEnableMultiMac → enableSharedM3uLine
```

`handleFamilyAddMember` (ajout unitaire) : si `fam.multi_mac_enabled === 1`,
overwrite `device_sources` vers `sharedM3uSource(origin, token)` **après**
l’activation existante. Fail-open : un plantage ici ne retire pas le membre.

### 3. Gateway `handlePlayerApi` — **pas branché** (volontaire)

`gateway/src/server.js` → `handlePlayerApi` (vers L.178) et le dispatch :

```js
if (path === '/player_api.php') return handlePlayerApi(url, res);
```

C’est le point d’ancrage **si** un jour les box MAG/STB frappent la
façade Xtream du gateway au lieu de `/api/m3u/:token`.

Hook envisagé (ne pas l’écrire tant que le besoin MAG n’est pas là) :

```js
// Au début de handlePlayerApi, après authenticate() :
// const decision = interceptFamilyProfile(req, familyRow);
// if (decision.intercept) { servir le M3U / user_info façade ; return; }
```

`interceptFamilyProfile` reconnaît déjà `…/player_api.php` quand le
toggle est ON. Le Worker **ne réécrit pas** le gateway (additif panel +
Worker seulement).

## Migration D1

Runtime : `ensureFamilyMultiMac` fait les `ALTER TABLE` à la volée
(idempotent, ignore « duplicate column »).

Manuelle (bases déjà déployées) :

```bash
wrangler d1 execute tvking_licensing \
  --file=cloudflare/migrations/011_family_multi_mac.sql --remote
```

Un 2ᵉ passage échoue « duplicate column » — sans gravité (SQLite).

## Contrat helpers

```
parseBulkMacs(macCsv) → { ok, macs[], errors[] }
enableSharedM3uLine(env, { familyId, macCsv, multiMacEnabled, origin, deps })
ensureFamilyLinkToken(env, familyId, genId) → token
handlePublicFamilyM3u(token) avec branche toggle
refreshUpstreamIfExpired(source_json, cache, now, fetchFn)
interceptFamilyProfile(request, familyRow)
```

`deps` injectés par `api_v1.js` : `{ upsertDeviceSource, activateMember, genId }`.
`activateMember` = wrapper de `handleFamilyAddMember` (chemin existant).

## Smoke

```bash
node cloudflare/family_multi_mac.smoke.mjs
```

Couvre : parse CSV, plafond 12, OFF = pas d’intercept, ON = source
`/api/m3u/{token}` (jamais `get.php`), refresh tokens, 2 lectures = 1 fetch.

## Succès

- Toggle **OFF** : `GET /api/m3u/:token` reste un 302 fournisseur.
- Toggle **ON** : N MAC, un seul fetch amont, tokens rafraîchis.
- Aucun fichier sous `lib/` modifié.
