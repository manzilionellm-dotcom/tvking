// =========================================================
//  device_posture.dart — Signaux, jamais un mur
// =========================================================
//  Débogage, émulateur, options développeur, clés de test, binaire
//  `su`. On les NOTE pour la boîte noire. On ne coupe JAMAIS la
//  lecture : un téléphone de développement, un émulateur du support,
//  ou un faux positif sur `su` ne doit pas punir un client.
//
//  Aucun de ces signaux ne rend l'application inviolable.
// =========================================================

class DevicePosture {
  const DevicePosture({
    required this.debuggerConnected,
    required this.emulator,
    required this.developerOptions,
    required this.testKeys,
    required this.suPresent,
    required this.releaseBuild,
  });

  /// Plateforme sans le canal natif, ou appel échoué : on ne devine pas.
  static const DevicePosture unknown = DevicePosture(
    debuggerConnected: false,
    emulator: false,
    developerOptions: false,
    testKeys: false,
    suPresent: false,
    releaseBuild: true,
  );

  final bool debuggerConnected;
  final bool emulator;
  final bool developerOptions;
  final bool testKeys;
  final bool suPresent;
  final bool releaseBuild;

  /// Vrai si AU MOINS un signal matériel inhabituel est là.
  /// Informatif. Personne ne s'en sert pour refuser l'accès.
  bool get noteworthy =>
      debuggerConnected || emulator || testKeys || suPresent;

  factory DevicePosture.fromMap(Map<Object?, Object?> raw) {
    bool flag(String key) => raw[key] == true;
    return DevicePosture(
      debuggerConnected: flag('debuggerConnected'),
      emulator: flag('emulator'),
      developerOptions: flag('developerOptions'),
      testKeys: flag('testKeys'),
      suPresent: flag('suPresent'),
      releaseBuild: raw['releaseBuild'] != false,
    );
  }
}
