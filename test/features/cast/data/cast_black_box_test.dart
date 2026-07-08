// =========================================================
//  cast_black_box_test.dart — Boîte noire du pipeline cast
// =========================================================
//  Vérifie les invariants de CastDiagnostics (le singleton
//  boîte noire, cast_black_box.dart) :
//    - masquage des identifiants Xtream ET du token HMAC t= ;
//    - cycle begin/update/end d'une tentative ;
//    - bornes des ring buffers (journal + tentatives) ;
//    - rapport JSON parseable, sans URL en clair.
// =========================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_black_box.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

CastDevice _dev() => const CastDevice(
      id: 'cc:1',
      name: 'Salon',
      kind: CastDeviceKind.chromecast,
      host: '192.168.1.42',
      port: 8009,
      controlUrl: '',
      manufacturer: 'Google Cast',
      model: 'Chromecast',
    );

void main() {
  group('redactCastUrl', () {
    test('masque user/pass du chemin Xtream', () {
      final String out =
          redactCastUrl('http://panel.example.com/live/USER/PASS/1234.ts');
      expect(out, isNot(contains('USER')));
      expect(out, isNot(contains('PASS')));
      expect(out, contains('/live/***/***/1234.ts'));
    });

    test('masque le token HMAC t= du proxy Cast', () {
      final String out = redactCastUrl(
        'https://app.7themotion.com/cast-proxy?u=http%3A%2F%2Fx%2Fs.ts'
        '&e=1751000000&t=deadbeefdeadbeefdeadbeefdeadbeef',
      );
      expect(out, isNot(contains('deadbeef')));
      expect(out, contains('t=***'));
      // L'expiration n'est pas un secret, elle reste lisible.
      expect(out, contains('e=1751000000'));
    });

    test('masque les query params sensibles classiques', () {
      final String out =
          redactCastUrl('http://x/stream?username=bob&password=hunter2');
      expect(out, isNot(contains('hunter2')));
    });
  });

  group('cycle de tentative', () {
    test('begin → update → end archive un snapshot complet', () {
      final CastDiagnostics box = CastDiagnostics.instance;
      box.beginAttempt(
        device: _dev(),
        streamUrl: 'http://panel.example.com/live/USER/PASS/77.ts',
        channelName: 'Chaîne test',
      );
      expect(box.current, isNotNull);
      expect(box.current!.stage, 'routing');
      // L'URL d'origine est masquée dès l'entrée.
      expect(box.current!.originalUrlRedacted, isNot(contains('USER')));

      box.updateCurrent((CastAttemptSnapshot s) {
        s.castPath = 'cast_proxy';
        s.contentType = 'video/mp2t';
        s.requestedAppId = '5BDFD969';
        s.receiverSwitchOutcome = 'ok';
        s.castSignStatus = 200;
        s.castSignOk = true;
        s.proxyVerifyStatus = 502;
        s.proxyUpstreamStatus = '456';
        s.frameworkErrorKind = 'load_failed';
        s.frameworkErrorCode = 2100;
      });

      box.endAttempt(success: false, error: 'La TV a refusé le flux.');
      expect(box.current, isNull);
      expect(box.attempts, isNotEmpty);
      final CastAttemptSnapshot last = box.attempts.first;
      expect(last.stage, 'failed');
      expect(last.success, isFalse);
      expect(last.castPath, 'cast_proxy');
      expect(last.proxyUpstreamStatus, '456');
      expect(last.frameworkErrorCode, 2100);
      expect(last.totalDurationMs, isNotNull);
      expect(box.latest, same(last));
    });

    test('endAttempt sans begin est un no-op', () {
      final CastDiagnostics box = CastDiagnostics.instance;
      final int before = box.attempts.length;
      box.endAttempt(success: true);
      expect(box.attempts.length, before);
    });

    test('les tentatives sont bornées à 10', () {
      final CastDiagnostics box = CastDiagnostics.instance;
      for (int i = 0; i < 15; i++) {
        box.beginAttempt(device: _dev(), streamUrl: 'http://x/live/u/p/$i.ts');
        box.endAttempt(success: true);
      }
      expect(box.attempts.length, 10);
    });
  });

  group('journal', () {
    test('borné à 150 événements, les plus vieux tombent', () {
      final CastDiagnostics box = CastDiagnostics.instance;
      for (int i = 0; i < 200; i++) {
        box.logEvent('test.spam', 'event $i');
      }
      expect(box.events.length, 150);
      expect(box.events.last.message, 'event 199');
      // Le tout premier a été évincé.
      expect(
        box.events.any((CastBlackBoxEvent e) => e.message == 'event 0'),
        isFalse,
      );
    });
  });

  group('exportReport', () {
    test('JSON valide, structure attendue, aucune fuite d\'identifiants', () {
      final CastDiagnostics box = CastDiagnostics.instance;
      box.beginAttempt(
        device: _dev(),
        streamUrl: 'http://panel.example.com/live/SECRETUSER/SECRETPASS/9.ts',
      );
      box.updateCurrent((CastAttemptSnapshot s) {
        s.mediaUrlRedacted = redactCastUrl(
          'https://app.7themotion.com/cast-proxy?u=x&e=1&t=SECRETTOKEN',
        );
      });
      box.endAttempt(success: false, error: 'échec test');

      final String report = box.exportReport();
      expect(report, isNot(contains('SECRETUSER')));
      expect(report, isNot(contains('SECRETPASS')));
      expect(report, isNot(contains('SECRETTOKEN')));

      final Map<String, dynamic> parsed =
          jsonDecode(report) as Map<String, dynamic>;
      expect(parsed['meta'], isA<Map<String, dynamic>>());
      expect(
        (parsed['meta'] as Map<String, dynamic>)['report'],
        'cast_black_box',
      );
      expect(parsed['discovery'], isA<Map<String, dynamic>>());
      expect(parsed['attempts'], isA<List<dynamic>>());
      expect(parsed['journal'], isA<List<dynamic>>());
      final Map<String, dynamic> attempt =
          (parsed['attempts'] as List<dynamic>).first as Map<String, dynamic>;
      expect(attempt['success'], isFalse);
      expect(attempt['finalError'], 'échec test');
      expect(attempt['receiverPageUrl'],
          'https://app.7themotion.com/cast-receiver');
    });
  });
}
