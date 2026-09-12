// =========================================================
//  epg_id_normalize_test.dart — Règles de normalisation EPG
// =========================================================
//  Vague 4 : TF1.fr ≠ TF1 ≠ tf1.fr était la cause n°1 du 12/900.
//  Ces tests verrouillent les règles documentées dans epg_id.dart.
//  Purs, zéro réseau, zéro SQLite.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/epg/data/epg_id.dart';

void main() {
  group('EpgId.normalize', () {
    test('casse + suffixe TLD courant → même id', () {
      expect(EpgId.normalize('TF1.fr'), 'tf1');
      expect(EpgId.normalize('TF1'), 'tf1');
      expect(EpgId.normalize('tf1.fr'), 'tf1');
      expect(EpgId.normalize('TF1.COM'), 'tf1');
      expect(EpgId.normalize('  TF1.fr  '), 'tf1');
    });

    test('.co.uk (plus long) avant .uk', () {
      expect(EpgId.normalize('BBC.co.uk'), 'bbc');
      expect(EpgId.normalize('BBC.uk'), 'bbc');
    });

    test('suffixe technique (.hd) NON retiré — pas un TLD', () {
      expect(EpgId.normalize('tf1.hd'), 'tf1.hd');
      expect(EpgId.normalize('xtream-42'), 'xtream-42');
    });

    test('un seul TLD retiré (something.fr.com → something.fr)', () {
      expect(EpgId.normalize('something.fr.com'), 'something.fr');
    });

    test('blancs seuls → vide', () {
      expect(EpgId.normalize('   '), '');
      expect(EpgId.normalize(''), '');
    });

    test('same() compare après normalisation', () {
      expect(EpgId.same('TF1.fr', 'tf1'), isTrue);
      expect(EpgId.same('M6.fr', 'tf1'), isFalse);
      expect(EpgId.same('  ', 'tf1'), isFalse);
    });
  });
}
