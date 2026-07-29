# AUDIT-MOBILE — 7 MOTION (Android, `lib/main.dart`, lecteur media_kit)

Date : 2026-07-29 · Commit audité : `25d7cb3` · Méthode : revue de code
exhaustive (points d'entrée, lecteur, données/réseau/cache, cycle de vie,
sécurité) + baseline outillée (analyze, 664 tests, CI).
Statut de chaque constat : **CORRIGÉ** (commit dans cette branche) ou
**DOCUMENTÉ** (reporté au backlog avec justification).

## Critiques

| ID | Constat | Fichier | Statut |
|---|---|---|---|
| M-C1 | Resync EPG périodique morte depuis toujours : requête sur colonne `id` inexistante, exception avalée par `catch (_)` — le guide se vidait en ~48 h | playlists/data/playlist_repository.dart | **CORRIGÉ** + test |
| M-C2 | Table `epg_programs` sans unicité ni purge de fenêtre : doublait à chaque sync (guide en double, base illimitée) | epg/data/epg_repository.dart | **CORRIGÉ** + test |
| M-C3 | Fuite d'une instance mpv complète (player + texture + 10 abonnements) si l'écran est fermé pendant `_recyclePlayer()` | player/presentation/video_player_screen.dart | **CORRIGÉ** |
| M-C4 | Aucune garde anti double-ouverture du lecteur : double-tap = 2 mpv + 2 connexions fournisseur | player/presentation/play_channel.dart | **CORRIGÉ** |
| M-C5 | Écran noir permanent si SharedPreferences échoue avant `runApp` (3 initialize sans try/catch, le filet global log-et-retourne) | core/i18n, core/theme, onboarding/data | **CORRIGÉ** |
| M-C6 | `RemoteSourceRepository.sync()` : check-then-act sans verrou, appelé par 5 boucles concurrentes (timer 5 min, sondages 6-8 s, WebSocket, boot) → double import + pic mémoire doublé | playlists/data/remote_source_repository.dart | **CORRIGÉ** + test |

## Hauts

| ID | Constat | Statut |
|---|---|---|
| M-H1 | Borne anti-spinner du lecteur neutralisée par `_isPlaying` (mpv émet playing avant toute frame) → spinner infini sans CTA sur flux muets | **CORRIGÉ** |
| M-H2 | EOF live avec budget de reconnexions épuisé → impasse silencieuse (image figée, ni erreur ni CTA ni log) | **CORRIGÉ** |
| M-H3 | Aucune gestion AppLifecycleState du lecteur mobile : audio/connexion continuent en arrière-plan hors PiP ; position VOD perdue si l'OS tue l'app | **CORRIGÉ** |
| M-H4 | Téléchargement XMLTV sans timeout → verrou `_syncing` collé pour toute la session | **CORRIGÉ** |
| M-H5 | Sync EPG via client HTTP standard (TLS strict, pas de DoH) alors que l'URL vit sur le même panel que le M3U → échec systématique sur panels à certificat maison | **CORRIGÉ** |
| M-H6 | Cache statique `SmartSearch._docCache` non borné, jamais invalidé (dizaines de Mo immobilisés à vie) | **CORRIGÉ** |
| M-H7 | `refreshStale` contournait le mutex de `refreshAll` → double fetch/parse de la même playlist | **CORRIGÉ** (verrou par playlist) |
| M-H8 | Refresh : DELETE puis INSERT hors transaction → fenêtre « source vide » ~25 s + perte de données si crash au milieu | **CORRIGÉ** |
| M-H9 | Cinéma/Séries servis par la playlist Xtream la plus récente, jamais la playlist ACTIVE → catalogue du mauvais compte | **CORRIGÉ** |
| M-H10 | Rotation UA × boucle de catégories : jusqu'à ~1400 requêtes sans backoff sur panel qui rate-limite | **DOCUMENTÉ** (B-10 : refonte du retry XtreamClient, à tester contre panels réels) |
| M-H11 | Updater in-app : ni timeout, ni plafond de taille, ni vérif `received == contentLength` avant de lancer l'installateur | **CORRIGÉ** |
| M-H12 | Disjoncteur anti-boucle (BootGuard) neutralisé sur mobile (shim déprécié 8 s) — SafeModeApp jamais monté | **CORRIGÉ** (jalons + branche safe mode, modèle TV) |
| M-H13 | Splash infini si une préférence échoue au premier écran (3 futures sans catchError) | **CORRIGÉ** |
| M-H14 | Sondage d'activation mort après un import raté (`cancel()` sans remise à null puis `??=`) | **CORRIGÉ** |
| M-H15 | Crash backend Firebase recevait l'erreur BRUTE (identifiants dans l'URI) hors caviardage SecretRedactor | **CORRIGÉ** |
| M-H16 | Changement de profil : 8 dépôts sur 9 gardent l'état mémoire du profil précédent et écrasent les données du nouveau à la première écriture | **DOCUMENTÉ** (B-11 : refonte transverse des 8 dépôts — risque de régression trop large pour ce lot ; modèle correct dans WatchStatsService) |
| M-H17 | MAJ auto : téléchargement + installateur ouverts sans consentement (y compris données mobiles) | **DOCUMENTÉ** (décision produit — le canal téléphone est coupé et les box sideload dépendent de la MAJ silencieuse) |

## Moyens / bas (sélection)

- Budget watchdog non réinitialisé au zap/retry (**CORRIGÉ**) ; position VOD sauvée au zap/arrière-plan (**CORRIGÉ**) ; watchdog anti-gel restreint au live (**CORRIGÉ**) ; gardes `mounted` sur toasts l10n post-await (**CORRIGÉ**) ; écriture `_adoptedAltUrl` après await sans garde de génération (**CORRIGÉ**) ; timers globaux jamais suspendus en arrière-plan (**PARTIEL** : reconnexion WebSocket suspendue ; AppSchedulers global → B-12) ; deux systèmes de MAJ concurrents, versionCode mobile ≠ epoch TV (**DOCUMENTÉ** B-13 : unification à faire au moment d'une release maison mère) ; `buildNumber` illisible → boucle de MAJ perpétuelle (**CORRIGÉ**) ; dédup in-flight VOD/Séries/ShortEpg (**CORRIGÉ**) ; sondes de calibration parallèles sur compte 1-conn (**DOCUMENTÉ** B-14) ; `MediaKit.ensureInitialized()` bloquant au boot mobile (**DOCUMENTÉ** B-15 : init paresseuse, à valider sur appareil) ; index de pagination SQLite (**CORRIGÉ**, v7) ; purge orphelins 1×/session (**CORRIGÉ**) ; recherche `LIKE '%…%'` plein balayage (**DOCUMENTÉ** B-16 : FTS5) ; caches « LRU » en réalité FIFO (**DOCUMENTÉ** B-17).

## Points forts confirmés (à préserver)

Sérialisation des ouvertures du lecteur (`_openChain` + génération) ; instance
mpv jetable avec fermeture attendue ; `dispose()` du lecteur exemplaire
(9 timers, subs, wakelock, orientation) ; debounce de zap 400 ms + backoff
typé par statut HTTP ; discipline isolate + `TransferableTypedData` sur tout
le travail lourd ; bornes mémoire de bout en bout (`DeviceMemory`, streaming
plafonné, pagination keyset) ; filet d'erreurs global 4 couches mutualisé ;
bouclier d'abonnement hors-ligne (fenêtre + high-water-mark anti-recul
d'horloge) ; chiffrement des identifiants au repos (Keystore matériel).
