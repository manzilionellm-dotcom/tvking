/// Contrat immuable de NOVATUBE pour Google Play.
///
/// Cette branche décrit une application autonome : aucune préférence locale,
/// réponse du panel ni option de compilation ne réactive les fonctions exclues.
/// Les contenus proviennent exclusivement des sources saisies par la personne.
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
