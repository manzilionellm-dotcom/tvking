# 📋 Brief complet pour Fable — État réel + finalisation « indépendance »

> **À coller tel quel à Fable 5.** Ce document explique **tout** ce qu'on a
> construit, où on en est **vraiment** (pas la théorie — le réel qui tourne),
> et répond à tes dernières questions. Objectif : passer d'un montage qui
> marche à un système **solide, vérifiable, vendable**.

---

## 0. Tes questions — réponses directes

**Q1 — Dans le `.env` du gateway qui tourne, il y a quoi comme `BROADCAST_USER` / `BROADCAST_PASS` ?**

> **Rien.** Le gateway **actuellement en production sur le VPS** est l'**ancienne
> version** (celle d'avant tes changements « diffusion »). Son `.env` **n'a pas
> de variables `BROADCAST_*`**. L'authentification passe par `users.json` avec
> un seul utilisateur : `master` / `k2fa4qozvb`. Donc `BROADCAST_USER` et
> `BROADCAST_PASS` sont **vides / absents** sur le serveur qui répond en ce
> moment.
>
> Tes ajouts (`BROADCAST_USER=diffusion`, `BROADCAST_PASS`,
> `BROADCAST_MAX_STREAMS`) existent **dans le code sur la branche**
> (`gateway/.env.example`, `gateway/src/config.js`, `gateway/src/users.js`)
> mais **ne sont pas encore déployés** sur le VPS.

**Q2 — On teste d'abord à 100 (tout de suite) ou on passe direct à 500 (mise à jour du VPS puis test) ?**

> **On passe à 500.** Raison : le **panel et le Worker sont déjà en v500**
> (déployés, tes changements mergés dans le commit `5c28b1b`). Rester à 100 sur
> le gateway créerait un décalage : identité `broadcast` attendue par le panel
> mais absente du serveur. Autant aligner le gateway maintenant — c'est
> `git pull` + 3 variables `.env` + relance Docker. Détail au §5.

**Q3 — On a un nom de domaine ?**

> **Oui : `7themotion.com`.** On peut créer un sous-domaine
> **`gw.7themotion.com`** qui pointe vers le VPS. C'est **la clé** qui débloque
> la sonde du diagnostic (voir §3 : le Worker ne peut pas sonder une IP nue,
> mais il peut sonder un domaine HTTPS).

---

## 1. Ce qu'on a construit (inventaire)

### Dépôt & branche
- **Repo** : `manzilionellm-dotcom/tvking`
- **Branche de travail** : `claude/tv-box-bulletin-localization-7xwp9f`
- Dernier commit : `5c28b1b` (invisibilité testeurs).

### Les 4 briques
1. **App mobile Flutter** (`lib/`) — client final.
2. **App TV « DeFew TV »** (Flutter, cible Android TV / Fire TV / Google TV).
3. **Gateway `gateway/`** (Node 20 + Docker + undici) — la **maison mère** :
   mutualise les flux identiques (1 chaîne = 1 connexion upstream quel que soit
   le nombre de spectateurs), façade Xtream (`player_api.php`, `get.php`,
   `/live`), reconnexion/failover, plafond `PROVIDER_MAX_CONNECTIONS`.
4. **Worker Cloudflare** (`cloudflare/worker.js` + `api_v1.js`, base D1) +
   **panel admin React** (`admin-panel/`) — la console du **maître**.

### Ce que le maître peut faire depuis le panel (déjà codé, déployé)
- **Copieur intelligent** : le maître **colle** son lien (Xtream `get.php` ou
  URL M3U), le panel lit **toutes** ses chaînes, les **catégorise**, il
  **coche** ce qu'il veut, **réorganise** (drag-drop, ▲▼, renommer, grouper,
  ajout manuel), pagination (200 puis +500) — **jamais de troncature
  silencieuse** (plafond 20k, affiché).
- **Liste de test « notre liste »** (< 5 chaînes possible) servie derrière une
  **référence opaque** `ml_…` : la MAC du maître **n'apparaît jamais** dans
  l'URL du testeur.
- **Façade** : chaque URL de chaîne est **réécrite sur le gateway** (stabilité
  + confidentialité) — le fournisseur ne voit **qu'une** connexion.
- **Donner / gérer les tests** : par MAC ou par code, durée **1 h → 1 an**,
  révoquer, prolonger.
- **Invisibilité** : le maître **et** les sessions de test en cours sont
  détournés vers `admin_presence` → **hors** des stats clients (`presence`).
- **Diagnostic « boîte noire »** : détecte les problèmes, score + pistes de
  correction, lisible par une IA.

### VPS (le serveur d'indépendance)
- **Hébergeur** : Hetzner Cloud, **CPX12**.
- **IP** : `167.233.193.51`.
- **OS** : Docker installé, gateway lancé, **santé confirmée** :
  `{"ok":true,"upstreamActive":0,"providerMax":5,"uptimeSec":...}` via
  `http://167.233.193.51.nip.io/health`.
- **Gateway actuel** : ancienne version, port `80:8088`, `users.json` =
  `master`/`k2fa4qozvb`, `PROVIDER_MAX_CONNECTIONS=5`,
  `PUBLIC_BASE=http://167.233.193.51`. **Pas** de `BROADCAST_*`.

---

## 2. Le modèle d'affaires (pour cadrer les décisions)

**Une seule ligne fournisseur** (un trio serveur/user/pass) → copiée et
**curée** en une petite liste → **donnée en test** à 10+ personnes qui
**regardent ce qu'elles veulent**. Grâce à la mutualisation du gateway, le
**fournisseur ne voit qu'une connexion** : les testeurs sont **invisibles**
pour lui, et le maître est **invisible** dans les stats clients.

