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

    // CHANGEMENT DE COMPORTEMENT ASSUMÉ (2026-08-03).
    //
    // Ce test exigeait auparavant le REFUS des fichiers locaux. C'était
    // une erreur, et elle a coûté cher : le clip de démonstration
    // embarqué dans l'app affichait « Lecture bloquée : lien invalide »
    // sur un fichier que l'app avait elle-même écrit sur le disque.
    //
    // Le lecteur, lui, a toujours su ouvrir un fichier local (branche
    // `isLocalFile` de `_openMedia`). Mais `playChannel` est la seule
    // porte d'entrée du lecteur téléphone : ce refus rendait cette
    // branche INATTEIGNABLE, et condamnait du même coup la lecture
    // hors-ligne des films téléchargés. Le test protégeait un bug.
    //
    // Ce qu'on garde : seul l'ABSOLU passe.
    test('accepte un fichier local — le lecteur sait les ouvrir', () {
      expect(verifyStreamUrl('file:///data/app/clip.mp4').ok, isTrue);
      expect(verifyStreamUrl('/data/user/0/com.x/files/clip.mp4').ok, isTrue);
    });

    test('un chemin RELATIF reste illisible', () {
      final LinkCheck c = verifyStreamUrl('files/clip.mp4');
      expect(c.ok, isFalse);
      expect(c.reason, LinkCheckReason.unreadable,
          reason: 'sans racine, personne ne sait à quoi il se rapporte');
    });

    test('refuse une URL http sans hôte', () {
      final LinkCheck c = verifyStreamUrl('http:///flux.m3u8');
      expect(c.ok, isFalse);
      expect(c.reason, LinkCheckReason.noHost);
    });
  });
}
