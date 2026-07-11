// =========================================================
//  realtime_sync_service_test.dart — Couche temps réel (pur Dart)
// =========================================================
//  Verrouille les deux briques PURES du service WebSocket (aucun socket,
//  aucun réseau nécessaire) :
//    1. `computeBackoff` — la séquence de reconnexion 5→10→30→60→120 s
//       (plafond) avec jitter ±20 % borné (contrat REALTIME-PROTOCOL §6) ;
//    2. `RtEvent.parse` — le décodage/normalisation des frames entrantes
//       (sync / message / bye), avec rejet SILENCIEUX de tout le reste
//       (frames non-JSON ignorées — contrat §8).
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/realtime/realtime_sync_service.dart';

void main() {
  group('computeBackoff', () {
    test('séquence nominale 5 → 10 → 30 → 60 → 120 s (jitter 0)', () {
      expect(RealtimeSyncService.computeBackoff(0),
          const Duration(seconds: 5));
      expect(RealtimeSyncService.computeBackoff(1),
          const Duration(seconds: 10));
      expect(RealtimeSyncService.computeBackoff(2),
          const Duration(seconds: 30));
      expect(RealtimeSyncService.computeBackoff(3),
          const Duration(seconds: 60));
      expect(RealtimeSyncService.computeBackoff(4),
          const Duration(seconds: 120));
    });

    test('plafonné à 120 s au-delà du dernier palier', () {
      expect(RealtimeSyncService.computeBackoff(5),
          const Duration(seconds: 120));
      expect(RealtimeSyncService.computeBackoff(42),
          const Duration(seconds: 120));
    });

    test('un attempt négatif retombe sur le 1er palier', () {
      expect(RealtimeSyncService.computeBackoff(-3),
          const Duration(seconds: 5));
    });

    test('jitter ±20 % appliqué proportionnellement', () {
      expect(RealtimeSyncService.computeBackoff(0, jitter: 0.2),
          const Duration(seconds: 6)); // 5 s +20 %
      expect(RealtimeSyncService.computeBackoff(0, jitter: -0.2),
          const Duration(seconds: 4)); // 5 s −20 %
      expect(RealtimeSyncService.computeBackoff(4, jitter: 0.1),
          const Duration(seconds: 132)); // 120 s +10 %
    });

    test('jitter hors bornes ramené dans [−0.2, +0.2]', () {
      // Un jitter aberrant (bug d'appelant) ne doit JAMAIS produire un
      // délai nul ou démesuré : il est borné à ±20 %.
      expect(RealtimeSyncService.computeBackoff(0, jitter: 5.0),
          const Duration(seconds: 6));
      expect(RealtimeSyncService.computeBackoff(0, jitter: -5.0),
          const Duration(seconds: 4));
    });
  });

  group('RtEvent.parse — frames sync', () {
    test('sync complet avec id et what', () {
      final RtEvent? ev = RtEvent.parse(
          '{"type":"sync","what":"sources","id":"evt_ab12cd"}');
      expect(ev, isNotNull);
      expect(ev!.type, 'sync');
      expect(ev.what, 'sources');
      expect(ev.id, 'evt_ab12cd');
    });

    test('sync sans id → id null (pas d\'ack attendu)', () {
      final RtEvent? ev = RtEvent.parse('{"type":"sync","what":"status"}');
      expect(ev!.id, isNull);
      expect(ev.what, 'status');
    });

    test('sync avec what inconnu ou absent → normalisé en "all"', () {
      expect(RtEvent.parse('{"type":"sync","what":"exotique"}')!.what, 'all');
      expect(RtEvent.parse('{"type":"sync"}')!.what, 'all');
    });
  });

  group('RtEvent.parse — frames message', () {
    test('message complet', () {
      final RtEvent? ev = RtEvent.parse('{"type":"message","id":"m1",'
          '"title":"Bonjour","body":"Promo ce soir","kind":"success",'
          '"durationSec":30}');
      expect(ev, isNotNull);
      expect(ev!.type, 'message');
      expect(ev.id, 'm1');
      final AdminMessage msg = ev.message!;
      expect(msg.id, 'm1');
      expect(msg.title, 'Bonjour');
      expect(msg.body, 'Promo ce soir');
      expect(msg.kind, 'success');
      expect(msg.durationSec, 30);
    });

    test('message minimal → défauts (kind info, 15 s)', () {
      final RtEvent? ev = RtEvent.parse('{"type":"message","body":"salut"}');
      final AdminMessage msg = ev!.message!;
      expect(msg.kind, 'info');
      expect(msg.durationSec, 15);
      expect(msg.title, '');
      expect(ev.id, isNull);
    });

    test('kind inconnu → normalisé en info, durée bornée 3–120 s', () {
      final AdminMessage a = RtEvent.parse(
              '{"type":"message","kind":"danger","durationSec":9999}')!
          .message!;
      expect(a.kind, 'info');
      expect(a.durationSec, 120);
      final AdminMessage b =
          RtEvent.parse('{"type":"message","durationSec":0}')!.message!;
      expect(b.durationSec, 3);
    });
  });

  group('RtEvent.parse — frames bye + rejets', () {
    test('bye avec raison', () {
      final RtEvent? ev = RtEvent.parse('{"type":"bye","reason":"replaced"}');
      expect(ev!.type, 'bye');
      expect(ev.reason, 'replaced');
    });

    test('tout ce qui n\'est pas un objet JSON typé → null (silencieux)', () {
      expect(RtEvent.parse('pong'), isNull); // texte keepalive
      expect(RtEvent.parse('pas du json {'), isNull);
      expect(RtEvent.parse('[1,2,3]'), isNull); // JSON mais pas un objet
      expect(RtEvent.parse('{"foo":"bar"}'), isNull); // pas de type
      expect(RtEvent.parse('{"type":42}'), isNull); // type non-string
      expect(RtEvent.parse('{"type":"snapshot"}'), isNull); // type panel
      expect(RtEvent.parse(''), isNull);
    });
  });
}
