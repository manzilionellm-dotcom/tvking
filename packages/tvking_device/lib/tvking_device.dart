// =========================================================
//  tvking_device — pas d'API Dart à appeler directement
// =========================================================
//  Ce plugin ne sert qu'à ENREGISTRER côté Android le MethodChannel
//  `com.manzilionellm.tvking/device` (getAndroidId / getDeviceInfo). Le code
//  applicatif existant (`lib/features/device/data/device_identity.dart`)
//  ouvre ce channel par son nom et l'appelle — il n'a pas besoin d'importer
//  ce package. On expose juste le nom du channel pour référence.
library tvking_device;

/// Nom du MethodChannel natif enregistré par ce plugin (Android).
const String kTvkingDeviceChannel = 'com.manzilionellm.tvking/device';
