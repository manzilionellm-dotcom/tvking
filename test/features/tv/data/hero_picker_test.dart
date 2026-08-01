// =========================================================
//  hero_picker_test.dart — Choix du héro d'accueil (Modèles B/C)
// =========================================================
//  Contrat de la brique pure heroCandidates (photo terrain 2026-08-01 :
//  le héro pointait une chaîne morte côté fournisseur → cadre noir) :
//    1. ordre d'affection : créneau → récents → favoris → 1re chaîne ;
//    2. les chaînes marquées PEU FIABLES (score n°38) passent en fin de
//       liste — jamais écartées totalement (dernier recours) ;
//    3. dédoublonnage, liste bornée, jamais vide si le bouquet ne l'est pas.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/data/hero_picker.dart';

Channel _c(String id) => Channel(
      id: id,
      name: 'Chaîne $id',
      category: 'Test',
      streamUrl: 'http://panel.example/live/u/p/$id.ts',
      isLive: true,
    );

void main() {
  final List<Channel> all = <Channel>[for (int i = 1; i <= 8; i++) _c('c$i')];
  final Map<String, Channel> byId = <String, Channel>{
    for (final Channel c in all) c.id: c
  };

  test('ordre d\'affection : créneau → récents → favoris → 1re chaîne', () {
    final List<Channel> out = heroCandidates(
      all: all,
      byId: byId,
      slotId: 'c4',
      recents: <String>['c2', 'c3'],
      favorites: <String>['c5'],
      isFlaky: (_) => false,
    );
    expect(out.map((Channel c) => c.id).toList(),
        <String>['c4', 'c2', 'c3', 'c5', 'c1']);
  });

  test('une chaîne peu fiable recule en fin de liste, jamais supprimée', () {
    final List<Channel> out = heroCandidates(
      all: all,
      byId: byId,
      slotId: 'c4', // la préférée du créneau… mais morte chez ce client
      recents: <String>['c2'],
      favorites: <String>['c5'],
      isFlaky: (String id) => id == 'c4',
    );
    // c4 n'est plus en tête (cadre noir garanti sinon) mais reste en
    // dernier recours.
    expect(out.first.id, 'c2');
    expect(out.map((Channel c) => c.id), contains('c4'));
    expect(out.last.id, 'c4');
  });

  test('tout est marqué peu fiable → on garde quand même des candidats', () {
    final List<Channel> out = heroCandidates(
      all: all,
      byId: byId,
      recents: <String>['c2'],
      favorites: <String>[],
      isFlaky: (_) => true,
    );
    expect(out, isNotEmpty);
    expect(out.first.id, 'c2'); // l'ordre d'affection survit au marquage
  });

  test('dédoublonnage + borne max', () {
    final List<Channel> out = heroCandidates(
      all: all,
      byId: byId,
      slotId: 'c1',
      recents: <String>['c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7'],
      favorites: <String>['c2', 'c8'],
      isFlaky: (_) => false,
      max: 4,
    );
    expect(out.length, 4);
    expect(out.map((Channel c) => c.id).toSet().length, 4); // uniques
    expect(out.first.id, 'c1');
  });

  test('bouquet vide → liste vide (l\'accueil garde son logo)', () {
    expect(
        heroCandidates(
          all: const <Channel>[],
          byId: const <String, Channel>{},
          recents: const <String>[],
          favorites: const <String>[],
          isFlaky: (_) => false,
        ),
        isEmpty);
  });

  test('ids inconnus (chaîne disparue du bouquet) ignorés sans erreur', () {
    final List<Channel> out = heroCandidates(
      all: all,
      byId: byId,
      slotId: 'fantome',
      recents: <String>['disparu', 'c3'],
      favorites: <String>['aussi-disparu'],
      isFlaky: (_) => false,
    );
    expect(out.first.id, 'c3');
  });
}
