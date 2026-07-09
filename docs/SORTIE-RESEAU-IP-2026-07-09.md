# Changer l'IP d'un client depuis le panel — « Sortie réseau »

**Branche :** `claude/tvking-admin-panel-redesign-zt8js5`
**Besoin métier :** un fournisseur IPTV verrouille souvent le compte Xtream sur UNE seule IP (la première qui se connecte). Quand le client voyage (Suède → Allemagne), le fournisseur voit une IP différente et coupe tout. L'admin doit pouvoir, à distance, faire passer ce client par une **sortie fixe** — sans que le client touche à rien.

---

## Comment ça marche

1. **L'admin déclare ses « sorties » une fois** (page Réseau & localisation → *Sorties prédéfinies*) : un label pays + un proxy. Ex. « Suède 🇸🇪 » → `http://user:pass@relais-se.mon-infra.net:8080`. Ce sont **tes** relais (loués ou hébergés) : c'est leur emplacement physique qui donne le « pays » vu par le fournisseur.
2. **L'admin assigne une sortie à un appareil** (par MAC), d'un clic. Ou « Direct » pour revenir à l'IP réelle.
3. **Livraison instantanée** : l'app applique la nouvelle sortie en moins de 20 s (via le poll `/api/sync`), sans redémarrage.
4. **Tout le trafic IPTV du client sort alors par cette IP** — le fournisseur voit une adresse fixe, où que voyage le client.

Accès rapide : palette **Ctrl+K** → colle une MAC → « Changer l'IP de MK:… ».

## Ce qui est routé par la sortie (côté app)

Le proxy est appliqué au **seul point de passage réseau IPTV** de l'app, donc de façon exhaustive et sans risque de régression (quand aucune sortie n'est assignée, tout reste en direct, à l'octet près) :

| Trafic | Chemin | Routé ? |
|---|---|---|
| Connexion Xtream, playlist, refresh, health-check | `createIptvHttpClient()` → `HttpClient.findProxy` | ✅ toutes plateformes |
| Sonde HLS / preflight | même client | ✅ (même IP que le flux — évite d'exposer une 2ᵉ IP) |
| Vidéo — mobile & Windows | lecteur **mpv** → propriété `http-proxy` | ✅ |
| Vidéo — TV (Android TV / Fire TV) en direct `.ts` | **relais local** (son upstream honore la sortie) | ✅ |
| Vidéo — TV en HLS `.m3u8` pur | ExoPlayer natif, lecture directe | ⚠️ non routé (voir ci-dessous) |

**Cas non couvert (documenté) :** sur la TV, une chaîne *live servie uniquement en HLS* est lue directement par ExoPlayer et ne passe donc pas par la sortie. En pratique l'app **préfère déjà le `.ts`** pour le live (comptes « 1 connexion »), donc le chemin dominant (relais TS) est couvert. Router aussi le HLS-direct TV demanderait une modification native (OkHttp DataSource dans `packages/native_video_player`) — à faire dans un second temps si un fournisseur ne sert que du HLS.

## Formats de proxy acceptés

- `http://host:port`
- `http://user:pass@host:port` (proxy authentifié — Basic)
- `socks5://host:port`

Le proxy est **validé** côté serveur (schéma + host + port). Un champ vide = « repasser en direct ».

## Sécurité

- Le proxy peut contenir des identifiants → l'endpoint public `/api/device-net/:mac` renvoie une réponse **privée** (pas de CORS `*`), et l'audit log ne journalise **jamais** le proxy complet (seulement « assigné / retiré » + le label).
- Rate-limit anti-énumération de MAC sur `/api/device-net/:mac` (bucket `dev`).
- Changer l'IP requiert la capacité `sources` (admin, ou revendeur autorisé) — c'est un geste de dépannage client.
- Webhook `device.exit_changed` émis à chaque changement (pour tes systèmes).

## Endpoints ajoutés

| Route | Rôle |
|---|---|
| `GET/PUT /api/v1/net-exits` | Sorties prédéfinies (owner) |
| `GET/PUT/DELETE /api/v1/device-net/:mac` | Sortie d'un appareil (admin / revendeur `sources`, + clé API scope `sources`) |
| `GET /api/device-net/:mac` | Public — l'app lit sa sortie (réponse privée) |

Table D1 `device_net` + clé `app_config.net_exits`, créées automatiquement au premier usage. Aucune migration manuelle. Bump de synchro + webhook à chaque changement.

## Déploiement

1. `cd cloudflare && npx wrangler deploy` (tables auto-créées).
2. Panel : déjà déployé au build.
3. **App** : le routage réseau nécessite le nouveau build (mobile + TV). Les apps actuelles ignorent la sortie et restent en direct — aucune rupture pendant la transition.

## Pour l'utiliser en pratique

1. Loue/héberge un proxy dans le pays voulu (beaucoup de revendeurs IPTV en ont déjà). Note son `host:port` (+ user:pass si protégé).
2. Panel → Réseau & localisation → ajoute-le comme sortie (« Suède 🇸🇪 »), enregistre.
3. Quand un client voyage et se fait couper : colle sa MAC, choisis la sortie du pays où son compte est autorisé, applique. En quelques secondes, ses chaînes reviennent.
