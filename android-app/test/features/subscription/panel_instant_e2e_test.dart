// =========================================================
//  panel_instant_e2e_test.dart — Preuve : chaque action du panel
//  arrive sur la box, avec l'heure d'accusé.
// =========================================================
//  Worker RÉEL (wrangler dev + D1 locale) et code client RÉEL
//  (RemoteActivationWatch, BoxSignalClient, SubscriptionState).
//
//    flutter test --dart-define=RUN_E2E=true \
//      --dart-define=BACKEND_URL=http://127.0.0.1:8787 \
//      test/features/subscription/panel_instant_e2e_test.dart
//
//  Sans RUN_E2E, le test est ignoré.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/device/data/device_secret.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/signal_inbox.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';

const bool _kRun = bool.fromEnvironment('RUN_E2E');
const String _base = 'http://127.0.0.1:8787';
const String _adminSecret = 'e2e-admin-secret-not-production';
const String _mac = 'MK:AA:BB:CC:DD:01';
const String _other = 'MK:AA:BB:CC:DD:02';
const String _rateMac = 'MK:AA:BB:CC:DD:03';
const String _pass = 'secret-liste-a';

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
    'chaque action du panel arrive, avec accusé, 401 et 403',
    () async {
      FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
      SignalInbox.instance.resetForTesting();
      await SubscriptionState.instance.initialize();

      // ----- Sécurité, avant d'ouvrir le canal -----
      final Map<String, dynamic> noToken = await _send('GET', '/api/v1/boxes/live');
      expect(noToken['status'], 401, reason: 'live sans jeton');

      final Map<String, dynamic> noSecret = await _send(
        'GET',
        '/api/box/wait/$_mac?timeout=200',
      );
      expect(noSecret['status'], 401, reason: 'attente sans secret');

      final Map<String, dynamic> badSecret = await _send(
        'GET',
        '/api/box/wait/$_mac?timeout=200',
        headers: <String, String>{
          'X-Device-Secret': 'mauvais-secret-0123456789abcdef',
        },
      );
      expect(badSecret['status'], 401, reason: 'mauvais secret');

      final Map<String, dynamic> oldStatus =
          await _send('GET', '/api/status/$_mac');
      expect(oldStatus['status'], 200, reason: 'ancien statut sans secret');
      // Sur une base neuve, la table des listes n'existe pas encore :
      // le numéro de source est alors absent (comportement 103).
      // `revoked` est toujours là, et aucun secret n'est demandé.
      expect(oldStatus['body'].toString().contains('revoked'), isTrue,
          reason: oldStatus['body'].toString());
      expect(oldStatus['body'].toString().contains(_pass), isFalse);

      final String resellerA = await _reseller(
        adminToken,
        email: 'a-instant@exemple.test',
        password: 'revendeur-a-secret',
        permissions: <String>['activate', 'sources'],
      );
      final String tokenB = await _login(
        'b-instant@exemple.test',
        'revendeur-b-secret',
        create: true,
        reseller: true,
        adminToken: adminToken,
        permissions: <String>['activate', 'sources'],
      );
      final String tokenA = await _login(
        'a-instant@exemple.test',
        'revendeur-a-secret',
        reseller: true,
      );

      await _send('GET', '/api/status/$_other');
      final Map<String, dynamic> claim = await _send(
        'POST',
        '/api/v1/activate',
        token: adminToken,
        body: <String, dynamic>{
          'mac': _other,
          'plan': 'trial_7d',
          'reseller_id': resellerA,
        },
      );
      expect(claim['status'], anyOf(200, 201), reason: claim['body'].toString());

      final Map<String, dynamic> liveB = await _send(
        'GET',
        '/api/v1/boxes/live?mac=$_other',
        token: tokenB,
      );
      expect(liveB['status'], 403, reason: 'autre revendeur');
      expect(liveB['body'].toString().contains(_pass), isFalse);

      final Map<String, dynamic> liveA = await _send(
        'GET',
        '/api/v1/boxes/live?mac=$_other',
        token: tokenA,
      );
      expect(liveA['status'], 200, reason: liveA['body'].toString());
      expect(liveA['body'].toString().contains(_other), isTrue);

      final Map<String, dynamic> listB = await _send(
        'GET',
        '/api/v1/boxes/live',
        token: tokenB,
      );
      expect(listB['status'], 200);
      expect(listB['body'].toString().contains(_other), isFalse);
      expect(listB['body'].toString().contains(_mac), isFalse);

      final Map<String, dynamic> steal = await _send(
        'DELETE',
        '/api/v1/sources/$_other',
        token: tokenB,
      );
      expect(steal['status'], 403, reason: 'effacement par un autre');

      final String? licenseId = claim['json']['license_id'] as String?;
      expect(licenseId, isNotNull);
      final Map<String, dynamic> foreignRenew = await _send(
        'POST',
        '/api/v1/licenses/$licenseId/renew',
        token: tokenB,
        body: <String, dynamic>{'plan': 'yearly'},
      );
      expect(foreignRenew['status'], 403, reason: 'renouvellement d\'un autre');

      // Limite : 30 attentes par minute, la 31e est refusée.
      const String rateSecret = 'rate-secret-0123456789abcdefEXTRA';
      final Map<String, dynamic> enroll = await _send(
        'POST',
        '/api/device-proof',
        body: <String, dynamic>{
          'mac': _rateMac,
          'androidId': '',
          'secret': rateSecret,
        },
      );
      expect(enroll['status'], 200, reason: enroll['body'].toString());
      int limited = 0;
      for (int i = 0; i < 31; i++) {
        final Map<String, dynamic> w = await _send(
          'GET',
          '/api/box/wait/$_rateMac?timeout=200',
          headers: <String, String>{'X-Device-Secret': rateSecret},
        );
        if (w['status'] == 429) limited = i + 1;
        if (limited != 0) break;
      }
      expect(limited, 31, reason: 'la 31e attente doit être limitée');

      // La version remonte avec l'attente, pas avec un heartbeat.
      final String boxSecret = await DeviceSecret.instance.getOrCreate();
      final Map<String, dynamic> proof = await _send(
        'POST',
        '/api/device-proof',
        body: <String, dynamic>{
          'mac': _mac,
          'androidId': 'android-e2e',
          'secret': boxSecret,
        },
      );
      expect(proof['status'], 200, reason: proof['body'].toString());
      final Map<String, dynamic> ver = await _send(
        'GET',
        '/api/box/wait/$_mac?timeout=200&v=103-test&b=11',
        headers: <String, String>{'X-Device-Secret': boxSecret},
      );
      expect(ver['status'], 200, reason: ver['body'].toString());
      final Map<String, dynamic> liveVer = await _send(
        'GET',
        '/api/v1/boxes/live?mac=$_mac',
        token: adminToken,
      );
      expect(liveVer['status'], 200, reason: liveVer['body'].toString());
      expect(liveVer['body'].toString().contains('103-test'), isTrue);

      // ----- Canal réel de l'app -----
      RemoteActivationWatch.instance.start();
      final Map<String, double> measures = <String, double>{};

      Future<void> measure(String kind, Future<void> Function() act) async {
        final int before = SignalInbox.instance.appliedKinds.length;
        final Stopwatch sw = Stopwatch()..start();
        await act();
        await _waitUntil(
          () => SignalInbox.instance.appliedKinds.skip(before).contains(kind),
          kind,
        );
        sw.stop();
        final double seconds = sw.elapsedMilliseconds / 1000.0;
        measures[kind] = seconds;
        // ignore: avoid_print
        print('MESURE ${kind}_secondes=$seconds');
        expect(seconds, lessThan(8), reason: kind);
      }

      String? deviceId;
      String? mainLicense;
      await measure('activate', () async {
        final Map<String, dynamic> act = await _send(
          'POST',
          '/api/v1/activate',
          token: adminToken,
          body: <String, dynamic>{'mac': _mac, 'plan': 'lifetime'},
        );
        expect(act['status'], anyOf(200, 201), reason: act['body'].toString());
        deviceId = act['json']['device_id'] as String?;
        mainLicense = act['json']['license_id'] as String?;
      });
      expect(SubscriptionState.instance.remote.paid, isTrue);
      expect(deviceId, isNotNull);
      expect(mainLicense, isNotNull);

      final Map<String, dynamic> liveNow = await _send(
        'GET',
        '/api/v1/boxes/live?mac=$_mac',
        token: adminToken,
      );
      final Map<String, dynamic> item = _liveItem(liveNow);
      expect(item['online'], isTrue);
      expect(item['last_applied'], isNotNull);
      final int appliedAt =
          (item['last_applied'] as Map)['applied_at'] as int;
      expect(appliedAt, greaterThan(0));
      // ignore: avoid_print
      print('MESURE applique_a_epoch_ms=$appliedAt');

      await measure('suspend', () async {
        final Map<String, dynamic> r = await _send(
          'PATCH',
          '/api/v1/devices/$deviceId',
          token: adminToken,
          body: <String, dynamic>{'block_status': 'frozen'},
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });
      expect(SubscriptionState.instance.remote.frozen, isTrue);

      await measure('resume', () async {
        final Map<String, dynamic> r = await _send(
          'PATCH',
          '/api/v1/devices/$deviceId',
          token: adminToken,
          body: <String, dynamic>{'block_status': 'active'},
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });
      expect(SubscriptionState.instance.remote.frozen, isFalse);

      await measure('block', () async {
        final Map<String, dynamic> r = await _send(
          'PATCH',
          '/api/v1/devices/$deviceId',
          token: adminToken,
          body: <String, dynamic>{'block_status': 'banned'},
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });
      expect(SubscriptionState.instance.remote.banned, isTrue);

      await measure('resume', () async {
        final Map<String, dynamic> r = await _send(
          'PATCH',
          '/api/v1/devices/$deviceId',
          token: adminToken,
          body: <String, dynamic>{'block_status': 'active'},
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });

      await measure('expire', () async {
        final Map<String, dynamic> r = await _send(
          'PATCH',
          '/api/v1/licenses/$mainLicense',
          token: adminToken,
          body: <String, dynamic>{
            'expires_at': DateTime.now().millisecondsSinceEpoch - 5000,
            'status': 'active',
          },
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });
      expect(SubscriptionState.instance.remote.expired, isTrue);

      await measure('renew', () async {
        final Map<String, dynamic> r = await _send(
          'POST',
          '/api/v1/licenses/$mainLicense/renew',
          token: adminToken,
          body: <String, dynamic>{'plan': 'yearly'},
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });
      expect(SubscriptionState.instance.remote.paid, isTrue);

      await measure('source', () async {
        final Map<String, dynamic> r = await _send(
          'PUT',
          '/api/v1/sources/$_mac',
          token: adminToken,
          body: <String, dynamic>{
            'type': 'xtream',
            'server_url': 'http://127.0.0.1:9',
            'username': 'user-a',
            'password': _pass,
          },
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });
      expect(
        RemoteActivationWatch.instance.lastSignalBody.contains(_pass),
        isFalse,
        reason: 'le canal ne transporte pas le mot de passe',
      );

      await measure('source_clear', () async {
        final Map<String, dynamic> r = await _send(
          'DELETE',
          '/api/v1/sources/$_mac',
          token: adminToken,
          body: <String, dynamic>{
            'server_url': 'http://127.0.0.1:9',
            'username': 'user-a',
          },
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });

      await measure('message', () async {
        final Map<String, dynamic> r = await _send(
          'POST',
          '/api/v1/announcements',
          token: adminToken,
          body: <String, dynamic>{
            'title': 'Bonjour',
            'body': 'Message de test',
          },
        );
        expect(r['status'], anyOf(200, 201), reason: r['body'].toString());
      });

      await measure('theme', () async {
        final Map<String, dynamic> r = await _send(
          'PUT',
          '/api/v1/theme?platform=tv',
          token: adminToken,
          body: <String, dynamic>{
            'appName': 'Zuno',
            'accent': '#112233',
            'bg': 'dark',
          },
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });

      await measure('force_update', () async {
        final Map<String, dynamic> r = await _send(
          'POST',
          '/api/v1/force-update?platform=tv',
          token: adminToken,
          body: <String, dynamic>{'action': 'disable'},
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });

      await measure('featured', () async {
        final Map<String, dynamic> r = await _send(
          'POST',
          '/api/v1/featured',
          token: adminToken,
          body: <String, dynamic>{'name': '', 'note': ''},
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });

      await measure('ad', () async {
        final Map<String, dynamic> r = await _send(
          'PUT',
          '/api/v1/ad',
          token: adminToken,
          body: <String, dynamic>{'enabled': false, 'url': ''},
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });

      await measure('pricing', () async {
        final Map<String, dynamic> r = await _send(
          'PUT',
          '/api/v1/pricing',
          token: adminToken,
          body: <String, dynamic>{'lifetime': '9,9', 'yearly': '4,9'},
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });

      await measure('feedback', () async {
        final Map<String, dynamic> r = await _send(
          'PUT',
          '/api/v1/feedback-prompt',
          token: adminToken,
          body: <String, dynamic>{'enabled': false, 'message': ''},
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });

      await measure('home', () async {
        final Map<String, dynamic> r = await _send(
          'PUT',
          '/api/v1/home-layout',
          token: adminToken,
          body: <String, dynamic>{'items': <Object>[]},
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });

      await measure('servers', () async {
        final Map<String, dynamic> r = await _send(
          'POST',
          '/api/v1/servers',
          token: adminToken,
          body: <String, dynamic>{
            'label': 'Serveur test',
            'url': 'http://127.0.0.1:9',
          },
        );
        expect(r['status'], anyOf(200, 201), reason: r['body'].toString());
      });

      await measure('license', () async {
        final Map<String, dynamic> r = await _send(
          'POST',
          '/api/v1/grant-trial-all',
          token: adminToken,
          body: <String, dynamic>{'days': 7},
        );
        expect(r['status'], 200, reason: r['body'].toString());
      });

      // Même ordre une deuxième fois : l'heure d'accusé ne bouge pas.
      final Map<String, dynamic> beforeAck = await _send(
        'GET',
        '/api/v1/boxes/live?mac=$_mac',
        token: adminToken,
      );
      final Map<String, dynamic> applied = _liveItem(beforeAck);
      final int stamp =
          (applied['last_applied'] as Map)['applied_at'] as int;
      final int id = (applied['last_applied'] as Map)['id'] as int;
      final Map<String, dynamic> again = await _send(
        'POST',
        '/api/box/ack/$_mac',
        headers: <String, String>{'X-Device-Secret': boxSecret},
        body: <String, dynamic>{
          'box': <int>[id],
          'fleet': <int>[],
        },
      );
      expect(again['status'], 200, reason: again['body'].toString());
      expect(again['json']['already'], isTrue);
      final Map<String, dynamic> afterAck = await _send(
        'GET',
        '/api/v1/boxes/live?mac=$_mac',
        token: adminToken,
      );
      final int stamp2 =
          (_liveItem(afterAck)['last_applied'] as Map)['applied_at'] as int;
      expect(stamp2, stamp);

      // Box arrêtée : l'ordre reste en file, il part au rallumage.
      RemoteActivationWatch.instance.stopForTesting();
      final int mark = SignalInbox.instance.appliedKinds.length;
      final Stopwatch reprise = Stopwatch()..start();
      final Map<String, dynamic> queued = await _send(
        'PATCH',
        '/api/v1/devices/$deviceId',
        token: adminToken,
        body: <String, dynamic>{'block_status': 'frozen'},
      );
      expect(queued['status'], 200, reason: queued['body'].toString());
      expect(SubscriptionState.instance.remote.frozen, isFalse);
      RemoteActivationWatch.instance.start();
      await _waitUntil(
        () => SignalInbox.instance.appliedKinds.skip(mark).contains('suspend'),
        'reprise',
      );
      reprise.stop();
      final double repriseS = reprise.elapsedMilliseconds / 1000.0;
      // ignore: avoid_print
      print('MESURE reprise_secondes=$repriseS');
      expect(repriseS, lessThan(8));
      expect(SubscriptionState.instance.remote.frozen, isTrue);

      // Coupure du Worker : l'état déjà connu reste. Au retour, l'ordre part.
      final Process running = worker!;
      await _stopWorker(running);
      worker = null;
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(SubscriptionState.instance.remote.frozen, isTrue);
      worker = await _startWorker(persist.path);
      final int mark2 = SignalInbox.instance.appliedKinds.length;
      final Stopwatch back = Stopwatch()..start();
      // La D1 locale peut répondre « database is locked » une fois,
      // juste après le redémarrage du Worker. On réessaie : c'est
      // le fichier SQLite de wrangler, pas un refus de l'API.
      Map<String, dynamic> afterNet = <String, dynamic>{};
      for (int i = 0; i < 15; i++) {
        afterNet = await _send(
          'PATCH',
          '/api/v1/devices/$deviceId',
          token: adminToken,
          body: <String, dynamic>{'block_status': 'active'},
        );
        if (afterNet['status'] == 200) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(afterNet['status'], 200, reason: afterNet['body'].toString());
      await _waitUntil(
        () => SignalInbox.instance.appliedKinds.skip(mark2).contains('resume'),
        'retour réseau',
      );
      back.stop();
      final double backS = back.elapsedMilliseconds / 1000.0;
      // ignore: avoid_print
      print('MESURE retour_reseau_secondes=$backS');
      expect(backS, lessThan(12));
      expect(SubscriptionState.instance.remote.frozen, isFalse);

      // Transfert : une autre box, le même code d'attente.
      const String fresh = 'MK:AA:BB:CC:DD:04';
      await _send('GET', '/api/status/$fresh');
      final Map<String, dynamic> enrollFresh = await _send(
        'POST',
        '/api/device-proof',
        body: <String, dynamic>{
          'mac': fresh,
          'androidId': '',
          'secret': boxSecret,
        },
      );
      expect(enrollFresh['status'], 200, reason: enrollFresh['body'].toString());
      final http.Client client = http.Client();
      try {
        // Les messages / thèmes déjà envoyés sont en file pour tout
        // le parc. On les laisse de côté : on mesure le transfert.
        final http.Response drained = await client.get(
          Uri.parse('$_base/api/box/wait/${Uri.encodeComponent(fresh)}?after=0&fleet_after=0&timeout=200'),
          headers: <String, String>{
            'Accept': 'application/json',
            'X-Device-Secret': boxSecret,
          },
        );
        expect(drained.statusCode, 200, reason: drained.body);
        int fleetAfter = 0;
        final Object? drainedJson = jsonDecode(drained.body);
        if (drainedJson is Map<String, dynamic>) {
          final List<dynamic> fleet =
              drainedJson['fleet'] as List<dynamic>? ?? <dynamic>[];
          for (final Object? row in fleet) {
            if (row is Map && row['id'] is num) {
              final int id = (row['id'] as num).toInt();
              if (id > fleetAfter) fleetAfter = id;
            }
          }
        }
        final Future<http.Response> waiting = client.get(
          Uri.parse(
            '$_base/api/box/wait/${Uri.encodeComponent(fresh)}'
            '?after=0&fleet_after=$fleetAfter&timeout=8000',
          ),
          headers: <String, String>{
            'Accept': 'application/json',
            'X-Device-Secret': boxSecret,
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final Stopwatch transferSw = Stopwatch()..start();
        final Map<String, dynamic> moved = await _send(
          'POST',
          '/api/v1/transfer',
          token: adminToken,
          body: <String, dynamic>{'old_mac': _other, 'new_mac': fresh},
        );
        expect(moved['status'], 200, reason: moved['body'].toString());
        final http.Response got =
            await waiting.timeout(const Duration(seconds: 10));
        transferSw.stop();
        final double transferS = transferSw.elapsedMilliseconds / 1000.0;
        // ignore: avoid_print
        print('MESURE transfer_secondes=$transferS');
        expect(got.statusCode, 200, reason: got.body);
        expect(got.body.contains('transfer'), isTrue, reason: got.body);
        expect(got.body.contains(_pass), isFalse);
        expect(transferS, lessThan(8));
      } finally {
        client.close();
      }

      // ignore: avoid_print
      print('MESURES ${jsonEncode(measures)}');
    },
    skip: _kRun ? false : 'RUN_E2E non posé — preuve miniflare non lancée',
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Map<String, dynamic> _liveItem(Map<String, dynamic> res) {
  final Object? json = res['json'];
  expect(json, isA<Map<String, dynamic>>());
  final List<dynamic> items =
      (json! as Map<String, dynamic>)['items'] as List<dynamic>;
  expect(items, isNotEmpty);
  return (items.first as Map).cast<String, dynamic>();
}

Future<void> _waitUntil(bool Function() ready, String label) async {
  final DateTime end = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(end)) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('délai dépassé : $label');
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
      'wrangler', 'dev',
      '--port', '8787',
      '--ip', '127.0.0.1',
      '--persist-to', persistDir,
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
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  process.kill();
  throw StateError('wrangler pas prêt\n$log');
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

Future<void> _freeDevPort() async {
  // `ps` tronque la ligne : on lit /proc, sinon le redémarrage
  // du Worker (coupure réseau) trouve le port encore pris.
  const String script = r'''
import os, signal
port = 8787
skip = {os.getpid(), os.getppid()}
inodes = set()
for path in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        lines = open(path)
    except FileNotFoundError:
        continue
    next(lines, None)
    for line in lines:
        parts = line.split()
        if int(parts[1].split(":")[-1], 16) == port and parts[3] == "0A":
            inodes.add(parts[9])
pids = set()
for pid in os.listdir("/proc"):
    if not pid.isdigit() or int(pid) in skip:
        continue
    fd = f"/proc/{pid}/fd"
    try:
        names = os.listdir(fd)
    except OSError:
        names = []
    for name in names:
        try:
            target = os.readlink(f"{fd}/{name}")
        except OSError:
            continue
        if target.startswith("socket:[") and target[8:-1] in inodes:
            pids.add(int(pid))
    try:
        args = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\x00")
    except OSError:
        continue
    # Jetons séparés : le texte de CE script contient « 8787 »
    # mais pas l'option --port, donc il ne se tue pas lui-même.
    if b"--port" in args and b"8787" in args:
        pids.add(int(pid))
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
''';
  await Process.run('python3', <String>['-c', script]);
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
  Map<String, String>? headers,
}) async {
  final http.Request req = http.Request(method, Uri.parse('$_base$path'));
  req.headers['Accept'] = 'application/json';
  if (token != null) req.headers['Authorization'] = 'Bearer $token';
  if (headers != null) req.headers.addAll(headers);
  if (body != null) {
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode(body);
  }
  final http.StreamedResponse streamed =
      await req.send().timeout(const Duration(seconds: 20));
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
