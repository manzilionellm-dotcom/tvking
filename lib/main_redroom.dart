// =========================================================
//  main_redroom.dart — Entrypoint variante Red Room (adulte)
// =========================================================
//  Cet entrypoint ne contient PRESQUE rien : tout le code
//  d'init (libmpv, repos, locale, theme…) reste partagé avec
//  `main.dart` via `bootApp()` réexporté depuis la version
//  BLACK7 ROYAL. La SEULE différence : on pose `FlavorConfig.redRoom`
//  avant d'appeler le boot commun, ce qui suffit pour activer :
//
//    - filtre `adultOnly` sur le repo de chaînes (le repo lit
//      `FlavorConfig.current.adultOnly` au moment de servir
//      `getAllChannels`),
//    - gate âge "j'ai 18 ans" au premier lancement,
//    - biométrie obligatoire au cold start (le réglage user
//      est ignoré),
//    - libellé "Red Room" sur le titre Material et le splash.
//
//  Côté Android, ce fichier est ciblé par la CI via :
//    flutter build apk -t lib/main_redroom.dart
//  avec un applicationId distinct (`com.redroom.player`) pour
//  que les deux apps coexistent installées en parallèle sur
//  le même téléphone.
// =========================================================

import 'core/flavor/flavor.dart';
import 'main.dart' show bootApp;

Future<void> main() async {
  // Pose le flavor AVANT d'appeler le boot commun. C'est le SEUL
  // appel qui distingue cet entrypoint de `lib/main.dart`. Tout
  // le reste de l'init (bindings, libmpv, repos, locale, MaterialApp)
  // est délégué à `bootApp()` qui lit `FlavorConfig.current` à plein
  // de niveaux pour appliquer les différences de comportement.
  FlavorConfig.setCurrent(FlavorConfig.redRoom);
  await bootApp();
}
