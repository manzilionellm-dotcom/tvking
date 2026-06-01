// =========================================================
//  lg_diagnostic_fixes_test.dart — Tests issus du diag LG QNED816QA
// =========================================================
//  Diagnostic terrain 2026-06-01 a montre 3 vrais bugs UX :
//
//  B1 : hint "WiFi invite" affiche en faux positif quand les strategies
//       relay ont echoue avec un VRAI message TV ("Transition not
//       available") plutot qu'un timeout reseau.
//  B2 : messages "Transition not available" / "Action Failed" / "458"
//       n'avaient pas de branche dediee dans friendlyMessageFor.
//  B3 : URLs avec `?` orphelin en fin (cas Xtream tres frequent)
//       cassaient les recepteurs DLNA stricts.
//
//  Ces tests verrouillent les 3 fixes.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_session_diagnostic.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

// ===========================================================
//  Helpers
// ===========================================================

CastSessionDiagnostic _diagWith(List<AttemptResult> attempts) {
  const CastDevice device = CastDevice(
    id: 'test',
    name: 'LG TV',
    kind: CastDeviceKind.dlna,
    host: '192.168.8.4',
    port: 0,
    controlUrl: 'http://192.168.8.4/',
  );
  final CastSessionDiagnostic d = CastSessionDiagnostic(
    startedAt: DateTime.utc(2026, 6, 1),
    device: device,
    originalUrl: 'http://example.com/x.ts',
  );
  d.attempts.addAll(attempts);
  return d;
}

AttemptResult _failed(int idx, String msg) => AttemptResult(
      strategyIndex: idx,
      strategyName: 'strategy-$idx',
      urlKind: idx < 3 ? 'direct' : 'relay',
      metadataMode: 'full',
      durationMs: 1000,
      success: false,
      errorMessage: msg,
    );

