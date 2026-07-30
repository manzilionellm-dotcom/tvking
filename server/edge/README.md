# Edge proxy — déduplication de flux et cache local

Service Node autonome (`server/edge/`) placé entre les clients du réseau local
(TV, téléphones, écrans de test) et l'origine média distante.

Il tient six promesses :

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
5. **Un catalogue Cinéma/VOD unifié.** Plusieurs playlists sont agrégées en
   **un** catalogue dédoublonné, avec cache disque par tranches : le deuxième
   spectateur d'un film populaire ne coûte rien au WAN.
6. **Des abonnés, des durées et une expiration qui mord.** Portails MAC (MAG /
   Stalker) et Xtream Codes, formules 24 h / 1 / 3 / 6 / 12 mois, et un
   applicateur qui **coupe les flux en cours** dès l'échéance.

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
| `db/schema.ts` / `db/database.ts` | Migrations SQLite numérotées + accès (base intégrée à Node) |
| `portal/plans.ts` | Durées d'abonnement (mois calendaires, UTC) |
| `portal/devices.ts` | Abonnés : bouquets, MAC/Xtream, octrois, authentification |
| `portal/enforcer.ts` | Applicateur d'expiration : coupe les flux dès l'échéance |
| `portal/xtream.ts` / `portal/stalker.ts` | Portails abonnés (API Xtream, portail MAG) |
| `vod/classify.ts` | Heuristiques titre/genre/épisode sur les lignes M3U |
| `vod/catalog.ts` | Catalogue VOD dédoublonné (1 œuvre, N sources) |
| `vod/ingest.ts` | Ouvrier d'ingestion périodique |
| `vod/cache.ts` | Cache disque par tranches, LRU indexé en base, Range |
| `http/deliver.ts` | Livraison HTTP partagée (direct lissé, VOD avec Range) |
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

### 5. Agrégation Cinéma / VOD (`vod/`)

L'ouvrier parcourt les sources actives, télécharge chaque playlist **dans le
budget de connexions du compte** (une actualisation de catalogue est une
connexion montante comme une autre : si un spectateur occupe le slot, l'ouvrier
passe son tour et réessaie), ne garde que les lignes qui ressemblent à de la
VOD, puis les replie dans le catalogue.

Le dédoublonnage est le cœur : les lignes fournisseurs sont des noms de fichiers
décorés (`FR - Le Grand Bleu (1988) [MULTI 1080p]`). `classify.ts` en extrait
l'œuvre, l'année, la qualité, la saison/épisode et le genre ; la clé
`(type, titre normalisé, année)` fait que le même film présent chez quatre
fournisseurs devient **un** titre avec quatre flux jouables — et donc un
repli gratuit quand l'un des fournisseurs bronche. Les heuristiques sont
prudentes : un titre illisible reste tel quel plutôt que d'être mal fusionné.

Piège vécu : `.ts` est **à la fois** un conteneur VOD et l'extension normale
d'une chaîne en direct. S'en servir comme indice de VOD range toutes les
chaînes dans la vidéothèque — le chemin `/movie/` tranche, pas l'extension.

Le cache VOD est l'inverse du direct : un fichier fixe, lu à des endroits
différents par des gens différents. L'unité utile est donc la **tranche
d'octets** sur disque (4 Mio par défaut), indexée en base pour que l'ordre LRU
survive à un redémarrage. Les lecteurs concurrents d'une même tranche manquante
se rejoignent sur **une** requête `Range` (single-flight), et une tranche déjà
là ne coûte rien. Le `Range` envoyé au fournisseur est un multiple de la taille
de tranche : identique quel que soit le spectateur, donc sans information sur
lui — c'est la seule exception admise à la signature maître.

### 6. Abonnés, durées et expiration (`portal/`)

Un **appareil** est une identité d'abonné : une MAC (boîtier MAG) ou un login
Xtream, rattachée à un **bouquet** (un compte maître, éventuellement restreint
à des groupes ou des chaînes). Les octrois sont un historique append-only :
qui a reçu quoi, quand, et qui l'a révoqué.

| Formule | Durée |
| --- | --- |
| `trial-24h` | 24 h pile (essai) |
| `1m` / `3m` / `6m` / `12m` | mois **calendaires**, en UTC |

Mois calendaires et non « 30 jours » : trois mois achetés le 15 mars finissent
le 15 juin, comme sur la facture. Le jour est ramené à la fin du mois quand il
n'existe pas (31 janvier + 1 mois = 28 ou 29 février). Renouveler en avance
**ajoute** au reliquat au lieu de le jeter.

Vérifier l'abonnement à la connexion n'est pas de l'application : un client
connecté une minute avant l'échéance garderait le flux des heures. L'applicateur
balaie donc les sessions vivantes et coupe celles dont l'appareil n'est plus en
règle — expiré, révoqué, désactivé ou supprimé — en réévaluant la base à chaque
passage plutôt qu'en se fiant à un horodatage capturé à la connexion.

Deux horloges distinctes, volontairement : les abonnements expirent sur des
dates (horloge murale), le lissage et les délais sur une horloge monotone. Les
mélanger, c'est laisser un ajustement NTP ressusciter un compte expiré ou tuer
un flux en cours.

