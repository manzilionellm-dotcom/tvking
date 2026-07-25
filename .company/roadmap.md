# Roadmap — USINE APP v2 (périmètre mobile)

## Fait (runs 001-003)
- Bootstrap mémoire `.company/` + journal de run.
- Run 002 : observabilité vidéo S3 du lecteur mobile (taxonomie + agrégats).
- Run 003 (v3) : T2/S9 — caviardage des secrets dans TOUS les puits de logs
  (StructuredLogger + BlackBox + CrashReporting) ; allowBackup=false au
  manifeste build-android. QA 663/663.
- Baseline mesurée : analyze 0 err / 25 warn / 264 infos ; 647 tests verts.
- Sprint 1 : 20/20 warnings hors TV purgés (+ 2 fixes réels : anti-fuite
  caches Channel, garde anti multi-open du zap bouton).

## Prochains runs (ordre du graphe de dépendances USINE, adapté mobile)
1. **T1 Observabilité vidéo (S3)** : inventorier les métriques déjà émises
   (Boîte noire, CinePerf, structured_logger) vs la liste S3 (TTFF, zapping,
   rebuffering, taux de démarrage, taxonomie d'erreurs, watchdogs) ; combler
   les trous côté MOBILE (media_kit AnalyticsListener équivalent).
2. **T2 Sécurité mobile — reste** : FLAG_SECURE sur écrans sensibles mobile
   (lock/PIN — l'app principale n'a pas le patch FLAG_SECURE du flavor
   Privé), constat CI du patch allowBackup (run build-android sur la
   branche), audit tokens au repos (secret_cipher v2 existe — vérifier les
   chemins).
3. **T3 Deps** : traiter D4 (paquet discontinué + majeures bloquées),
   décision pubspec.lock (D1, partagée avec TV — demander au client).
4. **T5 Harnais S6 (mobile)** : scénarios réseau simulés exécutables en CI
   (émulateur requis — vérifier la faisabilité runner GitHub).
5. **T6 Perf + échelle S5 (mobile)** : banc `perf-bench` sur émulateur CI
   (démarrage à froid, scroll 20k chaînes, RAM plafonnée), budgets posés
   à la baseline AVANT toute optimisation.
6. **Infos analyze** : 264 infos restantes (prefer_const…) — descente
   progressive par petits lots, puis passer la CI Quality en mode strict
   (retirer --no-fatal-warnings) une fois à zéro.
7. **Dettes D2/D3/D5** (voir state.json).

## Hors périmètre (consigne client — ne pas toucher)
- Tout `lib/features/tv/`, `main_tv.dart`, builds/tags TV, Tizen, Windows.
