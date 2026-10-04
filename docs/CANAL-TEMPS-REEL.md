# Canal temps réel — panel → box

Contrat partagé par deux branches qui ne doivent pas être fusionnées
à l’aveugle :

| Branche | Contenu |
| --- | --- |
| `cursor/canal-temps-reel-worker-c1d5` (issue de `claude/panel-mise-en-ligne`) | Worker + panel |
| `cursor/canal-temps-reel-box-c1d5` (issue de `ccr-1d45eb8b-x46ieg`) | App box |

Le Worker de production ne déploie rien tant que Lionel ne l’écrit.
Aucun mot de passe, identifiant Xtream ou adresse de flux ne transite
sur ce canal. La box relit `GET /api/device-source/<mac>` elle-même.

## Interrupteurs de repli (coupés par défaut)

| Où | Nom | Défaut | Effet si on l’allume |
| --- | --- | --- | --- |
| Worker | variable `REALTIME_PUSH_OFF=1` | absente = canal ouvert | `/api/box/*` et `/api/v1/rt/ws` répondent 404, aucune notification |
| Panel | `REALTIME_POLL_LEGACY` dans `admin-panel/src/lib/live-sync.ts` | `false` | le panel ignore le WebSocket et sonde toutes les 2 s |
| App | `RepairFlags.realtimeLegacy` (`zuno.channel.legacy`) | `false` | la box n’ouvre pas de WebSocket et garde l’attente longue puis la lecture courte |

## Ce qui réveille la box

Après une écriture réussie, le Worker appelle le Durable Object.
Le message ne dit que « relis », jamais le contenu de la liste.

| Action panel | `type` |
| --- | --- |
| `PUT /api/v1/sources/:mac` | `source` |
| `DELETE /api/v1/sources/:mac` | `source_clear` |
| `POST /api/v1/activate` | `activate` ou `renew` |
| `POST /api/v1/trial-extend` | `license` |
| gel / ban / réactivation | `suspend` / `block` / `resume` |
| suppression de la MAC | `device_delete` |

D’autres noms sont réservés (`message`, `theme`, `home`, `banner`…)
mais pas encore émis. Un nom inconnu est ignoré.

La liste stockée en D1 ne change pas : uniquement
`type`, `label`, `server_url`, `username`, `password`, `m3u_url`, `epg_url`.

## WebSocket box

`GET /api/box/ws?mac=MK:XX:XX:XX:XX:XX` avec `Upgrade: websocket`.

Message serveur → box (texte JSON) :

```json
{"v":1,"seq":12,"type":"source","mac":"MK:AA:BB:CC:DD:EE","at":1710000000000}
```

- `seq` augmente de 1 pour cette MAC. Un `seq` déjà vu ne se rejoue pas.
- À la connexion, le serveur renvoie le dernier message s’il y en a un.
- La box peut envoyer `{"v":1,"type":"hello"}` (sans autre champ) pour
  garder le chemin ouvert. Le serveur répond le même hello.
- Tout autre texte est ignoré et n’est pas journalisé.

Dès `source` ou `source_clear`, la box relit
`GET /api/device-source/<mac>` et applique. Les autres `type` relisent
ce que l’app connaît déjà (`/api/status`, annonce, thème…).

## Repli attente longue

Si le WebSocket ne s’ouvre pas (404, réseau, ancien Worker), la box
reprend `GET /api/box/wait/<mac>?after=<seq>&timeout=<ms>`.

- `timeout` est borné entre 200 ms et 20 s (défaut 20 s).
- Réponse 200 :

```json
{
  "v": 1,
  "timeout": false,
  "box": [{ "id": 12, "kind": "source", "created_at": 1710000000000 }],
  "fleet": [],
  "events": [{ "v": 1, "seq": 12, "type": "source", "mac": "MK:AA:BB:CC:DD:EE", "at": 1710000000000 }]
}
```

- `timeout: true` et listes vides = rien de nouveau, on rouvre.
- `box[].id` est le même numéro que `seq`. `box[].kind` est le `type`.
  C’est la forme déjà lue par l’app de la branche box.
- `POST /api/box/ack/<mac>` répond `{ "ok": true }`. Le curseur réel
  est `after` : l’accusé ne fait que confirmer.
- 404 = canal coupé (repli allumé, ou Durable Object absent). L’app
  retombe sur sa lecture courte de `/api/status`.
- Cette ligne de Worker ne demande pas `X-Device-Secret` : le secret
  de box vit sur l’autre branche, pas en production. Le corps ne
  contient aucun secret. Les limites sont 60 requêtes / minute / IP.

## WebSocket panel

`GET /api/v1/rt/ws?token=<jwt>` (le navigateur ne peut pas poser
`Authorization`). Le Worker ne journalise pas l’URL.

Même JSON que pour la box. `seq` est celui du hub panel (il peut
différer du `seq` de la MAC). Un revendeur ne reçoit que les MAC
qui lui sont rattachées ; un admin reçoit tout.

Tant que le socket est ouvert, la page Appareils ne sonde plus
toutes les 2 s (filet 60 s) et relit dès qu’un message arrive.
S’il se ferme, le sondage à 2 s reprend. La page « En ligne »
reste à 2 s : la présence vient encore du heartbeat, pas de ce canal.

## Durable Object

- Classe exportée : `RealtimeHub` (obligatoire : la production en a
  déjà, erreur Cloudflare 10064 sinon).
- Binding : `RT_HUB`. Migration déjà appliquée : tag `v1-rt-hub`,
  `new_sqlite_classes = ["RealtimeHub"]`. Ne pas la recréer sous
  un autre tag.
- Une instance par MAC (`idFromName(mac)`), plus `panel-v1`.
- WebSocket en hibernation (`acceptWebSocket`). L’attente longue
  garde l’instance éveillée au plus 20 s.
- Anneau des 32 derniers messages par instance. Au-delà, la box
  relit l’état courant (elle n’a pas besoin de l’historique).

## Déploiement du 3 octobre 2026

Run GitHub `37120120412` (workflow « Deploy panel + Worker »,
cible Worker, 11:35 UTC). Wrangler 3.90.0 a bien envoyé le script
(462 Ko) puis l’API a refusé la version :

`New version of script does not export class 'RealtimeHub' which is
depended on by existing Durable Objects` (code 10064).

La classe avait été créée avec le Worker `seven-motion-backend`
(commit `089bdcde`, binding `RT_HUB`). La branche panel ne
l’exportait plus. Le run du 4 octobre (`37226181877`) était
`panel-seul` : le Worker en ligne n’a pas changé. Rien n’a été
déployé par ce travail.
