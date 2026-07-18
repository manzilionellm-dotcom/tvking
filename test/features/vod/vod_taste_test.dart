// =========================================================
//  vod_taste_test.dart — « Goût » : score de compatibilité + tirage
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/vod/data/vod_taste.dart';
import 'package:tv_king/features/vod/domain/vod_movie.dart';

VodMovie _m(String id, String cat, {String? rating}) => VodMovie(
      id: id,
      name: 'n$id',
      category: cat,
      streamUrl: 'http://x/$id.mp4',
      containerExt: 'mp4',
      rating: rating,
    );

void main() {
  group('affinity', () {
    test('derniers vus pèsent plus que Ma Liste', () {
      final aff = VodTaste.affinity(
        recent: <VodMovie>[_m('1', 'Action')],
        watchlist: <VodMovie>[_m('2', 'Action'), _m('3', 'Drame')],
      );
      expect(aff['action'], 3.0); // 2 (vu) + 1 (liste)
      expect(aff['drame'], 1.0);
    });

    test('sans historique → map vide', () {
      expect(
          VodTaste.affinity(
              recent: const <VodMovie>[], watchlist: const <VodMovie>[]),
          isEmpty);
    });
  });

  group('matchPercent', () {
    test('catégorie inconnue ET pas de note → null (honnête)', () {
      expect(
          VodTaste.matchPercent(_m('9', 'Inconnu'),
              affinity: <String, double>{'action': 4}, maxAffinity: 4),
          isNull);
    });

    test('catégorie fétiche + bonne note → score élevé, borné à 98', () {
      final int? p = VodTaste.matchPercent(_m('1', 'Action', rating: '9.0'),
          affinity: <String, double>{'action': 4}, maxAffinity: 4);
      expect(p, isNotNull);
      expect(p, greaterThanOrEqualTo(90));
      expect(p, lessThanOrEqualTo(98));
    });

    test('jamais en dessous de 72 quand affiché', () {
      final int? p = VodTaste.matchPercent(_m('2', 'Drame', rating: '5.0'),
          affinity: <String, double>{'action': 8, 'drame': 1},
          maxAffinity: 8);
      expect(p, isNotNull);
      expect(p, greaterThanOrEqualTo(72));
    });

    test('note sur 5 remise sur 10', () {
      // rating 4/5 → 8/10 : contribue comme une bonne note.
      final int? p = VodTaste.matchPercent(_m('3', 'X', rating: '4'),
          affinity: <String, double>{}, maxAffinity: 0);
      expect(p, isNotNull); // note présente → score calculable
    });
  });

  group('surpriseIndex', () {
    test('liste vide → -1', () {
      expect(
          VodTaste.surpriseIndex(const <VodMovie>[],
              affinity: const <String, double>{}, rngUnit: 0.5),
          -1);
    });

    test('rngUnit 0 → premier élément', () {
      final movies = <VodMovie>[_m('1', 'A'), _m('2', 'B')];
      expect(
          VodTaste.surpriseIndex(movies,
              affinity: const <String, double>{}, rngUnit: 0.0),
          0);
    });

    test('favorise la catégorie aimée pour rngUnit élevé', () {
      // 2 films : A (aimé, poids 1+10=11) puis B (poids 1). Total 12.
      // rngUnit 0.5 → target 6 → tombe dans A (0..11). A doit gagner souvent.
      final movies = <VodMovie>[_m('1', 'Aime'), _m('2', 'Autre')];
      final idx = VodTaste.surpriseIndex(movies,
          affinity: <String, double>{'aime': 10}, rngUnit: 0.5);
      expect(idx, 0);
    });
  });
}
