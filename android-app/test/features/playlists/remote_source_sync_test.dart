// =========================================================
//  remote_source_sync_test.dart — décision d'effacement panel
// =========================================================
//  Même contrat que tool/remote_source_sync_check.dart, pour
//  `flutter test` le jour où le SDK Flutter est là.
//  La preuve exécutée dans cet environnement est le script Dart
//  autonome (pas de Flutter sur la machine de build de l'agent).
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/remote_source_sync.dart';

const String _m3uPanel = 'https://example.invalid/liste-panel.m3u';
const String _m3uNouveau = 'https://example.invalid/liste-nouvelle.m3u';
const String _m3uClient = 'https://example.invalid/liste-client.m3u';

void main() {
  final String keyPanel = 'm3u\n$_m3uPanel';
  final String keyNouveau = 'm3u\n$_m3uNouveau';
  final String keyClient = 'm3u\n$_m3uClient';

  final Map<String, dynamic> efface = <String, dynamic>{
    'source': null,
    'sources': <Object>[],
    'cleared': true,
  };

  final List<LocalSourceRef> local = <LocalSourceRef>[
    const LocalSourceRef(
        id: 7, key: 'm3u\nhttps://example.invalid/liste-panel.m3u'),
    LocalSourceRef(id: 8, key: keyClient),
  ];

  test('interrupteur livré coupé, sondage à 2 s', () {
    expect(kHonorRemoteListClear, isFalse);
    expect(kRemoteClearPollInterval.inSeconds, 2);
  });

  test('interrupteur coupé : cleared ne retire rien et garde la mémoire', () {
    final RemoteListSyncPlan plan = planRemoteListSync(
      honorClear: false,
      local: local,
      rememberedKeys: <String>{keyPanel},
      blockedRestoreKeys: const <String>{},
      body: efface,
    );
    expect(plan.removeIds, isEmpty);
    expect(plan.rememberKeys, contains(keyPanel));
  });

  test('interrupteur allumé : cleared retire la liste panel, pas le client',
      () {
    final RemoteListSyncPlan plan = planRemoteListSync(
      honorClear: true,
      local: local,
      rememberedKeys: <String>{keyPanel},
      blockedRestoreKeys: const <String>{},
      body: efface,
    );
    expect(plan.removeIds, <int>[7]);
    expect(plan.rememberKeys, isEmpty);
    expect(plan.blockRestoreKeys, contains(keyPanel));
    expect(plan.blockRestoreKeys, isNot(contains(keyClient)));
  });

  test('source null sans cleared (licence ou jamais assigné) ne retire rien',
      () {
    for (final Map<String, dynamic> body in <Map<String, dynamic>>[
      <String, dynamic>{
        'source': null,
        'sources': <Object>[],
        'blocked': 'banned',
      },
      <String, dynamic>{'source': null, 'sources': <Object>[]},
    ]) {
      final RemoteListSyncPlan plan = planRemoteListSync(
        honorClear: true,
        local: local,
        rememberedKeys: <String>{keyPanel},
        blockedRestoreKeys: const <String>{},
        body: body,
      );
      expect(plan.removeIds, isEmpty);
    }
  });

  test('source encore présente : on garde la liste', () {
    final RemoteListSyncPlan plan = planRemoteListSync(
      honorClear: true,
      local: local,
      rememberedKeys: <String>{keyPanel},
      blockedRestoreKeys: const <String>{},
      body: <String, dynamic>{
        'sources': <Object>[
          <String, dynamic>{'type': 'm3u', 'm3u_url': _m3uPanel},
        ],
        'cleared': false,
      },
    );
    expect(plan.removeIds, isEmpty);
  });

  test('remplacement : retire l\'ancienne clé, garde la liste du client', () {
    final RemoteListSyncPlan plan = planRemoteListSync(
      honorClear: true,
      local: <LocalSourceRef>[
        LocalSourceRef(id: 7, key: keyPanel),
        LocalSourceRef(id: 9, key: keyNouveau),
        LocalSourceRef(id: 8, key: keyClient),
      ],
      rememberedKeys: <String>{keyPanel},
      blockedRestoreKeys: <String>{keyPanel},
      body: <String, dynamic>{
        'sources': <Object>[
          <String, dynamic>{'type': 'm3u', 'm3u_url': _m3uNouveau},
        ],
      },
    );
    expect(plan.removeIds, <int>[7]);
    expect(plan.rememberKeys, contains(keyNouveau));
    expect(plan.rememberKeys, isNot(contains(keyPanel)));
    expect(plan.blockRestoreKeys, isNot(contains(keyNouveau)));
  });

  test('clé Xtream sans mot de passe', () {
    const String secret = 'not-a-secret';
    final String? key = identityKeyFromSource(<String, dynamic>{
      'type': 'xtream',
      'server_url': 'https://xtream.example.invalid:8080',
      'username': 'demo',
      'password': secret,
    });
    expect(key, 'xtream\nhttps://xtream.example.invalid:8080\ndemo');
    expect(key, isNot(contains(secret)));
  });
}
