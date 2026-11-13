import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/build_info.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';

void main() {
  test(
    'le backend ZUNO de production utilise le domaine actuel',
    () => expect(kSubscriptionBaseUrl, 'https://api.zuno8k.com'),
    // Un build de staging doit pouvoir conserver sa surcharge explicite.
    skip: const bool.hasEnvironment('BACKEND_URL'),
  );

  test('la surcharge de build reste la source unique du backend', () {
    const String expected = String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'https://api.zuno8k.com',
    );
    expect(kSubscriptionBaseUrl, expected);
  });

  test('le lien de téléchargement utilise le domaine de production actuel', () {
    expect(kDownloadUrl, 'https://api.zuno8k.com/vip');
  });

  test('les deux chemins Cast partagent la constante du backend', () {
    final String manager =
        File('lib/features/cast/data/cast_manager.dart').readAsStringSync();
    final String transport =
        File('lib/features/cast/data/google_cast_transport.dart')
            .readAsStringSync();
    expect(manager, contains(r"return '$kSubscriptionBaseUrl/cs/$b64.ts';"));
    expect(transport,
        contains('const String _kCastProxyBase = kSubscriptionBaseUrl;'));
  });

  test('les points de production et le contrôle du bundle ne gardent pas l’ancien domaine', () {
    // On contrôle le périmètre porté, sans toucher aux exemples historiques
    // des écrans admin, aux Workers ou à leurs migrations.
    const List<String> paths = <String>[
      'lib/core/app/build_info.dart',
      'lib/features/subscription/data/subscription_backend.dart',
      'lib/features/cast/data/cast_manager.dart',
      'lib/features/cast/data/google_cast_transport.dart',
      '../.github/workflows/build-zuno-tv.yml',
    ];
    for (final String path in paths) {
      expect(File(path).readAsStringSync(),
          isNot(contains('app.7themotion.com')), reason: path);
    }
  });
}
