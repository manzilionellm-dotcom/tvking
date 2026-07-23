# Gateway 7 MOTION — 500+ spectateurs sur 1 connexion fournisseur

Ce gateway **mutualise une unique connexion fournisseur** vers un nombre
**illimité de spectateurs regardant la MÊME chaîne** (fan-out). Il est conçu,
durci et **prouvé par un test de charge** pour tenir **500+ spectateurs
simultanés** sur une ligne dont le `max_connections` est faible (souvent 1).

> **La règle d'or (capacité honnête)**
> - **500 spectateurs sur LA MÊME chaîne = 1 connexion fournisseur.** ✅
>   (C'est le cas d'usage « liste de test / démo partagée ».)
> - **500 spectateurs sur des chaînes DIFFÉRENTES = borné par la ligne.** ❌
>   Le gateway ne tire en amont que `PROVIDER_MAX_CONNECTIONS` chaînes
>   distinctes à la fois ; au-delà il **refuse proprement (HTTP 503)**, sans
>   jamais dépasser la limite du fournisseur ni planter.
>   → Pour du **multi-chaînes massif**, prenez une ligne à plus de connexions.

---

## 1. Comment ça marche (le « secret »)

Pour une chaîne donnée, le gateway ouvre **une seule** connexion amont
(`src/hub.js` → `_openUpstream` / `_pump`). Chaque octet reçu est ré-émis **tel
quel** à **tous** les spectateurs abonnés :

- **Fan-out O(N)** : une boucle, N `res.write(chunk)`, **zéro copie** du payload
  (Node partage la même référence `Buffer` entre tous les sockets).
- **Backpressure sûr** : on n'attend jamais le `drain` d'un client dans le
  `_pump`. Un client lent accumule dans **sa propre** file de socket ; un
  balayage périodique (`_sweepBackpressure`) le coupe s'il dépasse son quota,
  **sans jamais ralentir le live des autres**.
- **Limite fournisseur respectée** : le nombre de chaînes ouvertes en même temps
  ne dépasse jamais `PROVIDER_MAX_CONNECTIONS`. Quand une chaîne n'a plus aucun
  spectateur, sa connexion amont est **relâchée** (le « slot » se libère).

```
                         ┌─────────────── gateway ───────────────┐
   ligne fournisseur     │   hub.js : 1 _pump  →  fan-out O(N)     │      500 spectateurs
   (max_connections=1)   │                                        │
        ───── 1 conn ───►│ [chaîne 42] ──┬─► client 1             │◄──── même chaîne 42
                         │               ├─► client 2             │
                         │               ├─► …                    │
                         │               └─► client 500           │
                         └────────────────────────────────────────┘
```

---

## 2. Déploiement clé en main (VPS + domaine + HTTPS)

