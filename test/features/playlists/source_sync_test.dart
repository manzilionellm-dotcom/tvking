// =========================================================
//  source_sync_test.dart — Le bouton « Synchroniser »
// =========================================================
//  Contrat donné par le client, mot pour mot :
//    « – si j'appuie, si j'ai enlevé toutes les chaînes, je reste avec
//        zéro chaînes ;
//      – si j'ajoutais des films, le film vient direct ;
//      – si j'ajoutais une autre chaîne, la chaîne s'ajoute direct. »
//
//  Le point dur, c'est le PREMIER : accepter le zéro. Il s'oppose
//  frontalement au garde-fou existant, qui refusait toute mise à zéro
//  pour éviter qu'un hoquet du fournisseur efface 40 000 chaînes.
//  La conciliation tient dans une seule décision, testée ici : on ne
//  tombe à zéro QUE si le serveur a vraiment répondu une playlist
//  valide. Une page d'erreur HTML ou un corps vide restent une panne.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/source_sync.dart';

SyncReport _report({
  int before = 100,
  int after = 100,
  int added = 0,
  int removed = 0,
  int movies = 0,
  int series = 0,
  int ok = 1,
  int failed = 0,
  bool newSource = false,
}) =>
    SyncReport(
      channelsBefore: before,
      channelsAfter: after,
      added: added,
      removed: removed,
      movies: movies,
      series: series,
      sourcesOk: ok,
      sourcesFailed: failed,
      newSourceReceived: newSource,
    );

void main() {
  // ---------------------------------------------------------
  //  LA DÉCISION QUI COMPTE : zéro volontaire ou panne ?
  // ---------------------------------------------------------
  group('vidée par le revendeur, ou fournisseur en panne ?', () {
    test('un M3U valide mais sans chaîne EST une source vidée', () {
      expect(looksLikeM3uBody('#EXTM3U\n'), isTrue);
      // Certains panels ajoutent un BOM ou des espaces avant l'en-tête.
      expect(looksLikeM3uBody('﻿#EXTM3U'), isTrue);
      expect(looksLikeM3uBody('  \n#EXTM3U x-tvg-url="…"'), isTrue);
      expect(looksLikeM3uBody('#extm3u'), isTrue);
    });

    test('une page d\'erreur ou du vide est une PANNE : on ne vide rien', () {
      // C'est le scénario qui coûterait 40 000 chaînes au client.
      expect(looksLikeM3uBody(''), isFalse);
      expect(
          looksLikeM3uBody('<!DOCTYPE html><h1>502 Bad Gateway</h1>'), isFalse);
      expect(looksLikeM3uBody('Account expired'), isFalse);
      expect(looksLikeM3uBody('{"user_info":{"auth":0}}'), isFalse);
      // Un M3U tronqué qui a perdu son en-tête : on ne parie pas dessus.
      expect(looksLikeM3uBody('#EXTINF:-1,Chaîne\nhttp://x/1.ts'), isFalse);
    });
  });

  // ---------------------------------------------------------
  //  LE COMPTE RENDU — la seule preuve que l'appui a servi
  // ---------------------------------------------------------
  group('ce qu\'on annonce au client', () {
    test('des chaînes retirées : on le DIT, on ne le cache pas', () {
      final String t =
          syncResultText(_report(before: 400, after: 60, removed: 340));
      expect(t, contains('340 retirées'));
      expect(t, contains('60 chaînes'));
    });

    test('des chaînes ajoutées, avec les films', () {
      final String t = syncResultText(
          _report(before: 100, after: 112, added: 12, movies: 850));
      expect(t, contains('12 ajoutées'));
      expect(t, contains('850 films'));
    });

    test('ajouts ET retraits dans la même passe', () {
      final String t = syncResultText(
          _report(before: 100, after: 90, added: 5, removed: 15));
      expect(t, contains('5 ajoutées'));
      expect(t, contains('15 retirées'));
    });

    test('une seule chaîne : pas de « 1 ajoutées »', () {
      expect(
          syncResultText(_report(after: 101, added: 1)), contains('1 ajoutée'));
      expect(syncResultText(_report(after: 101, added: 1)),
          isNot(contains('1 ajoutées')));
    });

    test('source vidée : zéro est annoncé comme un fait, pas une erreur', () {
      final String t =
          syncResultText(_report(before: 400, after: 0, removed: 400));
      expect(t, contains('400 retirées'));

      // Et au deuxième appui, plus rien ne bouge : toujours zéro.
      final String again = syncResultText(_report(before: 0, after: 0));
      expect(again, contains('Aucune chaîne'));
      expect(again, isNot(contains('injoignable')),
          reason: 'zéro voulu n\'est pas une panne — ne pas alarmer');
    });

    test('rien n\'a bougé : on le dit avec le compte pour preuve', () {
      final String t = syncResultText(_report(before: 250, after: 250));
      expect(t, contains('Déjà à jour'));
      expect(t, contains('250'));
    });

    test('nouvelle source poussée par le revendeur : c\'est annoncé', () {
      final String t = syncResultText(
          _report(before: 0, after: 500, added: 500, newSource: true));
      expect(t, contains('Nouvelle source'));
    });

    test('tout a échoué : on rassure au lieu de mentir « à jour »', () {
      final SyncReport r = _report(ok: 0, failed: 2);
      expect(r.allFailed, isTrue);
      final String t = syncResultText(r);
      expect(t, contains('injoignable'));
      expect(t, contains('intactes'),
          reason: 'le client doit savoir que son bouquet n\'a pas été touché');
      expect(t, isNot(contains('Déjà à jour')));
    });
  });

  group('lecture du rapport', () {
    test('unchanged ne vaut que si rien n\'a bougé du tout', () {
      expect(_report().unchanged, isTrue);
      expect(_report(added: 1).unchanged, isFalse);
      expect(_report(removed: 1).unchanged, isFalse);
      expect(_report(newSource: true).unchanged, isFalse);
    });

    test('allFailed ne se déclenche pas quand une source a réussi', () {
      expect(_report(ok: 1, failed: 3).allFailed, isFalse);
      expect(_report(ok: 0, failed: 0).allFailed, isFalse,
          reason: 'aucune source du tout n\'est pas un échec');
    });
  });
}
