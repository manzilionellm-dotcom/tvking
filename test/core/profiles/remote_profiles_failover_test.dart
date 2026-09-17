// =========================================================
//  remote_profiles_failover_test.dart — DNS maison KO → secours
// =========================================================
//  Terrain 17/09/2026 (Boîte noire code 3G9ITK) : pendant 40 min,
//  `profiles.remote.sync_fail` répétait
//    Failed host lookup: app.7themotion.com (errno = 7)
//  Le heartbeat savait déjà itérer BackendHosts.candidates() et
//  basculer sur workers.dev. Le GET profils, lui, tapait UNIQUEMENT
//  kSubscriptionBaseUrl (le domaine maison). Quand le DNS de ce
//  domaine tombe, l'abo/les profils restent morts alors que le
//  Worker Cloudflare répond encore.
//
//  Ce test lit le fichier RÉEL. Si quelqu'un remet un GET unique
//  sur kSubscriptionBaseUrl, ça casse ici — pas en clientèle.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File src = File('lib/core/profiles/remote_profiles_repository.dart');

  test('le fichier profils est là où on le croit', () {
    expect(src.existsSync(), isTrue, reason: src.path);
  });

  test('sync itère BackendHosts.candidates, pas seulement le domaine maison',
      () {
    final String code = src.readAsStringSync();
    expect(
      code.contains('BackendHosts.candidates()'),
      isTrue,
      reason: 'sans candidates(), un DNS KO sur app.7themotion.com '
          'boucle errno=7 et n\'essaie jamais workers.dev',
    );
    expect(
      code.contains('BackendHosts.markGood'),
      isTrue,
      reason: 'un succès sur le secours doit basculer kSubscriptionBaseUrl '
          'pour TOUTE l\'app, pas seulement ce GET',
    );
    expect(
      code.contains("kSubscriptionBaseUrl/api/device-profiles"),
      isFalse,
      reason: 'GET unique sur le domaine maison = le bug 3G9ITK',
    );
  });
}
