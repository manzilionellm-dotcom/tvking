// Simulation fonctionnelle de Zuno 107 face au Worker référencé en production.
// Le workflow copie CE TEST dans le code publié, sans modifier ses fichiers lib/.
// Seuls le système Android et le stockage de préférences sont remplacés.
// HTTP, WebSocket, SQLite, import M3U/Xtream et accusés utilisent le vrai code.
// Le fournisseur est local, synthétique : aucun abonnement client ni flux vidéo.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/device/data/device_identity.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';

const bool _kRun = bool.fromEnvironment('RUN_E2E');
const String _base = 'http://127.0.0.1:8787';
const String _adminSecret = 'local-simulation-only-not-production';
const String _mac = 'MK:AA:BB:CC:DD:17';
final Map<String, int> _hits = <String, int>{};

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttp();
  Process? worker;
  HttpServer? provider;
  late Directory persist;
  late String adminToken;
  late String fixtureBase;

  setUpAll(() async {
    if (!_kRun) return;
    // Garde-fou : ce scénario ne doit jamais contacter le backend public.
    expect(const String.fromEnvironment('BACKEND_URL'), _base);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': _mac,
    });
    final Directory dbDir = await Directory.systemTemp.createTemp(
      'zuno107-db-',
    );
    PlaylistDatabase.debugFilePath = '${dbDir.path}/tv_king.db';
    persist = await Directory.systemTemp.createTemp('zuno107-d1-');
    provider = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fixtureBase = 'http://127.0.0.1:${provider!.port}';
    provider!.listen(
      (HttpRequest req) => unawaited(_fixture(req, fixtureBase)),
    );
    worker = await _startWorker(persist.path);
    final Map<String, dynamic> login = await _request(
      'POST',
      '/api/v1/auth/login',
      body: <String, dynamic>{'email': 'admin', 'password': _adminSecret},
    );
    adminToken = login['token'] as String;
  });

  tearDownAll(() async {
    if (!_kRun) return;
    RemoteActivationWatch.instance.stopForTesting();
    if (worker != null) await _stopWorker(worker!);
    await provider?.close(force: true);
  });

  test(
    'activation, import réel, refus fidèle et reprise sur le serveur référencé',
    () async {
      FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
      PlaylistRepository.mergeAllPlaylists = true;
      await SubscriptionState.instance.initialize();
      await PlaylistRepository.instance.initialize();
      expect(PlaylistRepository.instance.currentChannels, isEmpty);
      expect(await DeviceIdentity.instance.mac, _mac);
      RemoteActivationWatch.instance.start();
      await _waitUntil(
        () => SubscriptionState.instance.remote.exists,
        'premier statut',
      );

      // Le chronomètre couvre l'appel admin ET le retour de la vraie app.
      final Stopwatch activation = Stopwatch()..start();
      final Map<String, dynamic> act = await _request(
        'POST',
        '/api/v1/activate',
        token: adminToken,
        body: <String, dynamic>{'mac': _mac, 'plan': 'lifetime'},
      );
      await _waitUntil(
        () => SubscriptionState.instance.remote.paid,
        'licence appliquée',
      );
      _measure('activation_app', activation);
      await _terminalOrder(adminToken, act, 'applied');
      _measure('activation_confirmee_panel', activation);

      // Aucun INSERT de chaînes dans le test : les octets M3U passent vraiment
      // par le téléchargement, le parseur, SQLite et les snapshots de l'app.
      await _import(
        adminToken,
        '$fixtureBase/liste-a.m3u',
        'A',
        3,
        'm3u_initial',
      );
      expect(_hits['/liste-a.m3u'], greaterThan(0));
      expect(
        PlaylistRepository.instance.currentPlaylists.single.type,
        PlaylistType.m3u,
      );

      // Même forme de lien get.php que celle fournie par le propriétaire,
      // avec des identifiants FACTICES. Vérifie le chemin Xtream prioritaire.
      final String xtream =
          '$fixtureBase/get.php?username=fixture-ok&password=fixture-only&type=m3u_plus&output=ts';
      await _import(adminToken, xtream, 'X', 5, 'get_php_via_xtream');
      expect(_hits['get_live_streams'], greaterThan(0));
      expect(
        _hits['/get.php'] ?? 0,
        0,
        reason: 'l’API Xtream évite le gros fichier',
      );
      expect(
        PlaylistRepository.instance.currentPlaylists.single.type,
        PlaylistType.xtream,
      );
      expect(
        PlaylistRepository.instance.currentPlaylists.single.m3uUrl,
        xtream,
      );

      // Un fournisseur qui refuse les identifiants doit donner FAILED au panel,
      // jamais un faux succès, et les cinq chaînes précédentes doivent rester.
      final Stopwatch refused = Stopwatch()..start();
      final Map<String, dynamic> bad = await _request(
        'PUT',
        '/api/v1/sources/$_mac',
        token: adminToken,
        body: _source(
          '$fixtureBase/get.php?username=fixture-refused&password=fixture-only&type=m3u_plus&output=ts',
        ),
      );
      final Map<String, dynamic> failed = await _terminalOrder(
        adminToken,
        bad,
        'failed',
      );
      expect(failed['error_code'], 'refused_kept_previous');
      expect(_channels('X', 5), isTrue);
      expect(PlaylistRepository.instance.currentPlaylists, hasLength(1));
      expect(
        _hits['/get.php'] ?? 0,
        0,
        reason: 'pas de repli M3U après refus explicite',
      );
      _measure('refus_fournisseur_confirme', refused);

      await _import(
        adminToken,
        '$fixtureBase/liste-b.m3u',
        'B',
        4,
        'remplacement_apres_refus',
      );

      // App mise en pause : l'ordre ne devient pas « appliqué » tout seul.
      RemoteActivationWatch.instance.stopForTesting();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final Map<String, dynamic> queued = await _request(
        'PUT',
        '/api/v1/sources/$_mac',
        token: adminToken,
        body: _source('$fixtureBase/liste-c.m3u'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final Map<String, dynamic> pending = await _readOrder(
        adminToken,
        queued['order_id'] as String,
      );
      expect(pending['state'], anyOf('created', 'sent'));
      expect(_channels('B', 4), isTrue);
      final Stopwatch resume = Stopwatch()..start();
      RemoteActivationWatch.instance.start();
      await _waitUntil(
        () => _channels('C', 2),
        'ordre conservé pendant la pause',
      );
      await _terminalOrder(adminToken, queued, 'applied');
      _measure('reprise_app_confirmee', resume);

      // Coupure réelle du Worker local, conservation du cache puis redémarrage
      // sur la même D1. Aucun effacement des données de l'app pour la reprise.
      RemoteActivationWatch.instance.stopForTesting();
      await _stopWorker(worker!);
      worker = null;
      expect(_channels('C', 2), isTrue);
      worker = await _startWorker(persist.path);
      final Map<String, dynamic> afterRestart = await _request(
        'PUT',
        '/api/v1/sources/$_mac',
        token: adminToken,
        body: _source('$fixtureBase/liste-d.m3u'),
      );
      final Stopwatch network = Stopwatch()..start();
      RemoteActivationWatch.instance.start();
      await _waitUntil(
        () => _channels('D', 3),
        'liste après redémarrage serveur',
      );
      await _terminalOrder(adminToken, afterRestart, 'applied');
      _measure('retour_serveur_confirme', network);

      final Stopwatch deletion = Stopwatch()..start();
      final Map<String, dynamic> cleared = await _request(
        'DELETE',
        '/api/v1/sources/$_mac',
        token: adminToken,
      );
      await _waitUntil(
        () => PlaylistRepository.instance.currentChannels.isEmpty,
        'chaînes effacées',
      );
      await _terminalOrder(adminToken, cleared, 'applied');
      expect(PlaylistRepository.instance.currentPlaylists, isEmpty);
      final Database db = await PlaylistDatabase.instance.database;
      expect(
        (await db.rawQuery('SELECT COUNT(*) AS n FROM channels')).single['n'],
        0,
      );
      expect(
        SubscriptionState.instance.remote.paid,
        isTrue,
        reason: 'effacer la liste ne coupe pas la licence',
      );
      expect(
        await DeviceIdentity.instance.mac,
        _mac,
        reason: 'identifiant inchangé',
      );
      _measure('effacement_confirme', deletion);
      debugPrint(
        'BILAN activation_import_m3u_xtream_refus_reprise_effacement=OK',
      );
    },
    skip: !_kRun,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Map<String, dynamic> _source(String url) => <String, dynamic>{
  'type': 'm3u',
  'm3u_url': url,
  'label': 'Fournisseur local de simulation',
};

bool _channels(String group, int count) {
  final channels = PlaylistRepository.instance.currentChannels;
  return channels.length == count &&
      channels.every((c) => c.name.startsWith('Demo $group '));
}

Future<void> _import(
  String token,
  String url,
  String group,
  int count,
  String label,
) async {
  final Stopwatch clock = Stopwatch()..start();
  final Map<String, dynamic> sent = await _request(
    'PUT',
    '/api/v1/sources/$_mac',
    token: token,
    body: _source(url),
  );
  await _waitUntil(
    () => _channels(group, count),
    '$label : $count chaînes importées',
  );
  _measure('${label}_app', clock);
  final Map<String, dynamic> ack = await _terminalOrder(token, sent, 'applied');
  expect(ack['result'], 'loaded');
  expect(ack['applied_rev'], sent['rev']);
  final Database db = await PlaylistDatabase.instance.database;
  expect(
    (await db.rawQuery('SELECT COUNT(*) AS n FROM channels')).single['n'],
    count,
  );
  _measure('${label}_confirme_panel', clock);
}

void _measure(String label, Stopwatch clock) {
  final double seconds = clock.elapsedMicroseconds / 1000000;
  debugPrint('MESURE ${label}_secondes=${seconds.toStringAsFixed(3)}');
  expect(seconds, lessThan(12), reason: 'délai de simulation : $label');
}

Future<Map<String, dynamic>> _terminalOrder(
  String token,
  Map<String, dynamic> sent,
  String expected,
) async {
  expect(sent['order_id'], isA<String>());
  Map<String, dynamic> order = <String, dynamic>{};
  await _waitUntil(() async {
    order = await _readOrder(token, sent['order_id'] as String);
    return <String>['applied', 'failed', 'expired'].contains(order['state']);
  }, 'accusé terminal de la vraie app');
  expect(
    order['state'],
    expected,
    reason: 'résultat=${order['result']} erreur=${order['error_code']}',
  );
  expect(order['received_at'], greaterThan(0));
  if (expected == 'applied') expect(order['applied_srv'], greaterThan(0));
  return order;
}

Future<Map<String, dynamic>> _readOrder(String token, String id) async {
  final Map<String, dynamic> result = await _request(
    'GET',
    '/api/v1/orders?mac=${Uri.encodeComponent(_mac)}',
    token: token,
  );
  for (final dynamic row in result['items'] as List<dynamic>) {
    if (row['order_id'] == id) return Map<String, dynamic>.from(row as Map);
  }
  return <String, dynamic>{};
}

Future<Map<String, dynamic>> _request(
  String method,
  String path, {
  String? token,
  Map<String, dynamic>? body,
}) async {
  final http.Request req = http.Request(method, Uri.parse('$_base$path'));
  if (token != null) req.headers['Authorization'] = 'Bearer $token';
  if (body != null) {
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode(body);
  }
  final http.Response response = await http.Response.fromStream(
    await req.send(),
  ).timeout(const Duration(seconds: 10));
  expect(
    response.statusCode,
    anyOf(200, 201),
    reason: '$method $path : HTTP ${response.statusCode}',
  );
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<void> _waitUntil(FutureOr<bool> Function() ready, String label) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (await ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TestFailure('délai dépassé : $label');
}

Future<void> _fixture(HttpRequest req, String base) async {
  // Serveur fermé sur ses seules données synthétiques, sans proxy sortant.
  final String path = req.uri.path;
  _hits[path] = (_hits[path] ?? 0) + 1;
  if (path == '/player_api.php') {
    final String action = req.uri.queryParameters['action'] ?? 'auth';
    _hits[action] = (_hits[action] ?? 0) + 1;
    Object body;
    if (req.uri.queryParameters['username'] != 'fixture-ok') {
      body = <String, Object>{
        'user_info': <String, Object>{'auth': 0},
      };
    } else if (action == 'auth') {
      body = <String, Object>{
        'user_info': <String, Object>{'auth': 1, 'status': 'Active'},
      };
    } else if (action == 'get_live_categories') {
      body = <Object>[
        <String, Object>{'category_id': '1', 'category_name': 'Simulation'},
      ];
    } else if (action == 'get_live_streams') {
      body = <Object>[
        for (int i = 1; i <= 5; i++)
          <String, Object>{
            'stream_id': i,
            'name': 'Demo X $i',
            'category_id': '1',
            'stream_type': 'live',
          },
      ];
    } else {
      body = <Object>[];
    }
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
  } else if (path == '/xmltv.php') {
    req.response.headers.contentType = ContentType('application', 'xml');
    req.response.write('<?xml version="1.0"?><tv></tv>');
  } else if (<String>[
    '/liste-a.m3u',
    '/liste-b.m3u',
    '/liste-c.m3u',
    '/liste-d.m3u',
  ].contains(path)) {
    final String group = path.substring(7, 8).toUpperCase();
    final int count = <String, int>{'A': 3, 'B': 4, 'C': 2, 'D': 3}[group]!;
    req.response.headers.contentType = ContentType(
      'audio',
      'x-mpegurl',
      charset: 'utf-8',
    );
    req.response.writeln('#EXTM3U');
    for (int i = 1; i <= count; i++) {
      req.response.writeln(
        '#EXTINF:-1 tvg-id="$group-$i" group-title="Simulation",Demo $group $i',
      );
      req.response.writeln('$base/stream/$group-$i.ts');
    }
  } else {
    req.response.statusCode = HttpStatus.notFound;
  }
  await req.response.close();
}

// Démarrage isolé repris du banc E2E publié ; aucun secret Cloudflare.
Future<Process> _startWorker(String persistDir) async {
  final ProcessResult schema = await Process.run(
    'npx',
    <String>[
      'wrangler',
      'd1',
      'execute',
      'tvking_licensing',
      '--local',
      '--persist-to',
      persistDir,
      '--file',
      'schema.sql',
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
      'wrangler',
      'd1',
      'execute',
      'tvking_licensing',
      '--local',
      '--persist-to',
      persistDir,
      '--file',
      'migrations/003_reseller_hierarchy.sql',
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
      '--local',
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
