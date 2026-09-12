// =========================================================
//  epg_alias_index_test.dart — Pont 1:N + merge + remap + why
// =========================================================
//  Vague 4 : matching, fusion d'alias, compteurs. Purs, zéro réseau.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/epg/data/epg_alias_index.dart';
import 'package:tv_king/features/epg/data/epg_import_stats.dart';

void main() {
  group('EpgAliasIndex 1:N', () {
    test('plusieurs Channel.id pour le même epg_channel_id (plus de LWW)', () {
      final EpgAliasIndex idx = EpgAliasIndex();
      idx.add('TF1.fr', 'xtream-42');
      idx.add('TF1', 'xtream-45'); // même id normalisé
      idx.add('tf1.com', 'xtream-99');
      expect(idx.lookup('tf1.fr'), <String>['xtream-42', 'xtream-45', 'xtream-99']);
      expect(idx.pairCount, 3);
      expect(idx.keyCount, 1);
    });

    test('epg_channel_id vide → pas d\'alias, compteur +1', () {
      final EpgAliasIndex idx = EpgAliasIndex();
      idx.add('  ', 'xtream-1');
      idx.recordEmpty();
      expect(idx.pairCount, 0);
      expect(idx.emptyEpgIdCount, 2);
    });

    test('doublon de paire ignoré', () {
      final EpgAliasIndex idx = EpgAliasIndex();
      idx.add('TF1.fr', 'xtream-42');
      idx.add('tf1', 'xtream-42');
      expect(idx.lookup('TF1'), <String>['xtream-42']);
      expect(idx.pairCount, 1);
    });
  });

  group('mergeKnown + isUnknown (normalisation)', () {
    test('XMLTV tf1.fr passe si known a TF1.fr (self-alias / norme)', () {
      final Set<String>? merged = EpgAliasIndex.mergeKnown(
        <String>{'TF1.fr', 'xtream-7'},
        EpgAliasIndex(),
      );
      expect(merged, containsAll(<String>{'TF1.fr', 'tf1', 'xtream-7'}));
      expect(EpgAliasIndex.isUnknown('tf1.fr', merged), isFalse);
      expect(EpgAliasIndex.isUnknown('M6.fr', merged), isTrue);
    });

    test('alias hors bouquet refusé (pas d\'élargissement sauvage)', () {
      final EpgAliasIndex idx = EpgAliasIndex();
      idx.add('M6.fr', 'xtream-99');
      idx.add('TF1.fr', 'xtream-42');
      final Set<String>? merged = EpgAliasIndex.mergeKnown(
        <String>{'xtream-42'},
        idx,
      );
      expect(merged, contains('tf1'));
      expect(merged, isNot(contains('m6')));
    });

    test('known null → pas de filtre', () {
      expect(EpgAliasIndex.mergeKnown(null, EpgAliasIndex()), isNull);
      expect(EpgAliasIndex.isUnknown('quoi', null), isFalse);
    });
  });

  group('expandRow', () {
    test('un XMLTV → toutes les variantes', () {
      final EpgAliasIndex idx = EpgAliasIndex();
      idx.add('TF1.fr', 'xtream-42');
      idx.add('TF1.fr', 'xtream-45');
      final List<Map<String, Object?>> rows = idx.expandRow(
        <String, Object?>{'channel_id': 'tf1.com', 'title': 'JT'},
      );
      expect(
        rows.map((Map<String, Object?> r) => r['channel_id']),
        <String>['xtream-42', 'xtream-45'],
      );
    });

    test('id inconnu → ligne inchangée (même instance)', () {
      final EpgAliasIndex idx = EpgAliasIndex();
      final Map<String, Object?> row = <String, Object?>{
        'channel_id': 'm3u-tvg-id',
        'title': 'Météo',
      };
      expect(idx.expandRow(row).single, same(row));
    });
  });

  group('explainEpgCoverage (POURQUOI FR)', () {
    test('pont vide + ids XMLTV sautés', () {
      final String why = explainEpgCoverage(
        aliasCount: 0,
        xmltvChannelIdsSeen: 50,
        retained: 0,
        skippedUnknownId: 200,
        skippedOutsideWindow: 0,
        coveredChannelCount: 0,
        knownChannelCount: 900,
        emptyEpgChannelIdCount: 0,
      );
      expect(why.toLowerCase(), contains('pont'));
      expect(why, contains('0 alias'));
    });

    test('fournisseur trop maigre (XMLTV 12 ids / 900 chaînes)', () {
      final String why = explainEpgCoverage(
        aliasCount: 800,
        xmltvChannelIdsSeen: 12,
        retained: 48,
        skippedUnknownId: 2,
        skippedOutsideWindow: 10,
        coveredChannelCount: 12,
        knownChannelCount: 900,
        emptyEpgChannelIdCount: 20,
      );
      expect(why.toLowerCase(), contains('fournisseur'));
    });

    test('filtre temps (hors fenêtre, ids reconnus)', () {
      final String why = explainEpgCoverage(
        aliasCount: 50,
        xmltvChannelIdsSeen: 50,
        retained: 0,
        skippedUnknownId: 0,
        skippedOutsideWindow: 4000,
        coveredChannelCount: 0,
        knownChannelCount: 900,
        emptyEpgChannelIdCount: 0,
      );
      expect(why.toLowerCase(), contains('fenêtre'));
    });

    test('couverture OK', () {
      final String why = explainEpgCoverage(
        aliasCount: 900,
        xmltvChannelIdsSeen: 900,
        retained: 4000,
        skippedUnknownId: 10,
        skippedOutsideWindow: 100,
        coveredChannelCount: 900,
        knownChannelCount: 900,
        emptyEpgChannelIdCount: 0,
      );
      expect(why.startsWith('OK'), isTrue);
    });

    test('chaînes sans epg_channel_id', () {
      final String why = explainEpgCoverage(
        aliasCount: 0,
        xmltvChannelIdsSeen: 40,
        retained: 0,
        skippedUnknownId: 100,
        skippedOutsideWindow: 0,
        coveredChannelCount: 0,
        knownChannelCount: 900,
        emptyEpgChannelIdCount: 800,
      );
      expect(why, contains('epg_channel_id'));
      expect(why, contains('800'));
    });
  });
}
