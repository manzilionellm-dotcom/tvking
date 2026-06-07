// =========================================================
//  preflight_reachability_test.dart — Phase 1+ / Pré-vol réseau
// =========================================================
//  Diag terrain 2026-06-01 sur LG QNED816QA : la TV apparaît dans
//  la liste (découverte multicast OK) mais TOUTES les sessions cast
//  échouent en `errno 113 "No route to host"` après ~25s de grind
//  (5 stratégies × timeouts). Cause : « AP isolation » de la box —
//  le multicast de découverte passe, l'unicast TCP du cast est
//  bloqué.
//
//  Fix : CastManager.castTo fait un pré-vol TCP (~2,5s) sur le port
//  de contrôle de la TV AVANT de lancer les stratégies. S'il échoue,
//  on remonte tout de suite une Exception "no route to host" que
//  friendlyMessageFor traduit en guidance actionnable nommant
//  l'« Isolation client / AP isolation ».
//
//  Ces tests verrouillent le message friendly de ce cas. Si un patch
//  futur casse le routage du message réseau / AP-isolation, on saute
//  ici.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';

void main() {
  final CastManager m = CastManager.instance;

  group('friendlyMessageFor — TV injoignable (errno 113 / AP isolation)', () {
    test('message du pré-vol TCP est routé vers le hint réseau', () {
      final String msg = m.friendlyMessageFor(
        Exception('TV injoignable sur le réseau (192.168.8.4:1178) '
            '— no route to host (pré-vol TCP)'),
      );
      expect(msg, contains('même WiFi'));
      expect(msg.toLowerCase(), contains('isolation'));
    });

    test('errno 113 brut (SocketException) → même guidance', () {
      final String msg = m.friendlyMessageFor(
        Exception('SocketException: No route to host '
            '(OS Error: No route to host, errno = 113)'),
      );
      expect(msg.toLowerCase(), contains('isolation'));
      expect(msg, contains('QR code'));
    });

    test('errno 101 (network unreachable) → même guidance', () {
      final String msg = m.friendlyMessageFor(
        Exception('SocketException: Network is unreachable (errno = 101)'),
      );
      expect(msg.toLowerCase(), contains('isolation'));
    });

    test('connection refused (errno 111) → même guidance réseau', () {
      final String msg = m.friendlyMessageFor(
        Exception('SocketException: Connection refused (errno = 111)'),
      );
      expect(msg.toLowerCase(), contains('isolation'));
    });

    test('NE confond PAS "transition not available" (état TV) avec réseau',
        () {
      final String msg = m.friendlyMessageFor(
        Exception('UPnP 701: Transition not available'),
      );
      expect(msg, contains('bloquée sur un précédent cast'));
      expect(msg.toLowerCase(), isNot(contains('isolation')));
    });
  });
}
