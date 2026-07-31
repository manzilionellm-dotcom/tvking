# SPORTS-AUDIT — État réel du dépôt avant le Centre Sportif

Date : 2026-07-31 · Branche : `claude/port-tvking-7motion-cb4ee9`
Règle appliquée : chaque affirmation cite un fichier réel du dépôt.

## Ce qui EXISTE déjà (preuves)

| Capacité | Preuve | État |
|---|---|---|
| Données sportives (équipes, matchs, scores) | `cloudflare/worker.js:502` (`_SPORTSDB`, proxy TheSportsDB, clé gratuite `/3`), routes `/api/sports/search` et `/api/sports/team/:id` (`worker.js:664,692`), cache 10 min | ✅ en prod |
| Dépôt app multi-équipes favorites | `lib/features/sports/data/sports_repository.dart` (persistance `sports.favorites.v2`, refresh 10 min, streams) | ✅ |
| Modèles | `lib/features/sports/domain/sport_models.dart` (`SportTeam`, `SportEvent` : score, date, statut, ligue) | ✅ |
| Rappels avant-match (~1 h) | `sports_repository.dart` → `_scheduleReminders` + `core/notifications/notification_service.dart` | ✅ (notifications LOCALES, pas de FCM) |
| UI TV (D-pad complet) | `lib/features/tv/presentation/tv_sports_screen.dart` (480 l.), `tv_team_picker_screen.dart` (404 l.) | ✅ |
| UI téléphone | `lib/features/sports/presentation/sports_screen.dart` + entrée barre du bas (`simple_home_screen.dart`) | ✅ ajouté par ce lot |
| i18n (8 langues, RTL arabe) | `lib/l10n/app_*.arb` — clés `tvSport*`, `genreSports`, `catSport` déjà traduites | ✅ |
| Panel admin + audit log | `admin-panel/src/` (31 pages), `cloudflare/api_v1.js` (`logAudit`) | ✅ |
| Affiliation générique + stats clics | table `ad_campaigns`, page « Affiliation & Pubs » (`AffiliationPage.tsx`), carte app (`affiliate_card.dart`) | ✅ (lot précédent) |
| Temps réel serveur→app | `cloudflare/realtime.js` (Durable Object WebSocket), `lib/core/realtime/realtime_sync_service.dart` | ✅ (config/annonces — PAS des incidents sportifs) |

## Ce qui N'EXISTE PAS (et pourquoi)

| Manque | Cause racine |
|---|---|
| Scores minute-par-minute, alertes de BUT en direct | TheSportsDB gratuit n'a **pas de flux d'incidents temps réel** (pas de push, rafraîchissement limité). Aucun fournisseur payant (API-Football, Sportradar, Sportmonks) n'est souscrit — voir SPORTS-DATA-PROVIDERS.md. **Bloqué sur une décision d'achat, pas sur du code.** |
| Notifications push serveur (FCM) | Aucune intégration FCM dans le dépôt (`grep -ri firebase lib/ → 0 résultat` hors commentaires). Les rappels actuels sont des notifications locales programmées. |
| Cotes / bookmakers | Aucun fournisseur de cotes, aucun contrat d'affiliation opérateur. Interdit de l'inventer (règle 1 du prompt). |
| Classements, statistiques détaillées, joueurs | Non couverts par les 2 routes proxy actuelles. |
| Overlay sportif pendant la lecture | Non implémenté (dépend d'un vrai flux live pour être utile). |

## Décision d'architecture prise

Phase 1 livrée avec les données réellement disponibles (TheSportsDB gratuit,
proxy Worker existant) : recherche internationale d'équipes, favoris
persistés, dernier/prochain match avec score, rappels avant-match, sur
téléphone ET TV. La fraîcheur est affichée (heure du dernier sync) — on ne
prétend jamais faire du temps réel avec une source qui n'en fait pas.

Les phases 2-4 (alertes de but, overlay, cotes, affiliation opérateurs)
sont conditionnées aux décisions listées dans SPORTS-DATA-PROVIDERS.md et
SPORTS-COMPLIANCE.md.
