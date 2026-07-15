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

## Démarrage (Docker)

```bash
cd gateway
cp .env.example .env         # remplis UPSTREAM_* + PROVIDER_MAX_CONNECTIONS
cp users.example.json users.json   # papa + clones
docker compose up -d --build
curl -s http://127.0.0.1:8088/health
```

Mets un reverse-proxy TLS (Caddy/Traefik/nginx) devant, et renseigne
`PUBLIC_BASE` avec l'URL publique (ex. `https://tv.mondomaine.com`).

## Brancher l'app / le panel

Dans le panel, pousse une source **Xtream** vers la MAC du client, mais avec :

- **Serveur** = l'URL de la passerelle (`PUBLIC_BASE`)
- **Utilisateur / Mot de passe** = ceux du membre (`papa`, `maman`, …) définis
  dans `users.json` — **pas** ceux de la ligne fournisseur.

L'app tape la passerelle exactement comme un panel Xtream normal. La ligne
réelle n'est jamais exposée au client.

## Configuration (variables d'env)

Voir `.env.example`. Les principales :

- `UPSTREAM_BASE`, `UPSTREAM_USER`, `UPSTREAM_PASS` — ta ligne (la seule).
- `PROVIDER_MAX_CONNECTIONS` — connexions simultanées **autorisées** par la
  ligne. La passerelle ne dépasse jamais ce chiffre.
- `PUBLIC_BASE` — URL publique (réécriture des playlists / `server_info`).
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
