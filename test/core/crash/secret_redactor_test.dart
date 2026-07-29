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

    test('RÉGRESSION perf (run 003) : longue ligne sans URL en temps linéaire',
        () {
      // Avant la borne du schéma dans _userInfo, cette entrée (grande ligne
      // alphanumérique, aucun secret) prenait des MINUTES (O(n²)) — le
      // timeout de 30 s du runner CI a cassé le test de rotation de la
      // boîte noire dès que le redactor est passé sur toutes les lignes.
      // Ici : doit rendre l'entrée inchangée bien avant le timeout du test.
      final String big = 'x' * 200000;
      expect(SecretRedactor.redact(big), big);
      // Même chose avec des '/' dedans (la sortie rapide ne s'applique
      // plus : les 4 regex tournent) — reste linéaire grâce à la borne.
      final String bigSlashes = List<String>.filled(20000, 'seg').join('/');
      expect(SecretRedactor.redact(bigSlashes), bigSlashes);
    });

    // AUDIT 2026-07-29 : couverture élargie (motifs qui passaient en clair).
    test('masque les nouveaux paramètres de query sensibles', () {
      const String msg =
          'GET /api?api_key=ABC123&secret=zzz&access_token=tok9&sig=deadbeef';
      final String out = SecretRedactor.redact(msg);
      expect(out, isNot(contains('ABC123')));
      expect(out, isNot(contains('zzz')));
      expect(out, isNot(contains('tok9')));
      expect(out, isNot(contains('deadbeef')));
      // Les noms de paramètres restent (utiles au diagnostic).
      expect(out, contains('api_key='));
      expect(out, contains('secret='));
    });

    test('masque les en-têtes Authorization / X-Admin-Secret / X-Api-Key', () {
      const String msg =
          'req headers: Authorization: Bearer eyJhbGci.secret.sig, '
          'X-Admin-Secret: sup3rs3cr3t, X-Api-Key: key-42';
      final String out = SecretRedactor.redact(msg);
      expect(out, isNot(contains('eyJhbGci.secret.sig')));
      expect(out, isNot(contains('sup3rs3cr3t')));
      expect(out, isNot(contains('key-42')));
      expect(out, contains('Authorization:'));
      expect(out, contains('X-Admin-Secret:'));
    });

    test('masque un chemin Xtream SANS extension (/live/USER/PASS/stream)', () {
      const String msg =
          'échec http://panel:8080/live/bob/hunter2/stream (no ext)';
      final String out = SecretRedactor.redact(msg);
      expect(out, isNot(contains('bob')));
      expect(out, isNot(contains('hunter2')));
      expect(out, contains('/live/•••/•••/'));
    });
  });
}
