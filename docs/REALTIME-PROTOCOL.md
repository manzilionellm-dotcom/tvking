# Protocole temps réel 7 MOTION — app ↔ backend ↔ panel

**Objectif :** qu'une action faite dans le panel (gel, activation, playlist
poussée, message…) atteigne l'appareil **en moins d'une seconde** quand il est
en ligne — au lieu des ~30 minutes du polling actuel. Et que le panel voie
**en direct** qui est connecté, ce qui est regardé, et la confirmation que
chaque action a bien été appliquée.

Le polling existant (heartbeat 6 h, sync sources 5 min, polls d'écran)
**reste en place tel quel** : c'est le filet de sécurité. Le temps réel est
une couche *en plus*, jamais *à la place*. Tout est fail-open : si le
WebSocket est indisponible, l'app et le panel se comportent exactement comme
avant.

---

## 1. Infrastructure

- **Durable Object `RealtimeHub`** (fichier `cloudflare/realtime.js`),
  instance unique `idFromName('hub-v1')`, exportée par `worker.js`,
  binding `env.RT_HUB` (wrangler.toml, migration `new_sqlite_classes`).
- Utilise l'**API WebSocket Hibernation** (`state.acceptWebSocket`,
  `webSocketMessage`, `webSocketClose`, attachments sérialisés) pour un coût
  quasi nul au repos. `state.setWebSocketAutoResponse('ping' → 'pong')`
  répond aux pings clients sans réveiller l'objet.
- Chaque socket porte un attachment `{kind: 'device'|'admin', mac?, meta}`.
  Après hibernation, l'état se reconstruit via `state.getWebSockets()` +
  attachments (aucune Map mémoire obligatoire).
- Si `env.RT_HUB` est absent (binding pas encore déployé), les routes rt
  répondent `503 {error:'rt_unavailable'}` et **rien d'autre ne casse**.

## 2. Endpoints WebSocket

### Appareil (public, même niveau de confiance que /api/heartbeat)
```
GET /api/rt/device?mac=MK%3AXX%3AXX%3AXX%3AXX%3AXX&platform=mobile|tv&v=<appVersion>&b=<appBuild>&model=<model>
Upgrade: websocket
```
- MAC validé contre `MAC_RX` (format `MK:..`), upper-case, `%3A` décodé.
- Le Worker capte `CF-Connecting-IP` et `CF-IPCountry` et les transmet au hub
  (headers internes `X-RT-IP`, `X-RT-Country`) — même logique que heartbeat.
