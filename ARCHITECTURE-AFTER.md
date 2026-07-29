# ARCHITECTURE-AFTER — Après corrections d'audit

L'architecture n'a **pas** été réécrite (interdiction du cahier des charges :
préserver la richesse existante). Les corrections sont ciblées et renforcent
les invariants déjà en place. Voir ARCHITECTURE-BEFORE.md pour la structure
de départ.

## Ce qui a changé (invariants renforcés)

### Séparation mobile / TV
- Invariant « aucun media_kit atteignable depuis `main_tv.dart` » désormais
  **verrouillé par un test automatisé** (`tv_media_kit_import_guard_test.dart`)
  qui recalcule la fermeture transitive d'imports à chaque CI, au lieu de
  reposer sur une convention.

### Couche données
- Écritures de refresh de playlist rendues **atomiques** (transaction
  DELETE+INSERT) et **sérialisées par playlist** (verrou in-flight) — plus de
  fenêtre « source vide » ni de double import concurrent.
- Sélection de la source Cinéma/Séries corrigée sur la **playlist active**
  (au lieu de la plus récente) — cohérence live/VOD garantie.
- Déduplication in-flight généralisée (VOD, Séries, ShortEpg,
  RemoteSourceRepository) : une requête réseau en cours est partagée, pas
  dupliquée.
- Schéma SQLite v7 : index couvrant la pagination + unicité EPG. Purges
  lourdes ramenées à une fois par session.

### Cycle de vie / démarrage
- Chemin de boot mobile aligné sur le modèle TV : jalons BootGuard + branche
  SafeMode (le disjoncteur anti-boucle fonctionne enfin sur mobile).
- Boot défensif : échec de préférences → défauts sûrs + `runApp` garanti (fin
  de l'écran noir permanent).
- Lecteur mobile : gestion `AppLifecycleState` ajoutée (pause hors
  PiP/cast/audio, sauvegarde de position) — parité avec le lecteur TV.

### Observabilité / sécurité
- Le caviardage des secrets couvre désormais **les 4 puits** (la fuite vers
  le backend Firebase est refermée) et davantage de motifs (en-têtes,
  paramètres, chemins sans extension).
- Plan de contrôle serveur **fail-closed** : plus aucun secret de repli
  (`dev-secret`/`change-me`), comparaisons à temps constant.

## Diagramme de dépendances (inchangé, rappel)

```
main.dart ─┐                         main_tv.dart ─┐
main_prive ─┼─ core/ (app, backend,   (ExoPlayer via  │
main_windows┤   crash, net, update,   registerTvPlayer)│
main_tizen ─┘   observability, …)                     │
                     │                                 │
        features/ ───┴── playlists · channels · epg · vod · player(mobile
                         media_kit) · tv(ExoPlayer) · cast · recordings ·
                         subscription · device · settings · …
                     │
        packages/native_video_player (TV)  ·  packages/tvking_device
                     │
        cloudflare/ (Worker + D1/KV)  ·  admin-panel/ (SPA)
```

Aucune dépendance circulaire introduite ; aucun module mobile tiré dans la
fermeture TV ; aucune nouvelle dépendance lourde ajoutée.
