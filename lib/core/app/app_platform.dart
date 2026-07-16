// =========================================================
//  app_platform.dart — Mobile vs TV (pour le panel)
// =========================================================
//  Posé UNE fois au démarrage : `main.dart` (mobile) laisse la valeur
//  par défaut, `main_tv.dart` met `isTv = true`. Le heartbeat envoie
// `platform` ('mobile' | 'tv') → le panel distingue et (appareils,
//  thème par plateforme, mise à jour forcée par plateforme…).
//  Additif : ne change RIEN au comportement du mobile.
// =========================================================
class AppPlatform {
  AppPlatform._();

  /// `true` uniquement dans l'app TV (DeFew TV). Défaut = mobile.
  static bool isTv = false;

  /// `true` uniquement dans l'app de BUREAU Windows (lib/main_windows.dart).
  /// Le panel pourra ainsi distinguer PC des box et des .
  static bool isWindows = false;

  /// Identifiant envoyé au backend.
  /// Windows est testé EN PREMIER car un poste PC peut aussi être une box TV
  /// (mini-PC branché à l'écran) : on veut alors l'étiquette la plus précise.
  static String get id => isWindows ? 'windows' : (isTv ? 'tv' : 'mobile');
}
