# Backend — tenir 5 millions d'appareils (et plus)

## TL;DR
- Le **compute scale tout seul** : Cloudflare Workers tourne sur tout le réseau
  edge mondial, sans serveur à gérer. 5M de téléchargements ne posent **aucun**
  problème de capacité de calcul.
- Le vrai sujet, c'est le **stockage** (D1) sur le **chemin chaud** = le
  `heartbeat` envoyé périodiquement par chaque app.

## Déjà en place dans le worker
- **Schéma + index initialisés une seule fois par isolat** (`ensureScaleSchema`,
  `_presenceReady`) au lieu d'un `CREATE TABLE`/`ALTER` à chaque heartbeat.
- **Index D1** : `presence(last_seen)`, `presence(channel)`, `devices(last_seen_at)`,
  `devices(android_id)`, `devices(reseller_id)`, `licenses(device_id)`.
- **Cache « Tendances »** en mémoire d'isolat (`_trendingCache`).
- **Écritures best-effort en arrière-plan** (`ctx.waitUntil`) : `recordPresence` et
  `updateDeviceInfo` ne bloquent plus la réponse du heartbeat → latence ↓,
  contention D1 ↓ (la réponse ne dépend plus que de `ensureD1Device` +
  `d1StatusForMac`).

## À faire AVANT un vrai pic à 5M (par ordre d'impact)

1. **Réduire la fréquence des heartbeats (côté app).** Le plus gros levier.
   60 s × 5M = ~83 000 écritures/s. Passer à **1 / 15–30 min** → charge ÷15–30.
2. **Cache edge sur les GET de lecture** (`/config/:mac`, `/api/theme`,
   `/api/pricing`, `/api/app-version`, `/api/announcement`, `/api/home-layout`,
   `/api/featured`) avec `Cache-Control: s-maxage` + `caches.default` → les
   lectures massives sont servies par l'edge, **zéro** touche D1.
3. **Présence → store de volume.** À 5M, remplacer les `UPSERT` D1 unitaires de
   `presence` par **Workers Analytics Engine** (millions d'événements/s) ou des
   **Durable Objects** d'agrégation. Garder D1 pour les licences (lecture++/écriture--).
4. **Surveiller les quotas D1** (taille base, débit d'écriture) → points 1 et 3.
5. **Rate limiting** sur `/api/heartbeat` (Cloudflare Rate Limiting ou Durable
   Object) contre les clients buggés/abusifs.

## Ce qui ne change PAS
- Aucune URL de flux ni playlist en dur (règle projet). Le backend ne sert que
  activation / présence / config / annonces.
- Aucune donnée sensible supplémentaire collectée.

> ⚠️ Toutes ces optimisations prennent effet au prochain `wrangler deploy`
> (déploiement manuel).
