# Edge proxy — déduplication de flux et cache local

Service Node autonome (`server/edge/`) placé entre les clients du réseau local
(TV, téléphones, écrans de test) et l'origine média distante.

Il tient trois promesses :

1. **Une seule connexion montante.** Quel que soit le nombre de lecteurs
   simultanés, l'origine ne voit qu'**une** connexion à la fois.
2. **Zapping gratuit.** Changer de flux — ou y revenir — consomme le cache
   local : pas de nouvelle poignée de main TCP/TLS, pas de renégociation.
3. **Aucune métadonnée client ne sort.** L'origine ne voit que l'IP du proxy et
   des en-têtes constants, identiques pour tous les spectateurs.

## Architecture

```
   TV ─┐
   TV ─┼─▶ server.ts ──▶ EdgeProxy ──▶ StreamHub ──▶ RingBuffer ──▶ Broadcaster ─┐
   TV ─┘   (HTTP LAN)     (edge.ts)     (hub.ts)     (cache)        (fan-out)     │
            ▲                │              │                                     │
            │                │              └── UNE connexion ──▶ origine (WAN)   │
            └── token bucket (CBR) ◀─────────────────────────────────────────────┘
```

| Fichier | Rôle |
| --- | --- |
| `sync.ts` | `Mutex`, `Semaphore`, `Deferred` — ferme les fenêtres de course autour des `await` |
| `singleflight.ts` | N appels concurrents sur une même clé → 1 exécution |
| `ring-buffer.ts` | Cache circulaire borné (octets **et** chunks), stockage par référence |
| `broadcast.ts` | Diffusion pub/sub asynchrone, file bornée par abonné, politique *drop-oldest* |
| `token-bucket.ts` | Lissage d'égress (quasi-CBR) + découpage en vues sans copie |
| `sanitize.ts` | Frontière de vie privée : les en-têtes montants sont **construits**, jamais transférés |
| `origin.ts` | Transport HTTP + compteur de connexions montantes actives |
| `hub.ts` | Machine à états d'un flux : slot, ouverture, pompe, linger, reconnexion |
| `edge.ts` | Registre des flux + plafond global de connexions montantes |
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

- **par flux** : `StreamHub` sérialise ses `join()` ; le premier ouvre, les
  autres s'abonnent au même tampon ;
- **global** : un `Semaphore` plafonne le total à `EDGE_MAX_UPSTREAM`
  (défaut **1**). Plafond atteint → on libère d'abord les flux que plus personne
  ne regarde (éviction LRU des hubs en linger), et seulement ensuite on attend.
  Si l'attente expire, la réponse est un `503` honnête — jamais une deuxième
  connexion silencieuse.

Le compteur qui fait foi (`countingTransport`) s'incrémente **à l'appel** de
`open()`, pas à sa résolution : c'est la seule façon de détecter deux
connexions qui s'établissent en parallèle.

### 2. Cache circulaire et diffusion sans copie (`ring-buffer.ts`, `broadcast.ts`)

Les chunks sont stockés **par référence** et remis **par référence** : diffuser
un flux à 200 clients coûte un tampon, pas 200. Les octets sont donc partagés et
doivent être traités comme lecture seule.

Un client qui joint reçoit d'abord la queue du cache (`backlogBytes`) : l'image
démarre tout de suite, sans rien redemander à l'origine. Un client lent voit ses
plus vieux octets tomber (*drop-oldest*, comme `tokio::sync::broadcast`) plutôt
que de faire enfler la mémoire ou de ralentir les autres ; les pertes sont
comptées, jamais silencieuses.

### 3. Vie privée (`sanitize.ts`)

La requête montante n'est pas *filtrée*, elle est **construite** à partir de
l'identité du proxy. `StreamHub` ne reçoit d'ailleurs jamais les en-têtes du
client : la frontière est structurelle, pas déclarative — un futur en-tête de
tracking ne peut pas fuir par oubli.

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

### 4. Lissage d'égress (`token-bucket.ts`)

Le WAN livre par rafales ; retransmises telles quelles à N clients, elles
saturent le lien et font trembler la lecture. Chaque client est servi à travers
un *token bucket* : `EDGE_EGRESS_BPS` en débit soutenu, profondeur = 100 ms de
débit par défaut (donc quasi-CBR). Les écritures trop grosses sont redécoupées
en `subarray` — toujours sans copie.

## Démarrer

```bash
EDGE_ORIGIN_TEMPLATE='https://origine.example/live/{id}.ts' \
EDGE_HOST=0.0.0.0 EDGE_PORT=8787 \
npm run edge
```

Le lecteur pointe alors sur `http://<edge>:8787/edge/<id>`.

| Variable | Défaut | Effet |
| --- | --- | --- |
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

Endpoints : `GET /edge/<id>` (flux), `GET /healthz`, `GET /metrics` (JSON :
connexions montantes, maximum atteint, octets WAN vs LAN, octets économisés).

## Vérification

`npm test` — 100 tests dédiés, dont :

- `hub.test.ts` : 150 clients simultanés → **1** ouverture ; churn aléatoire de
  200 tâches join/leave → `activeMax === 1` ; linger, reconnexion, échecs ;
- `edge.test.ts` : 200 clients sur un flux ; 150 joins concurrents sur 6 chaînes
  avec un seul slot → `activeMax === 1`, le surplus est refusé, pas empilé ;
- `proxy-e2e.test.ts` : sockets réelles — 120 clients HTTP, origine `node:http`
  qui compte **elle-même** ses requêtes et ses connexions (1 et 1), et vérifie
  qu'aucune valeur envoyée par les clients n'apparaît dans la requête montante.

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
  plusieurs secondes serait pire qu'un démarrage propre.
