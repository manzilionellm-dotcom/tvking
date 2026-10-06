// =========================================================
//  order_ack_client_test.dart — Envoi réel des accusés (client HTTP simulé)
// =========================================================
//  Prouve le contrat de compatibilité avec les Worker déjà en ligne :
//    • Worker sans route d'accusés (404) → UN seul envoi, pas de réessai,
//      la box continue (rend false, ne lève rien) ;
//    • panne passagère (503, coupure réseau) → réessai, puis succès ;
//    • panne durable → 1 + 3 essais au plus, puis abandon journalisé ;
//    • repli `zuno.ack.off` → aucun envoi.
//  Délais de réessai mis à zéro : on teste la logique, pas l'horloge.
// =========================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/subscription/data/order_ack_client.dart';

const String kMac = 'MK:AA:BB:CC:DD:EE';
const List<Duration> kNoDelay = <Duration>[Duration.zero, Duration.zero, Duration.zero];
final List<Map<String, Object?>> kOrders = <Map<String, Object?>>[
  <String, Object?>{'order_id': 'ord_12345678-aaaa', 'state': 'received', 'received_at': 1791300000000},
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RepairFlags.orderAckOff = false;
  });
  tearDown(() => RepairFlags.orderAckOff = false);

  test('Worker sans route d’accusés (404) : un seul envoi, pas de réessai, pas d’exception', () async {
    int calls = 0;
    final MockClient c = MockClient((http.Request r) async {
      calls++;
      return http.Response('{"error":"not_found"}', 404);
    });
    expect(await OrderAckClient.send(kMac, kOrders, client: c, delays: kNoDelay), isFalse);
    expect(calls, 1);
  });

  test('corps envoyé : la liste d’accusés telle quelle, sur la route de la MAC', () async {
    late http.Request seen;
    final MockClient c = MockClient((http.Request r) async {
      seen = r;
      return http.Response('{"ok":true}', 200);
    });
    expect(await OrderAckClient.send(kMac, kOrders, client: c, delays: kNoDelay), isTrue);
    expect(seen.method, 'POST');
    expect(seen.url.path, '/api/box/ack/${Uri.encodeComponent(kMac)}');
    expect(jsonDecode(seen.body), <String, Object?>{'orders': kOrders});
  });

  test('panne passagère : 503 puis coupure réseau puis 200 → réussi au 3e essai', () async {
    int calls = 0;
    final MockClient c = MockClient((http.Request r) async {
      calls++;
      if (calls == 1) return http.Response('busy', 503);
      if (calls == 2) throw const SocketException('coupure injectée');
      return http.Response('{"ok":true}', 200);
    });
    expect(await OrderAckClient.send(kMac, kOrders, client: c, delays: kNoDelay), isTrue);
    expect(calls, 3);
  });

  test('panne durable : 4 essais au plus, puis abandon (false)', () async {
    int calls = 0;
    final MockClient c = MockClient((http.Request r) async {
      calls++;
      return http.Response('down', 500);
    });
    expect(await OrderAckClient.send(kMac, kOrders, client: c, delays: kNoDelay), isFalse);
    expect(calls, 4);
  });

  test('repli zuno.ack.off : aucun envoi ; liste vide : aucun envoi', () async {
    int calls = 0;
    final MockClient c = MockClient((http.Request r) async {
      calls++;
      return http.Response('{"ok":true}', 200);
    });
    RepairFlags.orderAckOff = true;
    expect(await OrderAckClient.send(kMac, kOrders, client: c, delays: kNoDelay), isFalse);
    RepairFlags.orderAckOff = false;
    expect(await OrderAckClient.send(kMac, const <Map<String, Object?>>[], client: c, delays: kNoDelay), isFalse);
    expect(calls, 0);
  });
}
