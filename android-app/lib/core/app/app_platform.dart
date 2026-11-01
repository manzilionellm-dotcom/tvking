// =========================================================
//  app_platform.dart — Produit et type d'appareil
// =========================================================
//  Posé UNE fois au démarrage : `main.dart` (7 MOTION mobile) laisse la valeur
//  par défaut, ZUNO utilise sa détection native du matériel. Le champ historique
//  `platform` du backend distingue les PRODUITS : mobile = 7 MOTION, tv = ZUNO.
//  Ne pas le remplacer par le matériel, sinon ZUNO téléphone recevrait le thème
//  et les règles de mise à jour de 7 MOTION. `deviceKind` décrit le matériel
//  localement ; le contrat du heartbeat reste inchangé.
// =========================================================
class AppPlatform {
  AppPlatform._();

  /// Type d'appareil, distinct de la marque : ZUNO existe aussi sur téléphone.
  /// Les anciennes éditions mobiles gardent leur valeur par défaut.
  static bool isTv = false;

  /// La marque ne doit pas être déduite de `isTv`, sinon ZUNO téléphone
  /// serait nommé 7 MOTION dans le message de support.
  static bool isZuno = false;

  /// Appelé après la détection native, avant le premier heartbeat.
  /// Une détection absente conserve le comportement TV prudent de ZUNO.
  static void configureZuno({required bool isAndroidHandset}) {
    isZuno = true;
    isTv = !isAndroidHandset;
  }

  static String get zunoEditionName => isTv ? 'ZUNO TV' : 'ZUNO Mobile';

  /// Type matériel pour les diagnostics, sans modifier le namespace du produit.
  static String get deviceKind => isTv ? 'tv' : 'mobile';

  /// Identifiant PRODUIT envoyé au backend pour le thème, les mises à jour et
  /// le heartbeat. ZUNO téléphone ne doit jamais rejoindre le canal 7 MOTION.
  static String get id => isZuno || isTv ? 'tv' : 'mobile';
}
