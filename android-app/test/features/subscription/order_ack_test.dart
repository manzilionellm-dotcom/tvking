// =========================================================
//  order_ack_test.dart — Accusés d'ordres : décision, corps, lecture
// =========================================================
//  La box doit dire au serveur, pour chaque ordre suivi : reçu, puis
//  appliqué ou en échec, avec le résultat réel et la révision appliquée.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/subscription/data/box_signal_client.dart';
import 'package:tv_king/features/subscription/domain/box_channel.dart';
import 'package:tv_king/features/subscription/domain/order_ack.dart';

void main() {
  const int t = 1791300000000;

  group('issue d’un ordre de listes', () {
    test('lecture réussie après réception → APPLIED loaded + révision', () {
      final OrderOutcome o = orderOutcome(
        kind: 'source', receivedAtMs: t, statusRead: true, sideEffectOk: true,
        report: const SourceSyncReport(result: 'loaded', atMs: t + 10, configRev: 7),
      );
      expect(o.state, 'applied');
      expect(o.result, 'loaded');
      expect(o.configRev, 7);
    });

    test('liste refusée, ancienne gardée → FAILED refused_kept_previous', () {
      final OrderOutcome o = orderOutcome(
        kind: 'source', receivedAtMs: t, statusRead: true, sideEffectOk: true,
        report: const SourceSyncReport(result: 'sourceFailed', atMs: t + 10, configRev: 8, error: 'HTTP 500', keptPrevious: true),
      );
      expect(o.state, 'failed');
      expect(o.result, 'refused');
      expect(o.errorCode, 'refused_kept_previous');
      expect(o.errorMessage, 'HTTP 500');
      expect(o.configRev, 8);
    });

    test('rapport plus ancien que l’ordre → FAILED not_run (jamais un faux APPLIED)', () {
      final OrderOutcome o = orderOutcome(
        kind: 'source', receivedAtMs: t, statusRead: true, sideEffectOk: true,
        report: const SourceSyncReport(result: 'loaded', atMs: t - 1, configRev: 6),
      );
      expect(o.state, 'failed');
      expect(o.result, 'not_run');
    });

    test('aucun rapport → FAILED not_run', () {
      expect(orderOutcome(kind: 'reset', receivedAtMs: t, statusRead: true, sideEffectOk: true).state, 'failed');
    });

    test('listes vidées par le panel → APPLIED no_source ; réseau coupé → FAILED network', () {
      expect(orderOutcome(kind: 'source_clear', receivedAtMs: t, statusRead: true, sideEffectOk: true,
          report: const SourceSyncReport(result: 'noSource', atMs: t)).result, 'no_source');
      expect(orderOutcome(kind: 'source', receivedAtMs: t, statusRead: true, sideEffectOk: true,
          report: const SourceSyncReport(result: 'networkError', atMs: t)).result, 'network');
    });
  });

  test('ordres de licence : statut relu → APPLIED, illisible → FAILED', () {
    expect(orderOutcome(kind: 'activate', receivedAtMs: t, statusRead: true, sideEffectOk: true).result, 'status_ok');
    final OrderOutcome ko = orderOutcome(kind: 'renew', receivedAtMs: t, statusRead: false, sideEffectOk: true);
    expect(ko.state, 'failed');
    expect(ko.errorCode, 'status_unreachable');
  });

  test('autres ordres : relecture réussie ou en échec', () {
    expect(orderOutcome(kind: 'theme', receivedAtMs: t, statusRead: true, sideEffectOk: true).state, 'applied');
    expect(orderOutcome(kind: 'theme', receivedAtMs: t, statusRead: true, sideEffectOk: false).state, 'failed');
  });

  test('corps de l’accusé : exactement les champs validés par le Worker', () {
    final Map<String, Object?> body = ackPayload(
      orderId: 'ord_12345678-aaaa', state: 'failed', traceId: 'trace-0001', appVersion: '107-test',
      receivedAtMs: t, appliedAtMs: t + 5,
      outcome: const OrderOutcome(applied: false, result: 'refused', errorCode: 'refused', errorMessage: 'x', configRev: 3),
    );
    expect(body, <String, Object?>{
      'order_id': 'ord_12345678-aaaa', 'state': 'failed', 'received_at': t, 'applied_at': t + 5,
      'result': 'refused', 'error_code': 'refused', 'error_message': 'x', 'config_rev': 3,
      'trace_id': 'trace-0001', 'app_version': '107-test',
    });
    final Map<String, Object?> received = ackPayload(orderId: 'ord_12345678-aaaa', state: 'received', traceId: '', appVersion: '', receivedAtMs: t);
    expect(received.keys.toSet(), <String>{'order_id', 'state', 'received_at'});
  });

  test('trame WebSocket : order_id et trace_id lus, valeur douteuse ignorée', () {
    final BoxChannelFrame? f = parseBoxChannelFrame(
      '{"v":1,"seq":4,"type":"source","mac":"MK:AA:BB:CC:DD:EE","at":1,"order_id":"ord_abcdef12-3456","trace_id":"trace-xyz-0001"}');
    expect(f!.orderId, 'ord_abcdef12-3456');
    expect(f.traceId, 'trace-xyz-0001');
    final BoxChannelFrame? bad = parseBoxChannelFrame(
      '{"v":1,"seq":4,"type":"source","mac":"MK:AA:BB:CC:DD:EE","order_id":"<script>","trace_id":"a b"}');
    expect(bad!.orderId, '');
    expect(bad.traceId, '');
  });

  test('attente longue : order_id et trace_id lus ; ancien Worker → vides', () {
    final BoxWaitResult r = BoxSignalClient.readForTest(200,
        '{"v":1,"timeout":false,"box":[{"id":9,"kind":"activate","order_id":"ord_abcdef12-9999","trace_id":"trace-0002"},{"id":10,"kind":"theme"}],"fleet":[]}');
    expect(r.orders.length, 2);
    expect(r.orders[0].orderId, 'ord_abcdef12-9999');
    expect(r.orders[0].traceId, 'trace-0002');
    expect(r.orders[1].orderId, '');
  });
}
