// =========================================================
//  update_storage_test.dart — Avertissement « peu de place »
// =========================================================
//  Cas réel du 13/11/2026 : APK de 60 Mo, 710 Mo libres, Android
//  refuse l'installation sans dire pourquoi. La règle doit prévenir
//  dans ce cas, et se taire quand la mesure est impossible.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/update/update_storage.dart';

const int _mo = 1024 * 1024;

void main() {
  test('710 Mo libres pour un APK de 60 Mo : on prévient', () {
    expect(
      updateStorageIsTight(freeBytes: 710 * _mo, apkBytes: 60 * _mo),
      isTrue,
    );
  });

  test('3 Go libres : rien à dire', () {
    expect(
      updateStorageIsTight(freeBytes: 3 * 1024 * _mo, apkBytes: 60 * _mo),
      isFalse,
    );
  });

  test('mesure impossible ou taille inconnue : on ne dérange pas', () {
    expect(updateStorageIsTight(freeBytes: -1, apkBytes: 60 * _mo), isFalse);
    expect(updateStorageIsTight(freeBytes: 100 * _mo, apkBytes: 0), isFalse);
  });

  test('affichage en Mo entiers', () {
    expect(updateFreeMegabytes(710 * _mo + 5), 710);
    expect(updateFreeMegabytes(-1), 0);
  });
}