Règle de mutualisation : **nombre de spectateurs illimité par chaîne** ; c'est
le nombre de **chaînes distinctes jouées en même temps** qui est borné par la
limite de connexions de la ligne.

---

## 3. LE blocage qu'on a résolu (à connaître absolument)

**Un Worker Cloudflare ne peut PAS `fetch()` une origine en IP nue ou en
`nip.io` HTTP** → il reçoit 403/530, alors qu'un **navigateur**, lui, joint le
serveur sans problème. C'est ce qui faisait échouer le copieur
(`provider_http_403`) et le diagnostic (`Façade injoignable (530)`).

**La bonne solution (déjà en place dans le code)** :
- Le copieur **ne dépend jamais** de `Worker → gateway`. Il **lit chez le
  fournisseur** (domaine joignable) puis **réécrit** les URLs sur la façade.
- `validateFacadeBase` **accepte** toute origine http(s) valide et **classe la
  vérifiabilité** : `probe:true` (https + domaine → sondable par le relais) vs
  `probe:false` (http/IP → joignable par les **apps** seulement, sondes du
  diagnostic **informatives**, plus de blocage).

**La conséquence pratique** : tant que la façade est en **IP nue**
(`http://167.233.193.51`), tout **fonctionne** (les apps lisent) mais le
diagnostic ne peut **pas sonder** la façade → il reste « informatif », pas
« vert ». **Pour le vert vérifiable de bout en bout, il faut
`https://gw.7themotion.com`.** C'est l'objet du §5.

---

## 4. État de vérification (ce qui est prouvé vert)

- **TypeScript panel** : propre.
- **Worker** : syntaxe OK.
- **11 tests smoke** passent (`master_list`, `master_copier`, `invite_master`) :
  parité `masterListRefPanel ≡ masterListRef`, classification façade
  probe:true/false, réécriture d'origine (port fournisseur effacé, query
  préservée), auto-détection Xtream/M3U.
- **Gateway** : test `broadcast.test.mjs` exécuté.
- **Déploiements** : `deploy-worker.yml` + `deploy-admin-panel.yml` déclenchés
  sur le commit `5c28b1b`.
- **VPS** : gateway **ancienne version** en ligne, santé OK.

**Ce qui reste à prouver vert** : la chaîne complète **avec HTTPS** (façade
`https://gw.7themotion.com` → diagnostic sondable → « vert » réel).

---

## 5. Plan de finalisation (v500 + HTTPS) — procédure exacte

**But** : aligner le gateway sur la v500, lui donner l'identité `broadcast`, et
le mettre en **HTTPS** sur `gw.7themotion.com` pour que le diagnostic soit
**vérifiable vert**.

1. **DNS** (Cloudflare, zone `7themotion.com`) : enregistrement **A**
   `gw` → `167.233.193.51`, **nuage gris** (DNS only, pas de proxy — sinon
   Caddy ne peut pas obtenir le certificat Let's Encrypt).

2. **Sur le VPS** (dans le clone du repo, branche
   `claude/tv-box-bulletin-localization-7xwp9f`) :
   ```
   git pull
   ```
   (récupère ta version v500 : config `broadcast*`, `users.js` diffusion,
   `Caddyfile`.)

3. **`.env` du gateway** — ajouter/mettre à jour :
   ```
   BROADCAST_USER=diffusion
   BROADCAST_PASS=<un secret fort — jamais en clair ici>
   BROADCAST_MAX_STREAMS=100
   PUBLIC_BASE=https://gw.7themotion.com
   ```
   (garder `UPSTREAM_*`, `PROVIDER_MAX_CONNECTIONS=5`.)

4. **Caddy** (HTTPS auto Let's Encrypt) : le `gateway/Caddyfile` que tu as
   ajouté sert de reverse-proxy `gw.7themotion.com` → gateway. Lancer
   Caddy + gateway (docker compose), vérifier
   `https://gw.7themotion.com/health`.

5. **Panel** : façade = `https://gw.7themotion.com` ; identité de diffusion =
   `diffusion` / `<BROADCAST_PASS>`.

6. **Test de bout en bout** :
   - Copier les chaînes (le panel lit chez le fournisseur, réécrit sur la
     façade HTTPS).
   - Donner un test (MAC ou code, ex. 24 h).
   - Lire sur une app → doit jouer via `gw.7themotion.com`.
   - Lancer le **Diagnostic** → doit être **vert** (façade sondable).
   - Vérifier l'**invisibilité** : maître + testeur **hors** stats clients ;
     fournisseur ne voit **qu'une** connexion.

---

## 6. Garde-fous (non négociables)

- **Jamais** de mot de passe root / secret **en clair** (ni ici, ni en commit,
  ni en log).
- **Une seule** ligne fournisseur ; la **vraie** ligne n'apparaît **jamais**
  dans le M3U servi au testeur (toujours derrière la façade + `ml_…`).
- Maîtres et tests **invisibles** dans les stats clients.
- Commentaires **français** abondants (le projet est un support d'apprentissage).
- Pas d'URL IPTV en dur dans le code de prod ; couleurs/tailles via tokens.
- Ne **jamais** toucher la lecture cinéma / VOD.

---

## 7. Autres branches Fable à relire avant merge

- `claude/defew-tv-hardening-tbhlrw` — durcissement app TV (stabilité, crashes,
  géo, qualité/fluidité image, sécurité).
- `claude/independence-hardening-d51mdr` — **chevauche** le travail panel :
  **à relire avant merge** pour éviter les conflits.

---

*Fin du brief. Si tu veux, tu peux me donner TA procédure exacte pour le §5
(HTTPS + Caddy + compose) et je l'applique sur le VPS avec le maître.*
