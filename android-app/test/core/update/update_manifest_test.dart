import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/update/update_manifest.dart';

void main() {
  final Map<String, Object?> complet = <String, Object?>{
    'versionCode': 20,
    'versionName': '1.2.0',
    'url': 'https://exemple.test/app.apk',
    'sha256': 'ab' * 32,
    'size': 5000000,
    'mandatory': false,
  };

  test('manifeste sans empreinte refusé', () {
    final Map<String, Object?> j = Map<String, Object?>.from(complet)
      ..remove('sha256');
    expect(UpdateManifest.tryParse(j, currentBuild: 10), isNull);
  });

  test('manifeste sans taille refusé', () {
    final Map<String, Object?> j = Map<String, Object?>.from(complet)
      ..remove('size');
    expect(UpdateManifest.tryParse(j, currentBuild: 10), isNull);
  });

  test('manifeste complet accepté', () {
    final UpdateManifest? m =
        UpdateManifest.tryParse(complet, currentBuild: 10);
    expect(m, isNotNull);
    expect(m!.sha256, 'ab' * 32);
    expect(m.sizeBytes, 5000000);
  });

  test('déjà à jour → rien', () {
    expect(UpdateManifest.tryParse(complet, currentBuild: 20), isNull);
  });

  test('taille exacte exigée', () {
    expect(
      apkSizeMatches(received: 100, expected: 100, contentLength: 100),
      isTrue,
    );
    expect(
      apkSizeMatches(received: 2000000, expected: 5000000),
      isFalse,
    );
    expect(
      apkSizeMatches(received: 100, expected: 100, contentLength: 50),
      isFalse,
    );
  });
}
