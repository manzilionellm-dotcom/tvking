// =========================================================
//  dns_failure_classifier_test.dart — Phase 1+ / DNS retry
// =========================================================
//  Cas de diag terrain 2026-06-01 sur SHIELD : 7 sessions cast
//  echouent toutes en 11-15ms avec "No address associated with
//  hostname" alors que Chrome resout le domaine peu apres. Pour ne
//  PAS qu'on continue d'afficher "Le cast a echoue. Essaie de
//  relancer." (generique + culpabilise l'app) sur ce pattern, on a
//  ajoute :
//
//    1. StreamProbe.isDnsFailure(result) — detecte les erreurs DNS
//       canoniques dans une StreamProbeResult.
//    2. CastManager.friendlyMessageFor(e) — bascule sur "Internet ou
//       DNS instable" pour ces cas, AVANT la branche reseau generique.
//
//  Ces tests verrouillent la regle. Si un patch futur retire le
//  branchement hostname/DNS, on saute ici.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';

StreamProbeResult _fail(String reason) {
  return StreamProbeResult(
    originalUrl: 'http://example.com/x.ts',
    finalUrl: 'http://example.com/x.ts',
    success: false,
    errorReason: reason,
  );
}

void main() {
  group('StreamProbe.isDnsFailure', () {
    test('detecte le message Android exact ("No address associated with hostname")',
        () {
      final StreamProbeResult r =
          _fail('Connexion impossible (No address associated with hostname)');
      expect(StreamProbe.isDnsFailure(r), isTrue);
    });

    test('detecte le message Dart cross-platform ("Failed host lookup")', () {
      final StreamProbeResult r = _fail(
          'Connexion impossible (Failed host lookup: pro.iptv-provider.example.com)');
      expect(StreamProbe.isDnsFailure(r), isTrue);
    });

    test('detecte le message iOS/macOS ("nodename nor servname")', () {
      final StreamProbeResult r =
          _fail('Connexion impossible (nodename nor servname provided)');
      expect(StreamProbe.isDnsFailure(r), isTrue);
    });

    test('detecte "name resolution" en termes generiques', () {
      final StreamProbeResult r =
          _fail('Connexion impossible (Temporary failure in name resolution)');
      expect(StreamProbe.isDnsFailure(r), isTrue);
    });

    test('NE confond PAS un timeout serveur avec une erreur DNS', () {
      final StreamProbeResult r = _fail('Le serveur ne répond pas — réessaie');
      expect(StreamProbe.isDnsFailure(r), isFalse);
    });

    test('NE confond PAS un 401 avec une erreur DNS', () {
      final StreamProbeResult r = _fail('Authentification requise — token expiré ?');
      expect(StreamProbe.isDnsFailure(r), isFalse);
    });

    test('false sur un succes', () {
      final StreamProbeResult r = const StreamProbeResult(
        originalUrl: 'http://example.com/x.ts',
        finalUrl: 'http://example.com/x.ts',
        success: true,
      );
      expect(StreamProbe.isDnsFailure(r), isFalse);
    });

    test('false sur errorReason vide / null', () {
      final StreamProbeResult r1 = _fail('');
      expect(StreamProbe.isDnsFailure(r1), isFalse);
      final StreamProbeResult r2 = const StreamProbeResult(
        originalUrl: 'http://example.com/x.ts',
        finalUrl: 'http://example.com/x.ts',
        success: false,
      );
      expect(StreamProbe.isDnsFailure(r2), isFalse);
    });
  });

  group('CastManager.friendlyMessageFor — branche DNS', () {
    final CastManager mgr = CastManager.instance;

    test('DNS Android -> message "Internet ou DNS instable"', () {
      final Exception e = Exception(
          'Connexion impossible (No address associated with hostname)');
      expect(
        mgr.friendlyMessageFor(e),
        contains('DNS'),
      );
    });

    test('DNS Dart -> meme message', () {
      final Exception e = Exception(
          'Connexion impossible (Failed host lookup: pro.example.com)');
      expect(
        mgr.friendlyMessageFor(e),
        contains('DNS'),
      );
    });

    test('Timeout n\'enclenche PAS la branche DNS', () {
      final Exception e = Exception('Le serveur ne répond pas');
      expect(mgr.friendlyMessageFor(e), isNot(contains('DNS')));
      expect(mgr.friendlyMessageFor(e), contains('WiFi'));
    });

    test('401 / auth n\'enclenche PAS la branche DNS', () {
      final Exception e = Exception('Authentification 401 token expired');
      expect(mgr.friendlyMessageFor(e), isNot(contains('DNS')));
      expect(mgr.friendlyMessageFor(e), contains('abonnement'));
    });

    test('Cas generique tombe sur "Le cast a échoué"', () {
      final Exception e = Exception('quelque chose de complétement inconnu');
      expect(mgr.friendlyMessageFor(e), 'Le cast a échoué. Essaie de relancer.');
    });
  });
}
