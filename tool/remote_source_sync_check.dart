// =========================================================
//  remote_source_sync_check.dart — preuve exécutable
// =========================================================
//  Tourne SANS Flutter :
//    dart run tool/remote_source_sync_check.dart
//  L'interrupteur livré doit être coupé. Pour vérifier qu'on PEUT
//  l'allumer au build :
//    dart --define=HONOR_REMOTE_LIST_CLEAR=true run \
//      tool/remote_source_sync_check.dart -- --expect-on
//
//  Aucune URL de flux réelle, aucun mot de passe réel.
// =========================================================

import 'dart:io';

import '../android-app/lib/features/playlists/data/remote_source_sync.dart';

const String _m3uPanel = 'https://example.invalid/liste-panel.m3u';
const String _m3uNouveau = 'https://example.invalid/liste-nouvelle.m3u';
const String _m3uClient = 'https://example.invalid/liste-client.m3u';

final String _keyPanel = 'm3u\n$_m3uPanel';
final String _keyNouveau = 'm3u\n$_m3uNouveau';
final String _keyClient = 'm3u\n$_m3uClient';

void main(List<String> args) {
  final bool expectOn = args.contains('--expect-on');
  var failed = 0;

  void check(String name, bool ok) {
    if (ok) {
      stdout.writeln('OK  $name');
    } else {
      failed++;
      stderr.writeln('ÉCHEC  $name');
    }
  }

  // --- Décision actuelle des lignes historiques (source non-Map = on garde).
  bool legacyGardeLaListe(Map<String, dynamic> body) {
    final Object? list = body['sources'];
    if (list is List && list.isNotEmpty) return false;
    final Object? source = body['source'];
    if (source is! Map<String, dynamic>) return true;
    return false;
  }

  final Map<String, dynamic> efface = <String, dynamic>{
    'source': null,
    'sources': <Object>[],
    'cleared': true,
  };
  check(
    'défaut historique: source null + cleared garde la liste',
    legacyGardeLaListe(efface),
  );

  final List<LocalSourceRef> local = <LocalSourceRef>[
    LocalSourceRef(id: 7, key: _keyPanel),
    LocalSourceRef(id: 8, key: _keyClient),
  ];
  final Set<String> remembered = <String>{_keyPanel};

  final RemoteListSyncPlan coupe = planRemoteListSync(
    honorClear: false,
    local: local,
    rememberedKeys: remembered,
    blockedRestoreKeys: const <String>{},
    body: efface,
  );
  check(
    'interrupteur coupé + cleared: aucune suppression',
    coupe.removeIds.isEmpty && coupe.rememberKeys.contains(_keyPanel),
  );

  final RemoteListSyncPlan allume = planRemoteListSync(
    honorClear: true,
    local: local,
    rememberedKeys: remembered,
    blockedRestoreKeys: const <String>{},
    body: efface,
  );
  check(
    'interrupteur allumé + cleared: retire SEULEMENT la liste panel (id 7)',
    allume.removeIds.length == 1 &&
        allume.removeIds.single == 7 &&
        !allume.removeIds.contains(8) &&
        allume.rememberKeys.isEmpty &&
        allume.blockRestoreKeys.contains(_keyPanel) &&
        !allume.blockRestoreKeys.contains(_keyClient),
  );

  final Map<String, dynamic> bloque = <String, dynamic>{
    'source': null,
    'sources': <Object>[],
    'blocked': 'banned',
  };
  final RemoteListSyncPlan ban = planRemoteListSync(
    honorClear: true,
    local: local,
    rememberedKeys: remembered,
    blockedRestoreKeys: const <String>{},
    body: bloque,
  );
  check(
    'licence bloquée (source null SANS cleared): on ne retire rien',
    ban.removeIds.isEmpty && ban.rememberKeys.contains(_keyPanel),
  );

  final RemoteListSyncPlan jamais = planRemoteListSync(
    honorClear: true,
    local: local,
    rememberedKeys: remembered,
    blockedRestoreKeys: const <String>{},
    body: const <String, dynamic>{'source': null, 'sources': <Object>[]},
  );
  check(
    'jamais assigné (pas de cleared): on ne retire rien',
    jamais.removeIds.isEmpty,
  );

  final RemoteListSyncPlan toujoursLa = planRemoteListSync(
    honorClear: true,
    local: local,
    rememberedKeys: remembered,
    blockedRestoreKeys: const <String>{},
    body: <String, dynamic>{
      'source': <String, dynamic>{'type': 'm3u', 'm3u_url': _m3uPanel},
      'sources': <Object>[
        <String, dynamic>{'type': 'm3u', 'm3u_url': _m3uPanel},
      ],
      'cleared': false,
    },
  );
  check(
    'source encore là: la liste panel reste',
    toujoursLa.removeIds.isEmpty && toujoursLa.rememberKeys.contains(_keyPanel),
  );

  final RemoteListSyncPlan remplace = planRemoteListSync(
    honorClear: true,
    local: <LocalSourceRef>[
      LocalSourceRef(id: 7, key: _keyPanel),
      LocalSourceRef(id: 9, key: _keyNouveau),
      LocalSourceRef(id: 8, key: _keyClient),
    ],
    rememberedKeys: <String>{_keyPanel, _keyNouveau},
    blockedRestoreKeys: <String>{_keyPanel},
    body: <String, dynamic>{
      'source': <String, dynamic>{'type': 'm3u', 'm3u_url': _m3uNouveau},
      'sources': <Object>[
        <String, dynamic>{'type': 'm3u', 'm3u_url': _m3uNouveau},
      ],
      'cleared': false,
    },
  );
  check(
    'remplacement: retire l\'ancienne clé panel, garde le client, lève le bloc',
    remplace.removeIds.length == 1 &&
        remplace.removeIds.single == 7 &&
        remplace.rememberKeys.contains(_keyNouveau) &&
        !remplace.rememberKeys.contains(_keyPanel) &&
        !remplace.blockRestoreKeys.contains(_keyNouveau),
  );

  final RemoteListSyncPlan inconnue = planRemoteListSync(
    honorClear: true,
    local: <LocalSourceRef>[LocalSourceRef(id: 8, key: _keyClient)],
    rememberedKeys: const <String>{},
    blockedRestoreKeys: const <String>{},
    body: efface,
  );
  check(
    'cleared mais liste jamais vue comme panel: on ne touche pas au client',
    inconnue.removeIds.isEmpty,
  );

  const String motDePasse = 'not-a-secret';
  final String? xtream = identityKeyFromSource(<String, dynamic>{
    'type': 'xtream',
    'server_url': 'https://xtream.example.invalid:8080',
    'username': 'demo',
    'password': motDePasse,
  });
  check(
    'clé Xtream = serveur + identifiant, sans mot de passe',
    xtream == 'xtream\nhttps://xtream.example.invalid:8080\ndemo' &&
        xtream != null &&
        !xtream.contains(motDePasse),
  );

  check(
    'rythme de sondage = 2 s',
    kRemoteClearPollInterval.inSeconds == 2,
  );

  check(
    expectOn
        ? 'interrupteur vu allumé via --define'
        : 'interrupteur livré coupé (défaut)',
    kHonorRemoteListClear == expectOn,
  );

  failed += _wiring();

  if (failed > 0) {
    stderr.writeln('$failed contrôle(s) en échec');
    exitCode = 1;
  } else {
    stdout.writeln('TOUS LES CONTRÔLES PASSENT');
  }
}

