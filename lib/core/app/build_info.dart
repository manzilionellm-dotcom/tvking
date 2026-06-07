// =========================================================
//  build_info.dart — Identité du build + distribution
// =========================================================
//  - kBuildTs : DATE de compilation de CETTE app (epoch secondes),
//    injectée par le CI via `--dart-define=APP_BUILD_TS=...`.
//    Vaut 0 en build local (donc la mise à jour forcée est INACTIVE
//    hors CI — pas de blocage en dev).
//  - Sert à la "mise à jour forcée" : si une version publiée est
//    nettement plus récente que celle installée, on bloque l'app et
//    on invite à télécharger la nouvelle.
//
//  Les constantes de distribution (code Downloader + lien anonyme)
//  vivent ici aussi pour être affichées sur l'écran de mise à jour.
// =========================================================

/// Epoch (secondes) de compilation de cette app. 0 si build local.
const int kBuildTs = int.fromEnvironment('APP_BUILD_TS', defaultValue: 0);

/// Marge de tolérance avant de FORCER la mise à jour. Une version n'est
/// considérée "obsolète" que si la dernière publiée est plus récente
/// que celle-ci de PLUS que cette marge. Évite tout faux positif dû au
/// décalage entre l'heure de build (kBuildTs) et l'heure d'upload de
/// l'APK sur la release (quelques minutes). 6 h = large et sûr.
const int kForceUpdateGraceSeconds = 6 * 3600;

/// Code Downloader (aftv.news) à taper sur TV / Fire TV / box.
const String kDownloaderCode = '5640874';

/// Lien de téléchargement anonyme (domaine de marque, proxy de l'APK).
/// Affiché pour le téléphone (ouverture navigateur).
const String kDownloadUrl = 'https://dl.7themotion.com/royal';
