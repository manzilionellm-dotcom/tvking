# TEST-MATRIX-MOBILE — 7 MOTION

Suite automatisée : `flutter test` (Flutter 3.44.8). Les tests sqflite
utilisent SQLite FFI. Ce qui n'est pas automatisable dans cet environnement
(pas d'appareil/émulateur) est marqué **manuel sur appareil** avec la
protection de code correspondante.

## Couverture automatisée (extrait pertinent au mobile)

| Domaine | Fichiers de test | Vérifie |
|---|---|---|
| Parsing M3U | m3u_parser, source_input_normalizer, source_link_utils | classification live/VOD, normalisation d'URL, tolérance |
| Xtream | xtream_client, xtream_account_info, xtream_url_format_store, xtream_url_variants | API, cascade de formats, 1-connexion |
| EPG | xmltv_parse_isolate, epg_alias_short_epg, **epg_resync_ids (NOUVEAU)**, **epg_dedup (NOUVEAU)** | isolate borné, pont d'alias, resync sur external_id, anti-doublon |
| Lecteur | hls_normalizer, hls_playback, one_connection_zapping, stream_blocked_fallback, playback_session_stats, cascade_real_path | fallback, zap 1-conn, taxonomie d'erreurs |
| Cast | 20+ fichiers (relay, remux fMP4, DLNA, discovery) | remux AC-3, reconnexion, transitions UPnP |
| Sécurité | secret_redactor, secret_cipher, app_pin_settings | caviardage (motifs élargis), chiffrement, PIN durci |
| Boot/état | boot_guard, device_memory, **remote_source_repository_dedup (NOUVEAU)** | anti-boucle, plafond RAM, dédup sync |
| VOD | vod_catalog_cache, playback_position_repository, vod_download_service, m3u_vod_classifier | cache, reprise, téléchargements |

Total suite : **664 tests verts** à la baseline ; **+5 tests** ajoutés par
l'audit (epg_resync_ids, epg_dedup, remote_source_repository_dedup, + les
tests des agents) → suite maintenue verte (chiffre final dans BUILD-REPORT).

## Scénarios manuels sur appareil (protection de code associée)

| Scénario | Protection en place | À vérifier terrain |
|---|---|---|
| Démarrage réseau coupé | boot défensif + défauts sûrs (audit M-C5) | pas d'écran noir |
| Retour d'arrière-plan en lecture | AppLifecycleState (audit M-H3) | audio coupé hors PiP, reprise OK |
| Rotation écran | lecteur gère les contraintes d'orientation | pas de crash, état conservé |
| Réseau lent / perte / mode avion | timeouts, watchdogs, retry typé | erreur utile + CTA, pas de spinner infini |
| Session expirée (401/403) | bouclier abonnement + refresh | message clair |
| Reprise de lecture VOD | position sauvée au zap/arrière-plan/dispose (M-H1/P7) | reprend au bon endroit |
| MAJ in-app | timeout + plafond + vérif taille (M-H11) | pas de boucle, pas d'APK tronqué |
| Gros catalogue (1k/5k/15k/30k) | pagination keyset + plafonds RAM + index v7 | scroll fluide, recherche, pas d'OOM |
| Écran chargement/vide/erreur | états gérés | jamais bloqué |
