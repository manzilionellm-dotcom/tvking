// =========================================================
//  app_platform.dart — Mobile vs TV (pour le panel)
// =========================================================
//  Posé UNE fois au démarrage : `main.dart` (mobile) laisse la valeur
//  par défaut, `main_tv.dart` met `isTv = true`. Le heartbeat envoie
//  `platform` ('mobile' | 'tv') → le panel distingue 📱 et 📺 (appareils,
//  thème par plateforme, mise à jour forcée par plateforme…).
//  Additif : ne change RIEN au comportement du mobile.
// =========================================================
class AppPlatform {
  AppPlatform._();

  /// `true` uniquement dans l'app TV (DeFew TV). Défaut = mobile.
  static bool isTv = false;

  /// Identifiant envoyé au backend.
  static String get id => isTv ? 'tv' : 'mobile';
}
