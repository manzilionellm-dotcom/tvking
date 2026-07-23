# 🚦 Runbook — Finalisation « indépendance » : v500 + HTTPS (diagnostic VERT)

> **But** : amener la chaîne complète à l'état **« diagnostic VERT, vérifiable
> de bout en bout »**, façade en `https://gw.7themotion.com`, gateway en v500
> avec l'identité de diffusion, invisibilité prouvée.
>
> **Ce runbook est la procédure EXACTE.** Chaque étape a une **commande** et un
> **résultat attendu** pour que tu (ou une IA) puisses vérifier sans deviner.
> Aucun secret n'apparaît ici : les secrets se saisissent **sur le serveur**,
> masqués, via `gateway/scripts/setup-vps.sh`.

---

## 0. Où en est le code (déjà prêt, prouvé)

| Brique | État | Preuve |
| --- | --- | --- |
| Gateway v500 (`broadcast*`, `users.js` diffusion, `Caddyfile`, `docker-compose`) | **Prêt sur la branche** | 27/27 tests `node --test` passent |
| Worker + panel v500 | **Déjà déployés** (commit `5c28b1b`) | `validateFacadeBase` classe `https://gw.7themotion.com` en `probe:true` |
| Classement façade | **Correct** | https + domaine → sondable ; http/IP → app-seulement (ambre) |

**Ce qui reste = opérationnel** (accès VPS + Cloudflare requis) : DNS, `git pull`
sur le VPS, `.env`, lancer Docker, tester. C'est l'objet des étapes 1 → 6.

> ⚠️ **Ces étapes s'exécutent sur le VPS et dans le tableau de bord Cloudflare —
> pas depuis l'atelier de code.** Elles demandent tes accès (SSH au VPS, zone
> DNS). Le script `setup-vps.sh` fait tout le travail `.env` + Docker pour toi.

---

## 1. DNS — `gw` → VPS, **nuage GRIS**

Dans Cloudflare, zone **`7themotion.com`** :

- Type : **A**
- Nom : **`gw`**  (donne `gw.7themotion.com`)
- Contenu : **`167.233.193.51`**
- Proxy : **DNS only (nuage GRIS)** ← *indispensable*

> **Pourquoi gris ?** En orange (proxy Cloudflare), Caddy ne peut pas répondre
> au challenge HTTP-01 de Let's Encrypt → **pas de certificat**. Le gris laisse
> le VPS joignable en direct pour la validation TLS.

**Vérifier la propagation :**
```bash
dig +short gw.7themotion.com    # attendu : 167.233.193.51
```

---

## 2. Récupérer la v500 sur le VPS

En SSH sur le VPS, dans le clone du dépôt :
```bash
git fetch origin
git checkout claude/tv-box-bulletin-localization-7xwp9f
git pull --ff-only origin claude/tv-box-bulletin-localization-7xwp9f
```
> Récupère `broadcast*` (config), `users.js` diffusion, `Caddyfile`,
> `docker-compose.yml`, et le script d'installation `scripts/setup-vps.sh`.

---

## 3. + 4. `.env` + Caddy + Docker — en UNE commande sûre

```bash
cd gateway
bash scripts/setup-vps.sh
```

Le script (idempotent, secrets **masqués**, jamais loggés) :

1. crée/complète `.env` (permissions `600`) ;
2. met `DOMAIN=gw.7themotion.com` et `PUBLIC_BASE=https://gw.7themotion.com` ;
3. te demande la **ligne fournisseur** (`UPSTREAM_*`, mot de passe masqué) et
   garde `PROVIDER_MAX_CONNECTIONS=5` ;
4. règle l'**identité de diffusion** : `BROADCAST_USER=diffusion`,
   `BROADCAST_PASS` (généré fort **ou** saisi masqué), `BROADCAST_MAX_STREAMS=100` ;
5. génère un `ADMIN_TOKEN` si encore à l'exemple ;
6. lance `docker compose up -d --build` (gateway **+** Caddy = HTTPS auto) ;
7. sonde `https://gw.7themotion.com/health` et l'affiche.

> 🔐 **Le mot de passe de diffusion** : s'il est généré, le script l'affiche
> **une seule fois** à la fin, sur ton terminal, pour que tu le reportes dans
> le **panel**. Il est déjà dans `.env` côté serveur. **Ne le colle nulle part
> d'autre** (ni commit, ni doc, ni message).

**Résultat attendu (fin du script) :**
```json
{"ok":true,"upstreamActive":0,"providerMax":5,"uptimeSec":...}
```

