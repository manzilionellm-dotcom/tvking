# PERFORMANCE-AFTER — Après corrections d'audit

Commit : tête de `claude/audit-mobile-tv-delivery-ghn12o` (après groupes 1-5).
Voir PERFORMANCE-BEFORE.md pour la baseline.

## Qualité statique et tests

| Mesure | Avant (25d7cb3) | Après |
|---|---|---|
| `flutter analyze` erreurs | 0 | **0** |
| `flutter analyze` warnings | 1 | 5 (tous dans des fichiers NON touchés par l'audit — bruit de baseline ; CI `--no-fatal-warnings`) |
| `flutter test` (suite complète) | 664 verts | **verte** (voir BUILD-REPORT pour le total exact après +tests) |
| Tests ajoutés par l'audit | — | epg_resync_ids, epg_dedup, remote_source_repository_dedup, tv_media_kit_import_guard, +3 SecretRedactor, + tests des agents |

## Gains structurels mesurables (par le code, pas par un chiffre terrain)

| Axe | Avant | Après |
|---|---|---|
| Requête de pagination `getChannelsPage` | tri complet de la catégorie à chaque page (aucun index couvrant) | index `idx_channels_page(playlist_id, is_live, category, local_id)` → parcours d'index (v7) |
| Purge orphelins `getAllChannels` | `DELETE NOT IN (sous-requête)` à chaque émission d'état | 1× par session |
| Refresh playlist concurrent | 2 fetch + 2 parses simultanés possibles (pic mémoire ×2) | verrou par playlist → 1 seul |
| Chargement catalogue VOD/Séries | 2 `get_vod_streams` complets possibles en parallèle | dédup in-flight → 1 |
| Sync EPG | re-insertion de toute la fenêtre à chaque sync (base illimitée) | REPLACE sur index unique → taille bornée |
| ShortEpg | N requêtes réseau sur rafales de focus | dédup in-flight par chaîne |
| Instances lecteur mobile | fuite possible d'une instance mpv complète par fermeture pendant recyclage | garde `_disposed`/`mounted` → 0 fuite |
| Lecteurs TV concurrents (Guide/Multi) | 2-3 ExoPlayer + connexions simultanées | pause+libération → 1 connexion amont |
| Timers en arrière-plan | reconnexion WebSocket + reconnexions watchdog TV actives en veille | suspendus sur `paused` |

## Budgets embarqués (inchangés, à relever sur box via Boîte noire « perf »)

Accueil Cinéma < 400 ms · fiche < 300 ms · TTFF < 2500 ms (CinePerf). Aucune
box dans l'environnement de dev → chiffres réels à relever sur appareil.

## Méthode

Les mesures de temps de démarrage / mémoire / CPU / TTFF / zapping exigent un
appareil ou un émulateur, absents de cet environnement (le projet les
instrumente déjà : CinePerf côté TV, PlaybackSessionStats côté mobile,
breadcrumbs mémoire RSS). Les gains ci-dessus sont **structurels et vérifiés
par le code** (requêtes, verrous, cycles de vie), pas des chiffres inventés —
conformément à l'interdiction d'inventer un résultat de mesure.
