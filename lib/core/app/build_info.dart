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

//  ===== LE NUMÉRO QU'ON LIT AU TÉLÉPHONE (07/09/2026) =====
//
//  Demande du propriétaire : « on peut pas commencer par le chiffre 1 ? »
//  — parce que dicter « un milliard sept cent quatre-vingt-huit millions
//  cent vingt-sept mille trois cent quinze » à un client au téléphone est
//  impraticable, et comparer deux nombres à dix chiffres à l'oreille est
//  une source d'erreur garantie.
//
//  POURQUOI ON NE PEUT PAS SIMPLEMENT REPARTIR À 1. Le numéro technique
//  (`versionCode` Android) doit être STRICTEMENT CROISSANT à vie : Android
//  refuse d'installer un paquet dont le numéro est inférieur à celui déjà
//  installé, et notre vérificateur de mise à jour conclurait « déjà à
//  jour » pour toujours. Or tout le parc porte déjà 1788127315. Publier
//  « 65 » condamnerait la mise à jour de TOUTES les box, sans retour
//  possible — on ne peut pas redescendre un versionCode une fois publié.
//
//  LA SOLUTION : DEUX NUMÉROS, chacun pour son public.
//    • `versionCode` (horodatage) reste le numéro d'ANDROID. Il ne sert
//      qu'aux machines, personne ne le lit jamais.
//    • `kBuildLabel` est le numéro DES HUMAINS : le compteur de builds du
//      CI, qui commence à 1 et monte de 1 en 1. C'est lui qu'on affiche en
//      grand et qu'on dicte au téléphone.
//
//  Vide en build local : l'écran retombe alors sur le numéro technique
//  plutôt que d'afficher une case vide.
const String kBuildLabel =
    String.fromEnvironment('APP_BUILD_LABEL', defaultValue: '');

/// Marge de tolérance avant de FORCER la mise à jour. Une version n'est
/// considérée "obsolète" que si la dernière publiée est plus récente
/// que celle-ci de PLUS que cette marge. Évite tout faux positif dû au
/// décalage entre l'heure de build (kBuildTs) et l'heure d'upload de
/// l'APK sur la release (quelques minutes). 6 h = large et sûr.
const int kForceUpdateGraceSeconds = 6 * 3600;

/// Code Downloader (aftv.news) à taper sur TV / Fire TV / box.
const String kDownloaderCode = '7988141';

/// Lien de téléchargement anonyme (domaine de marque, proxy de l'APK).
/// Affiché pour le téléphone (ouverture navigateur).
const String kDownloadUrl = 'https://app.7themotion.com/vip';