**Si ça ne répond pas** — les 3 causes classiques (dans l'ordre) :
1. DNS pas encore propagé → attends, refais `dig`.
2. Nuage **orange** au lieu de gris → repasse en DNS only.
3. Ports 80/443 fermés → ouvre-les côté hébergeur/pare-feu.
```bash
docker compose logs --tail=50 caddy   # cherche « certificate obtained » / erreurs ACME
```

**Vérifs manuelles utiles :**
```bash
curl -fsS https://gw.7themotion.com/health           # → {"ok":true,...}
curl -sI https://gw.7themotion.com/health | grep -i strict   # TLS servi par Caddy
```

**Auto-test de configuration (état « vert » lisible à distance) :**
```bash
# Remplace <ADMIN_TOKEN> par la valeur de .env (ne la colle nulle part ailleurs).
curl -fsS -H "Authorization: Bearer <ADMIN_TOKEN>" https://gw.7themotion.com/admin/selftest
```
Réponse attendue (état « vert ») — **aucun secret n'y figure**, uniquement des
booléens et des valeurs publiques :
```json
{ "ok": true, "level": 0, "version": "v500",
  "facade":   { "base": "https://gw.7themotion.com", "probe": true, "reason": "" },
  "broadcast":{ "configured": true, "user": "diffusion", "maxStreams": 100 },
  "provider": { "configured": true, "maxConnections": 5 },
  "checks": [ /* facade_https, broadcast_identity, provider_line → level 0 */ ],
  "warnings": [] }
```
> `ok:true` + `facade.probe:true` = façade **sondable** → le Diagnostic du panel
> passera au **vert**. Si `probe:false`, le champ `warnings` explique quoi
> corriger (le plus souvent : PUBLIC_BASE pas en https + domaine).

---

## 5. Panel — pointer la façade HTTPS + identité de diffusion

Dans la **console maître** (panel admin) :

- **Ta façade (gateway)** : `https://gw.7themotion.com`
- **Utilisateur gateway (diffusion)** : `diffusion`
- **Mot de passe gateway (diffusion)** : *(le `BROADCAST_PASS` du serveur)*

> Ces valeurs **doivent** être identiques à celles du `.env`. Sinon les URLs de
> test seront rejetées par le gateway (auth diffusion) ou retomberont sur les
> identifiants fournisseur (moins privé).

---

## 6. Test de bout en bout — à **PROUVER**

| # | Action | Preuve attendue |
| --- | --- | --- |
| 6.1 | **Copier** les chaînes (colle le lien fournisseur ; le panel lit chez le fournisseur, réécrit sur la façade HTTPS) | Toutes les chaînes chargées, **pagination** 200 → +500, **jamais de troncature silencieuse** (compteur affiché, plafond 20k) |
| 6.2 | **Curer** la liste de test (3–5 chaînes) et **donner un test** (MAC ou code, ex. 24 h) | Test créé ; l'URL du testeur porte une **référence opaque `ml_…`**, jamais la MAC ni la ligne réelle |
| 6.3 | **Lire** sur une app (le lien de test) | La chaîne **joue via `gw.7themotion.com`** (URL réécrite sur la façade) |
| 6.4 | **Diagnostic** (bouton boîte noire) | Tous les contrôles **VERTS** : *façade en ligne* (probe:true), *identité de diffusion*, *liste de test*, *chaîne jouable* |
| 6.5 | **Invisibilité** | Le fournisseur ne voit **qu'UNE** connexion amont ; **maître ET testeur hors** des stats clients (`admin_presence` ≠ `presence`) |

### Vérifier l'invisibilité côté gateway (facultatif, si mapping loopback activé)
```bash
# Un seul flux amont même avec plusieurs testeurs sur la même chaîne :
curl -s "http://127.0.0.1:8088/health"     # upstreamActive reste bas (mutualisation)
# La vraie ligne n'apparaît JAMAIS dans le M3U servi au testeur :
#   → l'URL renvoyée pointe sur https://gw.7themotion.com/... (façade), pas sur le fournisseur.
```

### Pourquoi le diagnostic passe au VERT (rappel technique)
`validateFacadeBase("https://gw.7themotion.com")` → `{ ok:true, probe:true }`.
Le relais Cloudflare **peut** sonder un domaine https valide (fetch fiable),
là où une IP nue renvoyait 403/530. Contrôles `gateway` et `channel_probe`
passent donc de « informatif (ambre) » à « vert » dès que la façade répond.

---

## 7. Définition de « FINI » (cocher)

- [ ] `dig +short gw.7themotion.com` = `167.233.193.51` (nuage gris)
- [ ] `curl https://gw.7themotion.com/health` = `{"ok":true,...}`
- [ ] `.env` : `PUBLIC_BASE=https://gw.7themotion.com`, `BROADCAST_USER=diffusion`,
      `BROADCAST_MAX_STREAMS=100`, `PROVIDER_MAX_CONNECTIONS=5` (secrets masqués, `.env` en 600)
- [ ] Panel : façade HTTPS + identité `diffusion`
- [ ] Un test donné **joue** sur une app via `gw.7themotion.com`
- [ ] **Diagnostic VERT** (façade sondable)
- [ ] Invisibilité : maître + testeur hors stats ; fournisseur = **1 connexion**
- [ ] Rien de secret dans un commit / doc / log

---

## 8. Garde-fous (rappel, non négociables)

- **Jamais** de secret en clair (commit, doc, log). Saisie **masquée** sur le serveur.
- **Une seule** ligne fournisseur ; jamais visible dans le M3U servi (façade + `ml_…`).
- Maîtres et tests **invisibles** dans les stats clients.
- Ne **jamais** toucher la lecture cinéma / VOD.
- `.env` et `users.json` : **ignorés par Git** (`.gitignore`) — ne les force jamais.

---

## 9. Revue des branches sœurs (fait)

- `claude/independence-hardening-d51mdr` : **déjà intégré** dans la branche de
  travail (ancêtre direct) → **aucun conflit**, rien à merger.
- `claude/defew-tv-hardening-tbhlrw` : ne touche **que** l'app TV Flutter +
  natif Kotlin + traductions + tests. **Ne touche pas** `gateway/`,
  `cloudflare/` ni `admin-panel/` → **aucun conflit avec le panel**.

---

*Fin du runbook. Le code v500 est prêt et testé ; ce document rend les étapes*
*opérationnelles exécutables et vérifiables, sans jamais exposer de secret.*
