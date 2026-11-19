/// Identité séparée du nouveau paquet ZUNO Mobile. Android peut retourner le
/// même ANDROID_ID à deux apps signées avec la même clé : leurs secrets locaux
/// seraient alors concurrents auprès du panel. Le suffixe est fixe, donc une
/// réinstallation de l'édition mobile conserve sa MAC déterministe.
/// Les éditions existantes gardent exactement leur graine historique.
String deviceIdentitySeed(
  String seed, {
  String edition = const String.fromEnvironment('ZUNO_EDITION'),
}) => seed.isEmpty || edition != 'mobile' ? seed : '$seed:zuno-mobile:v1';
