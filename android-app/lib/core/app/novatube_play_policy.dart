/// Contrat immuable de NOVATUBE pour Google Play.
///
/// Le workflow Play conserve ces valeurs : aucune préférence locale ni
/// réponse du panel ne réactive les fonctions exclues de cette distribution.
/// Les contenus proviennent exclusivement des sources saisies par la personne.
/// L'APK installé directement peut inclure un espace +18 séparé, défini par
/// NovatubePrivateFeatures ; ce paramètre est absent du workflow AAB.
abstract final class NovatubePlayPolicy {
  static const bool isPlay = true;
  static const bool allowPanelSources = false;
  static const bool allowGold = false;
  static const bool allowAdult = false;
  static const bool allowPromotions = false;
  static const bool allowExternalPurchase = false;
  static const bool allowSelfUpdate = false;

  /// La lecture manuelle n'est pas conditionnée par une licence du revendeur.
  /// Ce droit local n'invente ni abonnement payé ni période d'essai de contenu.
  static const bool allowManualPlayback = true;
}
