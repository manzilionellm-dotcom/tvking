// Tests du rapport Boîte noire 24 h (FleetReporter.buildPayload, pur) :
// contenu exact, bornage à 50 entrées, vie privée (jamais d'URL de flux).

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/observability/fleet_reporter.dart';
import 'package:tv_king/features/tv/data/playback_failure_log.dart';

PlaybackFailureEntry _entry(int i) => PlaybackFailureEntry(
      timestamp: DateTime.utc(2026, 7, 31, 12, 0, i % 60),
      channelName: 'Chaîne $i',
      streamHost: 'srv$i.example.com',
      errorCodeName: 'ERROR_CODE_IO_BAD_HTTP_STATUS',
      errorCode: 2004,
      cause: 'Response code: 456',
      verdict: 'Chaîne bloquée par le fournisseur',
    );

void main() {
  group('FleetReporter.buildPayload', () {
    test('contenu complet et identifiants app corrects', () {
      final Map<String, Object?> p = FleetReporter.buildPayload(
        device: 'MK:A3:B2:F1:8E:91',
        isTv: true,
        versionName: '1.0.0',
        versionCode: 1785537865,
        platform: 'android 12',
        locale: 'fr_FR',
        failures: <PlaybackFailureEntry>[_entry(1)],
      );
      expect(p['device'], 'MK:A3:B2:F1:8E:91');
      expect(p['app'], 'tv');
      expect(p['version_code'], 1785537865);
      final List<Object?> f = p['failures']! as List<Object?>;
      expect(f, hasLength(1));
      final Map<String, Object?> e = f.first! as Map<String, Object?>;
      expect(e['channel'], 'Chaîne 1');
      expect(e['code'], 'ERROR_CODE_IO_BAD_HTTP_STATUS');
      expect(e['verdict'], 'Chaîne bloquée par le fournisseur');
    });

    test('téléphone → app=phone', () {
      final Map<String, Object?> p = FleetReporter.buildPayload(
        device: 'd',
        isTv: false,
        versionName: '1.0.0',
        versionCode: 1305,
        platform: '',
        locale: '',
        failures: const <PlaybackFailureEntry>[],
      );
      expect(p['app'], 'phone');
      expect(p['failures'], isEmpty);
    });

    test('borné à 50 échecs maximum', () {
      final Map<String, Object?> p = FleetReporter.buildPayload(
        device: 'd',
        isTv: true,
        versionName: '1.0.0',
        versionCode: 1,
        platform: '',
        locale: '',
        failures: List<PlaybackFailureEntry>.generate(80, _entry),
      );
      expect(p['failures']! as List<Object?>, hasLength(50));
    });

    test('vie privée : jamais d\'URL de flux, seulement l\'hôte', () {
      final Map<String, Object?> p = FleetReporter.buildPayload(
        device: 'd',
        isTv: true,
        versionName: '1.0.0',
        versionCode: 1,
        platform: '',
        locale: '',
        failures: <PlaybackFailureEntry>[_entry(2)],
      );
      final String flat = p.toString();
      expect(flat.contains('http://'), isFalse);
      expect(flat.contains('https://'), isFalse);
      final Map<String, Object?> e =
          (p['failures']! as List<Object?>).first! as Map<String, Object?>;
      expect(e['host'], 'srv2.example.com');
    });

    test('code numérique en repli quand codeName absent', () {
      final PlaybackFailureEntry e = PlaybackFailureEntry(
        timestamp: DateTime.utc(2026),
        channelName: 'X',
        streamHost: 'h',
        errorCode: 2004,
      );
      final Map<String, Object?> p = FleetReporter.buildPayload(
        device: 'd',
        isTv: false,
        versionName: '1',
        versionCode: 1,
        platform: '',
        locale: '',
        failures: <PlaybackFailureEntry>[e],
      );
      final Map<String, Object?> f =
          (p['failures']! as List<Object?>).first! as Map<String, Object?>;
      expect(f['code'], '2004');
    });
  });
}
