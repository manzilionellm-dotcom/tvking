# SPORTS-ARCHITECTURE — Centre Sportif : existant + cible

## Flux actuel (Phase 1, livré)

```
TheSportsDB (gratuit)
      ↓  (clé côté serveur, cache 10 min)
Worker Cloudflare  /api/sports/search · /api/sports/team/:id
      ↓  HTTPS (kSubscriptionBaseUrl, failover backend_hosts.dart)
SportsRepository (lib/features/sports/data/)
  · favoris persistés (SharedPreferences, sports.favorites.v2)
  · refresh 10 min + streams (favoritesStream / changesStream)
  · rappels locaux ~1 h avant match (NotificationService)
      ↓
UI téléphone : sports_screen.dart (barre du bas → « Sport »)
UI TV        : tv_sports_screen.dart + tv_team_picker_screen.dart (D-pad)
```

## Cible Phase 2+ (quand un fournisseur live sera souscrit)

```
Fournisseur officiel (API-Football / Sportmonks / TheSportsDB Premium)
      ↓
Worker : ingestion (cron trigger) → normalisation (ids internes)
      → déduplication d'incidents (event_id unique, corrections)
      ↓
D1 : events / event_incidents / user_favorite_teams / notification_logs
      ↓
RealtimeHub (Durable Object EXISTANT, cloudflare/realtime.js)
      → push WebSocket vers apps ouvertes (bandeau non intrusif)
FCM (À AJOUTER) → notifications app fermée (BUT — équipe, score, minute)
```

Réutilisation maximale : le canal temps réel Durable Object existe déjà
(il pousse les changements de config/annonces) ; les incidents sportifs
seraient un nouveau `scope` du même hub. La déduplication suit le modèle
déjà éprouvé des annonces (id serveur monotone + id « déjà vu » local).

## Principes tenus

- Pas de sport codé en dur : tout vient de la recherche fournisseur.
- L'UI ne montre que ce que la source alimente réellement.
- Lecture vidéo intouchée : le Centre Sportif est un écran séparé ;
  aucun changement dans `video_player_screen.dart` / `tv_player_screen.dart`.
- Feature flags : l'entrée Sports téléphone peut être coupée via le panel
  (Home Manager pilote déjà les sections de l'accueil) ; flags dédiés
  (`odds_enabled`, etc.) à créer en Phase 3 dans `app_config` (clé/valeur
  D1 existante, diffusée en temps réel — même mécanique que la pub vidéo).
