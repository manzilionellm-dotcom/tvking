// Chemin par défaut : vraie prise WebSocket et vrai synchroniseur officiel.
// Les mesures sont locales ; elles ne promettent pas le débit d'un fournisseur.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';

const bool _run = bool.fromEnvironment('RUN_PANEL_CONNECTION');
const String _mac = 'MK:11:22:33:44:66';
class _RealHttp extends HttpOverrides {}

Future<void> _until(bool Function() condition, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 7));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: reason);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('push par défaut : activation, source, statut et reprise HTTP rapides', () async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = _RealHttp();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18789);
    final dir = await Directory.systemTemp.createTemp('zuno-panel-ws-');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    PlaylistRepository.mergeAllPlaylists = true;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': _mac,
    });
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    RepairFlags.realtimeLegacy = false;
    WebSocket? peer;
    bool paid = false, frozen = false, pushAvailable = true;
    int sourceReads = 0;
    final applied = <String>{};
    server.listen((request) async {
      if (request.uri.path == '/api/box/ws' && pushAvailable) {
        peer = await WebSocketTransformer.upgrade(request);
        peer!.listen((_) {});
        return;
      }
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/box/ws' ||
          request.uri.path.startsWith('/api/box/wait/')) {
        // Rend le scénario indépendant du canal long : le push doit suffire,
        // puis sa coupure doit réveiller le filet HTTP sans attendre 25 s.
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{}');
      } else if (request.uri.path.startsWith('/api/box/ack/')) {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        final orders = body['orders'];
        if (orders is List) {
          for (final order in orders) {
            if (order is Map && order['state'] == 'applied') {
              applied.add(order['order_id'] as String);
            }
          }
        }
        request.response.write('{"ok":true}');
      } else if (request.uri.path.startsWith('/api/device-source/')) {
        sourceReads++;
        request.response.write('{"sources":[],"rev":1}');
      } else if (request.uri.path.startsWith('/api/status/') ||
          request.uri.path == '/api/heartbeat') {
        request.response.write(jsonEncode(<String, Object>{
          'exists': true, 'status': frozen ? 'frozen' : 'active', 'paid': paid,
          'plan': 'lifetime', 'paid_until': 0, 'expired': false,
          'frozen': frozen, 'banned': false, 'source_rev': 0,
          'trial_until': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
        }));
      } else {
        request.response.write('{"ok":true}');
      }
      await request.response.close();
    });
    final measurements = <String, int>{};
    Future<void> send(String type, int seq, bool Function() visible) async {
      final id = 'ord_ws_${seq}_fixture';
      final watch = Stopwatch()..start();
      peer!.add(jsonEncode(<String, Object>{
        'seq': seq, 'type': type, 'mac': _mac, 'order_id': id,
      }));
      await _until(() => visible() && applied.contains(id),
          'Le push $type doit appliquer son effet et accuser son résultat.');
      measurements[type] = watch.elapsedMilliseconds;
      expect(watch.elapsedMilliseconds, lessThan(1500),
          reason: 'Le signal reçu ne doit pas attendre le prochain polling.');
    }
    try {
      await SubscriptionState.instance.initialize();
      RemoteActivationWatch.instance.start();
      await _until(() => peer != null, 'La prise WebSocket par défaut doit s’ouvrir.');
      paid = true;
      await send('activate', 11, () => SubscriptionState.instance.remote.paid);
      final beforeSource = sourceReads;
      await send('source', 12, () => sourceReads > beforeSource);
      frozen = true;
      await send('suspend', 13, () => SubscriptionState.instance.remote.frozen);
      // Sans nouvel ordre, la perte du push doit faire relire le statut.
      frozen = false;
      pushAvailable = false;
      final watch = Stopwatch()..start();
      await peer!.close();
      await _until(() => !SubscriptionState.instance.remote.frozen,
          'Le filet HTTP doit reprendre dès que la prise est coupée.');
      measurements['repli_http'] = watch.elapsedMilliseconds;
      debugPrint('[mesure panel local, ms] ${jsonEncode(measurements)}');
      expect(watch.elapsedMilliseconds, lessThan(1500),
          reason: 'La coupure doit réveiller le statut sans attendre le polling.');
    } finally {
      RemoteActivationWatch.instance.stopForTesting();
      await peer?.close();
      await server.close(force: true);
      await PlaylistDatabase.instance.closeForTesting();
      PlaylistDatabase.debugFilePath = null;
      await dir.delete(recursive: true);
      HttpOverrides.global = previous;
    }
  }, skip: !_run);
}
