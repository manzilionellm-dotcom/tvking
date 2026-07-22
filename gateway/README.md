# Passerelle IPTV « maison mère » (7 MOTION)

Passerelle honnête et stable entre les appareils d'une **famille** et **UNE**
ligne fournisseur. Elle **mutualise uniquement les flux identiques**, **applique**
la limite de connexions de la ligne (jamais la dépasser), et gère les
utilisateurs, la reconnexion, la bande passante et le monitoring.

> ⚠️ **Aucune magie, aucun contournement.** 5 appareils qui regardent
> **5 chaînes différentes** = **5 connexions** vers le fournisseur : il faut une
> ligne qui autorise au minimum 5 connexions simultanées. La passerelle
> n'invente pas de connexions et ne casse aucune protection du fournisseur.
> Le seul gain réel : quand **plusieurs membres regardent la MÊME chaîne**, on
> ne tire **qu'un seul flux** en amont et on le redistribue.

## Ce que ça fait (et ne fait pas)

| Fonction | Détail |
|---|---|
| **Mutualisation** | Même chaîne demandée par N appareils → **1 seule** connexion fournisseur, redistribuée. Chaînes différentes → connexions distinctes. |
| **Garde-fou ligne** | Le nombre de connexions **distinctes** vers le fournisseur ne dépasse **jamais** `PROVIDER_MAX_CONNECTIONS`. Au-delà : `503` propre (protège d'un ban). |
| **Utilisateurs** | Papa + clones ont **chacun** leurs identifiants (révocables un par un), tous vers la même ligne. Quota d'écrans par utilisateur et par famille. |
| **Reconnexion** | Coupure amont → reconnexion avec backoff ; abandon propre après N essais (l'app cliente bascule sur son fallback). |
| **Bande passante** | Comptée par flux (métriques). Client trop lent → coupé pour protéger les autres. |
| **Monitoring** | `/health`, `/metrics` (Prometheus), `/admin/status` (JSON détaillé). |
| **Façade Xtream** | `player_api.php`, `get.php`, `/live|/movie|/series/...` : les apps ne changent pas. La ligne réelle est **masquée** (identifiants réécrits). |

## Déploiement HTTPS de bout en bout (reproductible)

> **Pourquoi HTTPS + un vrai domaine est OBLIGATOIRE (le point faible résolu).**
> Le copieur et le diagnostic tournent dans un **Worker Cloudflare**. Un Worker
> joint de façon **fiable** un **domaine public en HTTPS valide**, mais **échoue
> (403/530)** sur une **IP brute**, et ne peut pas valider le TLS d'un hôte sans
> certificat (une IP, un `nip.io`). L'ancienne rustine « IP → `nip.io` » donnait
> un diagnostic **vert mensonger** (la sonde passait parfois, la lecture réelle
> non). La solution robuste : mettre la passerelle **derrière un vrai domaine
> HTTPS** via **Caddy** (certificat Let's Encrypt **obtenu et renouvelé
> automatiquement**). `PUBLIC_BASE` et la « façade » du panel sont alors en
> `https://…` et joignables **réellement de bout en bout**.

Architecture : **Caddy** (public `80`/`443`, TLS auto) → **gateway** (interne
`8088`, jamais exposé). Tout est décrit dans `docker-compose.yml` + `Caddyfile`.

```bash
cd gateway
cp .env.example .env                 # (voir ci-dessous les champs à remplir)
cp users.example.json users.json     # papa + clones

# 1) DNS : fais pointer un enregistrement A (et AAAA si IPv6) de ton domaine
#    (ex. tv.mondomaine.com) vers l'IP publique du VPS. Ouvre les ports 80+443.
# 2) Dans .env, renseigne au minimum :
#      DOMAIN=tv.mondomaine.com
#      PUBLIC_BASE=https://tv.mondomaine.com
#      UPSTREAM_BASE / UPSTREAM_USER / UPSTREAM_PASS  (ta ligne)
#      PROVIDER_MAX_CONNECTIONS=…                     (limite de la ligne)
#      BROADCAST_USER / BROADCAST_PASS                (identité de diffusion)
#      ADMIN_TOKEN=…                                  (long secret)

docker compose up -d --build
```

Caddy demande le certificat au premier démarrage (quelques secondes), puis le
**renouvelle seul** en tâche de fond. Les certificats sont **persistés** dans le
volume `caddy_data` (pas de re-émission à chaque redéploiement → pas de
rate-limit Let's Encrypt). Les deux services redémarrent tout seuls
(`restart: unless-stopped`).

Vérifier :

```bash
# Depuis n'importe où : la façade publique répond en HTTPS valide.
curl -s https://tv.mondomaine.com/health

# Sur le VPS (si tu as décommenté le mapping loopback dans docker-compose) :
curl -s http://127.0.0.1:8088/health
```

### Alternative sans ouvrir de port : tunnel `cloudflared`

Si tu ne peux pas exposer 80/443 (NAT, pas de domaine pointé sur le VPS), un
tunnel **cloudflared** publie le gateway sous un hostname Cloudflare joignable
par le Worker **sans ouvrir de port**. Fais pointer le tunnel sur le service
interne `gateway:8088`, et mets `PUBLIC_BASE`/façade sur le hostname du tunnel
(toujours un domaine `https://` → même contrat, même robustesse). Caddy devient
alors optionnel. Ce mode reste un domaine HTTPS valide côté Worker.

### Identité de diffusion (confidentialité de la liste de test)

`BROADCAST_USER` / `BROADCAST_PASS` définissent un **utilisateur partagé, en
lecture seule**, que la **console maître** embarque dans les URLs de la petite
liste de test — **à la place des identifiants fournisseur**. Résultat : la ligne
réelle **n'apparaît jamais** dans le M3U servi aux testeurs, et l'URL est
**réellement jouable** (le gateway authentifie cette identité). Renseigne les
**mêmes** valeurs dans le panel (« Utilisateur / mot de passe gateway »).

- `BROADCAST_MAX_STREAMS` borne le nombre de **testeurs simultanés** — à ne pas
  confondre avec `PROVIDER_MAX_CONNECTIONS`, qui borne les connexions
  **fournisseur** (amont). Comme les testeurs regardent les **mêmes** quelques
  chaînes, la **mutualisation** garde l'amont à ~1 connexion : cette valeur peut
  être généreuse.
- Cette identité est **injectée depuis l'environnement uniquement** : elle n'est
  **jamais** écrite dans `users.json` ni éditable via le panel (voir
  `test/broadcast.test.mjs`).

> **Compromis assumé.** Sans identité de diffusion réglée mais **avec** une
> façade, les URLs de test copiées retombent sur les **identifiants
> fournisseur** : la lecture fonctionne si le gateway fait un passthrough, mais
> la ligne réelle transparaît dans le M3U servi. Le diagnostic le **signale**
> (contrôle « Identité de diffusion » en ambre). Règle `BROADCAST_*` pour un
> partage pleinement privé.

## Brancher l'app / le panel

Dans le panel, pousse une source **Xtream** vers la MAC du client, mais avec :

- **Serveur** = l'URL de la passerelle (`PUBLIC_BASE`)
- **Utilisateur / Mot de passe** = ceux du membre (`papa`, `maman`, …) définis
  dans `users.json` — **pas** ceux de la ligne fournisseur.

L'app tape la passerelle exactement comme un panel Xtream normal. La ligne
réelle n'est jamais exposée au client.

## Configuration (variables d'env)

Voir `.env.example`. Les principales :

- `DOMAIN` — domaine public servi par Caddy (certificat TLS + reverse-proxy).
- `PUBLIC_BASE` — URL publique **https** (réécriture des playlists /
  `server_info`). En général `https://$DOMAIN`.
- `UPSTREAM_BASE`, `UPSTREAM_USER`, `UPSTREAM_PASS` — ta ligne (la seule).
- `UPSTREAM_BASE_FALLBACKS` — lignes de secours (failover), séparées par des
  virgules.
- `PROVIDER_MAX_CONNECTIONS` — connexions simultanées **autorisées** par la
  ligne. La passerelle ne dépasse jamais ce chiffre.
- `BROADCAST_USER`, `BROADCAST_PASS` — identité de diffusion partagée pour la
  liste de test (voir section dédiée). Mêmes valeurs côté panel.
- `BROADCAST_MAX_STREAMS` — plafond de testeurs simultanés (≠ connexions
  fournisseur).
- `STREAM_IDLE_GRACE_MS` — délai avant fermeture d'un flux quand plus personne
  ne regarde (zapping aller-retour fluide).
- `CLIENT_BUFFER_MAX_BYTES` — au-delà, un client trop lent est coupé.
- `ADMIN_TOKEN` — protège `/metrics` et `/admin/*` (vide = désactivés).
- `ALLOW_INSECURE_TLS` — accepter les certificats fournisseur invalides.

## Utilisateurs (`users.json`)

```json
{
  "families": [
    { "id": "famille-karim", "maxStreams": 5,
      "users": [
        { "username": "papa",  "password": "…", "maxStreams": 2 },
        { "username": "maman", "password": "…" },
        { "username": "enfant1", "password": "…" }
      ] }
  ]
}
```

Rechargement à chaud (sans redémarrage) :

```bash
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  http://127.0.0.1:8088/admin/reload-users
```

## Supervision

```bash
curl -s http://127.0.0.1:8088/health
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" http://127.0.0.1:8088/metrics
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" http://127.0.0.1:8088/admin/status | jq
```

Métriques clés : `gw_upstream_active` (connexions fournisseur en cours),
`gw_clients_active`, `gw_mux_join_total` (branchements mutualisés),
`gw_rejected_provider_limit_total` (refus car ligne pleine),
`gw_bytes_upstream_total` / `gw_bytes_clients_total` (bande passante),
`gw_upstream_reconnects_total`.

## Tests

```bash
npm install
npm test
```

Les tests d'intégration démarrent un **faux fournisseur** local et prouvent :
1. **mutualisation** — 3 spectateurs d'une chaîne = **1** connexion amont ;
2. **limite fournisseur** — la 3ᵉ chaîne différente est refusée (`503`) quand
   la ligne est à 2, mais rejoindre une chaîne déjà ouverte reste possible.

## Dimensionnement (honnête)

La vidéo transite par ta passerelle : tu paies la bande passante **sortante**.
Ordre de grandeur : `débit_chaîne × nombre_de_flux_distribués`. Ex. 8 Mbps ×
5 écrans = ~40 Mbps soutenus par famille active. Prends un VPS avec une
bande passante suffisante et non facturée à l'excès.