String _repoPath(String relative) {
  final String scriptDir = File(Platform.script.toFilePath()).parent.path;
  final String root = File(scriptDir).parent.path;
  return '$root/$relative';
}

int _wiring() {
  var failed = 0;
  void need(String name, String src, String needle) {
    if (src.contains(needle)) {
      stdout.writeln('OK  câblage $name');
    } else {
      failed++;
      stderr.writeln('ÉCHEC  câblage $name — introuvable: $needle');
    }
  }

  final String repo = File(
    _repoPath(
      'android-app/lib/features/playlists/data/remote_source_repository.dart',
    ),
  ).readAsStringSync();
  need('plan appelé', repo, 'planRemoteListSync(');
  need(
    'effacement ignoré si interrupteur coupé',
    repo,
    'if (!kHonorRemoteListClear && explicitClear) return;',
  );
  need(
    'suppression seulement des ids du plan',
    repo,
    'for (final int id in plan.removeIds)',
  );
  final int callAt = repo.indexOf('await _applyClearPlan(body);');
  final int nullKeepAt = repo.indexOf('src is! Map<String, dynamic>');
  if (callAt >= 0 && nullKeepAt > callAt) {
    stdout.writeln('OK  câblage plan avant le retour source null');
  } else {
    failed++;
    stderr.writeln('ÉCHEC  câblage plan avant le retour source null');
  }

  final String mobile =
      File(_repoPath('android-app/lib/main.dart')).readAsStringSync();
  final String tv =
      File(_repoPath('android-app/lib/main_tv.dart')).readAsStringSync();
  for (final MapEntry<String, String> entry in <String, String>{
    'mobile': mobile,
    'tv': tv,
  }.entries) {
    need(
        '${entry.key} interrupteur', entry.value, 'if (kHonorRemoteListClear)');
    need(
      '${entry.key} période 2 s',
      entry.value,
      'Timer.periodic(kRemoteClearPollInterval',
    );
  }
  need('mobile garde le rythme 24 h', mobile, 'Duration(hours: 24)');

  final String live = File(
    _repoPath('android-app/lib/features/tv/presentation/tv_live_screen.dart'),
  ).readAsStringSync();
  need('TV garde le sondage 12 s', live, 'Duration(seconds: 12)');
  need('TV garde le palier lent', live, '_kSlowSyncEvery = 25');

  final String backup = File(
    _repoPath(
      'android-app/lib/features/playlists/data/cloud_backup_repository.dart',
    ),
  ).readAsStringSync();
  need('backup lit le blocage', backup, 'kHonorRemoteListClear');
  need('backup saute la clé bloquée', backup, 'blocked.contains(');

  return failed;
}
