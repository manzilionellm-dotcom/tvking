# cast-remux — relais IPTV mutualisé (Cast + option famille)

Remux **MPEG-TS live → HLS-fMP4** (format lu nativement par tous les
Chromecast / Google TV / récepteur Cast par défaut, et par mpv/ExoPlayer).
`ffmpeg -c copy` : **aucun ré-encodage**, juste un changement de conteneur
→ ~1-2 % CPU par chaîne, un petit VPS suffit.

> **Double usage.** Ce service sert AUSSI de **relais de flux mutualisé**
> pour l'**option famille** : plusieurs appareils qui regardent la MÊME
> chaîne partagent UN seul ffmpeg → **une seule connexion** vers le
> fournisseur (au lieu d'une par appareil). Dans le panel, colle son URL
> https dans **Réseau & localisation → Flux mutualisé**, puis coche « flux
> mutualisé » sur les appareils de la famille. Limite physique : ça ne
> collapse que les spectateurs d'une même chaîne — 5 chaînes différentes =
> 5 connexions (contenus différents, impossible à réduire).

## Pourquoi ce service
Le récepteur Cast par défaut (Shaka) ne sait pas lire du MPEG-TS brut.
Un Worker Cloudflare ne peut pas transcoder (pas de ffmpeg). Ce service,
lui, tourne sur un VPS et produit le HLS-fMP4 que le Cast accepte.

## Ce qu'il fait
- `GET /live/<b64url>/master.m3u8` → lance (ou réutilise) un ffmpeg qui
  tire l'upstream et produit une playlist HLS-fMP4 live + segments.
- `<b64url>` = l'URL du flux Xtream encodée en **base64url** (l'app le
  fait automatiquement). Service **stateless** (pas de base de données).
- **Mutualisation** : plusieurs spectateurs d'une même chaîne partagent
  un seul ffmpeg. **Reaper** : un flux sans spectateur depuis 30 s est tué.

## Déploiement (5 minutes)

### 1. Un VPS
N'importe quel petit VPS (Hetzner / Contabo / OVH ~3-5 €/mois, 1-2 vCPU,
Ubuntu/Debian). Installe Docker :
```bash
curl -fsSL https://get.docker.com | sh
```

### 2. DNS
Crée un enregistrement **A** : `cast.7themotion.com` → IP du VPS.
(Si tu utilises Cloudflare pour le DNS, mets le nuage en **gris / DNS
only** pour ce sous-domaine — sinon Cloudflare proxifie et peut couper
les longs flux. Caddy gère le TLS lui-même.)

### 3. Lancer
```bash
git clone <ce repo> && cd server/cast-remux
cp .env.example .env
nano .env          # mets ton domaine + ton email
docker compose up -d --build
```
Caddy obtient le certificat HTTPS tout seul. Vérifie :
```bash
curl https://cast.7themotion.com/health      # -> ok
```

### 4. Brancher l'app
Dans `lib/features/cast/data/google_cast_transport.dart`, la constante
`_kCastRemuxBase` doit valoir `https://cast.7themotion.com` (ou ton
domaine). C'est déjà le défaut ; change-la si tu prends un autre domaine,
puis rebuild l'APK.

## Test rapide sans l'app
```bash
# encode une URL de flux en base64url
B64=$(python3 -c "import base64,sys;print(base64.urlsafe_b64encode(sys.argv[1].encode()).decode().rstrip('='))" "http://pro.best-iptvinreviews.com/Manzi/xxx/162257.ts")
curl -s "https://cast.7themotion.com/live/$B64/master.m3u8"
# doit renvoyer une playlist #EXTM3U ... .m4s
```

## Dimensionnement
- Chaque chaîne active = 1 ffmpeg `-c copy` ≈ 1-2 % CPU + un peu de RAM.
- Bande passante = somme des flux actifs (entrée + sortie). Un VPS à
  1 Gbps tient des dizaines de spectateurs simultanés.
- Les segments sont écrits en **tmpfs (RAM)** : rapide, rien sur le disque.

## Sécurité (optionnel mais conseillé)
Le service relaie n'importe quelle URL http(s) qu'on lui donne en
base64url. Pour éviter qu'il serve de proxy ouvert, tu peux :
- le laisser derrière ton domaine seulement (pas d'IP publique nue), et/ou
- ajouter un jeton signé (HMAC) dans le chemin — me demander si tu veux
  cette variante.