**Prérequis**
- Un VPS (Docker + Docker Compose installés).
- Un **domaine** dont l'enregistrement **DNS A** pointe vers l'IP du VPS.
- Les ports **80** et **443** ouverts (Let's Encrypt en a besoin).

**Étapes**

```bash
# 1) Récupérez le dossier gateway/ sur le VPS, placez-vous dedans.
cd gateway

# 2) Créez votre configuration à partir de l'exemple, puis éditez-la.
cp .env.example .env
nano .env
#    → renseignez UPSTREAM_BASE / UPSTREAM_USER / UPSTREAM_PASS (la ligne réelle),
#      PROVIDER_MAX_CONNECTIONS (la vraie limite de la ligne),
#      BROADCAST_USER / BROADCAST_PASS (identité de diffusion),
#      BROADCAST_MAX_STREAMS=500 (ou plus),
#      PUBLIC_BASE=https://gateway.votre-domaine.tld,
#      CADDY_DOMAIN=gateway.votre-domaine.tld, CADDY_EMAIL=vous@domaine.tld

# 3) (Recommandé) Relevez la limite de descripteurs de fichiers de l'hôte
#    pour tenir 500+ sockets — voir la section « Réglages OS » plus bas.

# 4) Démarrez tout (gateway + Caddy HTTPS auto).
docker compose up -d

# 5) Suivez les journaux (Caddy obtient le certificat, le gateway démarre).
docker compose logs -f

# 6) Vérifiez la santé (depuis le VPS ou à distance) :
curl https://gateway.votre-domaine.tld/healthz
```

`/healthz` renvoie un JSON de stats (connexions amont actives, spectateurs,
mémoire tampon) — c'est aussi la sonde utilisée par le `HEALTHCHECK` Docker et
ce qui permet au **Diagnostic** du panel de passer au vert.

---

## 3. Réglage du panel (aucun code applicatif à modifier)

Dans le **panel → maître → « Liste de test »** :

- **Façade (gateway)** = `https://gateway.votre-domaine.tld` (votre `PUBLIC_BASE`).
- **Identité de diffusion** = `BROADCAST_USER` / `BROADCAST_PASS` (celles du `.env`).

> Les URLs de flux sont **réécrites au niveau du service** (déjà en place :
> `get.php` / `player_api.php` proxifient l'amont avec l'identité fournisseur,
> puis réécrivent les liens vers la façade). **La ligne réelle n'apparaît
> jamais** côté application ni côté panel.

Les spectateurs consomment alors, par exemple :

```
https://gateway.votre-domaine.tld/live/<BROADCAST_USER>/<BROADCAST_PASS>/<id>.ts
```

---

## 4. Réglages de capacité (justifiés)

| Variable | Défaut | Pourquoi |
|---|---|---|
| `BROADCAST_MAX_STREAMS` | **500** | Objectif : 500+ spectateurs simultanés. Montez-le si votre VPS suit (RAM + CPU + bande passante). |
| `CLIENT_BUFFER_MAX_BYTES` | **8 Mo** | Tampon max par client avant de le juger « lent ». Assez pour absorber un hoquet réseau sans qu'un seul client fasse gonfler la RAM. |
| `GLOBAL_CLIENT_BUFFER_MAX_BYTES` | **512 Mo** | Plafond mémoire tampon **cumulé** sur tous les clients. À 500 clients : 512 Mo ≈ 1 Mo/client. **128 Mo (256 Ko/client) était trop juste.** Montez à **1 Go** (`1073741824`) sur un VPS ≥ 4 Go de RAM et débits élevés ; **256 Mo** sur un petit VPS. |
| `SWEEP_INTERVAL_MS` | **1000** | Fréquence du balayage qui coupe les clients lents. |
| `PROVIDER_MAX_CONNECTIONS` | **1** | **La vraie limite de la ligne.** Jamais dépassée. |
| `UPSTREAM_MAX_RETRIES` / `UPSTREAM_RETRY_BASE_MS` | 3 / 500 | Reconnexion amont avec backoff exponentiel si la source hoquette. |

**Dimensionnement mémoire (ordre de grandeur).** Pire cas ≈
`GLOBAL_CLIENT_BUFFER_MAX_BYTES` de tampon + overhead sockets (~quelques dizaines
de Ko/socket). À 500 clients, prévoir **au moins 1 Go de RAM** avec le plafond
global à 512 Mo ; **2–4 Go** de RAM avec un plafond à 1 Go pour du confort.

### Réglages OS (indispensables pour 500 sockets)

- **Descripteurs de fichiers** — chaque spectateur = 1 socket. Relevez la limite :
  ```bash
  # Vérifier :
  ulimit -n
  # Recommandé : ≥ 65535. Via docker-compose, c'est déjà réglé (ulimits.nofile).
  # Sur l'hôte, dans /etc/security/limits.conf :
  #   *  soft  nofile  65535
  #   *  hard  nofile  65535
  ```
- **keep-alive / timeouts** — le gateway configure `keepAliveTimeout` (15 s par
  défaut, via `KEEPALIVE_MS`) et **désactive** le `requestTimeout` (un flux live
  n'a pas de durée maximale). Caddy proxifie en `flush_interval -1` (aucun tampon
  intermédiaire).
- **Bande passante** — 500 spectateurs × débit de la chaîne. Ex. une chaîne à
  6 Mbps → **~3 Gbps** en sortie agrégée. Vérifiez le lien réseau du VPS.

---

## 5. Validation & preuve

```bash
# Syntaxe de tous les modules.
node --check src/config.js && node --check src/hub.js \
  && node --check src/server.js && node --check src/index.js

# Tests unitaires du hub (mutualisation, limite fournisseur, backpressure).
node test/hub.test.mjs      # ou : npm test

# PREUVE PAR TEST DE CHARGE — 500 clients = 1 upstream.
node test/load_500.mjs      # ou : npm run load
```

Le test de charge (`test/load_500.mjs`) monte tout en local (faux upstream +
gateway + 500 clients sur la **même** chaîne) et **échoue (exit 1)** si un
invariant casse. Il vérifie :

- **A.** 1 **seule** connexion upstream (pas 500) → mutualisation prouvée.
- **B.** Les 500 clients sains reçoivent bien des octets.
- **C.** La mémoire tampon reste **bornée** sous le plafond global.
- **D.** Un client **lent est coupé** par le backpressure **sans bloquer** les autres.
- **E.** Une chaîne **distincte** au-delà de `PROVIDER_MAX_CONNECTIONS` est
  refusée proprement (**HTTP 503**), sans crash.

Paramètres surchargeables par variables d'env (ex. `LOAD_CLIENTS=1000`,
`LOAD_RUN_MS=12000`, `LOG_LEVEL=info`).

---

## 6. Sécurité & bonnes pratiques

- **Aucun secret en clair** : seuls `.env.example` et les fichiers de config sont
  versionnés ; le `.env` réel est ignoré (`.gitignore` / `.dockerignore`).
- **Identité fournisseur jamais exposée** : les spectateurs n'utilisent que
  `BROADCAST_USER/PASS` ; l'amont réel est réécrit au niveau du service.
- **HTTPS obligatoire** : Caddy termine le TLS sur votre vrai domaine
  (Let's Encrypt auto). Le gateway n'expose aucun port en clair sur l'hôte.

---

## 7. Structure du dossier

```
gateway/
  src/
    config.js      Lecture/validation de la configuration (env)
    hub.js         Mutualisation amont + fan-out O(N) + backpressure  ← le cœur
    server.js      Façade HTTP (auth diffusion, réécriture URLs, /healthz)
    index.js       Point d'entrée (démarrage + arrêt propre)
  test/
    hub.test.mjs   Tests unitaires (mutualisation, limite, backpressure)
    load_500.mjs   Test de charge : 500 clients = 1 upstream (PREUVE)
  Dockerfile       Image Node slim, non-root, sans dépendance
  docker-compose.yml  gateway + Caddy (HTTPS auto)
  Caddyfile        Reverse-proxy HTTPS + Let's Encrypt
  .env.example     Modèle de configuration documenté (à copier en .env)
```