void main() {
  final CastManager mgr = CastManager.instance;

  // ============================================================
  //  B2 : friendlyMessageFor — nouvelles branches
  // ============================================================

  group('friendlyMessageFor — branches specifiques (B2)', () {
    test('"Transition not available" -> message TV bloquee', () {
      final Exception e = Exception(
        'UPnP SetAVTransportURI a échoué : Transition not available',
      );
      final String msg = mgr.friendlyMessageFor(e);
      expect(msg, contains('bloquée'));
      expect(msg, contains('rallume'));
      expect(msg, isNot(contains('WiFi')));
    });

    test('"transitioning" lowercase aussi reconnu', () {
      final Exception e = Exception('Stuck transitioning forever');
      expect(mgr.friendlyMessageFor(e), contains('bloquée'));
    });

    test('"Action Failed" -> message format non accepte', () {
      final Exception e = Exception('UPnP Play a échoué : Action Failed');
      final String msg = mgr.friendlyMessageFor(e);
      expect(msg, contains('format'));
      expect(msg, contains('QR code'));
    });

    test('"Resource not found" -> meme branche format', () {
      final Exception e = Exception('UPnP : Resource not found');
      expect(mgr.friendlyMessageFor(e), contains('format'));
    });

    test('HTTP 458 -> message limite de connexions IPTV', () {
      final Exception e = Exception(
        'Serveur indisponible (458) — réessaie plus tard',
      );
      final String msg = mgr.friendlyMessageFor(e);
      expect(msg, contains('limite atteinte'));
      expect(msg.toLowerCase(), contains('iptv'));
    });

    test('priorite : Transition AVANT le timeout generique', () {
      // L'erreur contient les deux mots "TimeoutException" ET
      // "Transition" -> on prend Transition (plus specifique).
      final Exception e = Exception(
        'TimeoutException + Transition not available',
      );
      final String msg = mgr.friendlyMessageFor(e);
      expect(msg, contains('bloquée'));
    });

    test('cas generique reste sur "Le cast a échoué" si rien ne match', () {
      final Exception e = Exception('quelque chose de complètement inconnu');
      expect(
        mgr.friendlyMessageFor(e),
        'Le cast a échoué. Essaie de relancer.',
      );
    });
  });

  // ============================================================
  //  B1 : bothRelayStrategiesTimedOut — true UNIQUEMENT sur timeouts
  // ============================================================

  group('bothRelayStrategiesTimedOut — affine le hint WiFi (B1)', () {
    test('true quand 3 ET 4 ont timeout (vrai cas WiFi isolation)', () {
      final CastSessionDiagnostic d = _diagWith([
        _failed(3, 'TimeoutException after 0:00:15.000000: Future not completed'),
        _failed(4, 'TimeoutException after 0:00:15.000000: Future not completed'),
      ]);
      expect(mgr.bothRelayStrategiesTimedOut(d), isTrue);
    });

    test(
      'false si relay echoue avec "Transition not available" (faux positif evite)',
      () {
        // Cas LG QNED816QA 2026-06-01 : relay echoue avec un message
        // TV, pas un timeout reseau. Le hint WiFi etait FAUX.
        final CastSessionDiagnostic d = _diagWith([
          _failed(3, 'UPnP SetAVTransportURI a échoué : Transition not available'),
          _failed(4, 'UPnP Play a échoué : Transition not available'),
        ]);
        expect(mgr.bothRelayStrategiesTimedOut(d), isFalse);
      },
    );

    test('false si mix (3 timeout, 4 Transition)', () {
      final CastSessionDiagnostic d = _diagWith([
        _failed(3, 'TimeoutException after 0:00:15.000000'),
        _failed(4, 'UPnP SetAVTransportURI a échoué : Transition not available'),
      ]);
      expect(mgr.bothRelayStrategiesTimedOut(d), isFalse);
    });

    test('false si une seule strategie relay testee', () {
      final CastSessionDiagnostic d = _diagWith([
        _failed(3, 'TimeoutException'),
      ]);
      expect(mgr.bothRelayStrategiesTimedOut(d), isFalse);
    });

    test('false si aucune tentative relay', () {
      final CastSessionDiagnostic d = _diagWith([
        _failed(0, 'TimeoutException'),
        _failed(1, 'TimeoutException'),
      ]);
      expect(mgr.bothRelayStrategiesTimedOut(d), isFalse);
    });

    test('reconnait "timed out" et "Future not completed"', () {
      final CastSessionDiagnostic d = _diagWith([
        _failed(3, 'connection timed out'),
        _failed(4, 'Future not completed'),
      ]);
      expect(mgr.bothRelayStrategiesTimedOut(d), isTrue);
    });
  });

  // ============================================================
  //  B3 : sanitizeStreamUrl — strip ? orphelin
  // ============================================================

  group('StreamProbe.sanitizeStreamUrl (B3)', () {
    test('strip un ? trailing seul', () {
      expect(
        StreamProbe.sanitizeStreamUrl('http://x.com/live/u/p/1.ts?'),
        'http://x.com/live/u/p/1.ts',
      );
    });

    test('strip plusieurs ??? consecutifs', () {
      expect(
        StreamProbe.sanitizeStreamUrl('http://x.com/live/u/p/1.ts???'),
        'http://x.com/live/u/p/1.ts',
      );
    });

    test("trim les espaces", () {
      expect(
        StreamProbe.sanitizeStreamUrl('  http://x.com/live/1.ts  '),
        'http://x.com/live/1.ts',
      );
    });

    test('ne touche PAS un ? avec query string legitime', () {
      // C'est une URL Xtream get.php typique — on doit conserver la
      // query.
      expect(
        StreamProbe.sanitizeStreamUrl(
          'http://x.com/get.php?username=u&password=p&type=m3u',
        ),
        'http://x.com/get.php?username=u&password=p&type=m3u',
      );
    });

    test('idempotent', () {
      const String clean = 'http://x.com/1.ts';
      expect(StreamProbe.sanitizeStreamUrl(clean), clean);
      expect(
        StreamProbe.sanitizeStreamUrl(StreamProbe.sanitizeStreamUrl(clean)),
        clean,
      );
    });

    test('URL vide reste vide (pas de crash)', () {
      expect(StreamProbe.sanitizeStreamUrl(''), '');
      expect(StreamProbe.sanitizeStreamUrl('   '), '');
      expect(StreamProbe.sanitizeStreamUrl('?'), '');
    });
  });
}
