# Hypothèses — USINE APP v2 (périmètre mobile)

## Run 001 — 2026-07-24

1. **« Application mobile du téléphone » = l'app Flutter `lib/main.dart`**
   (7 MOTION, buildée par `build-android.yml` → `7motion.apk`), et non le
   prototype web Next.js de `main`. Indices : workflows `publish-phone-test`
   (« Équivalent MOBILE »), README de la branche Flutter. Confiance haute.
2. **Branche de référence téléphone = `claude/maison-mere-phone`** : la plus
   récente portant le code phone (43f751d, 2026-07-22), nom explicite
   (« maison mère phone »), CI Quality verte. Confiance haute. Si le client
   désigne une autre branche de référence, le run 002 rebasera.
3. **Flutter 3.44.8 stable local ≈ CI** : la CI utilise `channel: stable`
   au moment du run ; 647/647 tests verts localement ET CI verte sur le même
   commit de base → environnement jugé représentatif. Confiance moyenne.
4. **Métriques terrain (Tier B) indisponibles** : aucun accès console Play,
   crash reporting, ni analytics depuis ce sandbox. AUCUN chiffre terrain
   n'est cité dans les rapports (crash rate, installs, notes = NON VÉRIFIÉ).
5. **Le programme complet USINE v2 (bancs perf, video-bench, harnais chaos,
   rollout)** requiert émulateur Android + accès consoles, absents du
   sandbox : ce run livre bootstrap mémoire + baseline mesurée + sprint
   borné. Les phases restantes sont planifiées dans roadmap.md.
