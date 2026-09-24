// =========================================================
//  relay_failure_detection_test.dart — Phase 1 / F-12
// =========================================================
//  `CastManager.bothRelayStrategiesFailed(diag)` est la regle qui
//  decide quand on bascule sur le message UX "WiFi invite/isolation
//  AP" au lieu du message generique "TV n'a pas accepte ce flux".
//
//  La regle :
//    - les DEUX strategies relay (index 3 = relay+full, index 4 =
//      relay+minimal) ont ete tentees ET ont echoue → true
//    - sinon → false
//
//  Pas de test reseau ici — uniquement la logique de classification
//  a partir d'un diagnostic deja construit.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_session_diagnostic.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

CastSessionDiagnostic _makeDiag(List<AttemptResult> attempts) {
  // Device factice — bothRelayStrategiesFailed n'utilise que la
  // liste `attempts`, donc le device n'a pas besoin d'etre realiste.
  const CastDevice device = CastDevice(
    id: 'test',
    name: 'Test',
    kind: CastDeviceKind.dlna,
    host: '127.0.0.1',
    port: 0,
    controlUrl: 'http://127.0.0.1/',
  );
  final CastSessionDiagnostic d = CastSessionDiagnostic(
    startedAt: DateTime.utc(2026, 1, 1),
    device: device,
    originalUrl: 'http://example.com/live.ts',
  );
  d.attempts.addAll(attempts);
  return d;
}

AttemptResult _attempt(int idx, {required bool success}) {
  return AttemptResult(
    strategyIndex: idx,
    strategyName: 'strategy-$idx',
    urlKind: idx < 3 ? 'direct' : 'relay',
    metadataMode: 'full',
    durationMs: 100,
    success: success,
  );
}

void main() {
  final CastManager mgr = CastManager.instance;

  group('bothRelayStrategiesFailed', () {
    test('false si aucune tentative', () {
      final CastSessionDiagnostic d = _makeDiag(<AttemptResult>[]);
      expect(mgr.bothRelayStrategiesFailed(d), isFalse);
    });

    test('false si seule la strategie 3 a echoue (4 jamais tentee)', () {
      final CastSessionDiagnostic d = _makeDiag(<AttemptResult>[
        _attempt(0, success: false),
        _attempt(3, success: false),
      ]);
      expect(mgr.bothRelayStrategiesFailed(d), isFalse);
    });

    test('false si la strategie 3 reussit (cas relay OK)', () {
      final CastSessionDiagnostic d = _makeDiag(<AttemptResult>[
        _attempt(0, success: false),
        _attempt(3, success: true),
      ]);
      expect(mgr.bothRelayStrategiesFailed(d), isFalse);
    });

    test('false si la strategie 4 reussit', () {
      final CastSessionDiagnostic d = _makeDiag(<AttemptResult>[
        _attempt(0, success: false),
        _attempt(3, success: false),
        _attempt(4, success: true),
      ]);
      expect(mgr.bothRelayStrategiesFailed(d), isFalse);
    });

    test('true uniquement quand 3 ET 4 ont echoue', () {
      final CastSessionDiagnostic d = _makeDiag(<AttemptResult>[
        _attempt(0, success: false),
        _attempt(1, success: false),
        _attempt(2, success: false),
        _attempt(3, success: false),
        _attempt(4, success: false),
      ]);
      expect(mgr.bothRelayStrategiesFailed(d), isTrue);
    });

    test('true meme si une strategie directe a reussi avant — irrealiste mais correct', () {
      // En pratique, si 0 reussit, la boucle s'arrete et 3/4 ne sont
      // jamais tentees. Mais la regle doit rester pure : "les deux
      // relay ont echoue ?" — independamment des directes.
      final CastSessionDiagnostic d = _makeDiag(<AttemptResult>[
        _attempt(0, success: true),
        _attempt(3, success: false),
        _attempt(4, success: false),
      ]);
      expect(mgr.bothRelayStrategiesFailed(d), isTrue);
    });
  });
}
