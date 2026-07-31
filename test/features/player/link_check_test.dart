// =========================================================
//  link_check_test.dart — Vérification d'un lien avant lecture
// =========================================================
//  Mêmes cas que la suite d'origine TV King (tests/m3u.test.ts) :
//  un lien http(s) avec hôte passe, tout le reste est refusé avec
//  une raison structurée.

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/link_check.dart';

void main() {
  group('verifyStreamUrl', () {
    test('accepte une URL https classique', () {
      expect(verifyStreamUrl('https://stream.example/live.m3u8').ok, isTrue);
    });

    test('accepte une URL http IP:port entourée d\'espaces', () {
      expect(verifyStreamUrl('  http://10.0.0.2:8080/ch/1  ').ok, isTrue);
    });

    test('refuse un lien vide', () {
      final LinkCheck c = verifyStreamUrl('');
      expect(c.ok, isFalse);
      expect(c.reason, LinkCheckReason.empty);
    });

    test('refuse un texte qui n\'est pas une URL', () {
      final LinkCheck c = verifyStreamUrl('pas une url');
      expect(c.ok, isFalse);
      expect(c.reason, LinkCheckReason.unreadable);
    });

    test('refuse un protocole non pris en charge (ftp)', () {
      final LinkCheck c = verifyStreamUrl('ftp://x.example/a');
      expect(c.ok, isFalse);
      expect(c.reason, LinkCheckReason.scheme);
    });

    test('refuse un chemin local (file://)', () {
      expect(verifyStreamUrl('file:///etc/passwd').ok, isFalse);
    });

    test('refuse une URL http sans hôte', () {
      final LinkCheck c = verifyStreamUrl('http:///flux.m3u8');
      expect(c.ok, isFalse);
      expect(c.reason, LinkCheckReason.noHost);
    });
  });
}
