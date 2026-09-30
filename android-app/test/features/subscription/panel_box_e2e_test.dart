// =========================================================
//  panel_box_e2e_test.dart — Preuve panel → box
// =========================================================
//  Worker RÉEL (wrangler dev + D1 locale) et code client RÉEL
//  (RemoteActivationWatch, SubscriptionState, RemoteSourceRepository,
//  PlaylistRepository). Pas un faux du même code.
//
//  Lancé seulement avec :
//    flutter test --dart-define=RUN_E2E=true \
//      --dart-define=BACKEND_URL=http://127.0.0.1:8787 \
//      test/features/subscription/panel_box_e2e_test.dart
//
//  Sans ces defines, le test est ignoré : `flutter test` du
//  workflow n'a pas besoin de wrangler.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/data/recently_watched_repository.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/removed_list_notice.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';

const bool _kRun = bool.fromEnvironment('RUN_E2E');

const String _base = 'http://127.0.0.1:8787';
const String _adminSecret = 'e2e-admin-secret-not-production';
const String _mac = 'MK:AA:BB:CC:DD:01';
const String _otherMac = 'MK:AA:BB:CC:DD:99';
const String _server = 'http://127.0.0.1:9';
const String _userA = 'user-a';
const String _passA = 'secret-liste-a';
const String _userB = 'user-b';
const String _passB = 'secret-liste-b';