- Rate-limit : bucket `rt` (30 connexions / 5 min / IP).
- Une nouvelle connexion pour un MAC déjà connecté **remplace** l'ancienne
  (l'ancienne reçoit `{"type":"bye","reason":"replaced"}` puis close).

### Panel (admin/revendeur, JWT existant)
```
GET /api/v1/rt/ws?token=<JWT>
Upgrade: websocket
```
- Le token est vérifié avec `verifyJwt` (même secret HS256) AVANT l'upgrade.
  Les navigateurs ne peuvent pas mettre de header sur un WebSocket → query.
- Rôles admin (`super_admin|admin|support`) : voient tout.
- Revendeurs : v1 = **non connectés au WS** (le panel n'ouvre le socket que
  pour les rôles admin ; le serveur refuse `actor='reseller'` avec 403).

## 3. Messages — JSON, un objet par frame, champ `type` obligatoire

### Appareil → Hub
| type | payload | quand |
|---|---|---|
| `hello` | `{mac, platform, appVersion, appBuild, model, channel}` | 1re frame après connexion |
| `watching` | `{channel}` (`""` = rien) | à chaque changement de chaîne + toutes les 60 s |
| `ack` | `{id, ok, error?}` | après application d'un `sync`/`message` reçu avec `id` |
| `ping` | (frame texte littérale `ping`) | toutes les 45 s (keepalive NAT) |

### Hub → Appareil
| type | payload | effet côté app |
|---|---|---|
| `sync` | `{what: 'status'\|'sources'\|'config'\|'all', id?}` | relancer les fetchs HTTP existants correspondants, puis `ack` |
| `message` | `{id, title, body, kind: 'info'\|'success'\|'warning', durationSec?}` | bannière in-app immédiate, puis `ack` |
| `bye` | `{reason}` | ne PAS reconnecter immédiatement (attendre backoff max) |

Mapping `sync.what` → actions app :
- `status` → `SubscriptionState.instance.syncWithBackend()`
- `sources` → `RemoteSourceRepository.instance.sync()`
- `config` → re-fetch thème / annonce / pricing / home-layout / featured / ad / force-update
- `all` → les trois.

### Panel → Hub
| type | payload |
|---|---|
| `cmd` | `{id, mac, action: 'sync'\|'message', payload}` — ex. message direct à un appareil |
| `ping` | keepalive |

### Hub → Panel
| type | payload |
|---|---|
| `snapshot` | `{devices: [{mac, platform, country, channel, appVersion, model, connectedAt, lastSeen}]}` — envoyé à la connexion |
| `device_online` | `{device}` (même forme que dans snapshot) |
| `device_offline` | `{mac, at}` |
| `watching` | `{mac, channel}` |
| `ack` | `{id, mac, ok, latencyMs}` — l'appareil a appliqué la commande `id` |
| `changed` | `{scope, mac?}` — une mutation panel a eu lieu (autre onglet/admin) ; le panel rafraîchit la page concernée |

## 4. Publication interne (Worker → Hub)

Les handlers de mutation (api_v1.js et worker.js legacy) appellent après
succès :

```js
// realtime.js exporte :
publishRt(env, { targets, event })
// targets: 'admins' | 'all-devices' | ['MK:...']  (macs)
// event:   objet type sync/message/changed ci-dessus
// Retour : { delivered: <nb de sockets appareil touchés>, id: <event id> }
// TOUJOURS fail-open : try/catch, jamais d'erreur remontée au client HTTP.
```

Le hub expose en interne `POST /publish` (joignable uniquement via le binding
RT_HUB — pas d'auth supplémentaire nécessaire).

**Contrat de réponse HTTP enrichi** : les mutations api_v1 qui visent UN mac
ajoutent à leur réponse JSON existante un champ :
```json
"rt": { "delivered": 1, "id": "evt_ab12cd" }
```
`delivered ≥ 1` → le panel affiche « Appliqué sur l'appareil ✓ » dès réception
du `ack` correspondant ; `delivered: 0` → « Appareil hors ligne — sera
appliqué à sa prochaine connexion ».

### Points de branchement (mutation → publication)
| Mutation | Publication |
|---|---|
| `POST /api/v1/activate` | mac → `sync all` + admins `changed{scope:'licenses',mac}` |
| `PUT/DELETE /api/v1/sources/:mac` | mac → `sync sources` + admins `changed` |
| `PATCH /api/v1/devices/:id` (block/unblock), `DELETE` | mac → `sync status` + admins `changed` |
| `POST /api/v1/licenses` / `.../renew` / `PATCH` | mac (lookup) → `sync status` + admins `changed` |
| `POST /api/v1/transfer` | les 2 macs → `sync all` + admins `changed` |
| `POST /api/v1/grant-trial-all` | `all-devices` → `sync status` |
| annonces, thème, home-layout, featured, ad, pricing, force-update, feedback-prompt, servers | `all-devices` → `sync config` + admins `changed` |
| legacy `POST /admin/clients/:mac/action` (worker.js) | mac → `sync status` |

## 5. Présence D1 (compat descendante)

Le hub met à jour la table `presence` existante (best effort, throttlé ≥30 s
par mac) sur `hello`, `watching` et déconnexion — ainsi `/api/v1/online`,
`/api/trending` et le panneau legacy restent exacts même sans WS côté panel.

## 6. Côté app Flutter

`lib/core/realtime/realtime_sync_service.dart` — singleton `ChangeNotifier`,
**aucune nouvelle dépendance** (WebSocket de `dart:io`).
- Démarré dans le bootstrap de `main.dart` et `main_tv.dart` (les autres
  entrypoints : optionnel, garde try/catch).
- Reconnexion : backoff 5 s → 10 → 30 → 60 → 120 (plafond), jitter ±20 %,
  reset après 60 s de connexion stable. Sur `bye{replaced}` : backoff max.
- Hook `AppLifecycleState.resumed` → reconnexion immédiate + `syncWithBackend()`
  (comble le trou actuel : aucun re-check au retour au premier plan).
- Messages admin : exposés via le service ; l'UI (entry widget) affiche une
  bannière discrète, auto-dismiss `durationSec` (défaut 15 s), focusable D-pad.
- Interdits : `print()` (→ `debugPrint`), couleurs en dur, URL en dur
  (réutilise `BackendHosts.current`, bascule `https`→`wss`).

## 7. Côté panel React

`admin-panel/src/lib/realtime.ts` — client WS + mini pub/sub :
- Connexion après login (rôles admin uniquement), reconnexion backoff, token
  relu via `getToken()` à chaque tentative.
- API : `rtConnect()/rtDisconnect()`, `onRt(type, handler)`, hooks
  `useRtEvent(type, handler)`, `useRtStatus()` (connected/offline),
  `useLiveDevices()` (snapshot + deltas).
- Pages branchées : Online (live, plus de setInterval quand WS ok — le
  polling 30 s reste en fallback), Devices (pastille en ligne + acks),
  Dashboard (compteur en ligne live + insights), History (refresh sur
  `changed{scope:'audit'}` — optionnel).
- Indicateur global d'état WS dans la sidebar (● Direct / ○ Différé).

## 8. Sécurité

- Aucun secret nouveau. JWT admin réutilisé (query param — accepté car le
  token est déjà porteur, TLS de bout en bout, et expirera).
- Le socket appareil n'expose RIEN de sensible : il ne transporte que des
  ordres « va re-fetcher », jamais de credentials de playlist.
- Validation MAC systématique, rate-limit connexions, taille max frame 8 Ko,
  frames non-JSON ignorées silencieusement.
