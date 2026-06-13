// =========================================================
//  main_prive.dart — Point d'entrée « Privé » (édition 18+)
// =========================================================
//  MÊME application que The Few mobile (même code, même backend, même
//  lecteur, mêmes écrans) : on réutilise INTÉGRALEMENT `bootApp()` de
//  main.dart. La SEULE différence est le flavor posé ici :
//    - nom/logo « Privé » (BrandConfig lit FlavorConfig.current.appName),
//    - `adultOnly = true` → le repository ne livre QUE les chaînes
//      adultes (Live Adult / Cinema Adult…),
//    - portail d'âge 18+ au 1er lancement.
//
//  Build : flutter build apk -t lib/main_prive.dart → prive.apk
// =========================================================
import 'core/flavor/flavor.dart';
import 'main.dart' as app;

Future<void> main() async {
  // Flavor « Privé » posé AVANT bootApp (qui lit FlavorConfig.current).
  FlavorConfig.setCurrent(FlavorConfig.prive);
  await app.bootApp();
}
