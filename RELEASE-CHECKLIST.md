# RELEASE-CHECKLIST — Publier une version (mobile ou TV)

## Avant tout build

- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings` → 0 erreur
- [ ] `flutter test` → suite complète verte (ou CI `Quality` verte)
- [ ] `pubspec.yaml` : version/build bump si publication client
- [ ] Aucun secret dans le diff (`git diff` relu ; SecretRedactor intact)
- [ ] Vérifier qu'aucun import `media_kit` n'est atteignable depuis
      `lib/main_tv.dart` (contrainte build TV)

## Build de TEST (sans toucher aux clients)

1. Dispatch `Build Android APK` (`build-android.yml`) sur la branche —
   `make_release=false`. Noter le `run_id`.
2. Dispatch `Build DeFew TV (APK)` (`build-tv.yml`) sur la branche.
   Noter le `run_id`.
3. Attendre les runs VERTS (barrière : un APK non produit = pas de suite).
4. Dispatch `Publish Phone test APK` avec le run_id mobile →
   https://github.com/manzilionellm-dotcom/tvking/releases/download/phone-test/7motion-test.apk
5. Dispatch `Publish Cinéma test APK` avec le run_id TV →
   https://github.com/manzilionellm-dotcom/tvking/releases/download/cinema-test/defew-tv-cinema-test.apk
6. Télécharger chaque APK publié : vérifier taille, signature
   (`apksigner verify --print-certs` si dispo, sinon empreinte du cert
   via CI), SHA-256 consigné dans BUILD-REPORT.md.
7. Installer sur appareil réel : démarrage, navigation, lecture d'un
   flux, retour d'arrière-plan/veille.

## Publication CLIENT (uniquement sur décision humaine explicite)

- Téléphone : merger vers `claude/maison-mere-phone`, puis dispatch
  `build-android.yml` AVEC `make_release=true` (canal téléphone coupé par
  décision client 2026-07-16 — ne rouvrir que sur demande).
- TV : merger vers `claude/maison-mere-phone` — le push publie
  `tv-prod`/`tv-latest` automatiquement (anti-clobber versionCode :
  jamais de downgrade).
- Ne JAMAIS publier un canal client depuis une autre branche.
- Ne JAMAIS toucher `prive-latest` hors de son pipeline dédié.

## Après publication

- [ ] Télécharger l'asset publié et vérifier SHA-256 + signature
- [ ] Installer PAR-DESSUS l'ancienne version (test de mise à jour)
- [ ] Boîte noire : vérifier l'absence de nouvelles erreurs au premier
      lancement
- [ ] Consigner run_id, commit, checksums dans BUILD-REPORT.md
