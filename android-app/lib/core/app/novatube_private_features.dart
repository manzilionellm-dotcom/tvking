/// Options de l'APK installé directement, absentes du build Google Play.
/// Le workflow AAB ne fournit jamais ce paramètre de compilation.
abstract final class NovatubePrivateFeatures {
  static const bool adultCatalogs = bool.fromEnvironment(
    'NOVATUBE_PRIVATE_APK',
    defaultValue: false,
  );
}
