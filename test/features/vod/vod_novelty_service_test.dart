// =========================================================
//  vod_novelty_service_test.dart — « Nouveautés » (logique pure)
// =========================================================
//  On teste reconcilePure : la brique qui décide ce qui est « nouveau »
//  sans réseau ni disque. Points critiques :
//   • premier lancement = ligne de base (RIEN n'est neuf, pas de fausse
//     rangée « tout le catalogue ») ;
//   • un id inconnu ensuite = nouveauté horodatée ;
//   • fenêtre de fraîcheur (14 j) : au-delà, le contenu sort des
//     nouveautés ;
//   • purge des ids retirés de la source (pas de fuite mémoire).
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/vod/data/vod_novelty_service.dart';

void main() {
  const int t0 = 1000000000000; // horloge injectée (ms)

  test('premier lancement = ligne de base, rien de neuf', () {
    final Map<String, int> store = <String, int>{};
    final Set<String> fresh = VodNoveltyService.reconcilePure(
        store, <String>['a', 'b', 'c'],
        nowMs: t0);
    expect(fresh, isEmpty);
    // Tout est enregistré en base (0) → connu, jamais « nouveau ».
    expect(store.values.every((int v) => v == 0), isTrue);
  });

  test('un id inconnu après la base = nouveauté', () {
    final Map<String, int> store = <String, int>{};
    VodNoveltyService.reconcilePure(store, <String>['a', 'b'], nowMs: t0);
    final Set<String> fresh = VodNoveltyService.reconcilePure(
        store, <String>['a', 'b', 'c', 'd'],
        nowMs: t0 + 1000);
    expect(fresh, <String>{'c', 'd'});
  });

  test('au-delà de la fenêtre de fraîcheur, ce n\'est plus nouveau', () {
    final Map<String, int> store = <String, int>{};
    VodNoveltyService.reconcilePure(store, <String>['a'], nowMs: t0);
    // 'b' apparaît à t0+1000
    VodNoveltyService.reconcilePure(store, <String>['a', 'b'],
        nowMs: t0 + 1000);
    // 15 jours plus tard : 'b' est sorti des nouveautés.
    final int later = t0 + 1000 + const Duration(days: 15).inMilliseconds;
    final Set<String> fresh = VodNoveltyService.reconcilePure(
        store, <String>['a', 'b'],
        nowMs: later);
    expect(fresh, isEmpty);
  });

  test('un id retiré de la source est purgé du dictionnaire', () {
    final Map<String, int> store = <String, int>{};
    VodNoveltyService.reconcilePure(store, <String>['a', 'b', 'c'], nowMs: t0);
    VodNoveltyService.reconcilePure(store, <String>['a'], nowMs: t0 + 1000);
    expect(store.keys.toSet(), <String>{'a'});
  });

  test('la nouveauté persiste sur plusieurs visites dans la fenêtre', () {
    final Map<String, int> store = <String, int>{};
    VodNoveltyService.reconcilePure(store, <String>['a'], nowMs: t0);
    VodNoveltyService.reconcilePure(store, <String>['a', 'b'],
        nowMs: t0 + 1000);
    // Revisite 3 jours après : 'b' reste « nouveau ».
    final Set<String> fresh = VodNoveltyService.reconcilePure(
        store, <String>['a', 'b'],
        nowMs: t0 + const Duration(days: 3).inMilliseconds);
    expect(fresh.contains('b'), isTrue);
  });
}
