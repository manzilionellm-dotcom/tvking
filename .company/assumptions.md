# Hypothèses (run-001, 2026-07-25)
1. « Applications de TV Box seulement » = ce repo est traité comme l'app TV (UI 10-foot Next.js) ; les
   workflows mobiles `publish-phone-test.yml` / `publish-master.yml` et tout artefact « 7motion téléphone »
   ne sont PAS modifiés. Les workflows TV existants (`publish-cinema-test.yml`) ne sont pas modifiés non
   plus (ils publient l'APK d'un AUTRE repo/branche via run_id — hors périmètre de code ici).
2. Les builds APK TV (defew-tv) référencés par publish-cinema-test.yml vivent hors de cette branche ;
   MODULE S natif (Media3, codecs, DRM) ne s'applique pas au code présent — appliqué en équivalent web
   (focus D-pad, BACK, touches media, reprise persistée, états de lecteur).
3. Données de contenu = mock assumé (README l'annonce) ; on ne branche pas d'API réelle dans ce run.
4. MODULE D (teardown concurrents) et MODULE V (revenu) exigent des accès consoles/stores/analytics
   absents de ce repo → Tier B NON VÉRIFIÉ, exclus du rapport, reportés au backlog.
5. Pas de première publication production dans ce run → aucun point VALIDATION_HUMAINE déclenché,
   hormis le merge de la PR (laissé à l'humain — protection de main non configurable d'ici).
