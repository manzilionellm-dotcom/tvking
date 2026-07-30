# Edge proxy — déduplication de flux et cache local

Service Node autonome (`server/edge/`) placé entre les clients du réseau local
(TV, téléphones, écrans de test) et l'origine média distante.

Il tient quatre promesses :

1. **Une connexion montante par slot de compte maître.** Quel que soit le nombre
   de lecteurs simultanés, le fournisseur ne voit qu'**une** connexion à la fois
   par ligne d'abonnement (défaut : 1).
2. **Bascule de chaîne sans coupure.** Demander une autre chaîne pendant que le
   slot est pris échange la montée : le flux quitté rend son slot mais **garde
   ses clients connectés** sur le tampon local, et se remet en file pour revenir.
3. **Zapping gratuit.** Revenir sur un flux encore en cache ne rouvre rien : pas
   de nouvelle poignée de main TCP/TLS, pas de renégociation.
4. **Aucune métadonnée client ne sort.** Toutes les requêtes montantes d'un
   compte sont l'*empreinte d'un seul appareil maître*, identique au bit près.

## Architecture

```
   TV ─┐                                    ┌─ SlotPool (1 slot / compte maître)
   TV ─┼─▶ server.ts ─▶ EdgeProxy ─▶ StreamHub ─▶ RingBuffer ─▶ Broadcaster ─┐
   TV ─┘   (HTTP LAN)   (routeur)    (hub.ts)     (cache)       (fan-out)     │
            ▲               │            │                                    │
            │               │            └── UNE connexion ──▶ origine (WAN)  │
            │           admin.ts                                              │
            │        (API + tableau                                           │
            │          de bord, SSE)                                          │
            └── token bucket (CBR) ◀──────────────────────────────────────────┘
```

