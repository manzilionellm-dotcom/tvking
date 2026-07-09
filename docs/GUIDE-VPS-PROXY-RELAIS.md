# Guide simple — brancher un proxy (changer l'IP) et un relais (flux famille)

**Pour qui :** toi, le propriétaire. Aucune compétence de développeur nécessaire.
**Ce que tu vas obtenir :**
1. Un **proxy dans un pays** → pour dépanner un client qui voyage (fonction « Changer l'IP »).
2. Un **relais** → pour l'option **famille flux mutualisé** (1 connexion fournisseur par chaîne).

Les deux se collent dans le panel, page **Réseau & localisation**. Tu ne fais ça qu'**une fois par serveur**, ensuite tout se pilote d'un clic.

---

# PARTIE 1 — Un proxy pays (fonction « Changer l'IP »)

> Rappel : pour dépanner Marie (abonnement ouvert en France, elle voyage au
> Canada), il te faut un proxy **en France** (le pays de son abonnement).

## Option A — Le plus simple : louer un proxy (rien à installer)

Des services te donnent tout de suite une adresse prête à coller. Cherche
« **proxy France** » chez un de ces types de fournisseurs :

- **Proxys datacenter** (les moins chers, ~1-3 €/mois par IP) : suffisant
  dans la plupart des cas. Fournisseurs connus : Webshare, IPRoyal, Proxy-Cheap.
- **Proxys résidentiels** (plus chers, ~par Go) : une vraie IP « maison »,
  utile si le fournisseur IPTV bloque les IP datacenter.

Tu obtiens 4 informations : **hôte**, **port**, **utilisateur**, **mot de passe**.
Tu les assembles ainsi :

```
http://UTILISATEUR:MOTDEPASSE@HOTE:PORT
```

Exemple : `http://marie123:x9f2@fr-proxy.webshare.io:80`

## Option B — Un VPS + installer un proxy (moins cher, un peu technique)

1. Loue un **VPS en France** (Hetzner, Contabo, OVH… ~3-5 €/mois). Choisis
   Ubuntu. Tu reçois une IP et un accès SSH.
2. Installe un proxy léger. Le plus simple, **3proxy** ou **Squid**. Exemple
   Squid en 3 commandes (connecté au VPS en SSH) :
   ```bash
   sudo apt update && sudo apt install -y squid apache2-utils
   # crée un identifiant proxy (remplace "marie" par ce que tu veux)
   sudo htpasswd -c /etc/squid/passwd marie
   # (colle ce bloc d'auth basique — le README détaillé peut t'aider)
   ```
   *(Si tu ne veux pas toucher à ça, reste sur l'Option A — c'est fait pour.)*
3. Ton adresse à coller : `http://marie:TONMOTDEPASSE@IP_DU_VPS:3128`

## Coller dans le panel

1. Panel → **Réseau & localisation** → colonne **Sorties prédéfinies** → **Ajouter**.
2. **Label** : `France 🇫🇷` — **Proxy** : l'adresse ci-dessus. **Enregistrer**.
3. C'est disponible pour tous tes clients. Refais-le pour chaque pays voulu.

Ensuite, pour dépanner un client : **Ctrl+K** → colle sa MAC → **« Changer
l'IP »** → choisis le pays → **Appliquer**. Réglé en quelques secondes.

---

# PARTIE 2 — Un relais (option famille « flux mutualisé »)

> Rappel : le relais tire une chaîne **une seule fois** et la distribue à
> toute la famille qui regarde **cette** chaîne → 1 connexion fournisseur
> par chaîne, pas par appareil. Le code est déjà prêt dans le projet
> (`server/cast-remux`).

## Étape 1 — Un VPS

N'importe quel petit VPS (Hetzner / Contabo / OVH, ~3-5 €/mois, 1-2 vCPU,
Ubuntu/Debian). Installe Docker (une seule commande, connecté en SSH) :
```bash
curl -fsSL https://get.docker.com | sh
```

## Étape 2 — Un nom de domaine (pour le https)

Le relais doit être en **https** (obligatoire pour l'app). Il te faut un
petit sous-domaine qui pointe sur l'IP du VPS, par ex. `relais.tondomaine.com`
(un enregistrement DNS « A » vers l'IP du VPS). Si tu as déjà un domaine chez
Cloudflare/OVH, ça se fait en 1 minute.

## Étape 3 — Lancer le relais

Sur le VPS, récupère le dossier `server/cast-remux` du dépôt, puis :
```bash
cd cast-remux
cp .env.example .env
# édite .env : mets ton domaine (ex. relais.tondomaine.com) pour le https Caddy
docker compose up -d
```
Caddy obtient tout seul le certificat https (Let's Encrypt) en ~30 secondes.
Vérifie : ouvre `https://relais.tondomaine.com/health` dans un navigateur →
tu dois voir `ok`.

*(Le README dans `server/cast-remux/` détaille chaque ligne.)*

## Étape 4 — Coller dans le panel

1. Panel → **Réseau & localisation** → carte **Flux mutualisé**.
2. Colle `https://relais.tondomaine.com` → **Enregistrer le relais**.
3. Sur les appareils d'une famille : coche **« Flux mutualisé (option
   famille) »**. La case n'est plus grisée dès que le relais est enregistré.

---

# Résumé ultra-court

| Tu veux… | Il te faut… | Où le coller |
|---|---|---|
| Changer le pays/IP d'un client | un **proxy** dans ce pays (loué ou VPS) | Réseau & localisation → Sorties prédéfinies |
| Famille = 1 connexion par chaîne | un **relais** `cast-remux` (VPS + Docker + https) | Réseau & localisation → Flux mutualisé |

**Coût indicatif :** un proxy France ~1-3 €/mois + un VPS relais ~3-5 €/mois.
Une fois branchés, tout se pilote depuis le panel, sans jamais retoucher au
serveur.

**Important :** les clients doivent avoir la **dernière version de l'app**
(code Downloader TV `6248618`) — le routage réseau et le flux mutualisé
vivent dans l'app.
