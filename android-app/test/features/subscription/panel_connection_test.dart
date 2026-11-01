// Exerce le synchroniseur officiel contre un serveur local : réception d'une
// activation, accusé du canal, puis statut actualisé malgré un canal coupé.
// Aucun fournisseur ni service de production n'est contacté.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';

const bool _run = bool.fromEnvironment('RUN_PANEL_CONNECTION');

class _RealHttp extends HttpOverrides {}

Future<void> _until(bool Function() condition, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 7));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: reason);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('le statut continue après une activation et la perte du canal', () async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = _RealHttp();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18789);
    final activation = Completer<void>();
    bool paid = false;
    bool frozen = false;
    bool channelUnavailable = false;
    int statusReads = 0;
    final acknowledgedStates = <String>{};
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': 'MK:11:22:33:44:55',
    });
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    RepairFlags.realtimeLegacy = true;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.startsWith('/api/box/wait/')) {
        await activation.future;
        final after = int.tryParse(request.uri.queryParameters['after'] ?? '') ?? 0;
        if (after < 1) {
          request.response.write(jsonEncode(<String, Object>{
            'box': <Object>[
              <String, Object>{'id': 1, 'kind': 'activate', 'order_id': 'ord_connection123'},
            ],
            'fleet': <Object>[],
          }));
        } else {
          channelUnavailable = true;
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('{}');
        }
      } else if (request.uri.path.startsWith('/api/box/ack/')) {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        final orders = body['orders'];
        if (orders is List) {
          for (final order in orders) {
            if (order is Map && order['state'] is String) {
              acknowledgedStates.add(order['state'] as String);
            }
          }
        }
        // Le contrat officiel confirme cet accusé par son HTTP 200.
        request.response.write('{"ok":true}');
      } else if (request.uri.path.startsWith('/api/status/') ||
          request.uri.path == '/api/heartbeat') {
        statusReads++;
        request.response.write(jsonEncode(<String, Object>{
          'exists': true,
          'status': frozen ? 'frozen' : 'active',
          'paid': paid,
          'plan': 'lifetime',
          'paid_until': 0,
          'expired': false,
          'frozen': frozen,
          'banned': false,
          'source_rev': 0,
          'trial_until': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
        }));
      } else {
        request.response.write('{"ok":true}');
      }
      await request.response.close();
    });
    try {
      await SubscriptionState.instance.initialize();
      RemoteActivationWatch.instance.start(allowSourceImport: false);
      await _until(() => statusReads > 0, 'Le statut initial doit être lu.');
      paid = true;
      activation.complete();
      await _until(() => SubscriptionState.instance.remote.paid,
          'Le client doit recevoir son activation.');
      await _until(() => acknowledgedStates.contains('applied'),
          'Le serveur doit recevoir le résultat de son ordre.');
      await _until(() => channelUnavailable,
          'Le scénario doit couper le canal après cet ordre.');
      frozen = true;
      await _until(() => SubscriptionState.instance.remote.frozen,
          'La lecture HTTP périodique doit survivre à la perte du canal.');
      expect(statusReads, greaterThanOrEqualTo(3));
    } finally {
      if (!activation.isCompleted) activation.complete();
      RemoteActivationWatch.instance.stopForTesting();
      RepairFlags.realtimeLegacy = false;
      await server.close(force: true);
      HttpOverrides.global = previous;
    }
  }, skip: !_run);
}
