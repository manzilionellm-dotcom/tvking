// =========================================================
//  main_tv.dart — Entrypoint dédié TÉLÉVISION (Android TV / Fire TV)
// =========================================================
//  Identique à `main.dart` (flavor 7 MOTION, même `bootApp()`), à une
//  différence : on VERROUILLE l'app en mode TV (10-foot UI, navigation
//  télécommande, focus rings) quelle que soit la taille d'écran. Utile
//  pour les box dont la taille d'écran est mal détectée, et pour
//  distribuer un APK « TV » clairement séparé (code Downloader dédié).
//
//  Le cast est déjà ABSENT de l'interface TV (cf. tv_home_screen). Le
//  moteur de cast n'est pas touché.
//
//  Ciblé par la CI via :  flutter build apk -t lib/main_tv.dart
// =========================================================

import 'core/flavor/flavor.dart';
import 'features/onboarding/data/device_class_repository.dart';
import 'main.dart' show bootApp;

Future<void> main() async {
  // 7 MOTION + verrouillage TV, AVANT le boot commun.
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
  DeviceClassRepository.instance.forceTv();
  await bootApp();
}
