// Vrai WebSocket, HTTP et SQLite : un retrait confirmé ne patiente pas
// derrière le fournisseur, et l'ancien téléchargement ne ressuscite rien.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/box_reset.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';

const bool _run = bool.fromEnvironment('RUN_PANEL_CONNECTION');
const String _mac = 'MK:11:22:33:44:77';
const String _base = 'http://127.0.0.1:18789';
const String _m3u = '#EXTM3U\n#EXTINF:-1 group-title="G",Chaîne\n'
    'http://127.0.0.1/stream.ts\n';

class _RealHttp extends HttpOverrides {}

Future<void> _until(bool Function() condition, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 7));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: reason);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final String kind in <String>['source_clear', 'reset', 'source']) {
    test('$kind : effet réel pendant import bloqué, sans résurrection',
        () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = _RealHttp();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18789);
      final dir = await Directory.systemTemp.createTemp('zuno-removal-');
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await PlaylistDatabase.instance.closeForTesting();
      PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
      PlaylistRepository.mergeAllPlaylists = true;
      SharedPreferences.setMockInitialValues(<String, Object>{
        'device.virtual_mac.v1': _mac,
      });
      FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
      RepairFlags.debugReset();
      WebSocket? peer;
      bool servePending = false;
      bool removed = false;
      int statusWhileBlocked = 0;
      final started = Completer<void>();
      final gate = Completer<void>();
      final finals = <String, Map<String, dynamic>>{};
      final int first =
          kind == 'source_clear' ? 100 : (kind == 'reset' ? 200 : 300);
      void send(String type, int seq) => peer!.add(jsonEncode(<String, Object>{
            'seq': seq,
            'type': type,
            'mac': _mac,
            'order_id': 'ord_removal_${seq}_fixture',
          }));
      server.listen((request) async {
        if (request.uri.path == '/api/box/ws') {
          peer = await WebSocketTransformer.upgrade(request);
          peer!.listen((_) {});
          return;
        }
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.startsWith('/api/box/wait/')) {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('{}');
        } else if (request.uri.path.startsWith('/api/box/ack/')) {
          final body = jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
          for (final dynamic order in body['orders'] as List) {
            if (order['state'] == 'applied' || order['state'] == 'failed') {
              finals[order['order_id'] as String] =
                  Map<String, dynamic>.from(order as Map);
            }
          }
          request.response.write('{"ok":true}');
        } else if (request.uri.path.startsWith('/api/status/') ||
            request.uri.path == '/api/heartbeat') {
          if (started.isCompleted && !removed) statusWhileBlocked++;
          request.response.write(jsonEncode(<String, Object>{
            'exists': true,
            'status': 'active',
            'paid': true,
            'plan': 'lifetime',
            'expired': false,
            'frozen': false,
            'source_rev': removed ? 3 : (servePending ? 2 : 1),
            'reset_at': removed && kind == 'reset' ? 1791300001000 : 0,
            'revoked': <Map<String, String>>[
              if (removed && kind != 'reset')
                for (final String path in <String>['panel', 'slow'])
                  <String, String>{
                    'type': 'm3u',
                    'm3u_url': '$_base/$path.m3u',
                  },
            ],
          }));
        } else if (request.uri.path.startsWith('/api/device-source/')) {
          request.response.write(jsonEncode(<String, Object>{
            'sources': <Map<String, String>>[
              if (servePending && !removed)
                <String, String>{
                  'type': 'm3u',
                  'm3u_url': '$_base/slow.m3u',
                  'origin': 'panel',
                },
              if (removed && kind == 'source')
                <String, String>{
                  'type': 'm3u',
                  'm3u_url': '$_base/replacement.m3u',
                  'origin': 'panel',
                },
            ],
            'rev': removed ? 3 : 2,
          }));
        } else if (request.uri.path.endsWith('.m3u')) {
          if (request.uri.path == '/slow.m3u') {
            if (!started.isCompleted) started.complete();
            await gate.future;
          }
          request.response.write(_m3u);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('{}');
        }
        await request.response.close().catchError((Object _) {});
      });
      try {
        await PlaylistRepository.instance
            .addM3uPlaylist(name: 'Liste du panel', url: '$_base/panel.m3u');
        await PlaylistRepository.instance.addM3uPlaylist(
            name: 'Liste personnelle', url: '$_base/manual.m3u');
        await SubscriptionState.instance.initialize();
        RemoteActivationWatch.instance
            .start(deviceCredentials: () async => null);
        await _until(() => peer != null, 'Le canal suivi doit être ouvert.');
        servePending = true;
        send('source', first);
        await started.future.timeout(const Duration(seconds: 7));
        expect(gate.isCompleted, isFalse);
        // Un ordre antérieur sans preuve ne doit ni tout effacer, ni retenir
        // le retrait réellement confirmé qui arrive ensuite.
        send('source_clear', first + 1);
        await _until(() => statusWhileBlocked > 0,
            'La première demande doit lire un statut sans retrait autorisé.');
        expect(finals['ord_removal_${first + 1}_fixture'], isNull);
        expect((await PlaylistRepository.instance.getAllPlaylists()).length, 3);
        removed = true;
        final stopwatch = Stopwatch()..start();
        send(kind, first + 2);
        final removalId = 'ord_removal_${first + 2}_fixture';
        await _until(() => finals.containsKey(removalId),
            'Le retrait doit finir avant le fournisseur bloqué.');
        final int elapsed = stopwatch.elapsedMilliseconds;
        expect(elapsed, lessThan(1000),
            reason: 'Mesure locale, hors débit fournisseur.');
        expect(finals[removalId]!['state'], 'applied');
        expect(
            finals[removalId]!['result'],
            kind == 'reset'
                ? 'reset'
                : (kind == 'source' ? 'loaded' : 'revoked'));
        expect(gate.isCompleted, isFalse,
            reason: 'Le fournisseur ancien n’a toujours pas répondu.');
        final expectedUrls = <String>[
          if (kind != 'reset') '$_base/manual.m3u',
          if (kind == 'source') '$_base/replacement.m3u',
        ];
        List<Playlist> lists =
            await PlaylistRepository.instance.getAllPlaylists();
        expect(
            lists.map((p) => p.m3uUrl).toList(), unorderedEquals(expectedUrls));
        final prefs = await SharedPreferences.getInstance();
        if (!finals.containsKey('ord_removal_${first}_fixture')) {
          expect(prefs.getInt('zuno.signal.box_after.v1') ?? 0, lessThan(first),
              reason:
                  'Le retrait rapide ne saute pas l’import dans le curseur.');
        }
        if (kind == 'reset') {
          expect(prefs.getInt(BoxReset.appliedKey), 1791300001000);
        }
        final sourceId = 'ord_removal_${first}_fixture';
        await _until(() => finals.containsKey(sourceId),
            'L’ancienne source doit finir avec une issue explicite.');
        expect(finals[sourceId]!['state'], 'failed');
        expect(finals[sourceId]!['result'], 'superseded');
        gate.complete();
        await _until(
            () => (prefs.getInt('zuno.signal.box_after.v1') ?? 0) >= first + 2,
            'Le curseur progresse après les deux issues terminales.');
        lists = await PlaylistRepository.instance.getAllPlaylists();
        expect(
            lists.map((p) => p.m3uUrl).toList(), unorderedEquals(expectedUrls),
            reason: 'Aucune écriture tardive ne recrée la liste supprimée.');
        debugPrint('[mesure retrait local, ms] $kind=$elapsed');
      } finally {
        if (!gate.isCompleted) gate.complete();
        RemoteActivationWatch.instance.stopForTesting();
        await peer?.close();
        await server.close(force: true);
        await PlaylistDatabase.instance.closeForTesting();
        PlaylistDatabase.debugFilePath = null;
        await dir.delete(recursive: true);
        RepairFlags.debugReset();
        HttpOverrides.global = previous;
      }
    }, skip: !_run);
  }
}