/// Le binding de test remplace tout HttpClient par un faux qui
/// répond 400. On remet le client réel : ce fichier parle à wrangler.
class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttp();

  late Directory persist;
  Process? worker;
  late String adminToken;

  setUpAll(() async {
    if (!_kRun) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': _mac,
    });
    final Directory dbDir =
        await Directory.systemTemp.createTemp('zuno-box-db-');
    PlaylistDatabase.debugFilePath = '${dbDir.path}/tv_king.db';
    persist = await Directory.systemTemp.createTemp('zuno-d1-');
    worker = await _startWorker(persist.path);
    adminToken = await _login('admin', _adminSecret);
  });

  tearDownAll(() async {
    if (!_kRun) return;
    RemoteActivationWatch.instance.stopForTesting();
    final Process? running = worker;
    if (running != null) await _stopWorker(running);
  });

  test(
    'panel efface la liste, la box se vide, délais mesurés',
    () async {
      FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
      PlaylistRepository.mergeAllPlaylists = true;
      await SubscriptionState.instance.initialize();
      await _seed(onlyA: true);
      RemovedListNotice.instance.resetForTesting();

      RemoteActivationWatch.instance.start();
      await _waitUntil(
        () => SubscriptionState.instance.remote.exists,
        'premier statut',
      );

      final Stopwatch activation = Stopwatch()..start();
      final Map<String, dynamic> act = await _send(
        'POST',
        '/api/v1/activate',
        token: adminToken,
        body: <String, dynamic>{'mac': _mac, 'plan': 'lifetime'},
      );
      expect(act['status'], anyOf(200, 201), reason: 'activation panel ${act['body']}');
      await _waitUntil(
        () => SubscriptionState.instance.remote.paid,
        'statut payé sur la box',
      );
      activation.stop();
      final double activationSeconds =
          activation.elapsedMilliseconds / 1000.0;
      // ignore: avoid_print
      print('MESURE activation_secondes=$activationSeconds');
      expect(activationSeconds, lessThan(12));
      expect(SubscriptionState.instance.remote.plan, 'lifetime');

      final Map<String, dynamic> put = await _send(
        'PUT',
        '/api/v1/sources/$_mac',
        token: adminToken,
        body: <String, dynamic>{
          'type': 'xtream',
          'server_url': _server,
          'username': _userA,
          'password': _passA,
          'label': 'Liste A',
        },
      );
      expect(put['status'], 200, reason: 'PUT source ${put['body']}');
      await _waitUntil(
        () => (SubscriptionState.instance.remote.sourceRev ?? 0) > 0,
        'source_rev après pose',
      );

      final Map<String, dynamic> noAuth = await _send(
        'DELETE',
        '/api/v1/sources/$_mac',
        body: <String, dynamic>{
          'server_url': _server,
          'username': _userA,
        },
      );
      expect(noAuth['status'], 401, reason: 'sans jeton ${noAuth['body']}');
      expect(await _hasUser(_userA), isTrue);

      final String basicId = await _reseller(
        adminToken,
        email: 'basic-e2e@exemple.test',
        password: 'basic-password-e2e-0001',
        permissions: null,
      );
      final String basicToken = await _login(
        'basic-e2e@exemple.test',
        'basic-password-e2e-0001',
        reseller: true,
      );
      final Map<String, dynamic> noPerm = await _send(
        'DELETE',
        '/api/v1/sources/$_mac',
        token: basicToken,
        body: <String, dynamic>{
          'server_url': _server,
          'username': _userA,
        },
      );
      expect(noPerm['status'], 403, reason: 'sans droit sources ${noPerm['body']}');
      expect(basicId, isNotEmpty);

      final String otherToken = await _login(
        'other-e2e@exemple.test',
        'other-password-e2e-0001',
        create: true,
        reseller: true,
        adminToken: adminToken,
        permissions: <String>['activate', 'sources'],
      );
      final Map<String, dynamic> wrongReseller = await _send(
        'DELETE',
        '/api/v1/sources/$_mac',
        token: otherToken,
        body: <String, dynamic>{
          'server_url': _server,
          'username': _userA,
        },
      );
      expect(wrongReseller['status'], 403,
          reason: 'mauvais revendeur ${wrongReseller['body']}');
      expect(await _hasUser(_userA), isTrue);

      final Map<String, dynamic> wrongMac = await _send(
        'DELETE',
        '/api/v1/sources/$_otherMac',
        token: adminToken,
        body: <String, dynamic>{
          'server_url': _server,
          'username': _userA,
        },
      );
      expect(wrongMac['status'], anyOf(200, 400),
          reason: 'autre MAC ${wrongMac['body']}');
      await RemoteSourceRepository.sync();
      expect(await _hasUser(_userA), isTrue,
          reason: 'effacer une autre MAC ne vide pas cette box');

      final Stopwatch wipe = Stopwatch()..start();
      final Map<String, dynamic> deleted = await _send(
        'DELETE',
        '/api/v1/sources/$_mac',
        token: adminToken,
        body: <String, dynamic>{
          'server_url': _server,
          'username': _userA,
        },
      );
      expect(deleted['status'], 200, reason: 'DELETE ${deleted['body']}');
      expect(deleted['json']['removed'], 1);
      await _waitUntil(() => _hasUser(_userA).then((bool v) => !v), 'liste A partie');
      wipe.stop();
      final double wipeSeconds = wipe.elapsedMilliseconds / 1000.0;
      // ignore: avoid_print
      print('MESURE effacement_secondes=$wipeSeconds');
      expect(wipeSeconds, lessThan(12));

      expect(await _count('channels', "external_id = 'ch-a'"), 0);
      expect(await _count('favorites', "channel_id = 'ch-a'"), 0);
      expect(await _count('favorites_by_profile', "channel_id = 'ch-a'"), 0);
      expect(await _count('recently_watched', "channel_id = 'ch-a'"), 0);
      expect(
          await _count('recently_watched_by_profile', "channel_id = 'ch-a'"), 0);
      expect(await _count('watch_sessions', "channel_id = 'ch-a'"), 0);
      expect(await _count('favorites', "channel_id = 'ch-other'"), 1);
      expect(await _passwordPresent(_passA), isFalse);
      final RemovedListEvent? notice = RemovedListNotice.instance.event.value;
      expect(notice, isNotNull);
      expect(notice!.removed, greaterThan(0));
      expect(notice.noneLeft, isTrue);

      final http.Response status = await http
          .get(Uri.parse('$_base/api/status/$_mac'))
          .timeout(const Duration(seconds: 8));
      expect(status.body.contains(_passA), isFalse);
      expect(status.body.contains('"revoked"'), isTrue);

      final Map<String, dynamic> again = await _send(
        'DELETE',
        '/api/v1/sources/$_mac',
        token: adminToken,
        body: <String, dynamic>{
          'server_url': _server,
          'username': _userA,
        },
      );
      expect(again['status'], 200);
      expect(again['json']['already'], isTrue);
      expect(await _hasUser(_userA), isFalse);

      // Deuxième liste locale : seul A part, B reste.
      // On coupe la veille avant de reposer A, sinon la tombstone
      // encore en base l'effacerait avant le PUT.
      RemoteActivationWatch.instance.stopForTesting();
      await _seed(onlyA: false);
      final Map<String, dynamic> putAgain = await _send(
        'PUT',
        '/api/v1/sources/$_mac',
        token: adminToken,
        body: <String, dynamic>{
          'type': 'xtream',
          'server_url': _server,
          'username': _userA,
          'password': _passA,
          'label': 'Liste A',
        },
      );
      expect(putAgain['status'], 200, reason: '${putAgain['body']}');
      await RemoteSourceRepository.sync();
      expect(await _hasUser(_userA), isTrue);
      expect(await _hasUser(_userB), isTrue);

      RemoteActivationWatch.instance.stopForTesting();
      final Map<String, dynamic> offlineOrder = await _send(
        'DELETE',
        '/api/v1/sources/$_mac',
        token: adminToken,
        body: <String, dynamic>{
          'server_url': _server,
          'username': _userA,
        },
      );
      expect(offlineOrder['status'], 200, reason: '${offlineOrder['body']}');
      await _stopWorker(worker!);
      final RemoteSyncOutcome down =
          await SubscriptionState.instance.refreshRemote();
      expect(down, RemoteSyncOutcome.offline);
      final RemoteSyncResult downSrc = await RemoteSourceRepository.sync();
      expect(downSrc, RemoteSyncResult.networkError);
      expect(await _hasUser(_userA), isTrue,
          reason: 'hors-ligne : la liste reste');
      expect(await _hasUser(_userB), isTrue);

      worker = await _startWorker(persist.path);
      RemoteActivationWatch.instance.start();
      final Stopwatch back = Stopwatch()..start();
      await _waitUntil(
          () => _hasUser(_userA).then((bool v) => !v), 'effacement après retour réseau');
      back.stop();
      // ignore: avoid_print
      print('MESURE retour_reseau_secondes=${back.elapsedMilliseconds / 1000.0}');
      expect(await _hasUser(_userB), isTrue);
      expect(await _passwordPresent(_passB), isTrue);
      expect(await _count('channels', "external_id = 'ch-b'"), 1);
      expect(back.elapsedMilliseconds / 1000.0, lessThan(20));
    },
    skip: _kRun ? false : 'RUN_E2E non posé — preuve miniflare non lancée',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<Process> _startWorker(String persistDir) async {
  final ProcessResult schema = await Process.run(
    'npx',
    <String>[
      'wrangler', 'd1', 'execute', 'tvking_licensing',
      '--local',
      '--persist-to', persistDir,
      '--file', 'schema.sql',
    ],
    workingDirectory: 'cloudflare',
    environment: <String, String>{
      'CI': 'true',
      'WRANGLER_SEND_METRICS': 'false',
    },
  );
  if (schema.exitCode != 0) {
    throw StateError('schéma D1\n${schema.stdout}\n${schema.stderr}');
  }
  // schema.sql omet parent_reseller_id (ajouté en prod par la migration
  // 003). Sans elle, l'INSERT revendeur échoue et l'API répond 409.
  final ProcessResult hierarchy = await Process.run(
    'npx',
    <String>[
      'wrangler', 'd1', 'execute', 'tvking_licensing',
      '--local',
      '--persist-to', persistDir,
      '--file', 'migrations/003_reseller_hierarchy.sql',
    ],
    workingDirectory: 'cloudflare',
    environment: <String, String>{
      'CI': 'true',
      'WRANGLER_SEND_METRICS': 'false',
    },
  );
  if (hierarchy.exitCode != 0) {
    final String out = '${hierarchy.stdout}\n${hierarchy.stderr}';
    // Rejeu au redémarrage (retour réseau) : la colonne existe déjà.
    if (!out.contains('duplicate column')) {
      throw StateError('migration 003\n$out');
    }
  }
  await _freeDevPort();
  final File vars = File('cloudflare/.dev.vars');
  await vars.writeAsString(
    'ADMIN_SECRET=$_adminSecret\n'
    'SOURCE_ENCRYPTION_KEY=e2e-source-key-32chars-minimum\n',
  );
  final Process process = await Process.start(
    'npx',
    <String>[
      'wrangler',
      'dev',
      '--port',
      '8787',
      '--ip',
      '127.0.0.1',
      '--persist-to',
      persistDir,
      '--show-interactive-dev-session=false',
    ],
    workingDirectory: 'cloudflare',
    environment: <String, String>{
      'CI': 'true',
      'WRANGLER_SEND_METRICS': 'false',
    },
  );
  final StringBuffer log = StringBuffer();
  process.stdout.transform(utf8.decoder).listen(log.write);
  process.stderr.transform(utf8.decoder).listen(log.write);
  int? exited;
  unawaited(process.exitCode.then((int code) => exited = code));
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
  try {
  while (DateTime.now().isBefore(deadline)) {
    if (exited != null) {
      throw StateError('wrangler s\'est arrêté ($exited)\n$log');
    }
    if (log.toString().contains('Ready on http://127.0.0.1:8787')) {
      try {
        final http.Response ping = await http
            .get(Uri.parse('$_base/api/status/$_mac'))
            .timeout(const Duration(seconds: 3));
        if (ping.statusCode == 200) return process;
        log.write('\nstatut HTTP ${ping.statusCode} ${ping.body}\n');
      } catch (e) {
        log.write('\nping $e\n');
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  process.kill();
  throw StateError('wrangler pas prêt\n$log');
  } catch (e) {
    process.kill();
    rethrow;
  }
}

Future<void> _stopWorker(Process process) async {
  process.kill(ProcessSignal.sigterm);
  try {
    await process.exitCode.timeout(const Duration(seconds: 8));
  } catch (_) {
    process.kill(ProcessSignal.sigkill);
  }
  await _freeDevPort();
}

/// Tue wrangler/workerd sans que la commande ne se suicide
/// (un `pkill -f` dont la ligne contient le motif se tue elle-même
/// et laisse le port 8787 occupé par l'ancien Worker).
Future<void> _freeDevPort() async {
  const String script = r'''
for pid in $(ps -eo pid,args | awk '/[w]rangler dev --port 8787/ {print $1}'); do
  kill -9 "$pid" 2>/dev/null || true
done
for pid in $(ps -eo pid,args | awk '/[w]orkerd serve/ {print $1}'); do
  kill -9 "$pid" 2>/dev/null || true
done
''';
  await Process.run('bash', <String>['-c', script]);
  for (int i = 0; i < 25; i++) {
    final ProcessResult probe = await Process.run('python3', <String>[
      '-c',
      'import os\n'
          'def up():\n'
          '  f=open("/proc/net/tcp")\n'
          '  next(f)\n'
          '  return any(int(l.split()[1].split(":")[1],16)==8787 and l.split()[3]=="0A" for l in f)\n'
          'raise SystemExit(0 if not up() else 1)\n',
    ]);
    if (probe.exitCode == 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError('le port 8787 est encore pris');
}

Future<String> _login(
  String email,
  String password, {
  bool create = false,
  bool reseller = false,
  String? adminToken,
  List<String>? permissions,
}) async {
  if (create) {
    await _reseller(
      adminToken!,
      email: email,
      password: password,
      permissions: permissions,
    );
  }
  // Le panel connecte un revendeur sur /auth/reseller/login, pas sur
  // le login admin (table admin_users).
  final Map<String, dynamic> res = await _send(
    'POST',
    reseller ? '/api/v1/auth/reseller/login' : '/api/v1/auth/login',
    body: <String, dynamic>{'email': email, 'password': password},
  );
  expect(res['status'], 200, reason: 'login $email ${res['body']}');
  return res['json']['token'] as String;
}

Future<String> _reseller(
  String adminToken, {
  required String email,
  required String password,
  List<String>? permissions,
}) async {
  final Map<String, dynamic> created = await _send(
    'POST',
    '/api/v1/resellers',
    token: adminToken,
    body: <String, dynamic>{
      'email': email,
      'password': password,
      'name': email,
    },
  );
  expect(created['status'], 201, reason: 'revendeur ${created['body']}');
  final String id = created['json']['id'] as String;
  if (permissions != null) {
    final Map<String, dynamic> patched = await _send(
      'PATCH',
      '/api/v1/resellers/$id',
      token: adminToken,
      body: <String, dynamic>{'permissions': permissions},
    );
    expect(patched['status'], 200, reason: 'droits ${patched['body']}');
  }
  return id;
}

Future<Map<String, dynamic>> _send(
  String method,
  String path, {
  String? token,
  Map<String, dynamic>? body,
}) async {
  final http.Request req = http.Request(method, Uri.parse('$_base$path'));
  req.headers['Accept'] = 'application/json';
  if (token != null) req.headers['Authorization'] = 'Bearer $token';
  if (body != null) {
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode(body);
  }
  final http.StreamedResponse streamed =
      await req.send().timeout(const Duration(seconds: 15));
  final String text = await streamed.stream.bytesToString();
  Object? jsonBody;
  try {
    jsonBody = jsonDecode(text);
  } catch (_) {
    jsonBody = <String, dynamic>{};
  }
  return <String, dynamic>{
    'status': streamed.statusCode,
    'body': text,
    'json': jsonBody is Map<String, dynamic> ? jsonBody : <String, dynamic>{},
  };
}

Future<void> _seed({required bool onlyA}) async {
  await FavoritesRepository.instance.initialize();
  await RecentlyWatchedRepository.instance.initialize();
  final Database db = await PlaylistDatabase.instance.database;
  final int now = DateTime.now().millisecondsSinceEpoch;
  await _insertList(
    db,
    name: 'Liste A',
    user: _userA,
    pass: _passA,
    channel: 'ch-a',
    now: now,
    active: true,
  );
  if (!onlyA) {
    await _insertList(
      db,
      name: 'Liste B',
      user: _userB,
      pass: _passB,
      channel: 'ch-b',
      now: now + 1,
      active: false,
    );
  }
  await db.insert('favorites', <String, Object?>{'channel_id': 'ch-a'});
  await db.insert(
    'favorites_by_profile',
    <String, Object?>{'profile_id': 'p1', 'channel_id': 'ch-a'},
  );
  await db.insert(
    'favorites',
    <String, Object?>{'channel_id': 'ch-other'},
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
  await db.insert(
    'recently_watched',
    <String, Object?>{'channel_id': 'ch-a', 'last_watched_at': now},
  );
  await db.insert(
    'recently_watched_by_profile',
    <String, Object?>{
      'profile_id': 'p1',
      'channel_id': 'ch-a',
      'last_watched_at': now,
    },
  );
  await db.insert('watch_sessions', <String, Object?>{
    'channel_id': 'ch-a',
    'channel_name': 'Chaine A',
    'started_at': now,
    'duration_ms': 1000,
  });
  if (!onlyA) {
    await db.insert(
      'favorites_by_profile',
      <String, Object?>{'profile_id': 'p2', 'channel_id': 'ch-b'},
    );
    await db.insert('watch_sessions', <String, Object?>{
      'channel_id': 'ch-b',
      'channel_name': 'Chaine B',
      'started_at': now,
      'duration_ms': 1000,
    });
  }
  await PlaylistRepository.instance.initialize();
}

Future<void> _insertList(
  Database db, {
  required String name,
  required String user,
  required String pass,
  required String channel,
  required int now,
  required bool active,
}) async {
  final int id = await db.insert('playlists', <String, Object?>{
    'name': name,
    'type': 'xtream',
    'xtream_server': _server,
    'xtream_username': user,
    'xtream_password': pass,
    'created_at': now,
    'channel_count': 1,
    'is_active': active ? 1 : 0,
    'hidden': 0,
  });
  await db.insert('channels', <String, Object?>{
    'playlist_id': id,
    'external_id': channel,
    'name': name,
    'category': 'Autres',
    'stream_url': 'http://127.0.0.1:9/$channel.ts',
    'is_live': 1,
  });
}

Future<bool> _hasUser(String user) async {
  return (await _count('playlists', 'xtream_username = ?', <Object>[user])) > 0;
}

Future<int> _count(String table, String where, [List<Object?>? args]) async {
  final Database db = await PlaylistDatabase.instance.database;
  final List<Map<String, Object?>> rows = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM $table WHERE $where',
    args,
  );
  return (rows.first['n'] as int?) ?? 0;
}

Future<bool> _passwordPresent(String secret) async {
  final Database db = await PlaylistDatabase.instance.database;
  final List<Map<String, Object?>> rows =
      await db.rawQuery('SELECT xtream_password FROM playlists');
  for (final Map<String, Object?> row in rows) {
    if ('${row['xtream_password']}'.contains(secret)) return true;
  }
  return false;
}

Future<void> _waitUntil(FutureOr<bool> Function() ready, String label) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    if (await ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TestFailure('délai dépassé : $label');
}
