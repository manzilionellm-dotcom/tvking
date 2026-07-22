// =========================================================
//  secret_redactor_test.dart — Verrou anti-fuite d'identifiants
// =========================================================
//  Bug terrain (audit 2026-07-22) : les messages d'erreur remontés (boîte
//  noire disque + POST /api/error-log) embarquaient l'URI Xtream complète,
//  identifiants de l'abonné en clair. Ces tests verrouillent le caviardage.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/crash/secret_redactor.dart';

void main() {
  group('SecretRedactor.redact', () {
    test('masque user/pass dans un chemin Xtream /live/USER/PASS/id.ts', () {
      const String msg =
          'ClientException: échec sur http://panel.tv:8080/live/jean/s3cr3t/123.ts';
      final String out = SecretRedactor.redact(msg);
      expect(out, contains('/live/•••/•••/123.ts'));
      expect(out, isNot(contains('jean')));
      expect(out, isNot(contains('s3cr3t')));
      // Le préfixe structurel « live » est préservé (utile au diagnostic).
      expect(out, contains('/live/'));
    });

    test('masque un chemin Xtream « nu » host/USER/PASS/id.ts', () {
      const String msg =
          'HttpException sur http://1.2.3.4/marie/motdepasse/42.m3u8 (timeout)';
      final String out = SecretRedactor.redact(msg);
      expect(out, contains('/•••/•••/42.m3u8'));
      expect(out, isNot(contains('marie')));
      expect(out, isNot(contains('motdepasse')));
    });

    test('masque les paramètres de query sensibles', () {
      const String msg =
          'Erreur GET http://h/player_api.php?username=bob&password=p4ss&action=x';
      final String out = SecretRedactor.redact(msg);
      expect(out, contains('username=•••'));
      expect(out, contains('password=•••'));
      // Les paramètres non sensibles restent lisibles.
      expect(out, contains('action=x'));
      expect(out, isNot(contains('bob')));
      expect(out, isNot(contains('p4ss')));
    });

    test('masque le userinfo scheme://user:pass@host', () {
      const String msg = 'Socket vers http://admin:hunter2@10.0.0.1/stream';
      final String out = SecretRedactor.redact(msg);
      expect(out, contains('://•••:•••@'));
      expect(out, isNot(contains('admin')));
      expect(out, isNot(contains('hunter2')));
    });

    test('un message sans secret ressort inchangé', () {
      const String msg = 'RangeError (index): out of bounds';
      expect(SecretRedactor.redact(msg), msg);
    });

    test('chaîne vide → chaîne vide (jamais d\'exception)', () {
      expect(SecretRedactor.redact(''), '');
    });

    test('idempotent : re-caviarder ne change rien', () {
      const String msg =
          'échec http://h:8080/live/u/p/9.ts ?username=a&password=b';
      final String once = SecretRedactor.redact(msg);
      final String twice = SecretRedactor.redact(once);
      expect(twice, once);
    });
  });
}
