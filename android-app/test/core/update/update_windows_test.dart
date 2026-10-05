// =========================================================
//  update_windows_test.dart — Mise à jour de Zuno PC
// =========================================================
//  Même manifeste que la box (empreinte + taille obligatoires),
//  fichier .exe au lieu de .apk, installeur silencieux.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/update/update_manifest.dart';

void main() {
  test('nom du fichier : .exe sur PC, .apk sur box, numéro dedans', () {
    expect(updateFileName(windows: true, prefix: 'zuno-setup', versionCode: 13), 'zuno-setup-13.exe');
    expect(updateFileName(windows: false, prefix: 'zuno-tv', versionCode: 1791217147), 'zuno-tv-1791217147.apk');
  });

  test('manifeste PC : même règle stricte (empreinte, taille, plus récent)', () {
    final Map<String, Object?> m = <String, Object?>{
      'versionCode': 14,
      'versionName': '107.0.14',
      'url': 'https://example.invalid/Zuno-Setup.exe',
      'sha256': 'b' * 64,
      'size': 29000000,
    };
    expect(UpdateManifest.tryParse(m, currentBuild: 13)!.versionName, '107.0.14');
    expect(UpdateManifest.tryParse(m, currentBuild: 14), isNull, reason: 'déjà à jour');
    expect(UpdateManifest.tryParse(<String, Object?>{...m, 'sha256': ''}, currentBuild: 1), isNull);
  });

  test('installeur silencieux, sans question, Zuno fermé puis relancé', () {
    expect(kWindowsInstallerArgs, containsAll(<String>['/SILENT', '/SUPPRESSMSGBOXES', '/CLOSEAPPLICATIONS', '/NORESTART']));
    expect(kWindowsInstallerArgs, isNot(contains('/VERYSILENT')),
        reason: 'le client voit la barre de progression');
  });
}
