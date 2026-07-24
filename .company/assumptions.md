# Hypothèses (run 001)

Décisions prises sans question en cours de run (Loi 2), documentées ici.

1. **Framework ≠ Flutter.** Le prompt USINE APP v2 vise Flutter/Android natif/Media3.
   Le dépôt est une app Next.js 16 « 10-foot UI » empaquetée en APK WebView. On applique
   l'ESPRIT du framework (mesurer → ne rien casser → tester → livrer sûr), jamais sa lettre
   quand la surface n'existe pas (pas de moteur Media3, pas d'AAB/rollout, pas de back-end
   dans ce dépôt). Ne pas fabriquer de surface native inexistante (Loi 3).

2. **Branche.** Le framework suggère une branche filet `usine/run-NNN`. Les instructions de
   la tâche imposent `claude/tv-box-version-tv-6m5rph`. On respecte l'instruction : tout le
   travail git reste sur cette branche. Le « journal de run » vit dans `.company/runs/`.

3. **Périmètre = version TV.** On ne touche NI aux workflows de publication téléphone
   (`publish-phone-test.yml`, `publish-master.yml`), NI au pipeline natif (absent du dépôt).
   On ajoute un gate CI web (lint/typecheck/test/build) qui n'interfère avec aucun d'eux.

4. **Runner de test = vitest** (moderne, compatible React 19). Tests de logique pure en
   environnement `node` ; tests DOM ciblés en `jsdom`. Pas de dépendance lourde superflue.

5. **Budget de taille** : à défaut d'historique, la 1re exécution ÉCRIT la baseline
   (`.company/data/perf/baseline.json`) ; les suivantes échouent au-delà de +10 % (Loi 10).
   Honnête : ce n'est pas une régression tant qu'aucune baseline n'existe.
