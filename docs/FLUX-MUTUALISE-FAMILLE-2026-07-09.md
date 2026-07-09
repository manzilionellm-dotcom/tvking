# Option famille « flux mutualisé » — 1 connexion fournisseur pour N spectateurs

**Branche :** `claude/tvking-admin-panel-redesign-zt8js5`
**Besoin :** l'option famille partage une ligne Xtream sur plusieurs appareils, mais le fournisseur limite les connexions **simultanées** (souvent 1). Sans mutualisation, 5 appareils = 5 connexions = saturé.

---

## La vérité physique (à connaître)

La mutualisation ne réduit à **1 flux** que les spectateurs d'une **même chaîne** en même temps :

- Toute la famille sur le **même match** → **1 connexion** fournisseur. ✅
- 5 personnes sur 5 **chaînes différentes** → **5 connexions** (contenus différents — impossible à réduire, personne ne sait faire ça).

Formulation exacte : **« 1 connexion par chaîne regardée »** au lieu de « 1 par appareil ».

## Comment ça marche

Un **relais central** (`server/cast-remux`, déjà dans le dépôt) :
1. tire **une seule fois** le flux d'une chaîne depuis le fournisseur (`ffmpeg -c copy`, ~1-2 % CPU, pas de ré-encodage),
2. le redistribue en **HLS-fMP4** à tous les appareils qui regardent cette chaîne (clé de mutualisation = l'URL upstream).

Les appareils en « flux mutualisé » lisent donc `<relais>/live/<b64url(flux)>/master.m3u8` au lieu de taper le fournisseur. Le fournisseur ne voit que **le relais** → 1 connexion par chaîne.

## Côté panel (déjà en ligne au build)

Page **Réseau & localisation** :
1. **Flux mutualisé (owner)** : colle l'URL https de ton relais `cast-remux`. Vide = fonction OFF partout.
2. **Par appareil** : coche « Flux mutualisé (option famille) » sur les appareils d'une famille. Livraison instantanée (< 20 s, sans redémarrage).

La case est grisée tant qu'aucun relais n'est configuré.

## Côté app (nécessite le nouveau build)

- Singleton `FamilyRelay` (base du relais, livrée via `/api/device-net`, champ `relay`).
- `FamilyRelay.wrapLive(url)` réécrit une URL de **live** vers le relais (le VOD/replay reste direct — pas d'enjeu de connexions simultanées).
- Branché dans les deux lecteurs, en **bypassant le relais local** (le central fait déjà le tuyau) :
  - **Mobile** (`video_player_screen`, mpv) : ouvre directement l'URL relais.
  - **TV** (`tv_player_screen`, ExoPlayer) : idem, HLS-fMP4 lu nativement.
- Guardé : relais vide → lecture directe, comportement identique à aujourd'hui (zéro régression).
- Windows/Tizen : non routés dans cette itération (usage famille = téléphones + TV) — à ajouter si besoin.

## Backend

| Route | Rôle |
|---|---|
| `GET/PUT /api/v1/family-relay` | Base https du relais (owner) |
| `PUT /api/v1/device-net/:mac` `{ shared: true/false }` | Active/coupe le flux mutualisé d'un appareil (cap `sources`) |
| `GET /api/device-net/:mac` | Public — renvoie `relay` (non vide seulement si l'appareil est en flux mutualisé ET qu'un relais est configuré) |

Colonne `device_net.shared_stream` (ALTER auto). Config `app_config.family_relay_base`. Le relais DOIT être en https. Bump de synchro + webhook `device.exit_changed` à chaque changement.

## Déployer le relais (rappel)

1. Un petit VPS (Hetzner/Contabo/OVH ~3-5 €/mois), Docker installé.
2. `server/cast-remux` : `docker compose up -d` (Caddy fournit le https Let's Encrypt automatiquement — voir le README du dossier).
3. Panel → Réseau & localisation → Flux mutualisé → colle `https://ton-relais…` → Enregistrer.
4. Coche « flux mutualisé » sur les appareils de la famille.

## Vérifications

Panel build OK ; worker `node --check` + smoke tests **13/13** ; revue de compilation Dart des 5 fichiers touchés. La validation **streaming réelle** (débit, mutualisation effective) se fait sur ton relais/tes appareils — elle ne peut pas être simulée hors ligne.

## Modèle commercial

Tu vends une ligne fournisseur « 1 connexion » comme une **offre famille 5 écrans** tant qu'ils regardent la même chaîne (typique : le sport en famille). C'est exactement ce que font les revendeurs « premium ».
