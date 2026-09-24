// =========================================================
//  structured_logger_test.dart — Tests du logger structure
// =========================================================
//  Phase 1 — couvre les transitions critiques du logger :
//    - format JSON-Lines conforme (champs canoniques + ts ISO)
//    - fan-out a N sinks
//    - resilience : un sink defaillant ne bloque pas les autres
//    - elision du champ `ctx` quand vide (compacite des logs)
//
//  Pas de dependance externe ajoutee — flutter_test est deja dans
//  dev_dependencies.
// =========================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/observability/structured_logger.dart';

void main() {
  // Chaque test repart d'une liste de sinks vide pour eviter les
  // fuites entre tests (le logger est un singleton, on partage donc
  // l'etat — necessaire de clear explicitement).
  setUp(() {
    StructuredLogger.instance.clearSinks();
  });

  group('StructuredLogger format JSON-Lines', () {
    test('emet un JSON valide avec champs canoniques', () {
      final List<String> captured = <String>[];
      StructuredLogger.instance.addSink(captured.add);

      StructuredLogger.instance.info(
        domain: 'rec',
        event: 'job.start',
        ctx: <String, Object?>{'filePath': '/sdcard/x.ts', 'count': 3},
      );

      expect(captured.length, 1);
      final Map<String, Object?> json =
          jsonDecode(captured.first) as Map<String, Object?>;
      expect(json['lvl'], 'info');
      expect(json['domain'], 'rec');
      expect(json['event'], 'job.start');
      expect(json['ts'], isA<String>());
      // Format ISO 8601 UTC — se termine par 'Z'.
      expect((json['ts'] as String).endsWith('Z'), isTrue);
      final Map<String, Object?> ctx = json['ctx'] as Map<String, Object?>;
      expect(ctx['filePath'], '/sdcard/x.ts');
      expect(ctx['count'], 3);
    });

    test('omet `ctx` quand il est vide pour compacite', () {
      final List<String> captured = <String>[];
      StructuredLogger.instance.addSink(captured.add);

      StructuredLogger.instance.error(
        domain: 'cast',
        event: 'session.failure',
      );

      final Map<String, Object?> json =
          jsonDecode(captured.first) as Map<String, Object?>;
      expect(json.containsKey('ctx'), isFalse);
      expect(json['lvl'], 'error');
    });

    test('niveaux info/warn/error tous emis avec leur short name', () {
      final List<String> captured = <String>[];
      StructuredLogger.instance.addSink(captured.add);

      StructuredLogger.instance.info(domain: 'd', event: 'e');
      StructuredLogger.instance.warn(domain: 'd', event: 'e');
      StructuredLogger.instance.error(domain: 'd', event: 'e');

      expect(captured.length, 3);
      expect(
        captured
            .map((String s) =>
                (jsonDecode(s) as Map<String, Object?>)['lvl'] as String)
            .toList(),
        <String>['info', 'warn', 'error'],
      );
    });
  });

  group('StructuredLogger fan-out', () {
    test('diffuse a tous les sinks dans l\'ordre d\'ajout', () {
      final List<String> a = <String>[];
      final List<String> b = <String>[];
      StructuredLogger.instance.addSink(a.add);
      StructuredLogger.instance.addSink(b.add);

      StructuredLogger.instance.info(domain: 'rec', event: 'x');

      expect(a.length, 1);
      expect(b.length, 1);
      expect(a.first, equals(b.first));
    });

    test('un sink qui throw ne bloque pas les suivants', () {
      final List<String> before = <String>[];
      final List<String> after = <String>[];
      StructuredLogger.instance.addSink(before.add);
      StructuredLogger.instance.addSink((String s) {
        throw Exception('sink defaillant');
      });
      StructuredLogger.instance.addSink(after.add);

      StructuredLogger.instance.warn(domain: 'rec', event: 'x');

      // Both flanking sinks must still receive the event.
      expect(before.length, 1);
      expect(after.length, 1);
    });
  });
}
