// =========================================================
//  build_flags.dart — Drapeaux figés au moment du build
// =========================================================
//  `kIsPlayBuild` distingue le build Google Play (AAB) du build
//  sideload (APK GitHub). Il est injecté UNIQUEMENT pour l'App Bundle
//  par le CI :
//      flutter build appbundle ... --dart-define=PLAY_BUILD=true
//  L'APK GitHub, lui, ne passe pas ce define → `false`.
//
//  Pourquoi : sur le Play Store, les mises à jour viennent du Store.
//  L'updater interne (qui télécharge `7motion.apk` depuis GitHub et
//  l'installe via REQUEST_INSTALL_PACKAGES) y est donc inutile ET
//  contraire aux règles Google (permission restreinte + sideload
//  d'exécutable). Quand `kIsPlayBuild` vaut `true`, tous les chemins
//  d'auto-mise-à-jour sideload sont désactivés (early-return), et le CI
//  retire en parallèle la permission REQUEST_INSTALL_PACKAGES du
//  manifest de l'AAB. Le build APK sideload, lui, reste 100% inchangé.
// =========================================================

/// `true` uniquement pour l'App Bundle Play Store (via
/// `--dart-define=PLAY_BUILD=true`). `false` pour l'APK sideload GitHub.
const bool kIsPlayBuild =
    bool.fromEnvironment('PLAY_BUILD', defaultValue: false);
