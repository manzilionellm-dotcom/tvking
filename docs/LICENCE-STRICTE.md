# Licence stricte — anti-freeloader (7 MOTION)

## Trous trouvés (avant ce correctif)

| Trou | Effet |
|---|---|
| Grâce hors-ligne **30 jours** | Mode avion / Worker KO = TV gratuite un mois |
| Bouclier « le serveur se trompe » | Si D1 disait *expiré* mais le cache local `_paidUntil` était encore valide → l’app restait **payée** |
| Essai local 7 j au premier boot | Réinstall + hors-ligne = nouvel essai. Même en ligne, un GET `/api/status` **créait** une fiche (essai neuf) |
| `TvGate` : chaînes en cache + statut inconnu = accueil | Premiers frames / sync raté = live sans abo |
| Welcome TV à la place du verrou | Un expiré voyait le QR / collage M3U (mauvais message) |
| `device-source` livrait encore si **prêt** (`loaned`) | Propriétaire qui a prêté son abo continuait à recevoir les identifiants |
| Licence D1 `status=expired` avec `expires_at` futur | Traitée comme essai actif côté app |
| Heartbeat 6 h | Un ban/gel panel pouvait attendre des heures (box allumée) |

`ANDROID_ID` était déjà envoyé et indexé, mais **jamais relu** à la création de fiche : une nouvelle MAC (réinstall d’un vieux build à MAC aléatoire) = nouvel essai.

## Règle métier (app + Worker, même contrat)

On peut streamer **seulement si** :

1. licence D1 `status = active` **et** (`expires_at` null **ou** `expires_at > now`), **ou** essai Worker non expiré ;
2. **et** pas `block_status` gelé / banni, pas licence gelée / bannie, pas prêt (`loaned`).

Sinon : écran « abonnement requis / expiré / gelé / banni », **pas de player**, **pas de playlist utile** (`device-source` → `{ source: null, blocked }`).

## Grâce hors-ligne

- **6 heures** par défaut (`grace_hours` renvoyé par le Worker).
- Plafond app : **12 heures** (même si un vieux champ `grace_days` arrive).
- Un verdict serveur *négatif* **efface** le cache payant : on ne « survit » pas 30 j après expiration.

Documenté ici pour Lionel : un client payant sans Wi-Fi plus de 6–12 h verra le verrou jusqu’au prochain heartbeat OK. Ce n’est pas un bug, c’est le filet anti-freeloader.

## Essais et réinstall

- L’app dérive déjà la MAC depuis `ANDROID_ID` (stable entre réinstalls **si** l’ID Android ne change pas).
- Le Worker, au **heartbeat** (pas au GET status) : si `android_id` existe déjà → hérite `first_seen_at` + `block_status` (essai déjà consommé, ban/gel suit la box).
- **Limite** : reset usine / ROM qui change `ANDROID_ID` → nouvelle MAC, le Worker ne peut pas lier. Garde-fou possible plus tard : autre empreinte (build + modèle), hors scope.

## Revalidation (Firestick ~1 Go)

| Moment | Quoi |
|---|---|
| Cold start | `initialize()` (prefs) **avant** le 1er frame, puis heartbeat |
| Resume / sortie de veille | `ForegroundSync` + Realtime (debounce 8 min côté licence, 20 s côté sources) |
| Périodique | **45 min** (`syncIfStale`) |
| Pendant le live | heartbeat présence **3 min** (inchangé, déjà là) |
| Sondage sources | 60 s : si `blocked`, coupe l’état local tout de suite |

Pas de boucle agressive, pas de nouvel import playlist.

## Comment Lionel teste

### Device sans abo / essai fini

1. Box jamais activée dont l’essai panel est dépassé (ou Tarifs essai = 0 + `first_seen` ancien).
2. Ouvrir l’app → écran **verrou** (numéro de référence + « revérifier »), **pas** l’accueil chaînes.
3. Coller un M3U ne doit plus être proposé comme porte principale.

### Abo expiré

1. Sur une MAC payante, mettre `expires_at` dans le passé (ou ne pas renouveler).
2. Relancer **ou** attendre ≤ 1 min (sondage source) / résumé app.
3. Plus de live. `GET /api/device-source/<MAC>` → `blocked: "expired"`, `source: null`.

### Banni / gelé

1. Panel → Geler ou Bannir.
2. Au **prochain** check (résumé, 3 min si en lecture, 45 min max si idle) : lecture coupée, écran dédié.
3. Mode avion **après** le verdict : reste bloqué (cache `subscription.block`).

### Abo valide

1. Licence active non expirée → accueil + player OK.
2. Couper le Wi-Fi **moins de 6 h** → TV continue (grâce).
3. Recouper plus de 12 h → verrou jusqu’au retour réseau + heartbeat OK.

### Réinstall

1. Même box, désinstaller / réinstaller (sans reset usine).
2. Même `ANDROID_ID` → pas de nouvel essai si l’ancien est fini.
3. Si la MAC change encore (très vieux APK à MAC aléatoire) : le Worker rattache via `android_id`.

## Coordination PR admin (#24)

Même règle « licence active » : `status=active` + date. Le panel continue d’écrire `licenses` / `block_status` / essais 24h·48h·7j. Cette PR ne touche pas les filtres / renew / notes du panel (`api_v1.js`). Déployer le **Worker** (`worker.js`) avec ou juste après le panel.

## Fichiers clés

- `lib/features/subscription/data/subscription_state.dart`
- `lib/features/tv/presentation/tv_license_lock_screen.dart`
- `lib/features/subscription/presentation/license_playback_guard.dart`
- `cloudflare/worker.js` (`licenseAllowsPlayback`, `ensureD1Device`, `device-source`)
