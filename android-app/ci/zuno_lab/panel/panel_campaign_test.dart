import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/device/data/device_secret.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';

class _LocalHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (uri) =>
          ['localhost', '127.0.0.1', '::1'].contains(uri.host)
          ? 'DIRECT'
          : 'PROXY 127.0.0.1:1';
  }
}

bool reportHasOriginFailure(String? error) => error != null && error.isNotEmpty;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _LocalHttp();
  test('panel de test, révisions 5k et 20k, perte ACK, refus partiel', () async {
    expect(kSubscriptionBaseUrl, 'http://127.0.0.1:18787');
    final secret = Platform.environment['ZUNO_QA_PASS']!;
    final out = File(Platform.environment['ZUNO_QA_PROOF']!);
    final evidence = <Map<String, Object?>>[];
    void save(Map<String, Object?> row) {
      evidence.add(row);
      out.writeAsStringSync(jsonEncode(evidence));
    }

    // Identité entièrement fabriquée pour la base locale temporaire.
    final mac =
        'MK:' +
        List.generate(
          5,
          (i) => (176 + i).toRadixString(16).toUpperCase(),
        ).join(':');
    SharedPreferences.setMockInitialValues({'device.virtual_mac.v1': mac});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    PlaylistRepository.mergeAllPlaylists = true;
    final storage = await Directory.systemTemp.createTemp('zuno-panel-local-');
    PlaylistDatabase.debugFilePath = '${storage.path}/tv.db';
    final client = http.Client();
    final media = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      client.close();
      await media.close(force: true);
      await PlaylistDatabase.instance.closeForTesting();
      await storage.delete(recursive: true);
    });
    final requests = <int, int>{};
    media.listen((q) async {
      final size = int.parse(q.uri.pathSegments.last.split('.').first);
      requests[size] = (requests[size] ?? 0) + 1;
      if (size == 0) {
        q.response.statusCode = 404;
        await q.response.close();
        return;
      }
      q.response.headers.contentType = ContentType(
        'audio',
        'x-mpegurl',
        charset: 'utf-8',
      );
      q.response.write('#EXTM3U\n');
      for (var i = 0; i < size; i++) {
        q.response.write(
          '#EXTINF:-1 tvg-id="lab.$i" group-title="Groupe ${i % 8}",LAB ${size}_$i\nhttp://127.0.0.1/media/${size}_$i.ts\n',
        );
      }
      await q.response.close();
    });
    String? token;
    Future<Map<String, dynamic>> api(
      String method,
      String route, [
      Map<String, Object?>? body,
    ]) async {
      final req = http.Request(
        method,
        Uri.parse('$kSubscriptionBaseUrl$route'),
      );
      if (token != null)
        req.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      if (body != null) {
        req.headers[HttpHeaders.contentTypeHeader] = 'application/json';
        req.body = jsonEncode(body);
      }
      final res = await http.Response.fromStream(await client.send(req));
      expect(
        res.statusCode,
        inInclusiveRange(200, 201),
        reason: '$method route de test HTTP ${res.statusCode}',
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    }

    token =
        (await api('POST', '/api/v1/auth/login', {
              'email': 'admin',
              'password': secret,
            }))['token']
            as String;
    // Cohorte isolée, aucune opération sur un service de production.
    await api('GET', '/api/status/$mac');
    await api('POST', '/api/v1/activate', {'mac': mac, 'plan': 'lifetime'});
    await DeviceSecret.instance.enroll(mac);
    await SubscriptionState.instance.initialize();
    await PlaylistRepository.instance.initialize();
    RepairFlags.realtimeLegacy =
        true; // Exercise the numeric long-poll contract.
    RemoteActivationWatch.instance.start();
    addTearDown(RemoteActivationWatch.instance.stopForTesting);
    Future<Map<String, Object?>> sqlite() async {
      final db = await PlaylistDatabase.instance.database;
      final counts = (await db.rawQuery(
        'SELECT COUNT(*) AS rows, COUNT(DISTINCT category) AS categories,COUNT(DISTINCT stream_url) AS distinct_urls FROM channels',
      )).single;
      final n = (await db.rawQuery('SELECT COUNT(*) n FROM playlists'))
          .single['n'];
      final visible = await PlaylistRepository.instance.getAllChannels();
      return {
        ...counts,
        'playlists': n,
        'visible_repository_rows': visible.length,
      };
    }

    for (final sizes in <List<int>>[
      [5000],
      [20000],
      [20000, 0],
      [20000],
    ]) {
      final watch = Stopwatch()..start();
      final since = DateTime.now().millisecondsSinceEpoch;
      await api('PUT', '/api/v1/sources/$mac', {
        'sources': sizes
            .map(
              (n) => {
                'type': 'm3u',
                'm3u_url': 'http://127.0.0.1:${media.port}/$n.m3u',
                'label': 'LAB $n',
              },
            )
            .toList(),
      });
      final sourceWire = await client.get(
        Uri.parse('$kSubscriptionBaseUrl/api/device-source/$mac'),
        headers: await DeviceSecret.instance.headers(),
      );
      expect(sourceWire.statusCode, 200);
      final deliveredRev = (jsonDecode(sourceWire.body) as Map)['source_rev'] as int;
      expect(deliveredRev, isA<int>());
      final valid = sizes.length == 1;
      int? acceptedId;
      int? acceptedTime;
      int? lastSuccessfulId;
      int? firstFailedAt;
      int? pendingRefusedId;
      bool sameOrderRedelivered = false;
      final timestamps = <int>{};
      List<int> pendingIds = [];
      while (watch.elapsed < const Duration(seconds: 25)) {
        final live = await api('GET', '/api/v1/boxes/live?mac=$mac');
        final item = (live['items'] as List).first as Map;

        pendingIds = [
          for (final o in (item['pending'] as List).whereType<Map>())
            if (o['kind'] == 'source') o['id'] as int,
        ];
        final applied = item['last_applied'] as Map?;
        final last = RemoteSourceRepository.lastReport;
        if (applied?['kind'] == 'source' &&
            (applied?['applied_at'] as int? ?? 0) >= deliveredRev) {
          acceptedId = applied?['id'] as int?;
          acceptedTime = applied?['applied_at'] as int?;
        }
        lastSuccessfulId = applied?['id'] as int?;
        if (last != null &&
            last.atMs >= since &&
            ((valid && acceptedId != null) ||
                (!valid && (requests[0] ?? 0) > 0))) {
          if (valid) break;
          if (reportHasOriginFailure(last.error)) {
            timestamps.add(last.atMs);
            firstFailedAt ??= watch.elapsedMilliseconds;
            if (pendingIds.isNotEmpty) {
              pendingRefusedId ??= pendingIds.last;
              if (timestamps.length >= 2 &&
                  pendingIds.contains(pendingRefusedId)) {
                sameOrderRedelivered = true;
                break;
              }
            }
            // A numeric success on the first failed delivery is the defect.
            if (acceptedId != null &&
                watch.elapsedMilliseconds - firstFailedAt > 500)
              break;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final report = RemoteSourceRepository.lastReport;
      final snap = await sqlite();
      save({
        'step': 'watch',
        'sizes': sizes,
        'wire_rev': deliveredRev,
        'read_rev': report?.configRev,
        'report': report?.result,
        'rows': snap,
        'last_success_id': lastSuccessfulId,
        'accepted_id': acceptedId,
        'refused_id': pendingRefusedId,
        'pending_ids': pendingIds,
        'same_failed_revision_retried': sameOrderRedelivered,
        'distinct_refusal_timestamps': timestamps.toList(),
        'accepted_at': acceptedTime,
        'elapsed_ms': watch.elapsedMilliseconds,
        'requests': requests.map((k, v) => MapEntry(k.toString(), v)),
      });
    }
    RemoteActivationWatch.instance.stopForTesting();
    await PlaylistDatabase.instance.closeForTesting();
    save({'step': 'reopen_database', 'db': await sqlite()});
    final imports = evidence.where((row) => row['step'] == 'watch').toList();
    expect(imports.length, 4);
    expect(imports.last['pending_ids'], contains(imports[2]['refused_id']));
    expect((evidence.last['db'] as Map)['rows'], 20000);
    for (final sample in imports) {
      expect(sample['read_rev'], sample['wire_rev']);
      final rows = sample['rows'] as Map;
      final sizes = sample['sizes'] as List;
      expect(rows['rows'], sizes.first);
      expect(rows['distinct_urls'], sizes.first);
      expect(rows['visible_repository_rows'], sizes.first);
      expect(rows['categories'], 8);
      if (sizes.length == 1) {
        expect(sample['report'], 'loaded');
        expect(sample['accepted_id'], isNotNull);
      } else {
        expect(sample['report'], 'sourceFailed');
        expect(sample['accepted_id'], isNull);
        expect(sample['same_failed_revision_retried'], isTrue);
        expect((sample['requests'] as Map)['0'], greaterThan(0));
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
