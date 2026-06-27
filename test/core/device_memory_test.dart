// =========================================================
//  device_memory_test.dart — Plafond chaînes adapté à la RAM
// =========================================================
//  Vérifie le garde-fou anti-OOM : tant que la RAM n'est pas connue
//  (cas d'un isolate, ou avant ensureLoaded), le plafond reste PRUDENT.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/device_memory.dart';

void main() {
  test('RAM inconnue → plafond prudent (15000)', () {
    // Sans ensureLoaded(), isLoaded vaut false → on protège les petites box.
    expect(DeviceMemory.isLoaded, isFalse);
    expect(DeviceMemory.channelCap, 15000);
  });
}
