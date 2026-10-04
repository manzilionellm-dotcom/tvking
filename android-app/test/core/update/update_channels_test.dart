// =========================================================
//  update_channels_test.dart — Le bouton voit toujours le dernier build
// =========================================================
//  Box de test : release de test ET release clients, on prend la plus
//  récente des deux. Une release cassée ou absente ne cache pas l'autre.
//  Adresses factices, empreintes factices (64 caractères hex).
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/update/update_manifest.dart';

Map<String, Object?> _m(int code, {String name = '107', bool sha = true}) =>
    <String, Object?>{
      'versionCode': code,
      'versionName': name,
      'url': 'https://example.invalid/$code.apk',
      if (sha) 'sha256': 'a' * 64,
      'size': 1000,
    };

void main() {
  test('le plus récent des deux gagne, test ou client', () {
    final UpdateManifest? m = pickNewestManifest(
      <Object?>[_m(1791000000, name: '106'), _m(1791125395, name: '107-test.152')],
      currentBuild: 1790805013,
    );
    expect(m!.versionCode, 1791125395);
    expect(m.versionName, '107-test.152');

    final UpdateManifest? client = pickNewestManifest(
      <Object?>[_m(1792000000, name: '107'), _m(1791125395, name: '107-test.152')],
      currentBuild: 1791125395,
    );
    expect(client!.versionName, '107',
        reason: 'une publication client plus récente passe devant le build de test');
  });

  test('une release injoignable ou cassée ne cache pas l\'autre', () {
    final UpdateManifest? m = pickNewestManifest(
      <Object?>[null, 'pas du json', _m(1791125395)],
      currentBuild: 1790805013,
    );
    expect(m!.versionCode, 1791125395);
  });

  test('manifeste sans empreinte ignoré, même plus récent', () {
    final UpdateManifest? m = pickNewestManifest(
      <Object?>[_m(1799999999, sha: false), _m(1791125395)],
      currentBuild: 1790805013,
    );
    expect(m!.versionCode, 1791125395);
  });

  test('déjà à jour partout : rien', () {
    expect(
      pickNewestManifest(<Object?>[_m(1791125395), _m(1791000000)], currentBuild: 1791125395),
      isNull,
    );
    expect(pickNewestManifest(const <Object?>[], currentBuild: 1), isNull);
  });

  test('téléchargement : un débit lent mais régulier va au bout', () {
    // 55 Mo à 1 Mbit/s ≈ 7 min 20 s : sous la limite totale.
    const int bytes = 55 * 1000 * 1000;
    const double bytesPerSecond = 1000000 / 8;
    final Duration needed = Duration(seconds: (bytes / bytesPerSecond).ceil());
    expect(needed < UpdateDownloadLimits.total, isTrue);
    expect(needed > UpdateDownloadLimits.legacyTotal, isTrue,
        reason: 'c\'est exactement le cas qui échouait avec l\'ancienne limite de 3 min');
    expect(UpdateDownloadLimits.idle, const Duration(seconds: 45));
  });
}
