// =========================================================
//  device_memory_test.dart — Paliers de RAM (anti-OOM)
// =========================================================
//  Vérifie le garde-fou anti-OOM sur ses deux fronts :
//
//   1. RAM INCONNUE (isolate, ou avant ensureLoaded) → plafond PRUDENT ;
//   2. TÉLÉPHONE MINUSCULE (256 Mo, demande client du 22/08 : « ça doit
//      marcher même sur un petit Android à 256 Mo, passe-partout ») → le
//      profil le plus serré s'active vraiment.
//
//  ATTENTION À L'ORDRE : `DeviceMemory` est un cache statique lu UNE
//  seule fois (`ensureLoaded` est idempotent). Le 1er test doit donc
//  s'exécuter AVANT que le 2e ne charge la RAM simulée. Les fichiers de
//  test tournent chacun dans leur propre processus : ce couplage reste
//  confiné à ce fichier.
// =========================================================
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/device_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RAM inconnue → plafond prudent (8000)', () {
    // Sans ensureLoaded(), isLoaded vaut false → on protège les petites box.
    expect(DeviceMemory.isLoaded, isFalse);
    expect(DeviceMemory.channelCap, 8000);
    // Sur une simple incertitude on ne DÉGRADE jamais un appareil correct :
    // `isTiny` reste faux tant que la RAM n'a pas été lue.
    expect(DeviceMemory.isTiny, isFalse);
  });

  test('256 Mo → palier « minuscule » : 1500 chaînes, affiches en ×1', () async {
    // On simule le plugin natif : un vieux téléphone Android à 256 Mo qui,
    // comme beaucoup d'entrée de gamme, ne se DÉCLARE même pas « low RAM ».
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.manzilionellm.tvking/device'),
      (MethodCall call) async {
        if (call.method != 'getMemoryInfo') return null;
        return <String, Object?>{'totalMb': 256, 'lowRam': false};
      },
    );

    await DeviceMemory.ensureLoaded();

    expect(DeviceMemory.totalMb, 256);
    // Le palier ne dépend PAS du drapeau Android (qui ment souvent) :
    // 256 Mo suffit à déclencher le profil le plus serré…
    expect(DeviceMemory.lowRam, isFalse);
    expect(DeviceMemory.isTiny, isTrue);
    // …et « minuscule » implique toujours « petit ».
    expect(DeviceMemory.isSmall, isTrue);

    // Conséquences concrètes du palier :
    expect(DeviceMemory.channelCap, 1500);
    // Décodage des affiches à la taille EXACTE d'affichage (×1) : un bitmap
    // coûte largeur×hauteur×4 octets, ×2 le quadruplerait.
    expect(DeviceMemory.posterCacheWidth(120), 120);
  });
}