**Sécurité, dit clairement** : une MAC dans un cookie est un identifiant, pas un
secret ; quiconque connaît une MAC enregistrée peut la présenter. C'est ainsi
que fonctionne le protocole MAG. Ce qui est fait : la MAC doit être enregistrée
**et** avoir un abonnement vivant, les liens sont émis contre un jeton
court-lived lié à cette MAC, et la limite de connexions s'applique. À réserver
à un réseau de confiance.

### 7. Lissage d'égress (`token-bucket.ts`)

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
| `EDGE_DB` | — | Fichier SQLite ; **vide = pas d'abonnés ni de VOD** |
| `EDGE_PORTAL` | `1` | `0` désactive les portails MAC/Xtream |
| `EDGE_PUBLIC_BASE` | déduit de `Host` | Base publique des liens générés |
| `EDGE_ENFORCE_INTERVAL_MS` | `15000` | Période de balayage des expirations |
| `EDGE_VOD` | `1` | `0` désactive l'ingestion et le cache VOD |
| `EDGE_VOD_CACHE_DIR` | `./.edge-cache/vod` | Répertoire des tranches |
| `EDGE_VOD_CHUNK_BYTES` | `4 Mio` | Taille d'une tranche |
| `EDGE_VOD_CACHE_BYTES` | `2 Gio` | Budget disque (éviction LRU) |
| `EDGE_VOD_INGEST_INTERVAL_MS` | `6 h` | Période d'ingestion |

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
| `GET/POST /admin/devices` | Abonnés (liste, création avec formule) |
| `PATCH/DELETE /admin/devices/:id` | Modification / suppression (coupe ses flux) |
| `POST /admin/devices/:id/grant` | Octroi ou prolongation (`plan`) |
| `POST /admin/devices/:id/revoke` | Révocation **immédiate** (coupe les flux) |
| `GET/POST /admin/packages` | Bouquets |
| `GET /admin/vod` | Catalogue, sources, catégories, statistiques de cache |
| `POST /admin/vod/sources` · `PATCH/DELETE /admin/vod/sources/:id` | Sources VOD |
| `PATCH /admin/vod/categories/:id` | Activer/masquer une catégorie |
| `POST /admin/vod/ingest` | Ingestion immédiate (toutes sources ou une) |
| `GET /admin/vod/titles` | Titres (filtre `kind`, `search`) |

Portails abonnés (authentifiés par appareil) :

| Route | Dialecte |
| --- | --- |
| `GET /player_api.php` | Xtream : `user_info`, catégories, chaînes, VOD, séries |
| `GET /get.php?type=m3u_plus` | Xtream : playlist générée (liens vers l'edge) |
| `GET /live/<user>/<pass>/<id>.ts` | Xtream : flux direct |
| `GET /movie/<user>/<pass>/<id>.<ext>` | Xtream : VOD (avec `Range`) |
| `GET /portal.php` | MAG/Stalker : handshake, profil, chaînes, VOD, `create_link` |
| `GET /stalker/stream/<jeton>/…` | MAG/Stalker : lien émis par le portail |

Le tableau de bord a trois onglets — **Direct**, **Cinéma / VOD**, **Appareils**.
Il affiche les montées actives (et le maximum jamais atteint,
qui doit rester ≤ au budget), les clients connectés et leur chaîne, les bascules,
et l'efficacité de déduplication (requêtes servies par montée, octets LAN vs
WAN). Les sessions y sont des identifiants opaques : **le tableau de bord ne peut
pas montrer ce que le proxy refuse de collecter** — ni IP, ni User-Agent. Les
seules identités affichées sont celles que l'opérateur a lui-même créées (MAC,
login), avec un compte à rebours d'expiration calé sur l'horloge du serveur, un
sélecteur de formule, un bouton « Essai 24 h » et une révocation immédiate.

## Vérification

`npm test` — 245 tests dédiés, dont :

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
- `subscriptions.test.ts` : migrations, durées calendaires, authentification, et
  surtout l'**application de l'expiration** — un flux en cours est coupé à la
  seconde où l'abonnement se termine, comme à la révocation, la désactivation ou
  la suppression de l'appareil ;
- `vod-catalog.test.ts` : dédoublonnage multi-fournisseurs, catégories,
  idempotence, échec de source sans perte de catalogue, et « l'ingestion
  n'ouvre jamais une deuxième connexion » ;
- `vod-cache.test.ts` : `Range` exacts, deuxième lecture à coût WAN nul,
  25 lecteurs simultanés → une requête, éviction LRU, refus d'un fournisseur
  sans `Range` ;
- `portal.test.ts` : sockets réelles — un lecteur Xtream et un boîtier MAG
  s'authentifient, listent, lisent, se heurtent à la limite de connexions, et
  se font couper en pleine lecture à l'expiration ;
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
- **L'authentification MAC vaut ce que vaut le protocole MAG** : un identifiant,
  pas un secret (voir §6).
- **La VOD partage le budget de connexions du direct** : une tranche manquante
  prend un slot libre — ou un slot que personne ne regarde — et sinon renvoie
  503. Un film ne chasse jamais un spectateur du direct.
- **Pas de métadonnées enrichies** (TMDB & co) : le catalogue ne connaît que ce
  que les playlists disent. Les affiches viennent de `tvg-logo`.
- **Les comptes maîtres ne sont toujours pas persistés** (env + API) ; les
  abonnés et le catalogue, eux, vivent en base.
- **Pas d'EPG** : `xmltv.php` répond un document vide mais valide.
