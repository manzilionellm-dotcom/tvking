# Backend 7 MOTION — Cloudflare Worker

Mini backend serverless qui fait office de panneau admin pour assigner des
playlists IPTV (M3U ou Xtream Codes) à un client identifié par sa **MAC
virtuelle 7 MOTION** (`MK:XX:XX:XX:XX:XX`).

Remplace l'ancien hack GitHub Gist. Tourne sur le free tier Cloudflare —
**0 € / mois** pour des centaines de clients.

---

## Pourquoi Cloudflare Worker

- **Gratuit** : 100 000 requêtes/jour incluses. Largement assez.
- **Zéro maintenance** : pas de serveur à patcher, Cloudflare s'en occupe.
- **Rapide** : édge worldwide, 30 ms de latence partout.
- **Pas de carte bancaire** demandée pour le free tier.

---

## Déploiement — 15 min chrono

### 1. Crée un compte Cloudflare

https://dash.cloudflare.com/sign-up

(2 min. Email + mot de passe. Aucune CB.)

### 2. Installe la CLI Wrangler

Sur Mac/Linux/Windows depuis un terminal :

```bash
npm install -g wrangler
```

Puis log-toi :

```bash
wrangler login
```

(ouvre ton navigateur, te demande d'autoriser.)

### 3. Crée le KV namespace

Le KV (Key-Value store) sert à stocker les configs clients.

```bash
wrangler kv:namespace create "KV_7MOTION"
```

Ça affiche quelque chose comme :

```
✨ Add the following to your configuration file in your kv_namespaces array:
{ binding = "KV_7MOTION", id = "abc123def4567890" }
```

**Copie l'`id`** et colle-le dans `wrangler.toml` à la place de
`REMPLACE_MOI_PAR_L_ID_DU_KV`.

### 4. Définis ton secret admin

Choisis un mot de passe fort (pas un mot de dictionnaire) :

```bash
wrangler secret put ADMIN_SECRET
```

Wrangler te demande de taper le secret. Tape-le, valide. Il sera stocké
chiffré côté Cloudflare et **jamais committé dans Git**.

**Note ce secret quelque part** — tu vas en avoir besoin dans l'app 7 MOTION.

### 5. Déploie

```bash
wrangler deploy
```

Tu obtiens une URL du type :

```
https://seven-motion-backend.TON_PSEUDO.workers.dev
```

**Note cette URL** — tu vas la coller dans l'app 7 MOTION.

### 6. Teste rapidement

```bash
curl https://seven-motion-backend.TON_PSEUDO.workers.dev/
# → "7 MOTION worker is alive."
```

Et pour vérifier qu'il refuse bien sans auth :

```bash
curl https://seven-motion-backend.TON_PSEUDO.workers.dev/admin/clients
# → {"error":"unauthorized"}
```

### 7. Configure l'app 7 MOTION

Ouvre l'app → Réglages → Mode admin → tape ton PIN → dans la carte
"Connexion serveur" :

- **URL du serveur** : colle l'URL Worker (`https://seven-motion-backend.TON_PSEOUDO.workers.dev`)
- **Secret admin** : colle le mot de passe choisi à l'étape 4

Tape "Enregistrer et charger". La carte se replie en mini-badge vert et tu
peux commencer à ajouter des clients.

---

## Usage quotidien

Chaque nouveau client :
1. Tu reçois sa MAC par WhatsApp.
2. App → Mode admin → "+ Nouveau client" → colle MAC + nom + URL Xtream/M3U → Enregistrer.

Le client reçoit ses chaînes à sa prochaine sync auto (max 30 min) ou s'il
tape le bouton refresh dans son app.

---

## Mise à jour du Worker

Modifie `worker.js` localement puis :

```bash
wrangler deploy
```

Pas besoin de rien faire côté app — l'URL ne change pas.

---

## Sécurité

- Le `ADMIN_SECRET` est stocké chiffré chez Cloudflare. Si tu le perds,
  refais juste `wrangler secret put ADMIN_SECRET` avec un nouveau et
  mets-le à jour dans l'app.
- Le `KV_7MOTION` contient les URLs Xtream + mots de passe IPTV. Ne donne
  l'URL du Worker à personne — quiconque a l'URL **+** ton `ADMIN_SECRET`
  peut tout lire/modifier.
- Les routes `/config/:mac` (utilisées par les apps clientes) **n'exigent
  pas d'auth** — l'identifiant est le MAC. ~10^14 combinaisons en hex
  rendent le brute-force impraticable, mais si tu vois un MAC en clair
  quelque part (screenshot etc.), considère que ce client est compromis et
  régénère son MAC dans son app (Réglages → Mon appareil → Régénérer la MAC).

---

## Limites du free tier

- 100 000 req/jour gratuit. Au-delà : 0.50 $/million.
- KV : 1 000 writes/jour gratuit (largement assez pour des modifs admin).
- KV : 100 000 reads/jour gratuit (un client qui poll toutes les 30 min =
  48 reads/jour. 2 083 clients possibles sans payer un centime).

Au-delà : passe au plan payant à 5 $/mois, plafonds x10.