| Fichier | Rôle |
| --- | --- |
| `sync.ts` | `Mutex`, `Semaphore`, `Deferred` — ferme les fenêtres de course autour des `await` |
| `singleflight.ts` | N appels concurrents sur une même clé → 1 exécution |
| `ring-buffer.ts` | Cache circulaire borné (octets **et** chunks), stockage par référence |
| `broadcast.ts` | Diffusion pub/sub asynchrone, file bornée par abonné, politique *drop-oldest* |
| `token-bucket.ts` | Lissage d'égress (quasi-CBR) + découpage en vues sans copie |
| `sanitize.ts` | Frontière de vie privée + **empreintes d'appareil maître** |
| `origin.ts` | Transport HTTP + compteur de connexions montantes actives |
| `m3u.ts` | Analyseur M3U étendu (la ligne d'abonnement maître) |
| `accounts.ts` | Comptes maîtres : catalogue, signature, budget de connexions |
| `slots.ts` | Allocation de slots virtuels : bascule, éviction LRU, file d'attente |
| `hub.ts` | Machine à états d'un flux : slot, ouverture, pompe, **bascule**, linger, reconnexion |
| `edge.ts` | Routeur : comptes, slots, flux, sessions, métriques |
| `admin.ts` / `dashboard.ts` | API d'administration (jeton) + tableau de bord temps réel |
| `server.ts` | Façade HTTP LAN (flux, `/healthz`, `/metrics`) |
| `config.ts` / `main.ts` | Configuration par variables d'environnement + point d'entrée |

## Les garanties, et comment elles tiennent

### 1. Une seule montée (`hub.ts`, `edge.ts`)

Node est mono-thread, mais **pas** exempt de courses : chaque `await` est un
point de reprise. Entre « la connexion est-elle ouverte ? » et « ouvre-la »,
il y a l'acquisition du slot, le TCP, le TLS et les en-têtes de réponse — c'est
exactement là qu'un proxy naïf ouvre une deuxième connexion. Le cycle de vie du
hub est donc protégé par un `Mutex`, pas par un booléen.

Deux niveaux :

- **par chaîne** : `StreamHub` sérialise ses `join()` ; le premier ouvre, les
  autres s'abonnent au même tampon ;
- **par compte maître** : un `SlotPool` plafonne les connexions simultanées au
  budget du fournisseur (défaut **1**). Plafond atteint → voir la bascule
  ci-dessous ; si rien ne peut être libéré, la réponse est un `503` honnête —
  jamais une deuxième connexion silencieuse.

Le compteur qui fait foi (`countingTransport`) s'incrémente **à l'appel** de
`open()`, pas à sa résolution : c'est la seule façon de détecter deux
connexions qui s'établissent en parallèle.

### 2. Bascule dynamique de chaîne (`slots.ts`, `hub.ts`)

Un client demande une chaîne alors que le slot du compte est pris. Trois
politiques (`contention`) :

| Politique | Comportement |
| --- | --- |
| `swap` (défaut) | Le pool réclame le slot au détenteur le moins précieux |
| `wait` | Mise en file, `503` à l'expiration |
| `reject` | `503` immédiat — le spectateur en cours n'est jamais dérangé |

Ordre d'éviction : d'abord les flux que **personne ne regarde** (personne ne le
remarque), puis le moins récemment sollicité, puis le moins regardé.

Un flux évincé qui a encore des spectateurs ne s'arrête pas : il **passe en
`starved`**. Sa montée se ferme, son slot repart, mais son `Broadcaster`, son
cache et **toutes ses sockets clientes restent en place**. Les clients continuent
sur le tampon (c'est à cela que sert `EDGE_CLIENT_QUEUE_BYTES` : au débit
d'égress, il dit combien de temps la lecture survit à une bascule), pendant que
le flux se remet en file — **sans droit de bascule**, sinon deux chaînes
peuplées se chasseraient l'une l'autre indéfiniment. Le slot libéré revient, il
rouvre sa montée et reprend la diffusion dans le même `Broadcaster` : le client
n'a jamais été déconnecté. Passé `EDGE_STARVE_GRACE_MS` sans slot, ses clients
sont terminés proprement — mieux qu'une socket qui reste muette pour toujours.

Deux détails qui font la différence entre « ça a l'air de marcher » et « le
fournisseur ne voit jamais deux connexions » :

- le permis libéré est **remis au demandeur**, pas rendu au pot commun (le flux
  qui s'efface se replacerait sinon en tête et reprendrait son propre slot) ;
- le slot n'est rendu qu'après fermeture **effective** de la socket, plus un
  délai de décantation (`EDGE_SWAP_SETTLE_MS`, 100 ms) : fermer une socket
  localement n'est pas la même chose que l'origine la voyant fermée, et sans ce
  délai le fournisseur peut compter deux connexions le temps d'un aller-retour.

### 3. Cache circulaire et diffusion sans copie (`ring-buffer.ts`, `broadcast.ts`)

Les chunks sont stockés **par référence** et remis **par référence** : diffuser
un flux à 200 clients coûte un tampon, pas 200. Les octets sont donc partagés et
doivent être traités comme lecture seule.

Un client qui joint reçoit d'abord la queue du cache (`backlogBytes`) : l'image
démarre tout de suite, sans rien redemander à l'origine. Un client lent voit ses
plus vieux octets tomber (*drop-oldest*, comme `tokio::sync::broadcast`) plutôt
que de faire enfler la mémoire ou de ralentir les autres ; les pertes sont
comptées, jamais silencieuses.

### 4. Vie privée et empreinte maître (`sanitize.ts`)

La requête montante n'est pas *filtrée*, elle est **construite** à partir de
l'empreinte d'appareil du compte (`edge`, `vlc`, `kodi`, `tivimate`,
`exoplayer`). `StreamHub` ne reçoit d'ailleurs jamais les en-têtes du client : la
frontière est structurelle, pas déclarative — un futur en-tête de tracking ne
peut pas fuir par oubli. Avant chaque ouverture, `assertMirrorsMasterSignature`
vérifie que la requête est **exactement** la signature du compte : ni champ en
plus, ni valeur différente. Deux spectateurs produisent donc la même requête au
bit près — rien à corréler, rien à compter côté origine.

Ce que l'origine voit, à l'octet près (épinglé par le test e2e) :

```
host, connection, user-agent, accept, accept-encoding, accept-language,
sec-fetch-mode, pragma, cache-control, via
```

Toutes ces valeurs sont des constantes du proxy : deux spectateurs différents
produisent la même requête montante. Sont supprimés : `X-Forwarded-For`,
`Forwarded`, `X-Real-IP` et variantes CDN, `User-Agent` client, hints
`Sec-CH-UA-*`, `Cookie`, `Referer`, `Authorization` du client, `Accept-Language`,
`DNT`, `traceparent`/`baggage` et autres identifiants de corrélation.

Notes normatives : les en-têtes bond-à-bond et ceux nommés par `Connection` sont
retirés dans les deux sens (RFC 9110 §7.6.1) ; le proxy s'annonce par `Via`
(RFC 9110 §7.6.3) et **n'ajoute délibérément pas** `Forwarded` (RFC 7239), dont
l'objet est précisément de révéler la chaîne cliente. Dans l'autre sens, les
`Set-Cookie` et empreintes de l'origine ne redescendent pas vers le LAN.

Les journaux suivent la même règle : aucun IP client, aucun `User-Agent`, et les
URL d'origine sont rédigées (`redactUrl`) car elles portent souvent un jeton
d'abonnement.

### 5. Lissage d'égress (`token-bucket.ts`)

Le WAN livre par rafales ; retransmises telles quelles à N clients, elles
saturent le lien et font trembler la lecture. Chaque client est servi à travers
un *token bucket* : `EDGE_EGRESS_BPS` en débit soutenu, profondeur = 100 ms de
débit par défaut (donc quasi-CBR). Les écritures trop grosses sont redécoupées
en `subarray` — toujours sans copie.

## Démarrer

```bash
EDGE_ACCOUNTS='[{"id":"master","label":"Ligne principale",
  "playlistUrl":"https://fournisseur.example/get.php?username=…&type=m3u_plus",
  "maxConnections":1,"device":"vlc"}]' \
EDGE_ADMIN_TOKEN='un-jeton-long-et-aleatoire' \
EDGE_HOST=0.0.0.0 EDGE_PORT=8787 \
npm run edge
```

Le lecteur pointe alors sur `http://<edge>:8787/edge/<compte>/<chaîne>` (un
identifiant seul vise le compte `default`), et le tableau de bord est sur
`http://<edge>:8787/admin/`.

La forme mono-origine reste disponible (`EDGE_STREAM_MAP` ou
`EDGE_ORIGIN_TEMPLATE`) : elle crée le compte `default`.

| Variable | Défaut | Effet |
| --- | --- | --- |
| `EDGE_ACCOUNTS` | — | JSON des comptes maîtres (voir ci-dessous) |
| `EDGE_ADMIN_TOKEN` | — | Jeton d'administration ; **vide = plan d'admin désactivé** |
| `EDGE_ADMIN_PREFIX` | `/admin` | Préfixe du plan d'administration |
| `EDGE_CONTENTION` | `swap` | `swap`, `wait` ou `reject` pour le compte `default` |
| `EDGE_STARVE_GRACE_MS` | `30000` | Survie d'un flux basculé avant fin de ses clients |
| `EDGE_SWAP_SETTLE_MS` | `100` | Décantation entre fermeture et réouverture d'une montée |
| `EDGE_STREAM_MAP` | — | JSON `{"id":"url"}` ; un id absent → 404 (jamais d'URL devinée) |
| `EDGE_ORIGIN_TEMPLATE` | — | Gabarit avec `{id}` (alternative à la table) |
| `EDGE_ALLOWED_HOSTS` | — | Liste blanche d'hôtes d'origine (garde-fou SSRF) |
| `EDGE_HOST` / `EDGE_PORT` | `127.0.0.1` / `8787` | Écoute LAN — l'exposition est un choix explicite |
| `EDGE_MAX_UPSTREAM` | `1` | Plafond global de connexions montantes |
| `EDGE_SLOT_WAIT_MS` | `10000` | Attente d'un slot avant `503` |
| `EDGE_RING_BYTES` / `EDGE_RING_CHUNKS` | `16 Mio` / `4096` | Taille du cache |
| `EDGE_BACKLOG_BYTES` | `512 Kio` | Rejeu offert à un client qui joint |
| `EDGE_CLIENT_QUEUE_BYTES` | `4 Mio` | File par client avant *drop-oldest* |
| `EDGE_LINGER_MS` | `15000` | Fenêtre de zapping (montée gardée sans spectateur) |
| `EDGE_EGRESS_BPS` | `3 Mio/s` | Débit d'égress par client |
| `EDGE_MAX_CLIENTS` | `200` | Garde-fou mémoire |
| `EDGE_USER_AGENT` / `EDGE_VIA` | `tvking-edge/1.0` | Identité présentée à l'origine |
| `EDGE_UPSTREAM_HEADERS` | — | JSON d'en-têtes statiques (identifiants **du proxy**) |
| `EDGE_RECONNECT_*` | `5` / `250 ms` / `5000 ms` | Politique de reconnexion |

Champs d'un compte : `id`, `label`, `playlistUrl` **ou** `channels` **ou**
`channelTemplate`, `maxConnections` (défaut 1), `device`
(`edge`/`vlc`/`kodi`/`tivimate`/`exoplayer`), `headers` (identifiants **du
proxy**), `contention`, `playlistTtlMs`.

### Endpoints

Plan de données : `GET /edge/<compte>/<chaîne>`, `GET /healthz`, `GET /metrics`.

Plan d'administration (jeton `Authorization: Bearer …` ou `X-Admin-Token`) :

| Route | Effet |
| --- | --- |
| `GET /admin/` | Tableau de bord (page inerte, sans données) |
| `GET /admin/overview` | Instantané complet : montées, comptes, flux, sessions, efficacité |
| `GET /admin/events` | Flux SSE : activité temps réel + instantané périodique |
| `GET /admin/accounts` | Comptes maîtres (jamais les valeurs des identifiants) |
| `POST /admin/accounts` | Ajout / mise à jour d'un compte |
| `DELETE /admin/accounts/:id` | Suppression + arrêt de ses flux |
| `GET /admin/accounts/:id/channels` | Catalogue M3U (`?refresh=1` pour forcer) |
| `GET /admin/sessions` | Sessions clientes (identifiants opaques) |
| `POST /admin/streams/:clé/stop` | Coupe un flux |

Le tableau de bord affiche les montées actives (et le maximum jamais atteint,
qui doit rester ≤ au budget), les clients connectés et leur chaîne, les bascules,
et l'efficacité de déduplication (requêtes servies par montée, octets LAN vs
WAN). Les sessions y sont des identifiants opaques : **le tableau de bord ne peut
pas montrer ce que le proxy refuse de collecter** — ni IP, ni User-Agent.

## Vérification

`npm test` — 161 tests dédiés, dont :

- `hub.test.ts` : 150 clients simultanés → **1** ouverture ; churn aléatoire de
  200 tâches join/leave → `activeMax === 1` ; linger, reconnexion, échecs ;
- `edge.test.ts` : 200 clients sur un flux ; 150 joins concurrents sur 6 chaînes
  avec un seul slot → `activeMax === 1`, le surplus est refusé, pas empilé ;
- `swap.test.ts` : la bascule — socket cliente conservée, reprise automatique,
  fin honnête après la grâce, 60 clients zappant sur 6 chaînes avec **un** slot
  et **zéro** déconnexion ;
- `slots.test.ts` : arbitrage isolé, dont le cas « le flux qui s'efface ne
  reprend pas son propre permis » ;
- `accounts.test.ts` / `m3u.test.ts` : catalogue M3U, cache TTL, single-flight,
  rafraîchissement en échec qui garde la dernière bonne version ;
- `admin.test.ts` : authentification, gestion des comptes, SSE, et l'absence de
  toute donnée personnelle dans les réponses ;
- `proxy-e2e.test.ts` : sockets réelles — 120 clients HTTP, origine `node:http`
  qui compte **elle-même** ses requêtes et ses connexions, vérifie qu'aucune
  valeur envoyée par les clients n'apparaît dans la requête montante, et qu'à
  chaque requête reçue l'origine n'avait **qu'une seule** socket ouverte, y
  compris pendant une bascule de chaîne.

L'invariant est toujours mesuré à la frontière du transport (ce que l'origine
pourrait observer), jamais sur un drapeau interne au proxy.

## Limites assumées

- **Un seul processus.** L'invariant est garanti *par processus* : c'est
  pourquoi le service est un démon autonome et non un route handler Next.js —
  en serverless, chaque instance ouvrirait sa propre montée.
- **Flux continu** (MPEG-TS, progressif). La collapse d'une playlist HLS
  (manifeste court-TTL + segments) n'est pas implémentée ; pointer l'edge sur
  l'endpoint de flux continu, ou étendre `hub.ts` pour le cas segmenté.
- **Pas de TLS ni d'authentification côté LAN.** Le service détient les
  identifiants d'origine : le laisser sur `127.0.0.1` ou derrière un reverse
  proxy du réseau de confiance.
- **Le cache est vidé à l'arrêt d'un flux** : rejouer du direct vieux de
  plusieurs secondes serait pire qu'un démarrage propre. (Il est **conservé**
  pendant une bascule — c'est là tout l'intérêt.)
- **Une chaîne basculée ne re-bascule pas d'elle-même** : elle attend son tour.
  Avec un seul slot et deux chaînes regardées en permanence, la seconde finit
  par atteindre `EDGE_STARVE_GRACE_MS` et ses clients sont terminés proprement.
- **Le plan d'administration n'a pas de gestion d'utilisateurs** : un seul jeton
  partagé, pas de rôles, pas de journal d'audit.
